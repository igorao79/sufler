import CoreGraphics
import CoreVideo
import UIKit

/// Everything the renderer needs to draw one frame. Value type on purpose: it is snapshotted on
/// the main thread and handed to the draw call, so nothing can mutate underneath it.
struct FrameModel {
  var lines: [String] = []
  var currentLineIndex: Int = 0
  /// Character range of the active word inside its line, for the highlight box.
  var activeWordRange: Range<Int>? = nil
  var progress: Double = 0
  var mirrored: Bool = false
  var fontSize: CGFloat = 34
  /// Replaces the script entirely — used for "the microphone is busy" and similar states, which
  /// is exactly the kind of thing a custom PiP renderer is for.
  var overlayMessage: String? = nil
  var debugText: String? = nil
}

/// Draws the teleprompter into a `CVPixelBuffer`.
///
/// Drawing goes straight into the pixel buffer's base address through a `CGContext`. The obvious
/// alternative — render a `UIView` into a `UIImage`, then blit the `CGImage` — costs an extra
/// full-frame copy and a `CGImage` allocation every time, and buys nothing here because the frame
/// is a handful of text runs rather than a live view hierarchy.
enum TeleprompterFrameRenderer {

  static func render(_ model: FrameModel, into buffer: CVPixelBuffer) {
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

    guard let base = CVPixelBufferGetBaseAddress(buffer) else { return }
    let width = CVPixelBufferGetWidth(buffer)
    let height = CVPixelBufferGetHeight(buffer)
    let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)

    // `noneSkipFirst | byteOrder32Little` is how you spell BGRA to Core Graphics.
    guard let context = CGContext(
      data: base,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: bytesPerRow,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    ) else { return }

    let size = CGSize(width: width, height: height)

    // Core Graphics is bottom-left origin; UIKit text drawing assumes top-left.
    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: 1, y: -1)

    if model.mirrored {
      context.translateBy(x: CGFloat(width), y: 0)
      context.scaleBy(x: -1, y: 1)
    }

    UIGraphicsPushContext(context)
    defer { UIGraphicsPopContext() }

    UIColor.black.setFill()
    context.fill(CGRect(origin: .zero, size: size))

    if let message = model.overlayMessage {
      drawMessage(message, in: size)
    } else {
      drawScript(model, in: size)
    }

    drawProgress(model.progress, in: size)

    if let debug = model.debugText {
      drawDebug(debug, in: size)
    }
  }

  // MARK: - Script

  /// Three lines: what they just said, what they are saying, what comes next. The PiP window tops
  /// out at roughly a quarter of the screen, so anything more is unreadable at a glance — which is
  /// the only way this window is ever read.
  private static func drawScript(_ model: FrameModel, in size: CGSize) {
    let inset: CGFloat = size.width * 0.05
    let contentWidth = size.width - inset * 2
    let fontSize = model.fontSize * (size.width / 480)

    let previousFont = UIFont.systemFont(ofSize: fontSize * 0.72, weight: .regular)
    let currentFont = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
    let nextFont = UIFont.systemFont(ofSize: fontSize * 0.82, weight: .regular)

    let index = model.currentLineIndex
    let previous = line(model.lines, at: index - 1)
    let current = line(model.lines, at: index)
    let next = line(model.lines, at: index + 1)

    let currentHeight = boundingHeight(current, font: currentFont, width: contentWidth)
    let previousHeight = previous.isEmpty ? 0 : boundingHeight(previous, font: previousFont, width: contentWidth)
    let nextHeight = next.isEmpty ? 0 : boundingHeight(next, font: nextFont, width: contentWidth)

    let gap = fontSize * 0.35
    let total = previousHeight + currentHeight + nextHeight + gap * 2
    var y = max(inset * 0.6, (size.height - total) / 2)

    if !previous.isEmpty {
      draw(previous, font: previousFont, color: UIColor.white.withAlphaComponent(0.30),
           rect: CGRect(x: inset, y: y, width: contentWidth, height: previousHeight))
      y += previousHeight + gap
    }

    let currentRect = CGRect(x: inset, y: y, width: contentWidth, height: currentHeight)
    if let range = model.activeWordRange {
      drawActiveWordHighlight(current, range: range, font: currentFont, rect: currentRect)
    }
    draw(current, font: currentFont, color: .white, rect: currentRect)
    y += currentHeight + gap

    if !next.isEmpty {
      draw(next, font: nextFont, color: UIColor.white.withAlphaComponent(0.55),
           rect: CGRect(x: inset, y: y, width: contentWidth, height: nextHeight))
    }
  }

  /// A rounded box behind the word being spoken. Cheaper and far more legible at PiP sizes than
  /// recolouring the glyph run, and it survives the aggressive downscaling the system applies.
  private static func drawActiveWordHighlight(
    _ text: String, range: Range<Int>, font: UIFont, rect: CGRect
  ) {
    let characters = Array(text)
    guard range.lowerBound >= 0, range.upperBound <= characters.count,
          range.lowerBound < range.upperBound else { return }

    let attributes: [NSAttributedString.Key: Any] = [.font: font]
    let prefix = String(characters[0..<range.lowerBound])
    let word = String(characters[range.lowerBound..<range.upperBound])

    // Single-line measurement. Wrapped lines put the box in the wrong place; at three short lines
    // that is rare enough to accept, and a wrong-but-subtle box beats a per-frame layout pass.
    let prefixWidth = (prefix as NSString).size(withAttributes: attributes).width
    let wordSize = (word as NSString).size(withAttributes: attributes)
    guard prefixWidth + wordSize.width <= rect.width else { return }

    let padding: CGFloat = font.pointSize * 0.14
    let box = CGRect(
      x: rect.minX + prefixWidth - padding,
      y: rect.minY - padding * 0.4,
      width: wordSize.width + padding * 2,
      height: wordSize.height + padding * 0.8)

    UIColor(red: 1.0, green: 0.72, blue: 0.20, alpha: 0.28).setFill()
    UIBezierPath(roundedRect: box, cornerRadius: padding * 1.4).fill()
  }

  private static func drawMessage(_ message: String, in size: CGSize) {
    let font = UIFont.systemFont(ofSize: size.width / 20, weight: .medium)
    let inset = size.width * 0.08
    let width = size.width - inset * 2
    let height = boundingHeight(message, font: font, width: width)
    draw(message, font: font, color: UIColor.white.withAlphaComponent(0.85), alignment: .center,
         rect: CGRect(x: inset, y: (size.height - height) / 2, width: width, height: height))
  }

  private static func drawProgress(_ progress: Double, in size: CGSize) {
    let height: CGFloat = max(2, size.height * 0.012)
    let clamped = CGFloat(min(max(progress, 0), 1))

    UIColor.white.withAlphaComponent(0.12).setFill()
    UIBezierPath(rect: CGRect(x: 0, y: size.height - height, width: size.width, height: height)).fill()

    UIColor(red: 1.0, green: 0.72, blue: 0.20, alpha: 0.9).setFill()
    UIBezierPath(rect: CGRect(x: 0, y: size.height - height,
                              width: size.width * clamped, height: height)).fill()
  }

  private static func drawDebug(_ text: String, in size: CGSize) {
    let font = UIFont.monospacedSystemFont(ofSize: max(8, size.width / 46), weight: .regular)
    draw(text, font: font, color: UIColor.systemGreen.withAlphaComponent(0.9),
         rect: CGRect(x: 6, y: 4, width: size.width - 12, height: font.lineHeight * 2))
  }

  // MARK: - Text helpers

  private static func line(_ lines: [String], at index: Int) -> String {
    guard index >= 0, index < lines.count else { return "" }
    return lines[index]
  }

  private static func paragraphStyle(_ alignment: NSTextAlignment) -> NSParagraphStyle {
    let style = NSMutableParagraphStyle()
    style.alignment = alignment
    style.lineBreakMode = .byTruncatingTail
    return style
  }

  private static func boundingHeight(_ text: String, font: UIFont, width: CGFloat) -> CGFloat {
    guard !text.isEmpty else { return 0 }
    let rect = (text as NSString).boundingRect(
      with: CGSize(width: width, height: .greatestFiniteMagnitude),
      options: [.usesLineFragmentOrigin, .usesFontLeading],
      attributes: [.font: font],
      context: nil)
    return ceil(rect.height)
  }

  private static func draw(
    _ text: String, font: UIFont, color: UIColor,
    alignment: NSTextAlignment = .left, rect: CGRect
  ) {
    guard !text.isEmpty else { return }
    (text as NSString).draw(
      with: rect,
      options: [.usesLineFragmentOrigin, .usesFontLeading],
      attributes: [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: paragraphStyle(alignment),
      ],
      context: nil)
  }
}
