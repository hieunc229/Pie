//
//  TranscriptRows.swift
//  PiCode
//
//  How the transcript is *laid out*: a turn's work folds into one line, and the
//  words the user is actually reading — their own message, and Pi's answer — stay
//  as rows.
//
//  Pi's own output is noisy. A turn that thinks, reads three files, runs two
//  commands and narrates between them arrives as a dozen rows, and a card per call
//  — each with its own name, status pill, duration and output box — buries the
//  conversation the user is reading. A finished turn is shown instead as one dimmed
//  line, collapsed by default: “Worked for 1m 12s”, whose expansion lists the steps
//  (the calls Pi made, and the notes it wrote between them), whose own expansion
//  shows the command's output. Pi's last message in the turn is left out of the fold
//  — it is the answer, not the work that produced it.
//
//  Reasoning is not drawn at all. It is folded with the run — it is why the run took
//  the time it did, and it keeps the line live while it streams — but it is not one
//  of the steps the run opens onto, and a run that is only reasoning is not a row.
//  The user asked for the work and the answer, not Pi's first draft.
//
//  What folds is a *shape*, not a tool: reasoning, calls and notes belong together
//  because in Pi's output they are literally interleaved — thinking, call, note,
//  thinking, call. While the turn is still arriving the fold is built the way it
//  always was, one run of neighbouring steps at a time, so the work can be watched
//  as it lands; it becomes one “Worked for” row only once the turn is over.
//
//  Failures and system rows are not folded: a collapsed line whose content failed,
//  or a compaction, has to say so in the open.
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

    /// The label for one step *inside* an opened run. Singular, because the row is
    /// one call and not the run; the group line uses `label`/`pluralLabel`, and this
    /// is what each action under it says. The specific command or path is not the
    /// label — it is the summary beside it, the way the run's own line pairs a
    /// family with what it touched.
    var stepLabel: String {
        switch self {
        case .command: return "Run command"
        case .edit: return "Edited file"
        case .read: return "Read file"
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
    /// The steps a folded run actually draws. Reasoning is part of the run — it is
    /// why the run took the time it did, and it keeps the run live while it streams
    /// — but it is not shown: the fold is for the work and the answer, not Pi's
    /// first draft. Everything else in the run is a step.
    var visibleSteps: [TranscriptItem] {
        items.filter { $0.kind != .thinking }
    }

    /// "Run command" for a single call, "Thinking, edited files, run commands" for a
    /// run.
    ///
    /// The families are named in the order they first appear, which is the order the
    /// agent did them in, so the line reads as a summary of the work rather than as
    /// an inventory of it — and each family is named once however many times it
    /// recurs, because "thinking, thinking, thinking" is the noise this exists to
    /// remove. Reasoning is not named: it is hidden from the transcript, and a title
    /// cannot announce a step that has no row.
    var groupTitle: String {
        var order: [QuietFamily] = []
        var counts: [QuietFamily: Int] = [:]
        for item in visibleSteps {
            guard let family = QuietFamily.of(item) else { continue }
            if counts[family] == nil { order.append(family) }
            counts[family, default: 0] += 1
        }
        guard let first = order.first else { return "Actions" }
        if order.count == 1 { return counts[first] == 1 ? first.label : first.pluralLabel }
        return order.enumerated()
            .map { index, family in
                let words = family.listed(count: counts[family] ?? 1)
                return index == 0 ? words.capitalizedFirst : words
            }
            .joined(separator: ", ")
    }

    /// The icon on the folded line: the first family that appears, because the
    /// first thing that happened is what the run is about. A finished turn that
    /// opens with one of Pi's notes has no family there yet, so that case falls to
    /// the bubble rather than to the generic wrench.
    var groupSystemImage: String {
        if let family = visibleSteps.compactMap({ QuietFamily.of($0) }).first {
            return family.systemImage
        }
        return visibleSteps.first?.kind == .assistant ? "text.bubble" : "wrench.and.screwdriver"
    }

    /// Whether the run is currently producing reasoning, which the folded line says
    /// in place of the reasoning itself.
    var streamingThinkingItem: TranscriptItem? {
        items.last { QuietFamily.of($0) == .thinking && $0.isStreaming }
    }

    /// How long the folded work took, from the first step that started to the last
    /// that ended.
    ///
    /// Derived from the items rather than from the controller's live clock, so a
    /// session read back from disk gets the same line as the one that just ran:
    /// replayed steps carry `timestamp` and `toolEndedAt`, and only a step the app
    /// itself ran carries `toolStartedAt`. `nil` when the span is zero — a single
    /// call whose start and end are the same instant has no duration to claim.
    var workedDuration: TimeInterval? {
        let start = items.compactMap { $0.toolStartedAt ?? $0.timestamp }.min()
        let end = items.compactMap { $0.toolEndedAt ?? $0.timestamp ?? $0.toolStartedAt }.max()
        guard let start, let end, end > start else { return nil }
        return end.timeIntervalSince(start)
    }

    /// Whether any of the run's steps is still moving. Reasoning and notes count
    /// only while they are streaming; a call counts until it reaches a terminal
    /// status.
    var isLive: Bool {
        items.contains { item in
            switch item.kind {
            case .thinking, .assistant: return item.isStreaming
            case .toolCall: return !item.toolStatus.isTerminal
            default: return item.isStreaming
            }
        }
    }

    /// The line the transcript draws for this run: what it cost once it is over —
    /// “Worked for 1m 12s” — and the family list while it is still going, because
    /// a duration that is still growing is a clock rather than a result.
    var headline: String {
        if !isLive, let duration = workedDuration {
            return "Worked for \(Format.duration(duration))"
        }
        return groupTitle
    }
}

enum TranscriptRows {
    /// Lay out the transcript: fold each finished turn's work into one line, and
    /// leave everything the user actually reads — their own message, and Pi's
    /// answer — as rows.
    ///
    /// A turn is the span between user messages. While the last one is still
    /// running its work is folded the way it always was — runs of neighbouring
    /// reasoning and calls, split wherever another row interrupts them — because
    /// the work is arriving and the user is watching it arrive. Once the turn is
    /// over that work is one thing that happened, so it becomes one row:
    /// “Worked for 1m 12s”, openable to the same steps. Pi's last words in the turn
    /// stay out of it: they are the answer, not the process. Nothing is invented —
    /// the fold is a rearrangement of Pi's own rows.
    static func group(_ items: [TranscriptItem]) -> [TranscriptRow] {
        var rows: [TranscriptRow] = []
        var segment: [TranscriptItem] = []

        func flush() {
            guard !segment.isEmpty else { return }
            rows.append(contentsOf: turnRows(segment))
            segment = []
        }

        for item in items {
            if item.kind == .user {
                flush()
                rows.append(.item(item))
            } else {
                segment.append(item)
            }
        }
        flush()
        return rows
    }

    /// The rows for one turn's worth of non-user items.
    private static func turnRows(_ turn: [TranscriptItem]) -> [TranscriptRow] {
        guard !turn.isEmpty else { return [] }
        if isLive(turn) { return liveRows(turn) }
        return completedRows(turn)
    }

    /// Whether the turn is still producing something the user should watch. A
    /// running call counts, and so does a message that is still streaming — an
    /// unfinished answer has to stay on screen rather than fold away.
    private static func isLive(_ turn: [TranscriptItem]) -> Bool {
        turn.contains { item in
            switch item.kind {
            case .thinking, .assistant: return item.isStreaming
            case .toolCall: return !item.toolStatus.isTerminal
            default: return item.isStreaming
            }
        }
    }

    /// The rows of a finished turn: the process folded into as few rows as its
    /// interruptions allow, and the answer left out in the open.
    private static func completedRows(_ turn: [TranscriptItem]) -> [TranscriptRow] {
        let answerIndex = turn.lastIndex { $0.kind == .assistant && !$0.text.isEmpty }
        var process = turn
        var answer: TranscriptItem?
        if let answerIndex {
            answer = turn[answerIndex]
            process.remove(at: answerIndex)
        }
        var rows = foldableRows(process)
        if let answer { rows.append(.item(answer)) }
        return rows
    }

    /// A turn still in flight: the old rule, unchanged. A run is broken by
    /// anything that is not itself a step, so the fold grows and splits exactly as
    /// the work arrives.
    private static func liveRows(_ items: [TranscriptItem]) -> [TranscriptRow] {
        foldableRows(items) { QuietFamily.of($0) != nil }
    }

    /// Fold every run of foldable items into one row, leaving the rest as rows.
    /// Defaults to everything a finished turn considers process.
    private static func foldableRows(
        _ items: [TranscriptItem],
        _ isFoldable: (TranscriptItem) -> Bool = { Self.isProcess($0) }
    ) -> [TranscriptRow] {
        var rows: [TranscriptRow] = []
        var run: [TranscriptItem] = []

        func flush() {
            guard !run.isEmpty else { return }
            rows.append(.group(run))
            run = []
        }

        for item in items {
            if isFoldable(item) {
                run.append(item)
            } else {
                flush()
                rows.append(.item(item))
            }
        }
        flush()
        return rows
    }

    /// What a finished turn folds away: the reasoning, the calls, the notes Pi
    /// wrote between them, and any orphaned tool result. Failures and system rows
    /// are not process — they stay visible.
    static func isProcess(_ item: TranscriptItem) -> Bool {
        switch item.kind {
        case .thinking, .toolCall, .toolResult, .assistant: return true
        default: return false
        }
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
