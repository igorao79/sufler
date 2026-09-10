import AVFoundation
import Foundation

/// What a recogniser has to provide the aligner: a stream of "here is what I have heard so far".
///
/// The abstraction exists because `SFSpeechRecognizer` is soft-deprecated as of iOS 26 in favour
/// of `SpeechAnalyzer`/`SpeechTranscriber`, and because the aligner genuinely does not care which
/// one produced the words. Keeping the seam from the first commit costs nothing now and avoids a
/// rewrite of the only interesting file in the project later.
protocol SpeechBackend: AnyObject {

  /// Normalised words of the current hypothesis, oldest first. Called on an arbitrary queue.
  var onHypothesis: (([String]) -> Void)? { get set }
  var onError: ((Error) -> Void)? { get set }
  /// Fires when the backend has rotated its underlying request and would like fresh vocabulary.
  var onWantsContext: (() -> [String])? { get set }

  func start(locale: String, preferOnDevice: Bool, contextualStrings: [String]) throws
  func append(_ buffer: AVAudioPCMBuffer)
  func stop()
}

enum SpeechBackendError: LocalizedError {
  case localeUnsupported(String)
  case notAuthorized
  case recognizerUnavailable

  var errorDescription: String? {
    switch self {
    case .localeUnsupported(let locale):
      return "Speech recognition is not available for locale \(locale)."
    case .notAuthorized:
      return "Speech recognition or microphone access was not granted."
    case .recognizerUnavailable:
      return "The speech recogniser is temporarily unavailable."
    }
  }
}
