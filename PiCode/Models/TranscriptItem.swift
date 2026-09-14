//
//  TranscriptItem.swift
//  PiCode
//
//  Presentation model for one row in the transcript. Built from Pi messages and
//  live events; never persisted and never treated as authoritative state.
//

import Foundation

enum ToolStatus: Equatable {
    case pending
    case running
    case success
    case failure
    case cancelled

    var label: String {
        switch self {
        case .pending: return "Queued"
        case .running: return "Running"
        case .success: return "Done"
        case .failure: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }

    var isTerminal: Bool {
        switch self {
        case .success, .failure, .cancelled: return true
        default: return false
        }
    }
}

/// Pi records two kinds of summary, and they are different facts: a *compaction*
/// folded the earlier context away to make room, while a *branch summary*
/// describes the path that was left behind when the user switched branches.
///
/// Both are one quiet line in the transcript — the summary text is a compression
/// nobody reads as prose — so the row still has to know which one it is to name it
/// correctly. Carrying the distinction rather than the finished label keeps the
/// wording (and the glyph, which matches the session tree's for the same entry) in
/// one place, next to the model it describes.
enum SummaryKind: String, Equatable {
    case compaction
    case branch

    var label: String {
        switch self {
        case .compaction: return "Compact context"
        case .branch: return "Branch summary"
        }
    }

    var systemImage: String {
        switch self {
        case .compaction: return "arrow.down.right.and.arrow.up.left"
        case .branch: return "arrow.triangle.branch"
        }
    }
}

/// A file touched by an agent turn, derived from tool inputs/outputs.
struct FileChange: Identifiable, Equatable, Hashable {
    enum Kind: String {
        case created
        case modified
        case deleted
        case read

        var label: String {
            switch self {
            case .created: return "created"
            case .modified: return "modified"
            case .deleted: return "deleted"
            case .read: return "read"
            }
        }

        var systemImage: String {
            switch self {
            case .created: return "plus.circle"
            case .modified: return "pencil.circle"
            case .deleted: return "minus.circle"
            case .read: return "eye"
            }
        }

        /// The matching working-tree status, used when the change is not in
        /// `git status` (for example a file Pi created and then removed).
        var gitStatus: GitFileChange.Status {
            switch self {
            case .created: return .added
            case .modified: return .modified
            case .deleted: return .deleted
            case .read: return .modified
            }
        }
    }

    var id: String { path + kind.rawValue }
    var path: String
    var kind: Kind
    var additions: Int?
    var deletions: Int?
}

struct TranscriptItem: Identifiable, Equatable {
    enum Kind: Equatable {
        case user
        case assistant
        case thinking
        case toolCall
        case toolResult
        case system
        case error
        case compaction
        case retry
        case turnDuration

        var isMessage: Bool {
            switch self {
            case .user, .assistant: return true
            default: return false
            }
        }
    }

    var id: String
    var kind: Kind
    var text: String = ""
    var isStreaming: Bool = false
    var timestamp: Date?
    /// Durable Pi entry id when the item maps to a session entry.
    var entryId: String?

    // Assistant metadata
    var modelName: String?
    var provider: String?
    var usage: PiUsage?
    var stopReason: String?
    var errorMessage: String?

    // Tool metadata
    var toolCallId: String?
    var toolName: String?
    var toolArguments: JSONValue?
    var toolOutput: String?
    var toolResultContent: [PiContentBlock] = []
    var toolStatus: ToolStatus = .pending
    var toolStartedAt: Date?
    var toolEndedAt: Date?
    var toolDetails: JSONValue?
    var fullOutputPath: String?

    // System row metadata
    var badge: String?
    /// Set on `.compaction` items: which of Pi's two summaries this row is.
    var summaryKind: SummaryKind?
    /// Set on user items so the transcript can offer fork-from-here.
    var forkEntryId: String?

    var isError: Bool {
        kind == .error || (kind == .toolCall && toolStatus == .failure)
    }

    var duration: TimeInterval? {
        guard let toolStartedAt else { return nil }
        return (toolEndedAt ?? Date()).timeIntervalSince(toolStartedAt)
    }

    /// One-line summary of a tool invocation, e.g. `bash(command: ls -la)`.
    var toolInputSummary: String {
        guard let toolArguments else { return "" }
        if case .object(let dictionary) = toolArguments {
            // Prefer the single most descriptive argument.
            for key in ["command", "file_path", "path", "pattern", "url", "query", "prompt"] {
                if let value = dictionary[key]?.stringValue, !value.isEmpty {
                    return "\(key): \(value.oneLinePreview(limit: 160))"
                }
            }
            if let first = dictionary.keys.sorted().first, let value = dictionary[first] {
                return "\(first): \(value.compactDescription.oneLinePreview(limit: 160))"
            }
        }
        return toolArguments.compactDescription.oneLinePreview(limit: 160)
    }

    /// File changes implied by this item, when it is a write/edit/read tool call.
    var fileChanges: [FileChange] {
        guard kind == .toolCall, let toolName, let toolArguments else { return [] }
        let lower = toolName.lowercased()
        let path = toolArguments.string("file_path")
            ?? toolArguments.string("path")
            ?? toolArguments.string("filePath")

        switch lower {
        case "write":
            guard let path else { return [] }
            let content = toolArguments.string("content") ?? ""
            let lines = content.isEmpty ? nil : content.split(separator: "\n", omittingEmptySubsequences: false).count
            return [FileChange(path: path, kind: .created, additions: lines, deletions: nil)]
        case "edit", "multiedit", "patch", "apply_patch":
            guard let path else { return [] }
            var additions = 0
            var deletions = 0
            let blocks = toolArguments.array("edits") ?? []
            if blocks.isEmpty {
                if let new = toolArguments.string("new_string") ?? toolArguments.string("newText") {
                    additions += new.split(separator: "\n", omittingEmptySubsequences: false).count
                }
                if let old = toolArguments.string("old_string") ?? toolArguments.string("oldText") {
                    deletions += old.split(separator: "\n", omittingEmptySubsequences: false).count
                }
            } else {
                for block in blocks {
                    if let new = block.string("new_string") ?? block.string("newText") {
                        additions += new.split(separator: "\n", omittingEmptySubsequences: false).count
                    }
                    if let old = block.string("old_string") ?? block.string("oldText") {
                        deletions += old.split(separator: "\n", omittingEmptySubsequences: false).count
                    }
                }
            }
            return [FileChange(path: path, kind: .modified, additions: additions, deletions: deletions)]
        case "read":
            guard let path else { return [] }
            return [FileChange(path: path, kind: .read, additions: nil, deletions: nil)]
        default:
            return []
        }
    }
}

/// Pending steering and follow-up messages reported by `queue_update`.
struct QueueSnapshot: Equatable {
    var steering: [QueuedMessage] = []
    var followUp: [QueuedMessage] = []

    struct QueuedMessage: Identifiable, Equatable {
        var id = UUID()
        var text: String
    }

    var isEmpty: Bool { steering.isEmpty && followUp.isEmpty }

    mutating func update(steering texts: [String], followUp followUpTexts: [String]) {
        steering = Self.merge(existing: steering, incoming: texts)
        followUp = Self.merge(existing: followUp, incoming: followUpTexts)
    }

    /// Pi reports queue text only, so retain existing ids for identical text to
    /// keep SwiftUI from re-animating rows that did not change.
    private static func merge(existing: [QueuedMessage], incoming: [String]) -> [QueuedMessage] {
        var pool = existing
        var result: [QueuedMessage] = []
        for text in incoming {
            if let index = pool.firstIndex(where: { $0.text == text }) {
                result.append(pool.remove(at: index))
            } else {
                result.append(QueuedMessage(text: text))
            }
        }
        return result
    }

    var restoredDraftText: String {
        (steering + followUp).map(\.text).joined(separator: "\n\n")
    }
}
