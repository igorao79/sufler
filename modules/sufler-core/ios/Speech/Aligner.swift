import Foundation

/// Where in the script the speaker currently is, decided from what the recogniser just heard.
///
/// This is the product. Everything else — PiP, the audio session, the store — is plumbing around
/// the question "which word are they on right now?".
///
/// The approach is a **local Needleman–Wunsch** of the recognised tail against a window of the
/// script. A sliding fixed-window dot product is the obvious first idea and it does not survive
/// contact with real speakers: the moment someone skips a word or the recogniser inserts one,
/// every subsequent position is off by one and the score collapses. Gap-aware alignment absorbs
/// exactly those two failures, which between them account for most of what actually goes wrong.
final class Aligner {

  struct Tuning {
    /// How many recognised words to match against. Longer is more robust but lags further behind.
    var hypothesisWindow = 7
    /// How far ahead of the cursor to search.
    var lookahead = 60
    /// How far behind — a speaker who repeats a phrase should be allowed to move back a little.
    var backtrack = 8
    /// Below this the match is treated as noise and the cursor holds.
    var acceptThreshold = 0.55
    /// Backward moves have to clear a much higher bar than forward ones.
    var backtrackThreshold = 0.80
    /// A forward jump larger than this needs a strong match, otherwise we creep.
    var maxJump = 25
    /// Silence longer than this reports `stalled` (it never advances the cursor — there is no
    /// constant-speed mode in this app by design).
    var stallTimeoutMs = 2500

    static let `default` = Tuning()
  }

  struct Decision {
    let cursor: Int
    let moved: Bool
    let confidence: Double
    /// Best and runner-up scores, surfaced to the debug strip so alignment failures are
    /// diagnosable in the field rather than by guesswork.
    let best: Double
    let runnerUp: Double
  }

  var tuning: Tuning = .default

  private(set) var cursor: Int = 0
  private var script: ScriptModel = .empty
  private var lastHypothesis: [String] = []

  /// After a long silence the speaker may have moved somewhere far away in their notes, so the
  /// next few matches search a much wider window before snapping back to the cheap one.
  private var wideSearchMatchesRemaining = 0

  // Gap costs. Skipping a *script* word is cheap — people paraphrase and cut lines constantly.
  // Skipping a *hypothesis* word is expensive: it means the recogniser produced something the
  // script does not contain, which is a weaker signal than a speaker trimming a sentence.
  private let gapScript = 0.25
  private let gapHypothesis = 0.55
  private let mismatchPenalty = 0.60

  // Prefer positions near the cursor, and prefer forward over backward. The asymmetry is what
  // keeps the cursor monotone in the common case without hard-forbidding a correction.
  private let driftForward = 0.004
  private let driftBackward = 0.030
  private let ambiguityMargin = 0.10

  // MARK: - Lifecycle

  func load(script: ScriptModel, cursor: Int) {
    self.script = script
    self.cursor = min(max(cursor, 0), max(script.tokenCount - 1, 0))
    lastHypothesis = []
    wideSearchMatchesRemaining = 0
  }

  func setCursor(_ index: Int) {
    cursor = min(max(index, 0), max(script.tokenCount - 1, 0))
    lastHypothesis = []
  }

  /// Called when the mic has been quiet for a while — widens the next few searches so a presenter
  /// who resumed further down the page is re-acquired instead of being dragged back.
  func noteLongSilence() {
    wideSearchMatchesRemaining = 3
  }

  // MARK: - The hot path

  /// `recognised` is the full normalised word list of the current partial transcription.
  /// Returns `nil` when there is nothing new worth acting on.
  func ingest(_ recognised: [String]) -> Decision? {
    guard !script.isEmpty else { return nil }

    let tail = Array(recognised.suffix(tuning.hypothesisWindow))
    let hypothesis = tail.filter { !TextNormalizer.isFiller($0) }

    // Two words is the minimum that can distinguish a position; one word matches everywhere.
    guard hypothesis.count >= 2 else { return nil }
    guard hypothesis != lastHypothesis else { return nil }
    lastHypothesis = hypothesis

    let back = wideSearchMatchesRemaining > 0 ? 40 : tuning.backtrack
    let forward = wideSearchMatchesRemaining > 0 ? 200 : tuning.lookahead
    if wideSearchMatchesRemaining > 0 { wideSearchMatchesRemaining -= 1 }

    let (windowStart, window) = script.searchWindow(cursor: cursor, back: back, forward: forward)
    guard !window.isEmpty else { return nil }

    let scores = alignmentScores(hypothesis: hypothesis, window: window, windowStart: windowStart)
    guard let (bestIndex, best, runnerUp) = topTwo(scores) else { return nil }

    let matchedEnd = windowStart + bestIndex
    let decision = decide(matchedEnd: matchedEnd, best: best, runnerUp: runnerUp)
    return decision
  }

  // MARK: - DP

  /// Score of the best alignment of the whole hypothesis ending at each script position.
  ///
  /// Rows are hypothesis words (all must be consumed — we heard them, they happened); columns are
  /// script words. `D[0][j] = 0` for every `j` gives a free start anywhere in the window, which is
  /// what makes this *local* rather than global alignment.
  private func alignmentScores(
    hypothesis: [String],
    window: ArraySlice<ScriptToken>,
    windowStart: Int
  ) -> [Double] {
    let m = hypothesis.count
    let w = window.count
    let tokens = Array(window)
    let hypothesisChars = hypothesis.map { Array($0) }

    var previous = [Double](repeating: 0, count: w + 1)
    var current = [Double](repeating: 0, count: w + 1)

    for i in 1...m {
      current[0] = -gapHypothesis * Double(i)
      for j in 1...w {
        let s = similarity(hypothesis[i - 1], hypothesisChars[i - 1], tokens[j - 1])
        let align = previous[j - 1] + (s > 0 ? s : -mismatchPenalty)
        let insertion = previous[j] - gapHypothesis   // recogniser produced a word not in the script
        let deletion = current[j - 1] - gapScript     // speaker skipped a script word
        current[j] = max(align, max(insertion, deletion))
      }
      swap(&previous, &current)
    }

    // `previous` now holds row m. Normalise by hypothesis length so scores are comparable
    // across different tail sizes, then bias by distance from the cursor.
    var scores = [Double](repeating: -.infinity, count: w)
    for j in 1...w {
      let raw = previous[j] / Double(m)
      let position = windowStart + j - 1
      let distance = cursor - position
      let bias = distance <= 0
        ? driftForward * Double(min(-distance, tuning.lookahead))
        : driftBackward * Double(distance)
      scores[j - 1] = raw - bias
    }
    return scores
  }

  /// 1.0 for an exact form match; a graded score for near-misses; 0 for "unrelated", which the
  /// DP then charges `mismatchPenalty` for.
  private func similarity(_ word: String, _ wordChars: [Character], _ token: ScriptToken) -> Double {
    if token.forms.contains(word) { return 1.0 }

    let distance = TextNormalizer.levenshtein(wordChars, token.chars)
    let longer = max(wordChars.count, token.chars.count)
    guard longer > 0 else { return 0 }

    let ratio = 1.0 - Double(distance) / Double(longer)
    if ratio >= 0.75 { return ratio }

    // Russian inflection: the stem survives, the ending does not. A shared prefix of four or more
    // characters is a much better signal than edit distance for "говорил" vs "говорит".
    if TextNormalizer.commonPrefixLength(wordChars, token.chars) >= 4 { return 0.60 }

    return 0
  }

  /// Best score plus the best score that is not adjacent to it. Adjacency is excluded because the
  /// two cells either side of the peak are always near-ties and say nothing about ambiguity — what
  /// matters is whether a *different part of the script* scores just as well.
  private func topTwo(_ scores: [Double]) -> (index: Int, best: Double, runnerUp: Double)? {
    guard !scores.isEmpty else { return nil }
    var bestIndex = 0
    var best = -Double.infinity
    for (i, s) in scores.enumerated() where s > best {
      best = s; bestIndex = i
    }
    guard best > -.infinity else { return nil }

    var runnerUp = -Double.infinity
    for (i, s) in scores.enumerated() where abs(i - bestIndex) > 3 {
      runnerUp = max(runnerUp, s)
    }
    return (bestIndex, best, runnerUp == -.infinity ? 0 : runnerUp)
  }

  // MARK: - Decision

  private func decide(matchedEnd: Int, best: Double, runnerUp: Double) -> Decision {
    func hold() -> Decision {
      Decision(cursor: cursor, moved: false, confidence: best, best: best, runnerUp: runnerUp)
    }

    // Too weak to mean anything.
    guard best >= tuning.acceptThreshold else { return hold() }

    // A repeated phrase — a chorus, a slogan, "итак" for the fifth time — scores the same in two
    // places. Holding is correct: the next couple of words will disambiguate, and guessing wrong
    // yanks the reader somewhere they are not.
    guard best - runnerUp >= ambiguityMargin else { return hold() }

    if matchedEnd < cursor {
      guard best >= tuning.backtrackThreshold else { return hold() }
      guard cursor - matchedEnd <= tuning.backtrack else { return hold() }
    }

    var target = matchedEnd + 1
    if target - cursor > tuning.maxJump {
      // Either they skipped a paragraph, or we matched the wrong place. Only a strong match earns
      // the jump; otherwise creep forward so a bad match cannot strand the reader.
      target = best > 0.80 ? target : cursor + 3
    }

    target = min(max(target, 0), max(script.tokenCount - 1, 0))
    let moved = target != cursor
    cursor = target
    return Decision(cursor: target, moved: moved, confidence: best, best: best, runnerUp: runnerUp)
  }
}
