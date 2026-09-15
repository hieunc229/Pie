//
//  PiCode session-title smoke test.
//
//  A new chat is named from its first message. Pi's RPC protocol has no
//  "summarize this" command, so `SessionTitleService` asks a one-shot `pi
//  --print` run and then has to make a title out of prose. The two pure steps
//  on either side of that process — `sanitize` (the answer into a title) and
//  `fallback` (the name when Pi cannot answer) — are what this checks. No model
//  is called and nothing is written.
//
//      ./Tools/SmokeTest/run-title.sh
//

import Foundation

@main
enum SessionTitleTest {
    static func main() {
        exit(run())
    }
}

func run() -> Int32 {
    var failures = 0
    func check(_ name: String, _ condition: Bool, _ detail: String = "") {
        if condition {
            print("  ok   \(name)\(detail.isEmpty ? "" : " — \(detail)")")
        } else {
            failures += 1
            print("  FAIL \(name)\(detail.isEmpty ? "" : " — \(detail)")")
        }
    }

    print("== a completion becomes a title ==")
    check("the first non-empty line wins, not the whole answer",
          SessionTitleService.sanitize("Fixing the login bug\n\nThat is the title.") == "Fixing the login bug",
          SessionTitleService.sanitize("Fixing the login bug\n\nThat is the title.") ?? "nil")
    check("wrapping quotes are not part of the title",
          SessionTitleService.sanitize("\"Refactor the parser\"") == "Refactor the parser",
          SessionTitleService.sanitize("\"Refactor the parser\"") ?? "nil")
    check("smart quotes are trimmed too",
          SessionTitleService.sanitize("“Refactor the parser”") == "Refactor the parser",
          SessionTitleService.sanitize("“Refactor the parser”") ?? "nil")
    check("trailing sentence punctuation is dropped",
          SessionTitleService.sanitize("Ship the sidebar.") == "Ship the sidebar",
          SessionTitleService.sanitize("Ship the sidebar.") ?? "nil")
    check("an empty or whitespace answer is no title at all",
          SessionTitleService.sanitize("  \n\n  ") == nil)
    check("a punctuation-only answer is no title at all",
          SessionTitleService.sanitize("...") == nil)
    let long = String(repeating: "word ", count: 40)
    let clipped = SessionTitleService.sanitize(long)
    check("a long answer is clipped to a title's length",
          (clipped?.count ?? 0) <= 60, "\(clipped?.count ?? 0) chars")
    check("the clip never ends on a space",
          clipped?.last?.isWhitespace != true, clipped ?? "nil")

    print("\n== when Pi cannot answer, the message names the chat ==")
    check("the opening words are the fallback",
          SessionTitleService.fallback(for: "Fix the login bug") == "Fix the login bug",
          SessionTitleService.fallback(for: "Fix the login bug") ?? "nil")
    check("newlines are flattened",
          SessionTitleService.fallback(for: "Fix the login bug\non the second line") == "Fix the login bug on the",
          SessionTitleService.fallback(for: "Fix the login bug\non the second line") ?? "nil")
    check("a leading slash command drops only its slash",
          SessionTitleService.fallback(for: "/review src/main.swift") == "review src/main.swift",
          SessionTitleService.fallback(for: "/review src/main.swift") ?? "nil")
    check("a bare slash command keeps its word",
          SessionTitleService.fallback(for: "/review") == "review",
          SessionTitleService.fallback(for: "/review") ?? "nil")
    check("an empty message has no fallback",
          SessionTitleService.fallback(for: "   \n ") == nil)
    let many = SessionTitleService.fallback(for: "one two three four five six seven eight nine ten")
    check("the fallback stops at six words",
          many == "one two three four five six", many ?? "nil")
    let wide = SessionTitleService.fallback(for: String(repeating: "a", count: 80))
    check("the fallback is clipped to a title's length",
          (wide?.count ?? 0) <= 48, "\(wide?.count ?? 0) chars")

    print(failures == 0 ? "\nRESULT: all checks passed" : "\nRESULT: \(failures) check(s) failed")
    return failures == 0 ? 0 : 1
}
