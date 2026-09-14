//
//  TranscriptExporter.swift
//  PiCode
//
//  Plain-text rendering of the transcript for "Copy Transcript".
//
//  This is deliberately independent of Pi's own HTML export: it copies what the
//  window shows, including tool output, so pasting into a review thread keeps the
//  same information the user saw.
//

import Foundation

enum TranscriptExporter {
    static func plainText(_ items: [TranscriptItem], includeToolOutput: Bool = true) -> String {
        var lines: [String] = []
        for item in items {
            switch item.kind {
            case .user:
                lines.append("## You")
                lines.append(item.text)
            case .assistant:
                lines.append("## Assistant\(item.modelName.map { " (\($0))" } ?? "")")
                lines.append(item.text)
            case .thinking:
                lines.append("## Thinking")
                lines.append(item.text)
            case .toolCall:
                let name = item.toolName ?? "tool"
                lines.append("## Tool: \(name)")
                if !item.toolInputSummary.isEmpty {
                    lines.append(item.toolInputSummary)
                }
                if includeToolOutput, let output = item.toolOutput, !output.isEmpty {
                    lines.append("```")
                    lines.append(output)
                    lines.append("```")
                }
                lines.append("Status: \(item.toolStatus.label)")
            case .toolResult:
                lines.append("## Tool result")
                lines.append(item.toolOutput ?? item.text)
            case .system:
                lines.append("## \(item.badge ?? "Note")")
                lines.append(item.text)
            case .error:
                lines.append("## Error")
                lines.append(item.errorMessage ?? item.text)
            case .compaction:
                // The row is one line in the UI, but an exported transcript is read
                // without the conversation around it, so the summary itself belongs
                // here — under the same name the row used.
                lines.append("## \(item.summaryKind?.label ?? "Compaction")")
                lines.append(item.text)
            case .retry:
                lines.append("## Retry")
                lines.append(item.text)
            case .turnDuration:
                lines.append("## Turn")
                lines.append(item.text)
            }
            lines.append("")
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }
}
