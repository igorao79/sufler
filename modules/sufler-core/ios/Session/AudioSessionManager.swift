import AVFoundation
import Foundation

/// The single owner of `AVAudioSession` for the whole app.
///
/// PiP and speech recognition both need the session, and they need *different* things from it:
/// PiP needs an audio-capable session plus the `audio` background mode to stay alive off-screen,
/// speech needs the microphone. Configuring it twice — or letting either subsystem deactivate it
/// while the other is running — is how you get a PiP window that refuses to open or an audio
/// engine whose tap format silently goes stale.
///
/// So: one category, set once, and reference-counted activation. Nothing else in the codebase
/// touches `AVAudioSession`.
final class AudioSessionManager {

  static let shared = AudioSessionManager()

  private let session = AVAudioSession.sharedInstance()
  private var retainCount = 0
  private var configured = false
  private let queue = DispatchQueue(label: "sufler.audiosession")

  /// Fires when another app takes the microphone (Camera recording, a phone call, most video-call
  /// apps) and again when it gives it back. `shouldResume` is false when the system does not want
  /// us to restart on our own.
  var onInterruption: ((_ began: Bool, _ shouldResume: Bool) -> Void)?
  var onRouteChange: (() -> Void)?

  private init() {
    NotificationCenter.default.addObserver(
      self, selector: #selector(handleInterruption),
      name: AVAudioSession.interruptionNotification, object: session)
    NotificationCenter.default.addObserver(
      self, selector: #selector(handleRouteChange),
      name: AVAudioSession.routeChangeNotification, object: session)
  }

  // MARK: - Configuration

  /// `.playAndRecord` rather than `.record` because PiP's background eligibility is evaluated
  /// against a session that can play, and because switching category mid-flight invalidates a
  /// running `AVAudioEngine` tap.
  ///
  /// `.mixWithOthers` is not optional: without it, activating the session interrupts whatever the
  /// user was listening to. A teleprompter has no business stopping someone's music, and App
  /// Store reviewers do notice.
  ///
  /// Mode stays `.default` — `.measurement` disables AGC and noise suppression, which measurably
  /// hurts recognition at speakerphone distance, which is exactly how this app is used.
  private func configureIfNeeded() throws {
    guard !configured else { return }
    try session.setCategory(
      .playAndRecord,
      mode: .default,
      options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP])
    try? session.setPreferredSampleRate(48_000)
    try? session.setPreferredIOBufferDuration(0.02)
    configured = true
  }

  // MARK: - Reference-counted activation

  func retainSession() throws {
    try queue.sync {
      try configureIfNeeded()
      if retainCount == 0 {
        try session.setActive(true, options: [])
      }
      retainCount += 1
    }
  }

  /// Only the final release deactivates. `.notifyOthersOnDeactivation` lets a backgrounded music
  /// app resume instead of staying ducked.
  func releaseSession() {
    queue.sync {
      guard retainCount > 0 else { return }
      retainCount -= 1
      guard retainCount == 0 else { return }
      try? session.setActive(false, options: [.notifyOthersOnDeactivation])
    }
  }

  /// After an interruption the system has deactivated the session even though our reference count
  /// is unchanged. This forces it back on without disturbing the count.
  func reactivate() throws {
    try queue.sync {
      try configureIfNeeded()
      guard retainCount > 0 else { return }
      try session.setActive(true, options: [])
    }
  }

  var isActive: Bool { queue.sync { retainCount > 0 } }

  // MARK: - Notifications

  @objc private func handleInterruption(_ note: Notification) {
    guard let info = note.userInfo,
          let rawType = info[AVAudioSessionInterruptionTypeKey] as? UInt,
          let type = AVAudioSession.InterruptionType(rawValue: rawType)
    else { return }

    // These notifications arrive on an arbitrary queue, and every handler downstream touches
    // main-confined state (the audio engine, the render loop, the JS bridge).
    switch type {
    case .began:
      DispatchQueue.main.async { [weak self] in self?.onInterruption?(true, false) }
    case .ended:
      let rawOptions = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
      let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
      let shouldResume = options.contains(.shouldResume)
      DispatchQueue.main.async { [weak self] in self?.onInterruption?(false, shouldResume) }
    @unknown default:
      break
    }
  }

  /// A route change (AirPods connecting, for instance) changes the input node's hardware format.
  /// Any tap installed with the old format throws on the next buffer, so the engine has to be
  /// rebuilt — see `MicEngine.restart()`.
  @objc private func handleRouteChange(_ note: Notification) {
    guard let info = note.userInfo,
          let rawReason = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
          let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason)
    else { return }

    switch reason {
    case .newDeviceAvailable, .oldDeviceUnavailable, .override, .routeConfigurationChange:
      DispatchQueue.main.async { [weak self] in self?.onRouteChange?() }
    default:
      break
    }
  }
}
