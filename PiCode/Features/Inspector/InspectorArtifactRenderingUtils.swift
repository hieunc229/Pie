//
//  InspectorArtifactRenderingUtils.swift
//  PiCode
//
//  Content classification and diff parsing for the right-panel renderers.
//

import Foundation

enum InspectorArtifactRendering {
    private static let highlightLimit = 60_000

    static func content(for item: TranscriptItem) -> InspectorToolContent {
        let output = nonEmpty(item.toolOutput)
        let tool = (item.toolName ?? "").lowercased()

        if item.commandText != nil || ["bash", "shell", "terminal", "exec", "command"].contains(tool) {
            return .terminal(command: item.commandText, output: output)
        }

        if !item.editBlocks.isEmpty {
            return .diff(ToolDiff.unified(item.editBlocks))
        }

        if let output, looksLikeDiff(output) {
            return .diff(output)
        }

        let isFileRead = tool == "read" || item.fileChanges.contains(where: { $0.kind == .read })
        if let output, isFileRead {
            let language = item.toolFilePath.map { SyntaxLanguage(path: $0) } ?? .plain
            return .code(text: output, language: language)
        }

        if let output, let language = structuredLanguage(for: output) {
            return .code(text: output, language: language)
        }

        let arguments = nonEmpty(item.toolArguments?.prettyDescription)
        let details = item.toolDetails.flatMap { $0.isNull ? nil : nonEmpty($0.prettyDescription) }
        if arguments != nil || output != nil || details != nil {
            return .generic(arguments: arguments, output: output, details: details)
        }
        if item.isStreaming { return .running }
        return .empty(
            message: item.toolStatus == .failure || item.toolStatus == .cancelled
                ? "This tool reported a failure without output."
                : "This tool did not return any displayable content.",
            isFailure: item.toolStatus == .failure || item.toolStatus == .cancelled
        )
    }

    static func parseDiff(_ diff: String) -> [GitDiffLine] {
        var oldLine: Int?
        var newLine: Int?
        return diff.split(separator: "\n", omittingEmptySubsequences: false).enumerated().map { index, raw in
            let rawLine = String(raw)

            if rawLine.hasPrefix("@@") {
                let starts = hunkStarts(rawLine)
                oldLine = starts.old
                newLine = starts.new
                return GitDiffLine(id: index, kind: .hunk, text: rawLine, oldLine: nil, newLine: nil)
            }
            if isDiffMetadata(rawLine) {
                return GitDiffLine(id: index, kind: .metadata, text: rawLine, oldLine: nil, newLine: nil)
            }
            if rawLine.hasPrefix("+") {
                let line = GitDiffLine(id: index, kind: .addition, text: String(rawLine.dropFirst()), oldLine: nil, newLine: newLine)
                newLine = newLine.map { $0 + 1 }
                return line
            }
            if rawLine.hasPrefix("-") {
                let line = GitDiffLine(id: index, kind: .deletion, text: String(rawLine.dropFirst()), oldLine: oldLine, newLine: nil)
                oldLine = oldLine.map { $0 + 1 }
                return line
            }

            let text = rawLine.hasPrefix(" ") ? String(rawLine.dropFirst()) : rawLine
            let line = GitDiffLine(id: index, kind: .context, text: text, oldLine: oldLine, newLine: newLine)
            oldLine = oldLine.map { $0 + 1 }
            newLine = newLine.map { $0 + 1 }
            return line
        }
    }

    static func highlightedText(_ text: String, language: SyntaxLanguage) -> AttributedString {
        var highlighted = text.count <= highlightLimit
            ? SyntaxHighlighter.highlight(text, language: language)
            : AttributedString(text)
        // The highlighter embeds a body-sized font in its attributed result, which
        // takes precedence over a SwiftUI `.font` modifier at the call site.
        highlighted.font = Typography.inspectorCode
        return highlighted
    }

    private static func looksLikeDiff(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("diff --git") || trimmed.hasPrefix("@@")
            || (trimmed.hasPrefix("--- ") && trimmed.contains("\n+++ "))
    }

    private static func structuredLanguage(for text: String) -> SyntaxLanguage? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (trimmed.hasPrefix("{") && trimmed.hasSuffix("}"))
                || (trimmed.hasPrefix("[") && trimmed.hasSuffix("]")) else { return nil }
        return SyntaxLanguage(identifier: "json")
    }

    private static func isDiffMetadata(_ line: String) -> Bool {
        line.hasPrefix("diff ") || line.hasPrefix("index ") || line.hasPrefix("---")
            || line.hasPrefix("+++") || line.hasPrefix("new file") || line.hasPrefix("deleted file")
            || line.hasPrefix("similarity index") || line.hasPrefix("rename from") || line.hasPrefix("rename to")
            || line == "\\ No newline at end of file"
    }

    private static func hunkStarts(_ line: String) -> (old: Int?, new: Int?) {
        let pattern = #"@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let oldRange = Range(match.range(at: 1), in: line),
              let newRange = Range(match.range(at: 2), in: line) else { return (nil, nil) }
        return (Int(line[oldRange]), Int(line[newRange]))
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        return text
    }
}
