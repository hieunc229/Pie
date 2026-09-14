//
//  Markdown.swift
//  PiCode
//
//  Block-level Markdown parsing for the transcript.
//
//  Why not `AttributedString(markdown:)` alone? Assistant output streams in
//  fragments, so the transcript needs incremental, partial-safe parsing: an
//  unterminated code fence must still render as a code block that grows. This
//  parser handles blocks; inline formatting is delegated to Foundation's
//  Markdown support per block.
//

import Foundation
import SwiftUI

enum MarkdownBlock: Equatable, Identifiable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bulletList([MarkdownListItem])
    case orderedList([MarkdownListItem])
    case taskList([MarkdownListItem])
    case codeBlock(language: SyntaxLanguage, code: String, isComplete: Bool)
    case quote([String])
    case table(headers: [String], rows: [[String]])
    case rule
    case rawHTML(String)

    var id: String {
        switch self {
        case .heading(let level, let text): return "h\(level)-\(text)"
        case .paragraph(let text): return "p-\(text)"
        case .bulletList(let items): return "ul-\(items.map(\.id).joined(separator: "|"))"
        case .orderedList(let items): return "ol-\(items.map(\.id).joined(separator: "|"))"
        case .taskList(let items): return "tl-\(items.map(\.id).joined(separator: "|"))"
        case .codeBlock(let language, let code, _): return "code-\(language.label)-\(code.count)-\(code.hashValue)"
        case .quote(let lines): return "quote-\(lines.joined(separator: "|"))"
        case .table(let headers, let rows): return "table-\(headers.joined(separator: ","))-\(rows.count)"
        case .rule: return "rule"
        case .rawHTML(let raw): return "html-\(raw.count)"
        }
    }
}

struct MarkdownListItem: Equatable, Identifiable {
    var id: String { "\(depth)-\(marker)-\(text)" }
    var depth: Int
    var marker: String
    var text: String
    var isChecked: Bool?
}

enum MarkdownParser {
    /// Parses block structure. Safe to call on incomplete streaming text.
    static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = text.components(separatedBy: "\n")
        var index = 0

        // Paragraph and list accumulation buffers.
        var paragraph: [String] = []
        var quote: [String] = []
        var bullets: [MarkdownListItem] = []
        var ordered: [MarkdownListItem] = []
        var tasks: [MarkdownListItem] = []

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: "\n")))
            paragraph.removeAll()
        }
        func flushQuote() {
            guard !quote.isEmpty else { return }
            blocks.append(.quote(quote))
            quote.removeAll()
        }
        func flushLists() {
            if !tasks.isEmpty {
                blocks.append(.taskList(tasks))
                tasks.removeAll()
            }
            if !bullets.isEmpty {
                blocks.append(.bulletList(bullets))
                bullets.removeAll()
            }
            if !ordered.isEmpty {
                blocks.append(.orderedList(ordered))
                ordered.removeAll()
            }
        }
        func flushAll() {
            flushParagraph()
            flushQuote()
            flushLists()
        }

        while index < lines.count {
            let rawLine = lines[index]
            let line = rawLine
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Fenced code blocks, including incomplete fences while streaming.
            if let fence = fenceMarker(trimmed) {
                flushAll()
                let indent = line.prefix { $0 == " " || $0 == "\t" }.count
                let language = SyntaxLanguage(identifier: fence.info.isEmpty ? nil : fence.info)
                var code: [String] = []
                var cursor = index + 1
                var closed = false
                while cursor < lines.count {
                    let candidate = lines[cursor]
                    let candidateTrimmed = candidate.trimmingCharacters(in: .whitespaces)
                    if candidateTrimmed.hasPrefix(fence.marker),
                       candidateTrimmed.drop(while: { $0 == fence.marker.first }).trimmingCharacters(in: .whitespaces).isEmpty {
                        closed = true
                        cursor += 1
                        break
                    }
                    code.append(dedent(candidate, upTo: indent))
                    cursor += 1
                }
                blocks.append(.codeBlock(
                    language: language,
                    code: code.joined(separator: "\n"),
                    isComplete: closed
                ))
                index = cursor
                continue
            }

            if trimmed.isEmpty {
                flushAll()
                index += 1
                continue
            }

            if isRule(trimmed) {
                flushAll()
                blocks.append(.rule)
                index += 1
                continue
            }

            if let heading = headingLevel(trimmed) {
                flushAll()
                let content = trimmed.dropFirst(heading + 1).trimmingCharacters(in: .whitespaces)
                blocks.append(.heading(
                    level: heading,
                    text: content.replacingOccurrences(of: #"\s+#+$"#, with: "", options: .regularExpression)
                ))
                index += 1
                continue
            }

            // Tables: a header row followed by a separator row.
            if trimmed.contains("|"), index + 1 < lines.count, isTableSeparator(lines[index + 1].trimmingCharacters(in: .whitespaces)) {
                flushAll()
                let headers = splitTableRow(trimmed)
                var rows: [[String]] = []
                var cursor = index + 2
                while cursor < lines.count {
                    let row = lines[cursor].trimmingCharacters(in: .whitespaces)
                    guard row.contains("|"), !row.isEmpty else { break }
                    rows.append(splitTableRow(row))
                    cursor += 1
                }
                blocks.append(.table(headers: headers, rows: rows))
                index = cursor
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                flushLists()
                let content = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
                quote.append(content)
                index += 1
                continue
            }

            if let item = listItem(line) {
                flushParagraph()
                flushQuote()
                if item.isChecked != nil {
                    if !bullets.isEmpty || !ordered.isEmpty { flushLists() }
                    tasks.append(item)
                } else if item.marker == "-" || item.marker == "*" || item.marker == "+" {
                    if !tasks.isEmpty || !ordered.isEmpty { flushLists() }
                    bullets.append(item)
                } else {
                    if !tasks.isEmpty || !bullets.isEmpty { flushLists() }
                    ordered.append(item)
                }
                index += 1
                continue
            }

            if trimmed.hasPrefix("<") && trimmed.hasSuffix(">") && looksLikeHTML(trimmed) {
                flushAll()
                blocks.append(.rawHTML(trimmed))
                index += 1
                continue
            }

            flushQuote()
            flushLists()
            paragraph.append(trimmed)
            index += 1
        }

        flushAll()
        return blocks
    }

    // MARK: - Line helpers

    private static func fenceMarker(_ trimmed: String) -> (marker: String, info: String)? {
        for marker in ["```", "~~~"] where trimmed.hasPrefix(marker) {
            let info = trimmed.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
            return (marker, info)
        }
        return nil
    }

    private static func headingLevel(_ trimmed: String) -> Int? {
        var level = 0
        for character in trimmed {
            if character == "#" { level += 1 } else { break }
        }
        guard level > 0, level <= 6, trimmed.count > level else { return nil }
        let next = trimmed[trimmed.index(trimmed.startIndex, offsetBy: level)]
        return next == " " || next == "\t" ? level : nil
    }

    private static func isRule(_ trimmed: String) -> Bool {
        guard trimmed.count >= 3 else { return false }
        let stripped = trimmed.filter { !$0.isWhitespace }
        guard stripped.count >= 3 else { return false }
        return stripped.allSatisfy { $0 == "-" || $0 == "*" || $0 == "_" }
    }

    private static func isTableSeparator(_ trimmed: String) -> Bool {
        guard trimmed.contains("-") || trimmed.contains("=") else { return false }
        let cells = splitTableRow(trimmed)
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            let stripped = cell.trimmingCharacters(in: .whitespaces)
            guard !stripped.isEmpty else { return false }
            return stripped.allSatisfy { $0 == "-" || $0 == ":" || $0 == "=" }
        }
    }

    static func splitTableRow(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") { trimmed.removeFirst() }
        if trimmed.hasSuffix("|") { trimmed.removeLast() }
        return trimmed
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func listItem(_ line: String) -> MarkdownListItem? {
        let indent = line.prefix { $0 == " " || $0 == "\t" }.reduce(0) { partial, character in
            partial + (character == "\t" ? 4 : 1)
        }
        let depth = indent / 2
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        // Checkbox syntax first, so `- [x] item` is treated as a task.
        if let match = trimmed.range(of: #"^([-*+])\s+\[( |x|X)\]\s+"#, options: .regularExpression) {
            var text = String(trimmed[match.upperBound...])
            let state = trimmed[match.lowerBound..<match.upperBound]
            let isChecked = state.contains("x") || state.contains("X")
            text = text.trimmingCharacters(in: .whitespaces)
            return MarkdownListItem(depth: depth, marker: "-", text: text, isChecked: isChecked)
        }

        if let match = trimmed.range(of: #"^([-*+])\s+"#, options: .regularExpression) {
            let marker = String(trimmed[match.lowerBound]).trimmingCharacters(in: .whitespaces)
            let text = String(trimmed[match.upperBound...]).trimmingCharacters(in: .whitespaces)
            return MarkdownListItem(depth: depth, marker: marker, text: text, isChecked: nil)
        }

        if let match = trimmed.range(of: #"^(\d{1,9})[.)]\s+"#, options: .regularExpression) {
            let marker = String(trimmed[match.lowerBound]).trimmingCharacters(in: .whitespaces)
            let text = String(trimmed[match.upperBound...]).trimmingCharacters(in: .whitespaces)
            return MarkdownListItem(depth: depth, marker: marker, text: text, isChecked: nil)
        }

        return nil
    }

    private static func looksLikeHTML(_ trimmed: String) -> Bool {
        let known: [String] = ["<br", "<br/>", "<br />", "<hr", "<p", "<div", "<span", "<table", "<details", "<summary", "<img"]
        let lower = trimmed.lowercased()
        return known.contains { lower.hasPrefix($0) }
    }

    private static func dedent(_ line: String, upTo count: Int) -> String {
        guard count > 0 else { return line }
        var remaining = count
        var index = line.startIndex
        while remaining > 0, index < line.endIndex, line[index] == " " || line[index] == "\t" {
            index = line.index(after: index)
            remaining -= 1
        }
        return String(line[index...])
    }
}

// MARK: - Inline formatting

enum MarkdownInline {
    /// Rewrites plain-text path references like `Sources/App.swift:42` into
    /// `picode://` links so the transcript can open them on click.
    static func linkingFileReferences(_ text: String) -> String {
        guard text.contains("/") || text.contains(".") else { return text }
        let pattern = #"(?<![\w./@-])((?:[\w.@+-]+/)+[\w.@+-]+\.[A-Za-z0-9]{1,12}|[\w.@+-]+\.[A-Za-z0-9]{1,12})(?::(\d{1,7}))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return text }

        var result = ""
        var cursor = 0
        for match in matches {
            let full = ns.substring(with: match.range)
            guard MarkdownInline.isLikelyFilePath(full) else { continue }
            result += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let pathRange = match.range(at: 1)
            let path = ns.substring(with: pathRange)
            let lineRange = match.range(at: 2)
            let line = lineRange.location == NSNotFound ? nil : ns.substring(with: lineRange)
            var encoded = path.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? path
            if let line { encoded += "&line=\(line)" }
            let label = line == nil ? path : "\(path):\(line!)"
            result += "[\(label)](picode://file?path=\(encoded))"
            cursor = match.range.location + match.range.length
        }
        result += ns.substring(from: cursor)
        return result
    }

    /// Guards against turning prose numbers like `3.14` or versions into links.
    static func isLikelyFilePath(_ token: String) -> Bool {
        let withoutLine = token.split(separator: ":").first.map(String.init) ?? token
        let ext = (withoutLine as NSString).pathExtension.lowercased()
        guard !ext.isEmpty else { return false }
        let known = FileClassification.textExtensions
            .union(FileClassification.imageExtensions)
            .union(["xcodeproj", "xcworkspace", "app", "dylib", "so", "wasm", "lock", "resolved"])
        if known.contains(ext) { return true }
        // Require a directory separator for unknown extensions so `v1.2` stays text.
        return withoutLine.contains("/") && ext.count <= 12 && ext.allSatisfy { $0.isLetter || $0.isNumber }
    }

    /// Builds an inline-attributed string, falling back to plain text.
    static func attributed(_ text: String) -> AttributedString {
        let prepared = linkingFileReferences(text)
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        options.failurePolicy = .returnPartiallyParsedIfPossible
        guard var attributed = try? AttributedString(markdown: prepared, options: options) else {
            return AttributedString(text)
        }
        // Inline code should be monospaced with a subtle background, matching the
        // rest of the UI rather than the system default.
        let codeRuns = attributed.runs
            .filter { $0.inlinePresentationIntent?.contains(.code) == true }
            .map(\.range)
        for range in codeRuns {
            attributed[range].font = .system(.body, design: .monospaced)
            attributed[range].foregroundColor = Color(nsColor: .systemPink)
        }
        return attributed
    }
}

extension CharacterSet {
    /// Query values must escape `&`, `=`, and `?`, unlike `.urlQueryAllowed`.
    static var urlQueryValueAllowed: CharacterSet {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "&=?+#")
        return set
    }
}
