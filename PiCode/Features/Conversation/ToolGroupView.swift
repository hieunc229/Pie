//
//  ToolGroupView.swift
//  PiCode
//
//  The dimmed, folded line that a turn's process gets instead of a card per step.
//
//  One line, closed by default. A finished turn's line is “Worked for 1m 12s”; a
//  run that is still arriving keeps the family list — "Run command", "Edited
//  files", "Read files" — with the call's own summary beside it. Clicking opens
//  the content; for a run of several steps, clicking opens a *list* of those steps,
//  and clicking one of them opens that step's terminal block, file or diff. Two
//  levels, because a turn that ran six commands has six outputs and showing all of
//  them on one click is the noise this exists to remove.
//
//  Reasoning is not a step. It belongs to the run — it is why the run took the
//  time it did, and it keeps the line live while it streams — but it is not drawn:
//  `TranscriptRow.visibleSteps` leaves it out, and a run that is only reasoning is
//  dropped by `ConversationView`. A note Pi wrote between two calls *is* a step,
//  labelled `Said`, and opening it shows the note as prose.
//
//  Two things are deliberately *not* folded away:
//
//    * a failure. A collapsed row whose content failed has to say so on the line,
//      or the transcript hides the only thing worth reading;
//    * a command that is still running. The line keeps a spinner and its elapsed
//      time, so "Pi is doing something" stays visible without being expanded.
//
//  There is a chevron, and it says one thing: this line opens. A completed run is a
//  single “Worked for 1m 12s” row, and the triangle is what tells the eye that the
//  process is under it rather than that the row is itself the whole story. The line
//  is still the control — clicking anywhere along it opens it, the pointer lifts the
//  dimming, and the tooltip names what will happen — but the affordance is no longer
//  carried by dimming alone. `TranscriptRowView` hands every quiet step here rather
//  than drawing a line of its own.
//

import SwiftUI

struct ToolGroupView: View {
    var items: [TranscriptItem]
    var controller: PiSessionController

    @State private var isExpanded = false
    @State private var isHovering = false

    private var row: TranscriptRow { .group(items) }

    /// The steps the run draws. Reasoning is part of `items` — the run keeps its
    /// duration and its live state from it — but it is not one of them.
    private var steps: [TranscriptItem] { row.visibleSteps }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header

            if isExpanded {
                if steps.count == 1, let item = steps.first {
                    // One step: the content *is* the list, so it opens directly
                    // under the line rather than behind a second click.
                    QuietStepContent(item: item, controller: controller)
                        .padding(.top, 2)
                } else {
                    // The list is *not* indented: a step's glyph belongs in the same
                    // column as the run's own glyph, so the run and everything under
                    // it read as one block and the labels line up down the page. The
                    // indent starts inside a step, where its content opens — see
                    // `ToolActionRow`.
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(steps) { item in
                            ToolActionRow(item: item, controller: controller)
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - The folded line

    private var header: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { isExpanded.toggle() }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: row.groupSystemImage)
                    .imageScale(.small)
                    .foregroundStyle(.secondary)

                Text(headline)
                    // Dimmed, and *not* a heading: this line is a footnote to the
                    // conversation, which is the whole reason it is one line. Hovering
                    // lifts the dimming, which is half the affordance — the chevron at
                    // the far end is the other half.
                    .font(Typography.body)
                    .foregroundStyle(isHovering ? Color.primary : Color.secondary)

                summary

                Spacer(minLength: 0)

                status

                Image(systemName: "chevron.right")
                    .imageScale(.small)
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(isExpanded ? "Hide the details of these steps" : "Show the details of these steps")
        .accessibilityLabel("\(headline), \(steps.count) step\(steps.count == 1 ? "" : "s")")
    }

    /// What the line says — that is `TranscriptRow`'s decision, not this view's,
    /// so the smoke test can print the same words the transcript draws.
    private var headline: String { row.headline }

    /// The one thing worth naming on a folded line: the command, or the file. Only
    /// when there is one call to name — a run of six has six answers, and its list
    /// is one click away.
    @ViewBuilder
    private var summary: some View {
        if steps.count == 1, let item = steps.first {
            let text = item.foldedSummary
            if !text.isEmpty {
                Text(text)
                    .font(Typography.code)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        } else {
            Text("\(steps.count) steps")
                .font(Typography.body)
                .foregroundStyle(.tertiary)
        }
    }

    /// Running, failed or done — the folded line still has to carry the state, since
    /// it is all the user sees until they open it.
    @ViewBuilder
    private var status: some View {
        if row.streamingThinkingItem != nil {
            // Reasoning still arriving. The reasoning itself is not drawn, but the
            // line must not look finished while Pi is still working.
            ProgressView().controlSize(.small)
        } else if let running = items.last(where: { $0.toolStatus == .running }) {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                if let duration = running.duration {
                    Text(Format.duration(duration))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
        } else if items.contains(where: { $0.toolStatus == .failure }) {
            StatusPill(text: "Failed", systemImage: "xmark", tint: .red, isProminent: true)
        } else if items.contains(where: { $0.toolStatus == .cancelled }) {
            StatusPill(text: "Cancelled", systemImage: "slash.circle", tint: .orange)
        }
    }
}

/// One step inside an opened run: its own dimmed line, and its own content.
struct ToolActionRow: View {
    var item: TranscriptItem
    var controller: PiSessionController

    @State private var isExpanded = false
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: familyIcon)
                        .imageScale(.small)
                        .foregroundStyle(statusTint)

                    Text(stepLabel)
                        .font(Typography.body)
                        .foregroundStyle(isHovering ? Color.primary : Color.secondary)
                        .lineLimit(1)

                    if let summary = stepSummary {
                        Text(summary)
                            .font(Typography.code)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer(minLength: 0)

                    diffStats

                    if let duration = item.duration, item.toolStatus.isTerminal {
                        Text(Format.duration(duration))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }

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

            if isExpanded {
                // The one indent: a step's content sits under the step, in from the
                // glyph column it shares with everything else in the run.
                QuietStepContent(item: item, controller: controller)
                    .padding(.leading, ConversationLayout.nestedIndent)
            }
        }
    }

    private var family: QuietFamily? { QuietFamily.of(item) }

    private var isNarration: Bool { item.kind == .assistant }

    /// The step's family name: "Run command", "Edited file", "Read file",
    /// "Thinking", or "Said" for the notes Pi wrote between calls. Every action row
    /// carries a label, so an opened run reads as a list of actions rather than a
    /// list of bare file names.
    private var stepLabel: String {
        if isNarration { return "Said" }
        return family?.stepLabel ?? "Action"
    }

    /// What the step names, beside its label. A command names itself; a read or an
    /// edit names its file by the last path component, because the row is a line
    /// and the path is not — the full path stays in the item's arguments. A note
    /// gets its own opening words instead.
    private var stepSummary: String? {
        if isNarration {
            let text = item.text.oneLinePreview(limit: 120)
            return text.isEmpty ? nil : text
        }
        switch family {
        case .read, .edit:
            return item.toolFileDisplayName
        default:
            let text = item.foldedSummary
            return text.isEmpty ? nil : text
        }
    }

    private var familyIcon: String {
        if isNarration { return "text.bubble" }
        return family?.systemImage ?? "wrench.and.screwdriver"
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

/// What one quiet step has under its line when it is opened: the terminal block a
/// command ran, the file a read returned, the diff an edit made, or the prose of a
/// note Pi wrote between calls.
///
/// Both `ToolGroupView` and `ToolActionRow` draw it — a run of one step opens
/// straight into it, a run of several opens into rows that open into it — so the
/// two cannot drift apart. The three repeating actions get their own shape rather
/// than the generic arguments-and-output form: the arguments are Pi's bookkeeping,
/// and the row above already says what ran and on what file.
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
