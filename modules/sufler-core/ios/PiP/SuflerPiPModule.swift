import AVKit
import ExpoModulesCore

/// JS facade for the overlay.
///
/// Note what is *not* here: there is no per-frame or per-word call. The script is pushed once, the
/// style is pushed on change, and the cursor reaches the renderer natively through
/// `SuflerSession`. Anything at recognition rate that crossed this boundary would land on the JS
/// thread several times a second, competing with React.
public class SuflerPiPModule: Module {

  public func definition() -> ModuleDefinition {
    Name("SuflerPiP")

    Events("onPiPStateChanged", "onPiPPlaybackToggled", "onPiPError")

    Constant("isSupported") {
      AVPictureInPictureController.isPictureInPictureSupported()
    }

    OnCreate {
      SuflerSession.shared.pipModule = self
      SuflerSession.shared.pip.module = self
    }

    OnDestroy {
      // Fires on a Fast Refresh reload too. Tearing the overlay down here would kill a live PiP
      // window mid-development, so only detach the JS end.
      if SuflerSession.shared.pipModule === self { SuflerSession.shared.pipModule = nil }
    }

    AsyncFunction("setScript") { (lines: [String], startTokenIndex: Int) in
      SuflerSession.shared.loadScript(lines: lines, cursor: max(startTokenIndex, 0))
    }.runOnQueue(.main)

    AsyncFunction("setStyle") { (style: [String: Any]) in
      SuflerSession.shared.pip.applyStyle(PiPStyle(dictionary: style))
    }.runOnQueue(.main)

    /// Must be called from a user gesture. `startPictureInPicture()` is a silent no-op otherwise.
    ///
    /// `runOnQueue(.main)` puts this on the main queue but tells the compiler nothing, hence
    /// `assumeIsolated` rather than making the whole definition an actor-isolated context.
    AsyncFunction("startPictureInPicture") { () throws -> Bool in
      try MainActor.assumeIsolated {
        try SuflerSession.shared.pip.start()
      }
      return true
    }.runOnQueue(.main)

    AsyncFunction("stopPictureInPicture") {
      MainActor.assumeIsolated {
        SuflerSession.shared.pip.stop()
      }
    }.runOnQueue(.main)

    Function("isActive") { () -> Bool in
      SuflerSession.shared.pip.isActive
    }

    Function("isPossible") { () -> Bool in
      SuflerSession.shared.pip.isPossible
    }

    Function("getDiagnostics") { () -> [String: Any] in
      SuflerSession.shared.pip.diagnostics
    }

    Function("setCursor") { (tokenIndex: Int) in
      SuflerSession.shared.setCursor(tokenIndex)
    }

    OnAppEntersBackground {
      SuflerSession.shared.pip.appDidEnterBackground()
    }

    OnAppEntersForeground {
      SuflerSession.shared.pip.appWillEnterForeground()
    }

    View(PiPSourceView.self) {
      Events("onReady")
    }
  }

  // MARK: - Emitters used by PiPController

  func emitState(active: Bool, possible: Bool) {
    sendEvent("onPiPStateChanged", ["active": active, "possible": possible])
  }

  func emitPlaybackToggled(playing: Bool) {
    sendEvent("onPiPPlaybackToggled", ["playing": playing])
  }

  func emitError(code: String, message: String) {
    sendEvent("onPiPError", ["code": code, "message": message])
  }
}
