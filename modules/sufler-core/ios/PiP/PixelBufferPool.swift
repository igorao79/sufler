import CoreMedia
import CoreVideo
import Foundation

/// A `CVPixelBufferPool` sized to the current PiP render size.
///
/// Allocating a pixel buffer per frame is the easy way to write this and it shows up immediately
/// as jank plus a sawtooth memory graph. The pool is rebuilt only when the system tells us the
/// render size changed, which happens when the user resizes the PiP window — three sizes, a few
/// times per session.
final class PixelBufferPool {

  private(set) var pool: CVPixelBufferPool?
  private(set) var size: CGSize = .zero
  private(set) var formatDescription: CMFormatDescription?

  /// Returns true when the pool was actually rebuilt.
  @discardableResult
  func reconfigure(to newSize: CGSize) -> Bool {
    let rounded = CGSize(width: newSize.width.rounded(), height: newSize.height.rounded())
    guard rounded != size, rounded.width >= 16, rounded.height >= 16 else { return false }

    let attributes: [CFString: Any] = [
      kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
      kCVPixelBufferWidthKey: Int(rounded.width),
      kCVPixelBufferHeightKey: Int(rounded.height),
      // Without an IOSurface backing, `AVSampleBufferDisplayLayer` accepts the buffer and renders
      // nothing. This one line is the single most common cause of a black PiP window.
      kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
      kCVPixelBufferCGBitmapContextCompatibilityKey: true,
      kCVPixelBufferCGImageCompatibilityKey: true,
      kCVPixelBufferBytesPerRowAlignmentKey: 64,
    ]

    var created: CVPixelBufferPool?
    let status = CVPixelBufferPoolCreate(
      kCFAllocatorDefault,
      [kCVPixelBufferPoolMinimumBufferCountKey: 3] as CFDictionary,
      attributes as CFDictionary,
      &created)

    guard status == kCVReturnSuccess, let created else { return false }

    pool = created
    size = rounded
    formatDescription = nil  // rebuilt lazily from the next buffer
    return true
  }

  func makePixelBuffer() -> CVPixelBuffer? {
    guard let pool else { return nil }
    var buffer: CVPixelBuffer?
    guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer) == kCVReturnSuccess
    else { return nil }
    return buffer
  }

  func formatDescription(for buffer: CVPixelBuffer) -> CMFormatDescription? {
    if let formatDescription { return formatDescription }
    var created: CMFormatDescription?
    CMVideoFormatDescriptionCreateForImageBuffer(
      allocator: kCFAllocatorDefault, imageBuffer: buffer, formatDescriptionOut: &created)
    formatDescription = created
    return created
  }

  func invalidateFormatDescription() {
    formatDescription = nil
  }
}
