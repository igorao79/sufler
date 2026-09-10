import AVFoundation
import ExpoModulesCore
import Speech

struct SpeechStartOptions: Record {
  @Field var locale: String = "ru-RU"
  @Field var preferOnDevice: Bool = true
  /// `-1` means "keep the current cursor" — used when the PiP window's play button resumes.
  @Field var startTokenIndex: Int = 0
}

struct SpeechTuningOptions: Record {
  @Field var hypothesisWindow: Int = 7
  @Field var lookahead: Int = 60
  @Field var backtrack: Int = 8
  @Field var acceptThreshold: Double = 0.55
  @Field var backtrackThreshold: Double = 0.80
  @Field var maxJump: Int = 25
  @Field var stallTimeoutMs: Int = 2500

  func toAlignerTuning() -> Aligner.Tuning {
    var tuning = Aligner.Tuning()
    tuning.hypothesisWindow = max(2, min(hypothesisWindow, 16))
    tuning.lookahead = max(10, min(lookahead, 500))
    tuning.backtrack = max(0, min(backtrack, 100))
    tuning.acceptThreshold = min(max(acceptThreshold, 0), 1)
    tuning.backtrackThreshold = min(max(backtrackThreshold, 0), 1)
    tuning.maxJump = max(1, min(maxJump, 200))
    tuning.stallTimeoutMs = max(300, min(stallTimeoutMs, 20_000))
    return tuning
  }
}

/// JS facade for speech-following.
public class SuflerSpeechModule: Module {

  /// `onTranscript` carries the raw hypothesis and the aligner's scores for the debug strip. It is
  /// noisy, so it is only produced while something is actually listening for it.
  private(set) var emitsTranscript = false

  public func definition() -> ModuleDefinition {
    Name("SuflerSpeech")

    Events("onPosition", "onTranscript", "onSpeechState", "onSpeechError")

    OnCreate { SuflerSession.shared.speechModule = self }
    OnDestroy {
      if SuflerSession.shared.speechModule === self { SuflerSession.shared.speechModule = nil }
    }

    AsyncFunction("requestPermissions") { (promise: Promise) in
      SFSpeechRecognizer.requestAuthorization { speechStatus in
        AVAudioApplication.requestRecordPermission { micGranted in
          promise.resolve([
            "speech": Self.describe(speechStatus),
            "mic": micGranted ? "granted" : "denied",
          ])
        }
      }
    }

    Function("getPermissions") { () -> [String: String] in
      [
        "speech": Self.describe(SFSpeechRecognizer.authorizationStatus()),
        "mic": Self.describe(AVAudioApplication.shared.recordPermission),
      ]
    }

    Function("supportedLocales") { () -> [String] in
      SFSpeechBackend.supportedLocales()
    }

    Function("isOnDeviceAvailable") { (locale: String) -> Bool in
      SFSpeechBackend.supportsOnDevice(locale: locale)
    }

    AsyncFunction("start") { (options: SpeechStartOptions) in
      try await SuflerSession.shared.startFollowing(options)
    }

    AsyncFunction("stop") {
      SuflerSession.shared.stopFollowing()
    }.runOnQueue(.main)

    Function("setTuning") { (options: SpeechTuningOptions) in
      SuflerSession.shared.setTuning(options.toAlignerTuning())
    }

    Function("setPositionEventHz") { (hz: Double) in
      SuflerSession.shared.positionBus.jsThrottleHz = hz
    }

    OnStartObserving("onTranscript") { self.emitsTranscript = true }
    OnStopObserving("onTranscript") { self.emitsTranscript = false }
  }

  // MARK: - Emitters used by SuflerSession

  func emitPosition(_ position: PositionBus.Position) {
    sendEvent("onPosition", [
      "tokenIndex": position.tokenIndex,
      "lineIndex": position.lineIndex,
      "indexInLine": position.indexInLine,
      "confidence": position.confidence,
    ])
  }

  func emitTranscript(words: [String], decision: Aligner.Decision) {
    sendEvent("onTranscript", [
      "words": Array(words.suffix(12)),
      "cursor": decision.cursor,
      "moved": decision.moved,
      "best": decision.best,
      "runnerUp": decision.runnerUp,
    ])
  }

  func emitSpeechState(_ state: String) {
    sendEvent("onSpeechState", ["state": state])
  }

  func emitError(code: String, message: String) {
    sendEvent("onSpeechError", ["code": code, "message": message])
  }

  // MARK: - Permission mapping

  private static func describe(_ status: SFSpeechRecognizerAuthorizationStatus) -> String {
    switch status {
    case .authorized: return "granted"
    case .denied: return "denied"
    case .restricted: return "restricted"
    case .notDetermined: return "undetermined"
    @unknown default: return "undetermined"
    }
  }

  private static func describe(_ permission: AVAudioApplication.recordPermission) -> String {
    switch permission {
    case .granted: return "granted"
    case .denied: return "denied"
    case .undetermined: return "undetermined"
    @unknown default: return "undetermined"
    }
  }
}
