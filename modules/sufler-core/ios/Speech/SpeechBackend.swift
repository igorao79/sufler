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
  /// The backend has given up and stopped itself. The session must stop following — otherwise the
  /// UI keeps claiming it is listening while nothing is.
  var onFatalError: ((Error) -> Void)? { get set }
  /// Fires when the backend has rotated its underlying request and would like fresh vocabulary.
  var onWantsContext: (() -> [String])? { get set }
  /// On-device recognition turned out to be unusable and the backend switched to Apple's servers.
  /// The user asked for on-device, so they have to be told that audio now leaves the device.
  var onFellBackToServer: (() -> Void)? { get set }

  /// Async because recogniser availability is resolved off-thread — see `SFSpeechBackend.start`.
  func start(locale: String, preferOnDevice: Bool, contextualStrings: [String]) async throws
  func append(_ buffer: AVAudioPCMBuffer)
  func stop()
}

/// These reach the user verbatim on the prompter screen, so they are written in the app's
/// language and say what to actually do about it.
enum SpeechBackendError: LocalizedError {
  case localeUnsupported(String)
  case notAuthorized
  case recognizerUnavailable(locale: String, onDeviceSupported: Bool)

  var errorDescription: String? {
    switch self {
    case .localeUnsupported(let locale):
      return "Распознавание речи не поддерживает язык \(locale). Выберите другой в настройках."
    case .notAuthorized:
      return "Нет доступа к распознаванию речи. Разрешите его в Настройках iOS → Sufler."
    case .recognizerUnavailable(let locale, _):
      // Reached only after the on-device fallback has already been tried, so the hint names both
      // remaining causes instead of guessing at one.
      return """
        Не удалось запустить распознавание речи для \(locale). Проверьте интернет — облачному         режиму нужна сеть. Если сеть есть, установите языковую модель: Настройки iOS → Основные         → Клавиатура → Диктовка.
        """
    }
  }
}
