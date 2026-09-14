//
//  TranscriptRows.swift
//  PiCode
//
//  How the transcript is *laid out*: one row per item, except for the quiet rows,
//  which fold.
//
//  Pi's own output is noisy. A turn that thinks, reads three files and runs two
//  commands arrives as six or eight rows, and a card per call — each with its own
//  name, status pill, duration and output box — buries the conversation the user is
//  actually reading. The rows that repeat are shown instead as one dimmed line,
//  collapsed by default; a run of neighbouring ones becomes one line that names what
//  happened ("Thinking, read files, run commands"), whose expansion lists the steps,
//  whose own expansion shows the command's output or the reasoning.
//
//  What folds is a *shape*, not a tool: reasoning belongs in the same run as the
//  calls it is reasoning about, because in Pi's output it is literally interleaved
//  with them — thinking, tool call, thinking, tool call. Leaving thinking out would
//  leave a "Thinking" line above every group anyway, which is the same noise in a
//  different arrangement.
//
//  Nothing else folds: a `grep`, a `webfetch` or a `task` is not the same thing
//  five times over, so it keeps its card.
//
//  The grouping is a pure function of the item list on purpose — it is the part of
//  this presentation that can be proved without a window, and
//  `Tools/SmokeTest/run-replay.sh` checks it against every real session on disk.
//

import Foundation

/// The rows that fold, and the words they are described with. `thinking` is not a
/// tool, which is why this is not called a tool family: it is one of the things a
/// turn does that the transcript counts and folds together.
enum QuietFamily: String, CaseIterable {
    case command
    case edit
    case read
    case thinking

    /// The family an item belongs to, or `nil` for the rows that stand alone. The
    /// tool names are the ones Pi actually sends (checked across the real sessions
    /// on this machine: `bash`, `read`, `edit`, `write`).
    static func of(_ item: TranscriptItem) -> QuietFamily? {
        switch item.kind {
        case .thinking:
            return .thinking
        case .toolCall:
            return of(toolName: item.toolName)
        default:
            return nil
        }
    }

    static func of(toolName: String?) -> QuietFamily? {
        switch (toolName ?? "").lowercased() {
        case "bash": return .command
        case "edit", "multiedit", "write", "patch", "apply_patch": return .edit
        case "read": return .read
        default: return nil
        }
    }

    var systemImage: String {
        switch self {
        case .command: return "terminal"
        case .edit: return "pencil"
        case .read: return "doc.text"
        case .thinking: return "brain"
        }
    }

    /// The whole line when this family is on its own: one call, one line.
    var label: String {
        switch self {
        case .command: return "Run command"
        case .edit: return "Edited files"
        case .read: return "Read files"
        case .thinking: return "Thinking"
        }
    }

    /// …and when the run holds several of the same family. Only a command has a
    /// singular, and reasoning reads the same however much of it there is.
    var pluralLabel: String {
        switch self {
        case .command: return "Run commands"
        case .edit: return "Edited files"
        case .read: return "Read files"
        case .thinking: return "Thinking"
        }
    }

    /// The same family inside a list of families, where it is one item among others
    /// and the first letter is capitalised by position: "run commands". The count
    /// decides the noun, so a group holding one command says so.
    func listed(count: Int) -> String {
        switch self {
        case .command: return count == 1 ? "run command" : "run commands"
        case .edit: return "edited files"
        case .read: return "read files"
        case .thinking: return "thinking"
        }
    }
}

/// One row of the transcript. Everything is `.item` except the folded runs.
enum TranscriptRow: Identifiable {
    case item(TranscriptItem)
    case group([TranscriptItem])

    var id: String {
        switch self {
        case .item(let item):
            return item.id
        // Keyed by the group's *first* item, not its contents: appending another
        // call to a run must not change the row's identity, or a turn that is still
        // streaming would fold the row back up while the user is reading it.
        case .group(let items):
            return "group-\(items.first?.id ?? "empty")"
        }
    }

    var items: [TranscriptItem] {
        switch self {
        case .item(let item): return [item]
        case .group(let items): return items
        }
    }

    /// "Run command" for a single call, "Thinking, edited files, run commands" for a
    /// run.
    ///
    /// The families are named in the order they first appear, which is the order the
    /// agent did them in, so the line reads as a summary of the work rather than as
    /// an inventory of it — and each family is named once however many times it
    /// recurs, because "thinking, thinking, thinking" is the noise this exists to
    /// remove. Reasoning is named rather than hidden: a line that said only "Run
    /// commands" while the model had stopped to think would be a claim about what
    /// happened that the transcript cannot support.
    var groupTitle: String {
        var order: [QuietFamily] = []
        var counts: [QuietFamily: Int] = [:]
        for item in items {
            guard let family = QuietFamily.of(item) else { continue }
            if counts[family] == nil { order.append(family) }
            counts[family, default: 0] += 1
        }
        guard let first = order.first else { return "Actions" }
        if order.count == 1 { return items.count == 1 ? first.label : first.pluralLabel }
        return order.enumerated()
            .map { index, family in
                let words = family.listed(count: counts[family] ?? 1)
                return index == 0 ? words.capitalizedFirst : words
            }
            .joined(separator: ", ")
    }

    /// The icon on the folded line: the first family's, because the first thing that
    /// happened is what the run is about.
    var groupSystemImage: String {
        items.first.flatMap { QuietFamily.of($0) }?.systemImage ?? "wrench.and.screwdriver"
    }

    /// Whether the run is currently producing reasoning, which the folded line says
    /// in place of the reasoning itself.
    var streamingThinkingItem: TranscriptItem? {
        items.last { QuietFamily.of($0) == .thinking && $0.isStreaming }
    }
}

enum TranscriptRows {
    /// Fold neighbouring quiet rows into one; leave everything else exactly as it
    /// was.
    ///
    /// "Neighbouring" is literal, and deliberately so: an assistant message, an
    /// orphaned tool result or a non-folding tool between two steps ends the run.
    /// What the user reads is the shape of the work, and a paragraph of explanation
    /// between two commands is exactly that boundary.
    static func group(_ items: [TranscriptItem]) -> [TranscriptRow] {
        var rows: [TranscriptRow] = []
        var run: [TranscriptItem] = []

        func flush() {
            guard !run.isEmpty else { return }
            rows.append(.group(run))
            run = []
        }

        for item in items {
            if QuietFamily.of(item) != nil {
                run.append(item)
            } else {
                flush()
                rows.append(.item(item))
            }
        }
        flush()
        return rows
    }
}

extension TranscriptItem {
    /// The one line that identifies this call on a folded row: the command it ran,
    /// or the file it touched. Falls back to the generic input summary for shapes
    /// that carry neither — including reasoning, which is identified by its family
    /// rather than by a preview of what the model was thinking.
    ///
    /// The path is not abbreviated here — this is the only place the file is named
    /// on a folded row, and the transcript's own change chips show the full path
    /// too, so the two agree.
    var foldedSummary: String {
        if let command = toolArguments?.string("command"), !command.isEmpty {
            return command.oneLinePreview(limit: 120)
        }
        for key in ["file_path", "path", "filePath"] {
            if let path = toolArguments?.string(key), !path.isEmpty {
                return path.oneLinePreview(limit: 120)
            }
        }
        return toolInputSummary
    }
}

private extension String {
    /// "run commands" → "Run commands". Only ever applied to the head of a list.
    var capitalizedFirst: String {
        guard let first = first else { return self }
        return String(first).uppercased() + String(dropFirst())
    }
}
