import AVFoundation
import Foundation

/// Microphone capture: an `AVAudioEngine` input tap that feeds the recogniser, plus a very cheap
/// RMS voice-activity signal used to detect that the speaker has stopped.
///
/// The subtlety worth knowing: the tap must be installed with the input node's *hardware* format.
/// When the route changes — AirPods connect, the user plugs in a headset — that format changes and
/// the existing tap starts throwing on the next buffer. There is no way to update a tap in place,
/// so the whole engine gets rebuilt. `SuflerSession` drives that from the route-change callback.
final class MicEngine {

  /// Delivered on the audio thread. Keep the handler to `request.append` and arithmetic.
  var onBuffer: ((AVAudioPCMBuffer) -> Void)?
  /// Root-mean-square level of the last buffer, 0...1-ish. Also on the audio thread.
  var onLevel: ((Float) -> Void)?

  private var engine: AVAudioEngine?
  private(set) var isRunning = false

  func start() throws {
    stop()

    let engine = AVAudioEngine()
    let input = engine.inputNode
    let format = input.outputFormat(forBus: 0)

    // A zero sample rate means the session has no usable input route yet — starting the engine
    // here throws an opaque -10851, so fail with something legible instead.
    guard format.sampleRate > 0 else {
      throw NSError(domain: "sufler.mic", code: -1, userInfo: [
        NSLocalizedDescriptionKey: "No microphone input route is available."
      ])
    }

    input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
      guard let self else { return }
      self.onBuffer?(buffer)
      if let level = Self.rms(of: buffer) { self.onLevel?(level) }
    }

    engine.prepare()
    try engine.start()

    self.engine = engine
    isRunning = true
  }

  func stop() {
    guard let engine else { return }
    engine.inputNode.removeTap(onBus: 0)
    engine.stop()
    self.engine = nil
    isRunning = false
  }

  private static func rms(of buffer: AVAudioPCMBuffer) -> Float? {
    guard let channel = buffer.floatChannelData?[0] else { return nil }
    let count = Int(buffer.frameLength)
    guard count > 0 else { return nil }

    var sum: Float = 0
    for i in 0..<count {
      let sample = channel[i]
      sum += sample * sample
    }
    return (sum / Float(count)).squareRoot()
  }
}
