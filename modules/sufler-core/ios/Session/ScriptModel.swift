import Foundation

/// One word of the script, pre-normalised at load time so the aligner never does string work
/// on the hot path.
struct ScriptToken {
  let raw: String
  /// Every form this token is allowed to match — usually one, more for numbers.
  let forms: Set<String>
  /// Primary normalised form, kept as `[Character]` because Levenshtein needs random access.
  let chars: [Character]
  let lineIndex: Int
  /// Character range of `raw` inside its line, for word-level highlighting.
  let rangeInLine: Range<Int>
  let isFiller: Bool
}

/// The script as the aligner and the renderers see it: lines for display, a flat token array
/// for matching, and the mapping between them.
///
/// Immutable once loaded. `SuflerSession` replaces the whole instance when the user picks a
/// different script, which keeps concurrent readers safe without locking every field.
final class ScriptModel {

  private(set) var lines: [String] = []
  private(set) var tokens: [ScriptToken] = []
  /// `lineFirstToken[i]` is the index of the first token on line `i` (== next line's start when
  /// the line has no words, e.g. a blank paragraph separator).
  private(set) var lineFirstToken: [Int] = []

  var tokenCount: Int { tokens.count }
  var lineCount: Int { lines.count }
  var isEmpty: Bool { tokens.isEmpty }

  static let empty = ScriptModel()

  init() {}

  init(lines rawLines: [String]) {
    load(lines: rawLines)
  }

  private func load(lines rawLines: [String]) {
    lines = rawLines
    tokens.reserveCapacity(rawLines.reduce(0) { $0 + $1.count / 5 })
    lineFirstToken = []
    lineFirstToken.reserveCapacity(rawLines.count)

    for (lineIndex, line) in rawLines.enumerated() {
      lineFirstToken.append(tokens.count)

      let scalars = Array(line)
      var i = 0
      while i < scalars.count {
        // Skip separators.
        while i < scalars.count, scalars[i].isWhitespace { i += 1 }
        guard i < scalars.count else { break }

        let start = i
        while i < scalars.count, !scalars[i].isWhitespace { i += 1 }
        let raw = String(scalars[start..<i])

        let forms = TextNormalizer.forms(for: raw)
        guard let primary = forms.isEmpty ? nil : TextNormalizer.normalize(raw), !primary.isEmpty
        else { continue }  // pure punctuation, e.g. an em dash on its own

        tokens.append(ScriptToken(
          raw: raw,
          forms: forms,
          chars: Array(primary),
          lineIndex: lineIndex,
          rangeInLine: start..<i,
          isFiller: TextNormalizer.isFiller(primary)
        ))
      }
    }
  }

  // MARK: - Lookups

  func lineIndex(forToken index: Int) -> Int {
    guard !tokens.isEmpty else { return 0 }
    let clamped = min(max(index, 0), tokens.count - 1)
    return tokens[clamped].lineIndex
  }

  func indexInLine(forToken index: Int) -> Int {
    guard index >= 0, index < tokens.count else { return 0 }
    return index - lineFirstToken[tokens[index].lineIndex]
  }

  /// Words worth handing to `SFSpeechRecognitionRequest.contextualStrings`: rare, long, and
  /// coming up soon. Apple caps the list at 100 entries, and short common words only dilute it.
  func distinctiveWords(around cursor: Int, lookahead: Int, limit: Int) -> [String] {
    guard !tokens.isEmpty else { return [] }
    let start = min(max(cursor, 0), tokens.count)
    let end = min(start + lookahead, tokens.count)
    guard start < end else { return [] }

    var seen = Set<String>()
    var result: [String] = []
    for token in tokens[start..<end] {
      guard token.chars.count >= 6, !token.isFiller else { continue }
      let word = token.raw.trimmingCharacters(in: .punctuationCharacters)
      guard word.count >= 6, seen.insert(word.lowercased()).inserted else { continue }
      result.append(word)
      if result.count >= limit { break }
    }
    return result
  }

  /// The slice the aligner searches. Returns the absolute index the slice starts at, because
  /// the DP works in slice coordinates and has to translate back.
  func searchWindow(cursor: Int, back: Int, forward: Int) -> (start: Int, slice: ArraySlice<ScriptToken>) {
    guard !tokens.isEmpty else { return (0, tokens[0..<0]) }
    let start = max(0, min(cursor, tokens.count) - back)
    let end = min(tokens.count, max(cursor, 0) + forward)
    guard start < end else { return (start, tokens[start..<start]) }
    return (start, tokens[start..<end])
  }
}
