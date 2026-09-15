//
//  TranscriptRows.swift
//  PiCode
//
//  How the transcript is *laid out*: a turn's work folds into one line, and the
//  words the user is actually reading — their own message, and Pi's answer — stay
//  as rows.
//
//  Pi's own output is noisy. A turn that thinks, reads three files and runs two
//  commands arrives as a dozen rows, and a card per call — each with its own name,
//  status pill, duration and output box — buries the conversation the user is
//  reading. A finished turn is shown instead as one dimmed line, collapsed by
//  default: “Worked for 1m 12s”, opening onto the calls Pi made; each call opens
//  its own content in the inspector. A note Pi wrote between calls is prose, not
//  process, so it stays a normal message and breaks the fold where it was written.
//
//  Reasoning is not drawn at all. It is folded with the run — it is why the run took
//  the time it did, and it keeps the line live while it streams — but it is not one
//  of the steps the run opens onto, and a run that is only reasoning is not a row.
//  The user asked for the work and the answer, not Pi's first draft.
//
//  What folds is a *shape*, not a tool: reasoning, calls and notes belong together
//  because in Pi's output they are literally interleaved — thinking, call, note,
//  thinking, call. The same runs form while the turn is still arriving; only the
//  headline changes, because a line that is still going cannot claim a duration
//  the turn has not earned. It becomes one “Worked for” row once the turn is over.
//
//  A run that failed keeps no “Failed” pill on the finished line: the failure is
//  the task's own, the step inside the run still says so, and a line that reports
//  the run should not repeat it. A run still going does keep the pill, so the one
//  line the user is watching never hides a failure it just saw.
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

    /// The whole line when this family is on its own: one call, one line. Singular,
    /// because a family on its own is one call — the count decides between this and
    /// `pluralLabel`.
    var label: String {
        switch self {
        case .command: return "Ran command"
        case .edit: return "Edited file"
        case .read: return "Read file"
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
        case .command: return "Ran command"
        case .edit: return "Edited file"
        case .read: return "Read file"
        case .thinking: return "Thinking"
        }
    }

    /// …and when the run holds several of the same family. Only a command has a
    /// singular, and reasoning reads the same however much of it there is.
    var pluralLabel: String {
        switch self {
        case .command: return "Ran commands"
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
        case .command: return count == 1 ? "ran command" : "ran commands"
        case .edit: return count == 1 ? "edited file" : "edited files"
        case .read: return count == 1 ? "read file" : "read files"
        case .thinking: return "thinking"
        }
    }
}

/// One row of the transcript. Everything is `.item` except the folded runs.
///
/// `isLiveTurn` says whether the turn this row belongs to is still running. It is
/// carried on the row rather than derived from the run's own items because a run
/// of calls can all be finished while the turn is not: Pi may be thinking, or
/// writing the answer, and a finished sub-run must not claim “Worked for 2s” in
/// the middle of the work. Only a completed turn earns the duration line (§11).
enum TranscriptRow: Identifiable {
    case item(TranscriptItem)
    case group([TranscriptItem], isLiveTurn: Bool = false)

    var id: String {
        switch self {
        case .item(let item):
            return item.id
        // Keyed by the group's *first* item, not its contents: appending another
        // call to a run must not change the row's identity, or a turn that is still
        // streaming would fold the row back up while the user is reading it.
        case .group(let items, _):
            return "group-\(items.first?.id ?? "empty")"
        }
    }

    var items: [TranscriptItem] {
        switch self {
        case .item(let item): return [item]
        case .group(let items, _): return items
        }
    }

    /// Whether this row is part of a turn that is still running.
    var isLiveTurn: Bool {
        switch self {
        case .item: return false
        case .group(_, let isLiveTurn): return isLiveTurn
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
    /// first thing that happened is what the run is about. A group with no family
    /// at all is impossible — `foldableRows` only groups items `QuietFamily.of`
    /// knows — so the wrench is a defensive default, not a case.
    var groupSystemImage: String {
        visibleSteps.compactMap { QuietFamily.of($0) }.first?.systemImage
            ?? "wrench.and.screwdriver"
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

    /// The line the transcript draws for this run: what it cost once the *turn* is
    /// over — “Worked for 1m 12s” — and the family list while it is still going,
    /// because a duration that is still growing is a clock rather than a result.
    ///
    /// The test is the turn's liveness, not the run's: while Pi is still working
    /// the line names the families, so it never claims a duration the turn has not
    /// earned.
    var headline: String {
        if !isLiveTurn, let duration = workedDuration {
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
    /// A turn is the span between user messages. Only the **last** span can still
    /// be running: a turn the user has already sent a new message after is over by
    /// definition, however Pi left it. While that last span is live its runs are
    /// folded the same way, but the line names the families instead of a duration —
    /// the work is still arriving, so there is nothing to time yet. Once the turn is
    /// over the whole turn becomes one row: “Worked for 1m 12s”, openable to the
    /// same steps. A note Pi wrote between calls is left in the open as an ordinary
    /// message. Nothing is invented — the fold is a rearrangement of Pi's own rows.
    ///
    /// `isWorking` is the controller's own “Pi is working” state, and it is the
    /// authority on the last turn's liveness. The item list alone cannot say the
    /// turn is over: between two steps — after a call has reached a terminal
    /// status and before the next item arrives — every item can look finished
    /// while Pi is still thinking, and folding then would show “Worked for …”
    /// behind a spinner that is still turning. When `isWorking` is false the item
    /// list decides, which is what a session read back from disk needs (it has no
    /// controller and no live turn).
    static func group(_ items: [TranscriptItem], isWorking: Bool = false) -> [TranscriptRow] {
        var rows: [TranscriptRow] = []
        var segment: [TranscriptItem] = []

        func flush(canBeLive: Bool) {
            guard !segment.isEmpty else { return }
            rows.append(contentsOf: turnRows(segment, canBeLive: canBeLive, isWorking: isWorking))
            segment = []
        }

        for item in items {
            if item.kind == .user {
                flush(canBeLive: false)
                rows.append(.item(item))
            } else {
                segment.append(item)
            }
        }
        flush(canBeLive: true)
        return rows
    }

    /// The rows for one turn's worth of non-user items.
    private static func turnRows(_ turn: [TranscriptItem], canBeLive: Bool, isWorking: Bool) -> [TranscriptRow] {
        guard !turn.isEmpty else { return [] }
        if canBeLive, isWorking || isLive(turn) { return foldableRows(turn, isLiveTurn: true) }
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
    /// interruptions allow, and Pi's own words left in the open as ordinary rows.
    /// A note between two calls is prose, not process, so it breaks the fold where
    /// it was actually written; the last word is not lifted out and re-appended.
    private static func completedRows(_ turn: [TranscriptItem]) -> [TranscriptRow] {
        foldableRows(turn)
    }

    /// Fold every run of foldable items into one row, leaving the rest as rows.
    /// Defaults to everything a finished turn considers process.
    private static func foldableRows(
        _ items: [TranscriptItem],
        isLiveTurn: Bool = false,
        _ isFoldable: (TranscriptItem) -> Bool = { Self.isProcess($0) }
    ) -> [TranscriptRow] {
        var rows: [TranscriptRow] = []
        var run: [TranscriptItem] = []

        func flush() {
            guard !run.isEmpty else { return }
            rows.append(.group(run, isLiveTurn: isLiveTurn))
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

    /// What a finished turn folds away: the reasoning, the calls, and any orphaned
    /// tool result. A note Pi wrote between calls is the agent's answer, not the
    /// work that produced it, so it stays an ordinary row even when it interrupts a
    /// run. A compaction or another system row is not process — it stays visible.
    static func isProcess(_ item: TranscriptItem) -> Bool {
        switch item.kind {
        case .thinking, .toolCall, .toolResult: return true
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
