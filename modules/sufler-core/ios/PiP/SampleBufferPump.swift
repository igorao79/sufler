import AVFoundation
import CoreMedia
import CoreVideo
import QuartzCore
import UIKit

/// Produces frames for `AVSampleBufferDisplayLayer` — and, deliberately, produces as few as it can
/// get away with.
///
/// A sample-buffer display layer is a push surface: it holds the last frame it was given
/// indefinitely. A teleprompter changes when a word is recognised and is otherwise static, so a
/// fixed 30 fps loop would spend nearly all of its work redrawing identical pixels. Instead the
/// pump tracks a dirty flag and drops to a slow heartbeat when nothing is moving.
///
/// The clock is a `DispatchSourceTimer` rather than a `CADisplayLink`. That is not a style choice:
/// a display link is driven by the display refresh and **stops entirely once the app is in the
/// background** — which is precisely when Picture in Picture matters. Driving the overlay from one
/// meant the floating window was fed by nothing but the 1 Hz fallback the moment the user swiped
/// away, which is the whole point of the feature. Vsync alignment buys nothing here anyway; the
/// frames go into a video stream, not onto the screen directly.
final class SampleBufferPump {

  /// Asked for the current frame contents on the main thread, immediately before drawing.
  var frameModelProvider: (() -> FrameModel)?

  private let pool = PixelBufferPool()
  private weak var layer: AVSampleBufferDisplayLayer?

  private var timer: DispatchSourceTimer?
  private var timerInterval: TimeInterval = 0

  private var dirty = true
  private var lastRender: CFTimeInterval = 0
  private var lastDirtyAt: CFTimeInterval = 0
  private var renderSize = CGSize(width: 480, height: 270)

  /// Diagnostics. Picture in Picture fails silently more often than it fails loudly — an empty
  /// window and no error anywhere — so the pump keeps enough state to answer "is anything actually
  /// being produced, and did the renderer reject it".
  private(set) var framesEnqueued = 0
  private(set) var lastRendererError: String?

  /// Fast enough that scrolling reads as motion rather than as a slideshow.
  private let activeInterval: TimeInterval = 1.0 / 30
  /// Nothing is moving: keep the window alive without burning anything.
  private let idleInterval: TimeInterval = 1.0
  /// How long stillness has to last before dropping to the idle clock.
  private let idleAfter: CFTimeInterval = 2.0
  /// Even when idle, re-send a frame this often. Strictly the last frame persists, but the system
  /// re-creates the layer's backing store on render-size transitions and on foreground/background
  /// changes, and a heartbeat means the window is never blank for longer than this.
  private let heartbeat: CFTimeInterval = 1.0

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
    NSLog("[Sufler] PiP render size -> %.0fx%.0f", newSize.width, newSize.height)
    renderSize = newSize
    pool.reconfigure(to: newSize)
    layer?.sampleBufferRenderer.flush()
    markDirty(force: true)
  }

  // MARK: - Run loop

  func start() {
    pool.reconfigure(to: renderSize)
    startTimer(interval: activeInterval)
    markDirty(force: true)
  }

  func stop() {
    timer?.cancel()
    timer = nil
    timerInterval = 0
  }

  func markDirty(force: Bool = false) {
    // Called from the aligner queue several times a second as well as from the main thread. All
    // pump state is main-thread confined; one async hop per recognised word is nothing next to
    // the races that sharing it would buy.
    if Thread.isMainThread {
      applyDirty(force: force)
    } else {
      DispatchQueue.main.async { [weak self] in self?.applyDirty(force: force) }
    }
  }

  private func applyDirty(force: Bool) {
    dirty = true
    lastDirtyAt = CACurrentMediaTime()
    if force { lastRender = 0 }
    if timer != nil, timerInterval != activeInterval {
      startTimer(interval: activeInterval)
    }
  }

  private func startTimer(interval: TimeInterval) {
    timer?.cancel()
    let source = DispatchSource.makeTimerSource(queue: .main)
    source.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(4))
    source.setEventHandler { [weak self] in self?.tick() }
    source.resume()
    timer = source
    timerInterval = interval
  }

  private func tick() {
    let now = CACurrentMediaTime()

    if dirty {
      renderAndEnqueue()
      return
    }

    if now - lastRender >= heartbeat {
      renderAndEnqueue()
    }

    // Stillness: stop asking thirty times a second whether anything changed.
    if timerInterval == activeInterval, now - lastDirtyAt > idleAfter {
      startTimer(interval: idleInterval)
    }
  }

  // MARK: - Frame production

  private func renderAndEnqueue() {
    guard let layer, let provider = frameModelProvider else { return }

    let renderer = layer.sampleBufferRenderer
    if renderer.status == .failed {
      lastRendererError = renderer.error?.localizedDescription ?? "renderer failed"
      NSLog("[Sufler] sample buffer renderer failed: %@", lastRendererError ?? "?")
      renderer.flush()
      pool.invalidateFormatDescription()
    }
    guard renderer.isReadyForMoreMediaData else { return }

    if pool.size != renderSize { pool.reconfigure(to: renderSize) }
    guard let pixelBuffer = pool.makePixelBuffer() else {
      lastRendererError = "pixel buffer pool exhausted"
      return
    }

    TeleprompterFrameRenderer.render(provider(), into: pixelBuffer)

    guard let sampleBuffer = makeSampleBuffer(pixelBuffer) else {
      lastRendererError = "could not wrap pixel buffer"
      return
    }
    renderer.enqueue(sampleBuffer)

    framesEnqueued += 1
    lastRender = CACurrentMediaTime()
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
    // this is a live, untimed stream — and a mismatched one is a classic cause of a black PiP
    // window.
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

  // MARK: - Diagnostics

  var diagnostics: [String: Any] {
    [
      "framesEnqueued": framesEnqueued,
      "renderWidth": Int(renderSize.width),
      "renderHeight": Int(renderSize.height),
      "clockHz": timerInterval > 0 ? Int((1.0 / timerInterval).rounded()) : 0,
      "rendererError": lastRendererError ?? "",
      "hasLayer": layer != nil,
    ]
  }
}
