//
//  TranscriptRows.swift
//  PiCode
//
//  How the transcript is *laid out*: one row per item, except for the quiet tool
//  calls, which fold.
//
//  Pi's own output is noisy. A turn that reads three files and runs two commands
//  arrives as five tool calls, and a card per call — each with its own name,
//  status pill, duration and output box — buries the conversation the user is
//  actually reading. The three families that repeat are shown instead as one
//  dimmed line ("Run command", "Edited files", "Read files"), collapsed by
//  default; a run of neighbouring calls becomes one line that names what happened
//  ("Edited files, run commands"), whose expansion lists the calls, whose own
//  expansion shows the output.
//
//  Nothing else is folded: a `grep`, a `webfetch` or a `task` is not the same
//  thing five times over, so it keeps its card.
//
//  The grouping is a pure function of the item list on purpose — it is the part of
//  this presentation that can be proved without a window, and
//  `Tools/SmokeTest/run-replay.sh` checks it against every real session on disk.
//

import Foundation

/// The tool families that fold, and the words they are described with.
enum ToolFamily: String, CaseIterable {
    case command
    case edit
    case read

    /// `nil` for every other tool, which is what keeps its card. The names are the
    /// ones Pi actually sends (checked across the real sessions on this machine:
    /// `bash`, `read`, `edit`, `write`).
    static func of(_ toolName: String?) -> ToolFamily? {
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
        }
    }

    /// The whole line when this family is on its own: one call, one line.
    var label: String {
        switch self {
        case .command: return "Run command"
        case .edit: return "Edited files"
        case .read: return "Read files"
        }
    }

    /// …and when the run holds several of the same family. Two of the three read the
    /// same either way; only a command has a singular.
    var pluralLabel: String {
        switch self {
        case .command: return "Run commands"
        case .edit: return "Edited files"
        case .read: return "Read files"
        }
    }

    /// The same family inside a list of families, where it is one item among others
    /// and the first letter is capitalised by position: "run commands".
    var listedLabel: String {
        switch self {
        case .command: return "run commands"
        case .edit: return "edited files"
        case .read: return "read files"
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

    /// "Run command" for a single call, "Edited files, run commands" for a run.
    ///
    /// The families are named in the order they first appear, which is the order the
    /// agent did them in, so the line reads as a summary of the work rather than as
    /// an inventory of it.
    var groupTitle: String {
        let families = items.reduce(into: [ToolFamily]()) { found, item in
            guard let family = ToolFamily.of(item.toolName), !found.contains(family) else { return }
            found.append(family)
        }
        guard let first = families.first else { return "Tool calls" }
        if families.count == 1 { return items.count == 1 ? first.label : first.pluralLabel }
        return families.enumerated()
            .map { $0.offset == 0 ? $0.element.listedLabel.capitalizedFirst : $0.element.listedLabel }
            .joined(separator: ", ")
    }

    /// The icon on the folded line: the first family's, because the first thing that
    /// happened is what the run is about.
    var groupSystemImage: String {
        items.first.flatMap { ToolFamily.of($0.toolName) }?.systemImage ?? "wrench.and.screwdriver"
    }
}

enum TranscriptRows {
    /// Fold neighbouring quiet tool calls into one row; leave everything else
    /// exactly as it was.
    ///
    /// "Neighbouring" is literal, and deliberately so: an assistant message, a
    /// thinking block, an orphaned tool result or a non-folding tool between two
    /// calls ends the run. What the user reads is the shape of the work, and a
    /// paragraph of explanation between two commands is exactly that boundary.
    static func group(_ items: [TranscriptItem]) -> [TranscriptRow] {
        var rows: [TranscriptRow] = []
        var run: [TranscriptItem] = []

        func flush() {
            guard !run.isEmpty else { return }
            rows.append(.group(run))
            run = []
        }

        for item in items {
            if item.kind == .toolCall, ToolFamily.of(item.toolName) != nil {
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
    /// that carry neither.
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
