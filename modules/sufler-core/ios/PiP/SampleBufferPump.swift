import AVFoundation
import CoreMedia
import CoreVideo
import QuartzCore
import UIKit

/// `CADisplayLink` retains its target. Without an indirection the pump would keep itself alive
/// forever, which in practice means a leaked render loop burning battery after the user has moved
/// on. This is the standard fix.
private final class DisplayLinkProxy {
  weak var target: SampleBufferPump?
  init(target: SampleBufferPump) { self.target = target }
  @objc func tick(_ link: CADisplayLink) { target?.tick(link) }
}

/// Produces frames for `AVSampleBufferDisplayLayer` — and, deliberately, produces as few as it can
/// get away with.
///
/// A sample-buffer display layer is a push surface: it holds the last frame it was given
/// indefinitely. A teleprompter changes when a word is recognised and is otherwise static, so
/// running a 30 fps render loop would spend almost all of its work redrawing identical pixels.
/// Instead the pump tracks a dirty flag, eases the scroll offset toward its target, and when
/// nothing is moving it stops the display link entirely and falls back to a 1 Hz heartbeat.
///
/// Realistic steady state over a talk: a few frames per second, and zero while the speaker pauses.
final class SampleBufferPump {

  /// Asked for the current frame contents on the main thread, immediately before drawing.
  var frameModelProvider: (() -> FrameModel)?
  /// Vertical scroll target, in "lines" — the pump eases toward it so the text glides rather than
  /// snapping between recognised words.
  var onError: ((Error) -> Void)?

  private let pool = PixelBufferPool()
  private weak var layer: AVSampleBufferDisplayLayer?

  private var displayLink: CADisplayLink?
  private var heartbeat: DispatchSourceTimer?
  private var proxy: DisplayLinkProxy?

  private var dirty = true
  private var lastEnqueue: CFTimeInterval = 0
  private var lastDirtyAt: CFTimeInterval = 0
  private var renderSize: CGSize = CGSize(width: 480, height: 270)

  /// Long enough that the window is never blank for more than a moment if the system rebuilds the
  /// layer's backing store, short enough to cost nothing.
  private let heartbeatInterval: CFTimeInterval = 1.0
  /// After this much stillness the display link is torn down and only the heartbeat remains.
  private let idleTimeout: CFTimeInterval = 3.0

  // MARK: - Wiring

  func attach(layer: AVSampleBufferDisplayLayer) {
    self.layer = layer
    pool.invalidateFormatDescription()
    markDirty(force: true)
  }

  func detach() {
    stop()
    layer = nil
  }

  func reconfigure(renderSize newSize: CGSize) {
    guard newSize.width >= 16, newSize.height >= 16 else { return }
    renderSize = newSize
    pool.reconfigure(to: newSize)
    layer?.sampleBufferRenderer.flush()
    markDirty(force: true)
  }

  // MARK: - Run loop

  func start() {
    guard displayLink == nil else {
      markDirty(force: true)
      return
    }
    pool.reconfigure(to: renderSize)
    startDisplayLink()
    startHeartbeat()
    markDirty(force: true)
  }

  func stop() {
    displayLink?.invalidate()
    displayLink = nil
    proxy = nil
    heartbeat?.cancel()
    heartbeat = nil
  }

  /// Called from the aligner queue several times a second as well as from the main thread.
  ///
  /// All pump state — the display link in particular — is main-thread confined: `CADisplayLink`
  /// must be created and invalidated there, and racing the render loop over the dirty flag would
  /// mean dropped frames at exactly the moments that matter. One async hop per recognised word is
  /// nothing next to that.
  func markDirty(force: Bool = false) {
    if Thread.isMainThread {
      applyDirty(force: force)
    } else {
      DispatchQueue.main.async { [weak self] in self?.applyDirty(force: force) }
    }
  }

  private func applyDirty(force: Bool) {
    dirty = true
    lastDirtyAt = CACurrentMediaTime()
    if force { lastEnqueue = 0 }
    // Motion resumed after an idle stretch — bring the display link back.
    if displayLink == nil, heartbeat != nil { startDisplayLink() }
  }

  private func startDisplayLink() {
    let proxy = DisplayLinkProxy(target: self)
    let link = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.tick(_:)))
    // The minimum matters as much as the maximum: it tells the system it is free to run us slowly,
    // which is most of what keeps this from being a battery problem.
    link.preferredFrameRateRange = CAFrameRateRange(minimum: 8, maximum: 30, preferred: 30)
    link.add(to: .main, forMode: .common)
    self.proxy = proxy
    self.displayLink = link
  }

  private func startHeartbeat() {
    let timer = DispatchSource.makeTimerSource(queue: .main)
    timer.schedule(deadline: .now() + heartbeatInterval, repeating: heartbeatInterval)
    timer.setEventHandler { [weak self] in
      guard let self else { return }
      self.renderAndEnqueue()
    }
    timer.resume()
    heartbeat = timer
  }

  fileprivate func tick(_ link: CADisplayLink) {
    let now = CACurrentMediaTime()

    if !dirty {
      // Nothing has changed for a while: drop the display link and let the heartbeat carry on.
      if now - lastDirtyAt > idleTimeout {
        link.invalidate()
        displayLink = nil
        proxy = nil
      }
      return
    }

    renderAndEnqueue()
  }

  // MARK: - Frame production

  private func renderAndEnqueue() {
    guard let layer, let provider = frameModelProvider else { return }

    let renderer = layer.sampleBufferRenderer
    if renderer.status == .failed {
      renderer.flush()
      pool.invalidateFormatDescription()
    }
    guard renderer.isReadyForMoreMediaData else { return }

    if pool.size != renderSize { pool.reconfigure(to: renderSize) }
    guard let pixelBuffer = pool.makePixelBuffer() else { return }

    TeleprompterFrameRenderer.render(provider(), into: pixelBuffer)

    guard let sampleBuffer = makeSampleBuffer(pixelBuffer) else { return }
    renderer.enqueue(sampleBuffer)

    lastEnqueue = CACurrentMediaTime()
    dirty = false
  }

  private func makeSampleBuffer(_ pixelBuffer: CVPixelBuffer) -> CMSampleBuffer? {
    guard let formatDescription = pool.formatDescription(for: pixelBuffer) else { return nil }

    // The presentation timestamp has to be in the host time domain — the same clock
    // `CACurrentMediaTime()` reads. A zero-based or wall-clock PTS makes the layer stall or drop
    // everything, silently.
    var timing = CMSampleTimingInfo(
      duration: CMTime(value: 1, timescale: 30),
      presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
      decodeTimeStamp: .invalid)

    var sampleBuffer: CMSampleBuffer?
    let status = CMSampleBufferCreateReadyWithImageBuffer(
      allocator: kCFAllocatorDefault,
      imageBuffer: pixelBuffer,
      formatDescription: formatDescription,
      sampleTiming: &timing,
      sampleBufferOut: &sampleBuffer)

    guard status == noErr, let sampleBuffer else { return nil }

    // Display immediately rather than scheduling against a control timebase. We have no timebase —
    // this is a live, untimed stream — and a mismatched one is the other classic cause of a black
    // PiP window.
    if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true),
       CFArrayGetCount(attachments) > 0 {
      let dictionary = unsafeBitCast(
        CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
      CFDictionarySetValue(
        dictionary,
        Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
        Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
    }

    return sampleBuffer
  }
}
