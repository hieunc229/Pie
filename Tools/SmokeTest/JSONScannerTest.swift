//
//  JSONScannerTest.swift
//  PiCode (smoke test)
//
//  The RPC and session readers no longer use `JSONDecoder` (it crashed on Pi's
//  deep `get_tree` payloads), so the replacement is cross-checked here against
//  Foundation's own parser on every real session line, plus hand-written cases
//  for escapes, depth, malformed input and round trips.
//
//      ./Tools/SmokeTest/run-json.sh
//

import Foundation

@main
enum JSONScannerTest {
    static func main() async {
        setbuf(stdout, nil)
        var failures = 0
        func check(_ name: String, _ condition: Bool, _ detail: String = "") {
            if condition {
                print("  ok   \(name)\(detail.isEmpty ? "" : " — \(detail)")")
            } else {
                failures += 1
                print("  FAIL \(name)\(detail.isEmpty ? "" : " — \(detail)")")
            }
        }

        print("== literals and escapes ==")
        let cases: [(String, String)] = [
            ("null", "null"),
            ("true", "true"),
            ("false", "false"),
            ("integer", "42"),
            ("negative", "-17"),
            ("exponent", "1.5e3"),
            ("fraction", "0.125"),
            ("bare string", "\"hi\""),
            ("empty string", "\"\""),
            ("escaped quote", "\"a\\\"b\""),
            ("escaped slash", "\"a\\/b\""),
            ("escaped backslash", "\"a\\\\b\""),
            ("control escapes", "\"a\\nb\\tc\\rd\\be\\ff\""),
            ("basic unicode escape", "\"\\u0041\\u00e9\""),
            ("surrogate pair", "\"\\ud83d\\ude00\""),
            ("utf8 text", "\"héllo → 🎉\""),
            ("empty array", "[]"),
            ("empty object", "{}"),
            ("nested", "{\"a\":[1,{\"b\":null}],\"c\":true}"),
            ("whitespace", " \n\t { \"a\" : [ 1 , 2 ] } \r\n "),
            ("deep-ish", String(repeating: "[", count: 40) + String(repeating: "]", count: 40)),
        ]

        for (label, text) in cases {
            let mine = try? JSONScanner.parse(text)
            let reference = referenceValue(from: text)
            let matches = compare(mine, reference)
            check("parses \(label)", matches,
                  matches ? "" : "scanner \(mine.map(\.compactDescription) ?? "nil")"
                  + " vs Foundation \(reference.map(\.compactDescription) ?? "nil")")
        }

        // Two deliberate differences from Foundation, both chosen because Pi
        // never emits these and permissive parsing is safer than failing:
        // duplicate keys (last wins, like `JSONDecoder`) and lone surrogates
        // (replaced with U+FFFD rather than rejecting the whole record).
        check("duplicate keys keep the last value",
              (try? JSONScanner.parse("{\"a\":1,\"a\":2}"))?.int("a") == 2)
        check("lone surrogate becomes U+FFFD",
              (try? JSONScanner.parse("\"\\ud83d\""))?.stringValue == "\u{FFFD}")
        check("lone surrogate then text keeps both",
              (try? JSONScanner.parse("\"\\ud83dx\""))?.stringValue == "\u{FFFD}x")

        print("== deep nesting (the crash that motivated the scanner) ==")
        for depth in [200, 2_000, 20_000] {
            let text = String(repeating: "[", count: depth) + String(repeating: "]", count: depth)
            let parsed = try? JSONScanner.parse(text)
            var measured = 0
            var cursor = parsed
            while case .array(let items)? = cursor {
                measured += 1
                guard let first = items.first else { break }
                cursor = first
            }
            check("parses \(depth) levels without overflowing the stack", measured == depth,
                  "\(measured) levels")
        }

        print("== malformed input is rejected ==")
        let bad: [(String, String)] = [
            ("empty input", ""),
            ("truncated object", "{\"a\":"),
            ("unterminated string", "\"abc"),
            ("unterminated array", "[1, 2"),
            ("missing comma", "[1 2]"),
            ("missing colon", "{\"a\" 1}"),
            ("trailing content", "{} {}"),
            ("bare word", "nope"),
            ("closing only", "}"),
        ]
        for (label, text) in bad {
            let threw = (try? JSONScanner.parse(text)) == nil
            check("rejects \(label)", threw)
        }

        print("== writer round trips ==")
        for (label, text) in cases {
            guard let value = try? JSONScanner.parse(text) else { continue }
            let compact = JSONScanner.serialize(value)
            let pretty = JSONScanner.serialize(value, pretty: true)
            let compactBack = try? JSONScanner.parse(compact)
            let prettyBack = try? JSONScanner.parse(pretty)
            check("round trips \(label)",
                  compare(compactBack, value) && compare(prettyBack, value),
                  compact.count < 60 ? compact : "\(compact.prefix(57))…")
        }

        let nasty = JSONValue.object([
            "quote\"key": .string("line\nbreak\ttab \\ backslash"),
            "unicode": .string("héllo → 🎉 \u{1F600}"),
            "control": .string("bell\u{07}null\u{00}"),
            "numbers": .array([.number(0), .number(-0.5), .number(1e21), .number(9_007_199_254_740_992)]),
            "empty": .object([:]),
            "nulls": .array([.null, .null]),
        ])
        check("round trips a hostile document",
              compare(try? JSONScanner.parse(JSONScanner.serialize(nasty, pretty: true)), nasty))

        print("== against every real session line ==")
        let sessions = SessionIndex().loadAllSessions().compactMap(\.filePath)
        var lines = 0
        var mismatches: [String] = []
        var unreadable = 0
        var precisionLosses = 0
        var scannerSeconds = 0.0
        var foundationSeconds = 0.0

        for path in sessions {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { continue }
            for line in data.split(separator: 0x0A) {
                guard !line.isEmpty else { continue }
                lines += 1
                let lineData = Data(line)

                let start = Date()
                let mine = try? JSONScanner.parse(lineData)
                scannerSeconds += Date().timeIntervalSince(start)

                let foundationStart = Date()
                let reference = referenceValue(from: lineData)
                foundationSeconds += Date().timeIntervalSince(foundationStart)

                guard let mine, let reference else {
                    unreadable += 1
                    if mismatches.count < 5 { mismatches.append("unparsable line in \(path)") }
                    continue
                }
                if !compare(mine, reference) {
                    if mismatches.count < 5 {
                        mismatches.append("\(path): \(mine.compactDescription.prefix(80))")
                    }
                }
                precisionLosses += countPrecisionLoss(mine)
            }
        }

        check("every line parses with the scanner", unreadable == 0, "\(lines) lines")
        check("scanner agrees with Foundation on every line", mismatches.isEmpty,
              mismatches.first ?? "\(lines) lines compared")
        print("  timing: scanner \(String(format: "%.2f", scannerSeconds))s"
              + " vs JSONSerialization \(String(format: "%.2f", foundationSeconds))s"
              + " for \(lines) lines")
        if precisionLosses > 0 {
            print("  note: \(precisionLosses) number(s) exceed 2^53 and lose precision as Double")
        }

        print(failures == 0 ? "\nRESULT: all checks passed" : "\nRESULT: \(failures) check(s) failed")
        exit(failures == 0 ? 0 : 1)
    }

    // MARK: - Comparing against Foundation

    /// Independent implementation used as the reference: Foundation parses the
    /// bytes, then this code walks the resulting objects.
    private static func referenceValue(from text: String) -> JSONValue? {
        referenceValue(from: Data(text.utf8))
    }

    private static func referenceValue(from data: Data) -> JSONValue? {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return nil
        }
        return referenceValue(from: object)
    }

    private static func referenceValue(from object: Any) -> JSONValue? {
        switch object {
        case is NSNull:
            return .null
        case let number as NSNumber:
            // NSNumber also covers booleans; CoreFoundation tags them via objCType.
            if String(cString: number.objCType) == "c" || String(cString: number.objCType) == "B" {
                return .bool(number.boolValue)
            }
            return .number(number.doubleValue)
        case let text as String:
            return .string(text)
        case let array as [Any]:
            return .array(array.compactMap { referenceValue(from: $0) })
        case let dictionary as [String: Any]:
            var result: [String: JSONValue] = [:]
            for (key, value) in dictionary {
                guard let converted = referenceValue(from: value) else { return nil }
                result[key] = converted
            }
            return .object(result)
        default:
            return nil
        }
    }

    /// Numeric equality within Double precision; everything else is structural.
    private static func compare(_ lhs: JSONValue?, _ rhs: JSONValue?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case (.none, .some), (.some, .none):
            return false
        case let (.some(left), .some(right)):
            switch (left, right) {
            case (.null, .null):
                return true
            case let (.bool(a), .bool(b)):
                return a == b
            case let (.number(a), .number(b)):
                return a == b || abs(a - b) <= max(abs(a), abs(b)) * 1e-12
            case let (.string(a), .string(b)):
                return a == b
            case let (.array(a), .array(b)):
                return a.count == b.count && zip(a, b).allSatisfy { compare($0, $1) }
            case let (.object(a), .object(b)):
                return a.count == b.count
                    && Set(a.keys) == Set(b.keys)
                    && a.allSatisfy { compare($0.value, b[$0.key]) }
            default:
                return false
            }
        }
    }

    private static func countPrecisionLoss(_ value: JSONValue) -> Int {
        switch value {
        case .number(let number):
            return number.rounded() == number && abs(number) >= 9_007_199_254_740_992 ? 1 : 0
        case .array(let items):
            return items.reduce(0) { $0 + countPrecisionLoss($1) }
        case .object(let dictionary):
            return dictionary.values.reduce(0) { $0 + countPrecisionLoss($1) }
        default:
            return 0
        }
    }
}
