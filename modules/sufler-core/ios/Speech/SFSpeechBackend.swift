import AVFoundation
import Foundation
import Speech

/// `SFSpeechRecognizer` driving the aligner.
///
/// The important design decision is that this class is **stateless from the aligner's point of
/// view**. It never owns a position; it only ever answers "what have I heard lately". That is what
/// makes the mandatory rolling restart harmless: server-side recognition caps a single request at
/// roughly a minute, on-device drifts and accumulates, and errors happen — so the request is torn
/// down and rebuilt regularly, and because the cursor lives in `Aligner`, nothing is lost when it
/// happens mid-sentence.
final class SFSpeechBackend: NSObject, SpeechBackend {

  var onHypothesis: (([String]) -> Void)?
  var onError: ((Error) -> Void)?
  var onFatalError: ((Error) -> Void)?
  var onWantsContext: (() -> [String])?
  var onFellBackToServer: (() -> Void)?

  private var recognizer: SFSpeechRecognizer?
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var task: SFSpeechRecognitionTask?

  private var locale = "ru-RU"
  private var preferOnDevice = true
  private var usingOnDevice = false
  /// `supportsOnDeviceRecognition` reports capability, not installation: it returns true for a
  /// locale whose model has never been downloaded, and every request then fails instantly with
  /// kLSRErrorDomain. Once that happens there is no point asking again this session.
  private var onDeviceUnusable = false
  private var requestStartedAt: CFTimeInterval = 0
  private var consumedWordCount = 0
  private var isRunning = false

  private let queue = DispatchQueue(label: "sufler.speech.sf")

  /// A recogniser that keeps failing must not be rebuilt in a tight loop: each rotation is a new
  /// task, and an unavailable service would otherwise spin one up every few milliseconds for as
  /// long as the user leaves the screen open.
  private var recentRotations: [CFTimeInterval] = []
  private let rotationBurstLimit = 15
  private let rotationBurstWindow: CFTimeInterval = 60
  /// A failed task must not be rebuilt instantly. Without this the loop is bounded only by how
  /// fast the service can reject us, which on a machine with no usable audio input is very fast.
  private let restartDelayAfterFailure: TimeInterval = 0.4

  /// Server recognition rejects requests longer than about a minute; on-device has no hard cap but
  /// its cumulative transcript grows without bound, which slowly makes every partial result more
  /// expensive to process. Both get rotated, just on different clocks.
  private var maxRequestDuration: CFTimeInterval { usingOnDevice ? 240 : 50 }
  private let maxConsumedWords = 400

  // MARK: - SpeechBackend

  func start(locale: String, preferOnDevice: Bool, contextualStrings: [String]) async throws {
    self.locale = locale
    self.preferOnDevice = preferOnDevice

    guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
      throw SpeechBackendError.notAuthorized
    }
    guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)) else {
      throw SpeechBackendError.localeUnsupported(locale)
    }

    recognizer.defaultTaskHint = .dictation
    self.recognizer = recognizer

    // `isAvailable` is resolved asynchronously, off the calling thread. Reading it synchronously
    // right after `init` routinely returns false even when the service is perfectly healthy —
    // treating that as a hard failure is why pressing Start used to report "temporarily
    // unavailable" on a working device. Give it a moment to settle before believing it.
    if !recognizer.isAvailable {
      let available = await waitForAvailability(of: recognizer, timeout: 5)
      guard available else {
        throw SpeechBackendError.recognizerUnavailable(
          locale: locale, onDeviceSupported: recognizer.supportsOnDeviceRecognition)
      }
    }

    isRunning = true
    try beginRequest(contextualStrings: contextualStrings)
  }

  /// Polls rather than waiting on `SFSpeechRecognizerDelegate`. The delegate fires only on a
  /// *change*, so a recogniser that is already available by the time the observer is installed
  /// never calls back — a continuation waiting on it would hang until the timeout on the happy
  /// path. Thirty-odd checks, only ever at start, is the cheaper correctness.
  private func waitForAvailability(of recognizer: SFSpeechRecognizer, timeout: TimeInterval) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if recognizer.isAvailable { return true }
      try? await Task.sleep(nanoseconds: 150_000_000)
    }
    return recognizer.isAvailable
  }

  func append(_ buffer: AVAudioPCMBuffer) {
    // Called from the audio tap's real-time thread: append and get out. Everything expensive —
    // rotation checks, alignment — happens elsewhere.
    queue.async { [weak self] in
      guard let self, self.isRunning else { return }
      self.request?.append(buffer)
      if CACurrentMediaTime() - self.requestStartedAt > self.maxRequestDuration {
        self.rotate()
      }
    }
  }

  func stop() {
    queue.async { [weak self] in
      guard let self else { return }
      self.isRunning = false
      self.recentRotations.removeAll()
      self.onDeviceUnusable = false
      self.teardownRequest()
      self.recognizer = nil
    }
  }

  // MARK: - Request lifecycle

  private func beginRequest(contextualStrings: [String]) throws {
    guard let recognizer else {
      throw SpeechBackendError.recognizerUnavailable(locale: locale, onDeviceSupported: false)
    }

    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = true
    request.taskHint = .dictation
    // We strip punctuation during normalisation anyway, and asking for it makes the recogniser
    // hold words back while it decides where the sentence ends — which is latency we cannot spend.
    request.addsPunctuation = false

    usingOnDevice = preferOnDevice && !onDeviceUnusable && recognizer.supportsOnDeviceRecognition
    request.requiresOnDeviceRecognition = usingOnDevice

    // The cheapest accuracy win available: names, jargon and rare words from the part of the
    // script the speaker is about to reach. Apple caps this at 100 entries.
    if !contextualStrings.isEmpty {
      request.contextualStrings = Array(contextualStrings.prefix(100))
    }

    self.request = request
    requestStartedAt = CACurrentMediaTime()
    consumedWordCount = 0

    task = recognizer.recognitionTask(with: request) { [weak self] result, error in
      guard let self else { return }
      self.queue.async {
        guard self.isRunning else { return }

        if let result {
          let words = result.bestTranscription.formattedString
            .split(whereSeparator: { $0.isWhitespace })
            .map { TextNormalizer.normalize(String($0)) }
            .filter { !$0.isEmpty }

          self.consumedWordCount = words.count
          if !words.isEmpty { self.onHypothesis?(words) }

          if result.isFinal || words.count > self.maxConsumedWords {
            self.rotate()
            return
          }
        }

        if let error {
          // Speech failures are invisible from the outside — the app just stops following — so the
          // underlying domain and code go to the system log. `log stream --predicate 'eventMessage
          // CONTAINS "[Sufler]"'` is the fastest way to see why following died on a device.
          let nsError = error as NSError
          NSLog("[Sufler] recognition task ended: %@ %ld", nsError.domain, nsError.code)

          // The on-device model is missing. Falling back to the servers is the difference between
          // a teleprompter that works and one that does nothing at all — but it also means audio
          // starts leaving the device, which the user explicitly opted out of, so say so.
          if self.usingOnDevice, nsError.domain == "kLSRErrorDomain" {
            NSLog("[Sufler] on-device model unavailable for %@ — falling back to server recognition",
                  self.locale)
            self.onDeviceUnusable = true
            // This failure has a fix, so it must not count toward giving up.
            self.recentRotations.removeAll()
            self.onFellBackToServer?()
            self.rotate()
            return
          }

          // 203 (retry), 216 / 301 (cancellation from our own teardown) and 1110 (no speech) are
          // routine during a long session — rotate rather than surfacing them as failures.
          let routine = [203, 216, 301, 1110]
          if !routine.contains(nsError.code) {
            self.onError?(error)
          }
          self.rotate(afterFailure: true)
        }
      }
    }
  }

  /// Tear down and rebuild. Must be called on `queue`.
  private func rotate(afterFailure: Bool = false) {
    guard isRunning else { return }

    let now = CACurrentMediaTime()
    recentRotations.append(now)
    recentRotations.removeAll { now - $0 > rotationBurstWindow }
    if recentRotations.count > rotationBurstLimit {
      // Rebuilding is not going to fix whatever this is. Stop for real and tell the session, so
      // the UI stops claiming it is listening.
      isRunning = false
      teardownRequest()
      NSLog("[Sufler] giving up: %d recognition restarts in %.0fs",
            recentRotations.count, rotationBurstWindow)
      onFatalError?(SpeechBackendError.recognizerUnavailable(
        locale: locale, onDeviceSupported: recognizer?.supportsOnDeviceRecognition ?? false))
      return
    }

    teardownRequest()

    let restart = { [weak self] in
      guard let self, self.isRunning else { return }
      do {
        try self.beginRequest(contextualStrings: self.onWantsContext?() ?? [])
      } catch {
        self.onError?(error)
      }
    }

    if afterFailure {
      queue.asyncAfter(deadline: .now() + restartDelayAfterFailure, execute: restart)
    } else {
      restart()
    }
  }

  private func teardownRequest() {
    request?.endAudio()
    task?.cancel()
    task = nil
    request = nil
  }

  // MARK: - Capabilities

  static func supportsOnDevice(locale: String) -> Bool {
    SFSpeechRecognizer(locale: Locale(identifier: locale))?.supportsOnDeviceRecognition ?? false
  }

  static func supportedLocales() -> [String] {
    SFSpeechRecognizer.supportedLocales().map(\.identifier).sorted()
  }
}
