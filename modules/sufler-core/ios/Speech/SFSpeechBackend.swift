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
  var onWantsContext: (() -> [String])?

  private var recognizer: SFSpeechRecognizer?
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var task: SFSpeechRecognitionTask?

  private var locale = "ru-RU"
  private var preferOnDevice = true
  private var usingOnDevice = false
  private var requestStartedAt: CFTimeInterval = 0
  private var consumedWordCount = 0
  private var isRunning = false

  private let queue = DispatchQueue(label: "sufler.speech.sf")

  /// Server recognition rejects requests longer than about a minute; on-device has no hard cap but
  /// its cumulative transcript grows without bound, which slowly makes every partial result more
  /// expensive to process. Both get rotated, just on different clocks.
  private var maxRequestDuration: CFTimeInterval { usingOnDevice ? 240 : 50 }
  private let maxConsumedWords = 400

  // MARK: - SpeechBackend

  func start(locale: String, preferOnDevice: Bool, contextualStrings: [String]) throws {
    self.locale = locale
    self.preferOnDevice = preferOnDevice

    guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)) else {
      throw SpeechBackendError.localeUnsupported(locale)
    }
    guard recognizer.isAvailable else { throw SpeechBackendError.recognizerUnavailable }

    recognizer.defaultTaskHint = .dictation
    self.recognizer = recognizer
    isRunning = true
    try beginRequest(contextualStrings: contextualStrings)
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
      self.teardownRequest()
      self.recognizer = nil
    }
  }

  // MARK: - Request lifecycle

  private func beginRequest(contextualStrings: [String]) throws {
    guard let recognizer else { throw SpeechBackendError.recognizerUnavailable }

    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = true
    request.taskHint = .dictation
    // We strip punctuation during normalisation anyway, and asking for it makes the recogniser
    // hold words back while it decides where the sentence ends — which is latency we cannot spend.
    request.addsPunctuation = false

    usingOnDevice = preferOnDevice && recognizer.supportsOnDeviceRecognition
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
          // 203 (retry), 216 / 301 (cancellation from our own teardown) and 1110 (no speech) are
          // routine during a long session — rotate rather than surfacing them as failures.
          let code = (error as NSError).code
          let routine = [203, 216, 301, 1110]
          if routine.contains(code) {
            self.rotate()
          } else {
            self.onError?(error)
            self.rotate()
          }
        }
      }
    }
  }

  /// Tear down and rebuild. Must be called on `queue`.
  private func rotate() {
    guard isRunning else { return }
    teardownRequest()
    let context = onWantsContext?() ?? []
    do {
      try beginRequest(contextualStrings: context)
    } catch {
      onError?(error)
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
