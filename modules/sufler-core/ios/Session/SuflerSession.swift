import AVFoundation
import ExpoModulesCore
import Foundation
import Speech
import UIKit

struct PiPStyle {
  var fontSize: CGFloat = 34
  var mirrored: Bool = false
  var debugOverlay: Bool = false

  init() {}

  init(dictionary: [String: Any]) {
    if let value = dictionary["fontSize"] as? Double { fontSize = CGFloat(value) }
    if let value = dictionary["mirrored"] as? Bool { mirrored = value }
    if let value = dictionary["debugOverlay"] as? Bool { debugOverlay = value }
  }
}

/// The process-wide singleton that owns everything stateful.
///
/// Three JS-facing modules sit on top of this — PiP, speech, and the share inbox — and they need to
/// talk to each other constantly: the aligner pushes a cursor into the renderer several times a
/// second, and the PiP window's play button starts and stops the microphone. Routing that through
/// JavaScript would mean a native → JS → native round trip per recognised word, on the JS thread,
/// while React is rendering. So the coupling lives here, natively, and the modules are thin
/// facades over it.
///
/// It also survives Fast Refresh, which matters more than it sounds: a module reload during
/// development must not tear down a live PiP window.
final class SuflerSession {

  static let shared = SuflerSession()

  // MARK: - Owned state

  let positionBus = PositionBus()
  let pip = PiPController()
  private let aligner = Aligner()
  private let mic = MicEngine()
  private var backend: SpeechBackend?

  private(set) var script: ScriptModel = .empty
  private(set) var isFollowing = false

  /// Rendered into the PiP frame in place of the script when something has gone wrong that the
  /// user needs to know about — most often another app taking the microphone.
  private(set) var pipOverlayMessage: String?

  weak var pipModule: SuflerPiPModule?
  weak var speechModule: SuflerSpeechModule?

  private let alignQueue = DispatchQueue(label: "sufler.align", qos: .userInitiated)

  private var startOptions = SpeechStartOptions()
  private var lastVoiceAt: CFTimeInterval = 0
  private var stalled = false
  private var stallTimer: DispatchSourceTimer?
  private var interrupted = false
  private var lastDecision: Aligner.Decision?
  /// `aligner` is confined to `alignQueue`; the stall timer runs on main and needs this one value,
  /// so it is mirrored here rather than reaching across the queue boundary every half second.
  private var stallTimeoutSeconds: Double = Double(Aligner.Tuning.default.stallTimeoutMs) / 1000

  private init() {
    positionBus.onImmediateChange = { [weak self] _ in
      // Cheap and lock-free: just flip the renderer's dirty flag.
      self?.pip.markDirty()
    }
    positionBus.onThrottledChange = { [weak self] position in
      self?.speechModule?.emitPosition(position)
    }

    AudioSessionManager.shared.onInterruption = { [weak self] began, shouldResume in
      self?.handleInterruption(began: began, shouldResume: shouldResume)
    }
    AudioSessionManager.shared.onRouteChange = { [weak self] in
      self?.handleRouteChange()
    }
  }

  // MARK: - Script

  func loadScript(lines: [String], cursor: Int) {
    // The speech backend reads `script` from its own queue to refresh contextual strings, and
    // swapping it mid-sentence would be meaningless anyway — the cursor would point into a
    // different document.
    if isFollowing { stopFollowing() }

    let model = ScriptModel(lines: lines)
    script = model
    alignQueue.sync { aligner.load(script: model, cursor: cursor) }
    publishPosition(tokenIndex: cursor, confidence: 1)
    pip.markDirty(force: true)
  }

  func setCursor(_ tokenIndex: Int) {
    alignQueue.async { [weak self] in
      guard let self else { return }
      self.aligner.setCursor(tokenIndex)
      self.publishPosition(tokenIndex: self.aligner.cursor, confidence: 1)
    }
  }

  /// Used by the PiP window's skip buttons, when they are visible at all.
  func nudge(lines delta: Int) {
    guard !script.isEmpty else { return }
    let current = positionBus.position.lineIndex
    let target = min(max(current + delta, 0), max(script.lineCount - 1, 0))
    guard target < script.lineFirstToken.count else { return }
    setCursor(script.lineFirstToken[target])
  }

  private func publishPosition(tokenIndex: Int, confidence: Double) {
    let clamped = min(max(tokenIndex, 0), max(script.tokenCount - 1, 0))
    positionBus.commit(PositionBus.Position(
      tokenIndex: clamped,
      lineIndex: script.lineIndex(forToken: clamped),
      indexInLine: script.indexInLine(forToken: clamped),
      confidence: confidence))
  }

  // MARK: - Following

  func startFollowing(_ options: SpeechStartOptions) throws {
    guard !isFollowing else { return }
    guard !script.isEmpty else {
      throw NSError(domain: "sufler.session", code: 1, userInfo: [
        NSLocalizedDescriptionKey: "Load a script before starting."
      ])
    }

    startOptions = options
    if options.startTokenIndex >= 0 {
      alignQueue.sync { aligner.setCursor(options.startTokenIndex) }
      publishPosition(tokenIndex: options.startTokenIndex, confidence: 1)
    }

    try AudioSessionManager.shared.retainSession()

    let backend = SFSpeechBackend()
    backend.onHypothesis = { [weak self] words in
      self?.ingest(words)
    }
    backend.onError = { [weak self] error in
      self?.speechModule?.emitError(code: "speech_error", message: error.localizedDescription)
    }
    backend.onWantsContext = { [weak self] in
      guard let self else { return [] }
      return self.script.distinctiveWords(
        around: self.positionBus.position.tokenIndex, lookahead: 400, limit: 100)
    }

    let context = script.distinctiveWords(
      around: positionBus.position.tokenIndex, lookahead: 400, limit: 100)

    do {
      try backend.start(locale: options.locale,
                        preferOnDevice: options.preferOnDevice,
                        contextualStrings: context)
      mic.onBuffer = { [weak backend] buffer in backend?.append(buffer) }
      mic.onLevel = { [weak self] level in self?.noteLevel(level) }
      try mic.start()
    } catch {
      backend.stop()
      mic.stop()
      AudioSessionManager.shared.releaseSession()
      throw error
    }

    self.backend = backend
    isFollowing = true
    pipOverlayMessage = nil
    lastVoiceAt = CACurrentMediaTime()
    stalled = false
    startStallTimer()

    pip.invalidatePlaybackState()
    pip.markDirty(force: true)
    speechModule?.emitSpeechState("following")
  }

  func stopFollowing() {
    guard isFollowing else { return }
    isFollowing = false

    stallTimer?.cancel()
    stallTimer = nil
    mic.onBuffer = nil
    mic.onLevel = nil
    mic.stop()
    backend?.stop()
    backend = nil
    AudioSessionManager.shared.releaseSession()

    pipOverlayMessage = nil
    pip.invalidatePlaybackState()
    pip.markDirty(force: true)
    speechModule?.emitSpeechState("idle")
  }

  /// Entry point for the PiP window's play button, where there is no JS in the loop and no user
  /// interface to report an error into — so failures go out as an event and into the frame itself.
  func resumeFollowingFromPiP() {
    do {
      let options = startOptions
      options.startTokenIndex = -1  // keep the cursor where it is
      try startFollowing(options)
    } catch {
      pipOverlayMessage = error.localizedDescription
      pip.markDirty(force: true)
      speechModule?.emitError(code: "resume_failed", message: error.localizedDescription)
    }
  }

  // MARK: - Recognition plumbing

  private func ingest(_ words: [String]) {
    alignQueue.async { [weak self] in
      guard let self, self.isFollowing else { return }
      guard let decision = self.aligner.ingest(words) else { return }
      self.lastDecision = decision
      if decision.moved {
        self.publishPosition(tokenIndex: decision.cursor, confidence: decision.confidence)
      }
      if self.speechModule?.emitsTranscript == true {
        self.speechModule?.emitTranscript(words: words, decision: decision)
      }
    }
  }

  private func noteLevel(_ level: Float) {
    // A crude RMS gate. It only has to distinguish "someone is talking" from "nobody is", and it
    // runs on the audio thread, so anything more elaborate would be the wrong trade.
    guard level > 0.012 else { return }
    lastVoiceAt = CACurrentMediaTime()
    if stalled {
      stalled = false
      DispatchQueue.main.async { [weak self] in
        guard let self, self.isFollowing else { return }
        self.speechModule?.emitSpeechState("following")
      }
    }
  }

  private func startStallTimer() {
    let timer = DispatchSource.makeTimerSource(queue: .main)
    timer.schedule(deadline: .now() + 0.5, repeating: 0.5)
    timer.setEventHandler { [weak self] in
      guard let self, self.isFollowing, !self.interrupted else { return }
      let silence = CACurrentMediaTime() - self.lastVoiceAt
      let threshold = self.stallTimeoutSeconds

      if !self.stalled, silence > threshold {
        self.stalled = true
        self.speechModule?.emitSpeechState("stalled")
      }
      // A long pause usually means the speaker moved somewhere else in their notes. Widening the
      // next few searches re-acquires them; advancing on a timer would be a constant-speed
      // teleprompter, which is explicitly not what this app does.
      if self.stalled, silence > 8 {
        self.alignQueue.async { self.aligner.noteLongSilence() }
        self.lastVoiceAt = CACurrentMediaTime() - threshold
      }
    }
    timer.resume()
    stallTimer = timer
  }

  // MARK: - Audio session events

  /// The honest failure mode of this app. iPhone microphone input is exclusive: when the Camera
  /// starts recording, or a video call begins, we lose the mic and following stops. There is no
  /// workaround, so the frame says so instead of silently freezing.
  private func handleInterruption(began: Bool, shouldResume: Bool) {
    if began {
      interrupted = true
      mic.stop()
      pipOverlayMessage = "⏸ Микрофон занят другим приложением"
      pip.markDirty(force: true)
      pip.invalidatePlaybackState()
      speechModule?.emitSpeechState("interrupted")
      return
    }

    interrupted = false
    guard isFollowing, shouldResume else { return }
    do {
      // The system deactivated the session while our reference count was still held, so this is a
      // re-activation, not a new retain.
      try AudioSessionManager.shared.reactivate()
      try mic.start()
      pipOverlayMessage = nil
      lastVoiceAt = CACurrentMediaTime()
      pip.markDirty(force: true)
      speechModule?.emitSpeechState("following")
    } catch {
      pipOverlayMessage = "⏸ Не удалось вернуть микрофон"
      pip.markDirty(force: true)
      speechModule?.emitError(code: "resume_failed", message: error.localizedDescription)
    }
  }

  /// A new route means a new hardware format, which means the installed tap is now invalid. The
  /// engine has to be rebuilt — but the cursor is the aligner's, not the recogniser's, so nothing
  /// about the user's position is affected.
  private func handleRouteChange() {
    guard isFollowing, !interrupted else { return }
    mic.stop()
    do {
      try mic.start()
    } catch {
      speechModule?.emitError(code: "route_change_failed", message: error.localizedDescription)
    }
  }

  // MARK: - Diagnostics

  func debugSummary() -> String {
    let position = positionBus.position
    guard let decision = lastDecision else {
      return "t\(position.tokenIndex) l\(position.lineIndex)"
    }
    return String(format: "t%d l%d  best %.2f  run %.2f",
                  position.tokenIndex, position.lineIndex, decision.best, decision.runnerUp)
  }

  var lastAlignerDecision: Aligner.Decision? { lastDecision }

  func setTuning(_ tuning: Aligner.Tuning) {
    stallTimeoutSeconds = Double(tuning.stallTimeoutMs) / 1000
    alignQueue.async { [weak self] in self?.aligner.tuning = tuning }
  }
}
