import Foundation

/// Turns raw words — from the script and from the recogniser — into the small set of
/// comparable forms the aligner matches on.
///
/// Everything here is deliberately cheap: it runs once per script token at load time and
/// once per recognised word at ~5–20 Hz, so it must not allocate more than it has to.
enum TextNormalizer {

  // MARK: - Fillers

  /// Words a speaker emits without meaning to. They carry no positional information, so the
  /// aligner drops them from the hypothesis rather than trying to match them.
  private static let fillers: Set<String> = [
    // ru
    "э", "ээ", "эм", "мм", "ну", "вот", "как", "бы", "типа", "значит", "короче",
    "это", "самое", "так", "вообще", "просто",
    // en
    "um", "uh", "er", "ah", "like", "you", "know", "so", "well", "actually", "basically",
  ]

  static func isFiller(_ normalized: String) -> Bool { fillers.contains(normalized) }

  // MARK: - Homoglyphs

  /// Latin letters that are visually identical to Cyrillic ones. Mixed-script text is common in
  /// pasted scripts, and the recogniser always produces one script consistently — folding both
  /// onto the Cyrillic side makes them comparable.
  private static let homoglyphs: [Character: Character] = [
    "e": "е", "o": "о", "a": "а", "p": "р", "c": "с", "x": "х", "y": "у",
    "k": "к", "m": "м", "t": "т", "h": "н", "b": "в",
  ]

  // MARK: - Core normalisation

  /// Lowercase, strip punctuation/symbols, fold `ё`→`е` and Latin homoglyphs onto Cyrillic.
  /// Returns an empty string for tokens that were pure punctuation.
  static func normalize(_ raw: String) -> String {
    var out = String.UnicodeScalarView()
    out.reserveCapacity(raw.unicodeScalars.count)

    for scalar in raw.lowercased().unicodeScalars {
      if CharacterSet.alphanumerics.contains(scalar) {
        out.append(scalar)
      }
      // Everything else — punctuation, symbols, whitespace — is dropped.
    }

    var s = String(String.UnicodeScalarView(out))
    s = s.replacingOccurrences(of: "ё", with: "е")

    // Only fold homoglyphs in tokens that already look Cyrillic-ish or are short Latin
    // fragments; folding a genuinely English word would destroy it.
    if s.contains(where: { $0.unicodeScalars.first.map { $0.value >= 0x0400 && $0.value <= 0x04FF } ?? false }) {
      s = String(s.map { homoglyphs[$0] ?? $0 })
    }
    return s
  }

  /// All forms a token is allowed to match against. Usually one; numbers produce several.
  static func forms(for raw: String) -> Set<String> {
    let base = normalize(raw)
    guard !base.isEmpty else { return [] }

    var result: Set<String> = [base]

    // "1990" → also accept each word of its spoken form, so a recogniser that spells the number
    // out still lands on this token. The DP absorbs the extra hypothesis words as insertions.
    if let value = Int(base), base.count <= 12 {
      for word in spellRU(value) { result.insert(word) }
      for word in spellEN(value) { result.insert(word) }
    } else if let value = numeralValue(base) {
      // "девяносто" → also accept "90", for the reverse case.
      result.insert(String(value))
    }

    return result
  }

  // MARK: - Numerals

  private static let ruNumerals: [String: Int] = [
    "ноль": 0, "один": 1, "одна": 1, "два": 2, "две": 2, "три": 3, "четыре": 4, "пять": 5,
    "шесть": 6, "семь": 7, "восемь": 8, "девять": 9, "десять": 10, "одиннадцать": 11,
    "двенадцать": 12, "тринадцать": 13, "четырнадцать": 14, "пятнадцать": 15,
    "шестнадцать": 16, "семнадцать": 17, "восемнадцать": 18, "девятнадцать": 19,
    "двадцать": 20, "тридцать": 30, "сорок": 40, "пятьдесят": 50, "шестьдесят": 60,
    "семьдесят": 70, "восемьдесят": 80, "девяносто": 90, "сто": 100, "двести": 200,
    "триста": 300, "четыреста": 400, "пятьсот": 500, "шестьсот": 600, "семьсот": 700,
    "восемьсот": 800, "девятьсот": 900, "тысяча": 1000, "тысячи": 1000, "тысяч": 1000,
    "миллион": 1_000_000, "миллиона": 1_000_000, "миллионов": 1_000_000,
  ]

  private static let enNumerals: [String: Int] = [
    "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
    "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13,
    "fourteen": 14, "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18,
    "nineteen": 19, "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60,
    "seventy": 70, "eighty": 80, "ninety": 90, "hundred": 100, "thousand": 1000,
    "million": 1_000_000,
  ]

  private static func numeralValue(_ word: String) -> Int? {
    ruNumerals[word] ?? enNumerals[word]
  }

  /// Russian spelling of an integer, as the sequence of words a speaker would say.
  /// Grammatically simplified (nominative masculine) — the aligner matches word-by-word and
  /// tolerates inflection through prefix scoring, so declension does not need to be exact.
  private static func spellRU(_ value: Int) -> [String] {
    guard value >= 0, value < 1_000_000_000 else { return [] }
    if value == 0 { return ["ноль"] }

    let units = ["", "один", "два", "три", "четыре", "пять", "шесть", "семь", "восемь", "девять"]
    let teens = ["десять", "одиннадцать", "двенадцать", "тринадцать", "четырнадцать",
                 "пятнадцать", "шестнадцать", "семнадцать", "восемнадцать", "девятнадцать"]
    let tens = ["", "", "двадцать", "тридцать", "сорок", "пятьдесят", "шестьдесят",
                "семьдесят", "восемьдесят", "девяносто"]
    let hundreds = ["", "сто", "двести", "триста", "четыреста", "пятьсот", "шестьсот",
                    "семьсот", "восемьсот", "девятьсот"]

    func under1000(_ n: Int) -> [String] {
      var words: [String] = []
      let h = n / 100, rest = n % 100
      if h > 0 { words.append(hundreds[h]) }
      if rest >= 10 && rest < 20 {
        words.append(teens[rest - 10])
      } else {
        let t = rest / 10, u = rest % 10
        if t > 0 { words.append(tens[t]) }
        if u > 0 { words.append(units[u]) }
      }
      return words
    }

    var words: [String] = []
    let millions = value / 1_000_000
    let thousands = (value / 1000) % 1000
    let remainder = value % 1000

    if millions > 0 { words += under1000(millions) + ["миллион"] }
    if thousands > 0 {
      // "одна тысяча" / "две тысячи" — the aligner is inflection-tolerant, keep it simple.
      words += under1000(thousands) + ["тысяча"]
    }
    if remainder > 0 { words += under1000(remainder) }
    return words
  }

  /// English spelling, same contract as `spellRU`.
  private static func spellEN(_ value: Int) -> [String] {
    guard value >= 0, value < 1_000_000_000 else { return [] }
    if value == 0 { return ["zero"] }

    let units = ["", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"]
    let teens = ["ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen",
                 "seventeen", "eighteen", "nineteen"]
    let tens = ["", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]

    func under1000(_ n: Int) -> [String] {
      var words: [String] = []
      let h = n / 100, rest = n % 100
      if h > 0 { words += [units[h], "hundred"] }
      if rest >= 10 && rest < 20 {
        words.append(teens[rest - 10])
      } else {
        let t = rest / 10, u = rest % 10
        if t > 0 { words.append(tens[t]) }
        if u > 0 { words.append(units[u]) }
      }
      return words
    }

    var words: [String] = []
    let millions = value / 1_000_000
    let thousands = (value / 1000) % 1000
    let remainder = value % 1000

    if millions > 0 { words += under1000(millions) + ["million"] }
    if thousands > 0 { words += under1000(thousands) + ["thousand"] }
    if remainder > 0 { words += under1000(remainder) }
    return words
  }

  // MARK: - Similarity primitives

  /// Levenshtein distance, iterative two-row form. Inputs here are single words, so the
  /// quadratic cost is irrelevant, but the allocation is not — hence the reused row buffers.
  static func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
    if a.isEmpty { return b.count }
    if b.isEmpty { return a.count }

    var previous = Array(0...b.count)
    var current = [Int](repeating: 0, count: b.count + 1)

    for i in 1...a.count {
      current[0] = i
      for j in 1...b.count {
        let cost = a[i - 1] == b[j - 1] ? 0 : 1
        current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
      }
      swap(&previous, &current)
    }
    return previous[b.count]
  }

  /// Length of the shared prefix — the cheap signal that catches Russian inflection
  /// ("говорил" / "говорит") without a morphological analyser.
  static func commonPrefixLength(_ a: [Character], _ b: [Character]) -> Int {
    var i = 0
    while i < a.count && i < b.count && a[i] == b[i] { i += 1 }
    return i
  }
}
