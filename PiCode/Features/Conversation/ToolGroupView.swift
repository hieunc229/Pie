//
//  ToolGroupView.swift
//  PiCode
//
//  The dimmed, folded line that a turn's process gets instead of a card per step.
//
//  One line, closed by default. A finished turn's line is “Worked for 1m 12s”; a
//  run that is still arriving keeps the family list — "Run command", "Edited
//  file", "Read file" — with the call's own summary beside it. A run of several
//  steps opens onto its list, and clicking a step opens that step's terminal block,
//  file or diff in the right panel. Two levels, because a turn that ran six
//  commands has six outputs and showing all of them at once is the noise this
//  exists to remove; the panel is where a step is read, so opening it never
//  reshapes the conversation around it. A run of *one* step skips the list: there
//  is nothing to disclose, so the line is the step and clicking it opens the panel
//  directly.
//
//  Reasoning is not a step. It belongs to the run — it is why the run took the
//  time it did, and it keeps the line live while it streams — but it is not drawn:
//  `TranscriptRow.visibleSteps` leaves it out, and a run that is only reasoning is
//  dropped by `ConversationView`. A note Pi wrote between two calls is prose, not
//  process, so `TranscriptRows.isProcess` leaves it out of the fold and it stays an
//  ordinary message rather than a step in the run.
//
//  A command that is still running is not folded away either: the line keeps a
//  spinner, so "Pi is doing something" stays visible without being expanded. A
//  failure, by contrast, belongs to its task: while the turn is live the line
//  still carries the red pill, but a finished “Worked for …” line does not repeat
//  it — the step inside the run is where it is read.
//
//  A chevron says one thing: this line opens a list. It appears only on a run of
//  several steps, because that is the only run with a list under it. The line is
//  still the control — clicking anywhere along it opens the list or the step, the
//  pointer lifts the dimming, and the tooltip names what will happen.
//  `TranscriptRowView` hands every quiet step here rather than drawing a line of
//  its own.
//

import SwiftUI

struct ToolGroupView: View {
    var row: TranscriptRow
    var controller: PiSessionController

    @Environment(\.piCodeOpenTool) private var openTool
    @State private var isExpanded = false
    @State private var isHovering = false

    private var items: [TranscriptItem] { row.items }

    /// The steps the run draws. Reasoning is part of `items` — the run keeps its
    /// duration and its live state from it — but it is not one of them.
    private var steps: [TranscriptItem] { row.visibleSteps }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header

            if isExpanded {
                // The list a run of several steps opens. A step is a line that
                // opens its content in the inspector, and the indent starts inside
                // that content rather than under the labels, so the run and
                // everything under it read as one block. A run of one step never
                // gets here: it opens its content directly.
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(steps) { item in
                        ToolActionRow(item: item, controller: controller)
                    }
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - The folded line

    private var header: some View {
        Button {
            if let single = singleStep {
                openTool(single.id)
            } else {
                withAnimation(.easeOut(duration: 0.15)) { isExpanded.toggle() }
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: row.groupSystemImage)
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
                    .frame(width: 16, alignment: .center)

                Text(headline)
                    // Dimmed, and *not* a heading: this line is a footnote to the
                    // conversation, which is the whole reason it is one line. Hovering
                    // lifts the dimming, which is half the affordance — the chevron at
                    // the far end is the other half, on the runs that still open a list.
                    .font(Typography.body)
                    .foregroundStyle(isHovering ? Color.primary : Color.secondary)

                summary

                Spacer(minLength: 0)

                status

                // A run of one task has no list to disclose: the line *is* the
                // step, and clicking it opens the task's content in the right
                // panel. Only a run of several keeps the chevron.
                if singleStep == nil {
                    Image(systemName: "chevron.right")
                        .imageScale(.small)
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(singleStep == nil
            ? (isExpanded ? "Hide the details of these steps" : "Show the details of these steps")
            : "Show this in the inspector")
        .accessibilityLabel("\(headline), \(steps.count) step\(steps.count == 1 ? "" : "s")")
    }

    /// The step that opens directly when the run is a single task. A lone call has
    /// no list to lay out, so the folded line *is* the step and its content belongs
    /// in the right panel; `nil` for a run of several, where the chevron still opens
    /// the list.
    private var singleStep: TranscriptItem? {
        steps.count == 1 ? steps.first : nil
    }

    /// What the line says — that is `TranscriptRow`'s decision, not this view's,
    /// so the smoke test can print the same words the transcript draws.
    private var headline: String { row.headline }

    /// The one thing worth naming on a folded line: the command, or the file. Only
    /// when there is one call to name — a run of six has six answers, and the run's
    /// own line already names the families. The step count is deliberately not drawn,
    /// so the line stays a label rather than an inventory.
    @ViewBuilder
    private var summary: some View {
        if steps.count == 1, let item = steps.first {
            let text = item.foldedSummary
            if !text.isEmpty {
                Text(text)
                    .font(Typography.codeBlockCompact)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    /// Running or done — the folded line carries the state the user cannot see
    /// until they open the run. A failure is the task's own and is not repeated
    /// here once the turn is over; while the turn is live it is, because this line
    /// is all there is to watch. No duration is drawn on this line: the elapsed
    /// clock beside a running spinner is gone, and the step rows do not time
    /// themselves either.
    @ViewBuilder
    private var status: some View {
        if row.streamingThinkingItem != nil {
            // Reasoning still arriving. The reasoning itself is not drawn, but the
            // line must not look finished while Pi is still working.
            ProgressView().controlSize(.small)
        } else if items.last(where: { $0.toolStatus == .running }) != nil {
            // A step is still running. The line carries the spinner alone — the
            // elapsed clock is not drawn here, so the line is the action and not a
            // timer.
            ProgressView().controlSize(.small)
        } else if row.isLiveTurn, items.contains(where: { $0.toolStatus == .failure }) {
            StatusPill(text: "Failed", systemImage: "xmark", tint: .red, isProminent: true)
        } else if items.contains(where: { $0.toolStatus == .cancelled }) {
            StatusPill(text: "Cancelled", systemImage: "slash.circle", tint: .orange)
        } else if row.isLiveTurn {
            // Between two steps: Pi is thinking or about to write. The separate
            // “Pi is working” row is gone, so the live line carries the spinner.
            ProgressView().controlSize(.small)
        }
    }
}

/// One step inside an opened run: its own dimmed line. Selecting it opens that
/// call's content — the terminal block a command ran, the file a read returned,
/// the diff an edit made, or a generic tool's output — in the right panel, where
/// there is room to read it without pushing the conversation around.
struct ToolActionRow: View {
    var item: TranscriptItem
    var controller: PiSessionController

    @Environment(\.piCodeOpenTool) private var openTool
    @State private var isHovering = false

    var body: some View {
        Button {
            openTool(item.id)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: familyIcon)
                    .imageScale(.small)
                    .foregroundStyle(statusTint)
                    // Every row's glyph is given the same column, so the labels line
                    // up down the page whatever the symbol's natural width.
                    .frame(width: 16, alignment: .center)

                Text(stepLabel)
                    .font(Typography.body)
                    .foregroundStyle(isHovering ? Color.primary : Color.secondary)
                    .lineLimit(1)

                if let summary = stepSummary {
                    Text(summary)
                        .font(Typography.codeBlockCompact)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 0)

                diffStats

                if item.toolStatus == .failure {
                    Image(systemName: "xmark.circle.fill")
                        .imageScale(.small)
                        .foregroundStyle(.red)
                } else if item.toolStatus == .cancelled {
                    Image(systemName: "slash.circle")
                        .imageScale(.small)
                        .foregroundStyle(.orange)
                } else if item.toolStatus == .running || item.isStreaming {
                    ProgressView().controlSize(.small)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Show this in the inspector")
    }

    private var family: QuietFamily? { QuietFamily.of(item) }

    /// The step's family name: "Run command", "Edited file", "Read file", or
    /// "Thinking". Every action row carries a label, so an opened run reads as a
    /// list of actions rather than a list of bare file names.
    private var stepLabel: String {
        family?.stepLabel ?? "Action"
    }

    /// What the step names, beside its label. A command names itself; a read or an
    /// edit names its file by the last path component, because the row is a line
    /// and the path is not — the full path opens in the inspector's header.
    private var stepSummary: String? {
        switch family {
        case .read, .edit:
            return item.toolFileDisplayName
        default:
            let text = item.foldedSummary
            return text.isEmpty ? nil : text
        }
    }

    private var familyIcon: String {
        family?.systemImage ?? "wrench.and.screwdriver"
    }

    /// Only the calls that changed something have numbers to show; a read's chip
    /// would be an empty view with a gap in front of it.
    @ViewBuilder
    private var diffStats: some View {
        let counted = item.fileChanges.filter { ($0.additions ?? 0) > 0 || ($0.deletions ?? 0) > 0 }
        ForEach(counted) { change in
            DiffStatView(additions: change.additions, deletions: change.deletions)
        }
    }

    private var statusTint: Color {
        switch item.toolStatus {
        case .failure: return .red
        case .cancelled: return .orange
        case .running: return .accentColor
        default: return .secondary
        }
    }
}

/// What one quiet step has under its line: the terminal block a command ran, the
/// file a read returned, the diff an edit made, or the prose of a note Pi wrote
/// between calls.
///
/// `ToolActionRow` no longer draws it inline; selecting a step opens this in the
/// right panel instead, and the panel and the transcript's own cards draw the same
/// view so the two cannot describe one call differently.
struct QuietStepContent: View {
    var item: TranscriptItem
    var controller: PiSessionController

    var body: some View {
        switch QuietFamily.of(item) {
        case .command:
            CommandStepContent(item: item)
        case .read:
            ReadStepContent(item: item)
        case .edit:
            EditStepContent(item: item)
        default:
            if item.kind == .assistant {
                // A note Pi wrote between two calls. It is prose, so it renders as
                // prose; the fold is what hid it, not a different kind of row.
                MarkdownView(text: item.text)
                    .textSelection(.enabled)
            } else {
                ToolCallContent(item: item, controller: controller)
            }
        }
    }
}
