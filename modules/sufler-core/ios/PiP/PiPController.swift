import AVFoundation
import AVKit
import Foundation
import UIKit

/// Owns `AVPictureInPictureController` and both of its delegates.
///
/// This is the highest-risk file in the project, because nearly everything PiP gets wrong it gets
/// wrong silently: no exception, no log, just an empty window or a start call that does nothing.
/// The comments below mark the specific things that cause that.
final class PiPController: NSObject {

  enum PiPError: LocalizedError {
    case unsupported
    case notPossibleYet
    case noSourceLayer

    var errorDescription: String? {
      switch self {
      case .unsupported:
        return "Picture in Picture is not supported on this device. (It is unavailable on iPhone simulators.)"
      case .notPossibleYet:
        return "Picture in Picture is not ready yet — the preview must be visible on screen first."
      case .noSourceLayer:
        return "The Picture in Picture preview is not on screen."
      }
    }
  }

  /// Emitted to JS. Weakly held so a module teardown cannot keep the controller alive.
  weak var module: SuflerPiPModule?

  private(set) var isActive = false
  private let pump = SampleBufferPump()

  private var controller: AVPictureInPictureController?
  private weak var sourceView: PiPSourceView?
  private weak var sourceLayer: AVSampleBufferDisplayLayer?
  private var possibleObservation: NSKeyValueObservation?

  var style = PiPStyle()

  override init() {
    super.init()
    pump.frameModelProvider = { [weak self] in
      self?.currentFrameModel() ?? FrameModel()
    }
  }

  // MARK: - Source binding

  func bind(sourceView: PiPSourceView, layer: AVSampleBufferDisplayLayer) {
    self.sourceView = sourceView
    self.sourceLayer = layer

    pump.attach(layer: layer)
    pump.start()

    setUpController(with: layer)
  }

  func unbind(sourceView view: PiPSourceView) {
    guard sourceView === view else { return }
    // Leaving PiP running with no inline source is legal and expected — the user swiped away and
    // the screen unmounted. Only tear the renderer down when the window is actually gone.
    guard !isActive else { return }
    pump.detach()
    possibleObservation = nil
    controller = nil
    sourceView = nil
    sourceLayer = nil
  }

  private func setUpController(with layer: AVSampleBufferDisplayLayer) {
    guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
    guard controller == nil else { return }

    let source = AVPictureInPictureController.ContentSource(
      sampleBufferDisplayLayer: layer, playbackDelegate: self)
    let controller = AVPictureInPictureController(contentSource: source)
    controller.delegate = self
    // The whole point: the window appears when the user leaves the app, not only when they tap a
    // PiP button that does not exist for sample-buffer content.
    controller.canStartPictureInPictureAutomaticallyFromInline = true
    // Hides the skip-back/forward buttons, which mean nothing for a live teleprompter.
    controller.requiresLinearPlayback = true

    // `isPictureInPicturePossible` is false for a run loop turn or two after init, and false
    // whenever the layer is not in a window. Calling start() before it flips is a silent no-op.
    possibleObservation = controller.observe(\.isPictureInPicturePossible, options: [.new]) {
      [weak self] controller, _ in
      self?.module?.emitState(active: self?.isActive ?? false,
                              possible: controller.isPictureInPicturePossible)
    }

    self.controller = controller
  }

  // MARK: - Start / stop

  @MainActor
  func start() throws {
    guard AVPictureInPictureController.isPictureInPictureSupported() else { throw PiPError.unsupported }
    guard let controller else { throw PiPError.noSourceLayer }
    guard controller.isPictureInPicturePossible else { throw PiPError.notPossibleYet }

    pump.start()
    pump.markDirty(force: true)
    controller.startPictureInPicture()
  }

  @MainActor
  func stop() {
    controller?.stopPictureInPicture()
  }

  var isPossible: Bool { controller?.isPictureInPicturePossible ?? false }

  // MARK: - Content

  func markDirty(force: Bool = false) {
    pump.markDirty(force: force)
  }

  func applyStyle(_ style: PiPStyle) {
    self.style = style
    markDirty(force: true)
  }

  /// Called on the main thread by the pump, immediately before drawing.
  private func currentFrameModel() -> FrameModel {
    let session = SuflerSession.shared
    let script = session.script
    let position = session.positionBus.position

    var model = FrameModel()
    model.lines = script.lines
    model.currentLineIndex = position.lineIndex
    model.mirrored = style.mirrored
    model.fontSize = style.fontSize
    model.progress = script.tokenCount > 0
      ? Double(position.tokenIndex) / Double(max(script.tokenCount - 1, 1))
      : 0

    if let token = script.tokens.indices.contains(position.tokenIndex)
      ? script.tokens[position.tokenIndex] : nil {
      model.activeWordRange = token.rangeInLine
    }

    // A custom renderer earns its keep here: instead of a frozen window the user cannot explain,
    // they get told what happened and why the text stopped moving.
    model.overlayMessage = session.pipOverlayMessage

    if style.debugOverlay {
      model.debugText = session.debugSummary()
    }

    return model
  }

  // MARK: - App lifecycle

  func appDidEnterBackground() {
    // Auto-PiP either engaged during the transition or it did not. If it did not, the app is about
    // to be suspended despite the audio background mode, so say so rather than letting the user
    // come back to a teleprompter that quietly stopped.
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
      guard let self, !self.isActive else { return }
      self.module?.emitError(
        code: "pip_did_not_start",
        message: "Picture in Picture did not start when the app went to the background. The preview card must be visible on screen when you leave the app.")
    }
  }

  func appWillEnterForeground() {
    pump.markDirty(force: true)
  }
}

// MARK: - AVPictureInPictureControllerDelegate

extension PiPController: AVPictureInPictureControllerDelegate {

  func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
    isActive = true
    pump.markDirty(force: true)
    module?.emitState(active: true, possible: controller.isPictureInPicturePossible)
  }

  func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
    isActive = false
    module?.emitState(active: false, possible: controller.isPictureInPicturePossible)
  }

  func pictureInPictureController(
    _ controller: AVPictureInPictureController,
    failedToStartPictureInPictureWithError error: Error
  ) {
    isActive = false
    module?.emitError(code: "pip_start_failed", message: error.localizedDescription)
  }
}

// MARK: - AVPictureInPictureSampleBufferPlaybackDelegate

extension PiPController: AVPictureInPictureSampleBufferPlaybackDelegate {

  /// An infinite, non-scrubbable range marks this as a live stream, which gives the window the
  /// minimal chrome — play/pause, close, restore — and suppresses the scrubber.
  func pictureInPictureControllerTimeRangeForPlayback(
    _ controller: AVPictureInPictureController
  ) -> CMTimeRange {
    CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
  }

  /// "Paused" means speech-following is stopped. There is no other notion of playback here.
  func pictureInPictureControllerIsPlaybackPaused(
    _ controller: AVPictureInPictureController
  ) -> Bool {
    !SuflerSession.shared.isFollowing
  }

  /// The window's play/pause button *is* the Start/Stop button, which is what makes the overlay
  /// usable without coming back to the app.
  func pictureInPictureController(
    _ controller: AVPictureInPictureController,
    setPlaying playing: Bool
  ) {
    Task { @MainActor in
      if playing {
        SuflerSession.shared.resumeFollowingFromPiP()
      } else {
        SuflerSession.shared.stopFollowing()
      }
      self.module?.emitPlaybackToggled(playing: playing)
    }
  }

  /// The system tells us the pixel size it wants — which changes as the user resizes the window
  /// between its three sizes. Rendering at the inline card's size instead produces a blurry or
  /// letterboxed window.
  func pictureInPictureController(
    _ controller: AVPictureInPictureController,
    didTransitionToRenderSize newRenderSize: CMVideoDimensions
  ) {
    pump.reconfigure(renderSize: CGSize(width: Int(newRenderSize.width),
                                        height: Int(newRenderSize.height)))
  }

  /// Hidden by `requiresLinearPlayback`, but the completion handler still has to be invoked if it
  /// ever arrives — PiP waits on it and deadlocks otherwise.
  func pictureInPictureController(
    _ controller: AVPictureInPictureController,
    skipByInterval skipInterval: CMTime,
    completion completionHandler: @escaping () -> Void
  ) {
    SuflerSession.shared.nudge(lines: skipInterval.seconds > 0 ? 2 : -2)
    completionHandler()
  }

  /// Without this, iOS 16 and later suppress our background audio the moment PiP starts — which
  /// takes the microphone with it.
  func pictureInPictureControllerShouldProhibitBackgroundAudioPlayback(
    _ controller: AVPictureInPictureController
  ) -> Bool {
    false
  }
}

// MARK: - Playback state

extension PiPController {
  /// iOS only re-reads `isPlaybackPaused` when told to. Every state change that originates on our
  /// side — the in-app Start button, an interruption, a speech error — has to call this or the
  /// window keeps showing a stale icon.
  func invalidatePlaybackState() {
    controller?.invalidatePlaybackState()
  }
}
