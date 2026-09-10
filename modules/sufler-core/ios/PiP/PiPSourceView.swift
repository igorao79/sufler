import AVFoundation
import ExpoModulesCore
import UIKit

/// The on-screen home of the `AVSampleBufferDisplayLayer`.
///
/// Automatic Picture in Picture — the "press Start, then swipe to another app" flow that makes this
/// app work at all — requires the source layer to be in the key window's hierarchy, visible, and
/// non-degenerate in size. It is tempting to satisfy that with a 1×1 transparent view tucked into a
/// corner. Don't: it is fragile, it reads as a workaround, and it throws away something useful.
///
/// Instead this is a real 16:9 preview card on the prompter screen showing exactly the frames that
/// will float over other apps. The user sees what they are about to get, and — because the renderer
/// is visible without ever entering PiP — the whole frame pipeline stays debuggable in the
/// Simulator, where PiP itself does not exist.
final class PiPSourceView: ExpoView {

  private let displayLayer = AVSampleBufferDisplayLayer()

  let onReady = EventDispatcher()

  required init(appContext: AppContext? = nil) {
    super.init(appContext: appContext)
    backgroundColor = .black
    clipsToBounds = true
    layer.cornerRadius = 14
    layer.cornerCurve = .continuous

    displayLayer.videoGravity = .resizeAspect
    displayLayer.preventsDisplaySleepDuringVideoPlayback = true
    layer.addSublayer(displayLayer)
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    // Not animatable: the layer is not part of the UIKit animation hierarchy, and letting Core
    // Animation interpolate its frame makes the video content visibly lag the card during layout.
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    displayLayer.frame = bounds
    CATransaction.commit()
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window != nil {
      // The session owns the layer's lifecycle, not this view. Fabric recycles view instances, so
      // treating the view as the source of truth would tear PiP down at arbitrary moments.
      SuflerSession.shared.pip.bind(sourceView: self, layer: displayLayer)
      onReady(["ready": true])
    } else {
      SuflerSession.shared.pip.unbind(sourceView: self)
    }
  }
}
