import Foundation

// A standalone check of the alignment algorithm — the one piece of this app whose correctness is
// not visible by looking at the screen.
//
// It lives outside `ios/` on purpose: the podspec globs `ios/**/*.swift` into the app target, and
// a file with top-level code would break that build. Run it with `scripts/check-aligner.sh`, which
// compiles it together with the three Foundation-only sources it depends on.
//
// Simulates a speaker working through a script and checks the cursor follows.
let scriptLines = [
  "Добрый день, коллеги.",
  "Сегодня я расскажу, как мы за три месяца",
  "сократили время сборки приложения с двадцати",
  "минут до четырёх.",
  "Начну с того, где именно мы теряли время.",
  "Первое узкое место было очевидным: полная",
  "пересборка нативных зависимостей на каждом коммите.",
  "Второе оказалось куда интереснее.",
  "Кеш работал, но промахивался почти всегда,",
  "потому что ключ включал timestamp.",
]

let script = ScriptModel(lines: scriptLines)
let aligner = Aligner()
aligner.load(script: script, cursor: 0)

func norm(_ s: String) -> [String] {
  s.split(whereSeparator: { $0.isWhitespace }).map { TextNormalizer.normalize(String($0)) }.filter { !$0.isEmpty }
}

struct Case { let label: String; let heard: String; let expectLineAtLeast: Int; let expectLineAtMost: Int }

let cases: [Case] = [
  // Read verbatim.
  .init(label: "дословно, начало", heard: "добрый день коллеги сегодня я расскажу", expectLineAtLeast: 1, expectLineAtMost: 2),
  // Filler words injected — must not throw the cursor off.
  .init(label: "с филлерами", heard: "ну как мы за три месяца сократили время сборки", expectLineAtLeast: 2, expectLineAtMost: 3),
  // Recogniser produced a digit where the script spells the number out.
  .init(label: "число цифрой", heard: "приложения с двадцати минут до четырёх", expectLineAtLeast: 3, expectLineAtMost: 4),
  // A word skipped by the speaker.
  .init(label: "пропуск слова", heard: "начну с того где мы теряли время", expectLineAtLeast: 4, expectLineAtMost: 5),
  // Inflection differs from the script.
  .init(label: "словоизменение", heard: "первое узкое место было очевидным полной", expectLineAtLeast: 5, expectLineAtMost: 6),
  // Speaker jumps a paragraph.
  .init(label: "прыжок через абзац", heard: "кеш работал но промахивался почти всегда", expectLineAtLeast: 8, expectLineAtMost: 9),
]

var failures = 0
for c in cases {
  guard let decision = aligner.ingest(norm(c.heard)) else {
    print("  FAIL  \(c.label): аллайнер не выдал решения")
    failures += 1
    continue
  }
  let line = script.lineIndex(forToken: decision.cursor)
  let ok = line >= c.expectLineAtLeast && line <= c.expectLineAtMost
  if !ok { failures += 1 }
  print(String(format: "  %@  %-22@ строка %d (ожидали %d…%d)  best %.2f  run %.2f",
               ok ? "ok  " : "FAIL", c.label as NSString, line, c.expectLineAtLeast, c.expectLineAtMost,
               decision.best, decision.runnerUp))
}

// Noise must not move the cursor.
let before = aligner.cursor
let noiseDecision = aligner.ingest(norm("совершенно посторонняя фраза про погоду"))
let moved = (noiseDecision?.moved ?? false)
if moved { failures += 1 }
print("  \(moved ? "FAIL" : "ok  ")  шум не двигает курсор  (\(before) -> \(aligner.cursor))")

print(failures == 0 ? "\nALL PASS" : "\n\(failures) FAILURE(S)")
exit(failures == 0 ? 0 : 1)
