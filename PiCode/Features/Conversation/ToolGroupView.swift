//
//  ToolGroupView.swift
//  PiCode
//
//  The dimmed, folded line that the quiet rows get instead of a card.
//
//  One line — "Thinking", "Run command", "Edited files", "Read files" — with the
//  call's own summary beside it, closed by default. Clicking it opens the content;
//  for a run of several steps, clicking it opens a *list* of those steps, and
//  clicking one of them opens that step's output or reasoning. Two levels, because
//  a turn that ran six commands has six outputs and showing all of them on one
//  click is the noise this exists to remove.
//
//  A reasoning step is one of the steps: inside an opened run it is a line that
//  says `Thinking`, and opening it shows the reasoning. It is identified by its
//  family rather than by a preview of the text, because reasoning is a messy first
//  draft and a middle-truncated fragment of it on a collapsed line says nothing.
//
//  Two things are deliberately *not* folded away:
//
//    * a failure. A collapsed row whose content failed has to say so on the line,
//      or the transcript hides the only thing worth reading;
//    * a command that is still running. The line keeps a spinner and its elapsed
//      time, so "Pi is doing something" stays visible without being expanded.
//
//  There is no chevron. These lines are dimmed and short, and a column of little
//  arrows down the left of the conversation is more furniture than the fold is
//  worth; the line *is* the control — clicking anywhere along it opens it, the
//  pointer lifts the dimming, and the tooltip names what will happen. That is the
//  transcript's only way of saying "there is more under this": `TranscriptRowView`
//  hands every quiet step here rather than drawing a line of its own.
//

import SwiftUI

struct ToolGroupView: View {
    var items: [TranscriptItem]
    var controller: PiSessionController

    @State private var isExpanded = false
    @State private var isHovering = false

    private var row: TranscriptRow { .group(items) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header

            if isExpanded {
                if items.count == 1, let item = items.first {
                    // One step: the content *is* the list, so it opens directly
                    // under the line rather than behind a second click.
                    QuietStepContent(item: item, controller: controller)
                        .padding(.top, 2)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(items) { item in
                            ToolActionRow(item: item, controller: controller)
                        }
                    }
                    .padding(.top, 2)
                    .padding(.leading, ConversationLayout.nestedIndent)
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

                Text(row.groupTitle)
                    // Dimmed, and *not* a heading: this line is a footnote to the
                    // conversation, which is the whole reason it is one line. Hovering
                    // lifts the dimming, which is the only affordance offered — the
                    // line is a click target with no chrome of its own.
                    .font(.callout)
                    .foregroundStyle(isHovering ? Color.primary : Color.secondary)

                summary

                Spacer(minLength: 0)

                status
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(isExpanded ? "Hide the details of these steps" : "Show the details of these steps")
        .accessibilityLabel("\(row.groupTitle), \(items.count) step\(items.count == 1 ? "" : "s")")
    }

    /// The one thing worth naming on a folded line: the command, or the file. Only
    /// when there is one call to name — a run of six has six answers, and its list
    /// is one click away.
    @ViewBuilder
    private var summary: some View {
        if items.count == 1, let item = items.first {
            let text = item.foldedSummary
            if !text.isEmpty {
                Text(text)
                    .font(.callout.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        } else {
            Text("\(items.count) steps")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    /// Running, failed or done — the folded line still has to carry the state, since
    /// it is all the user sees until they open it.
    @ViewBuilder
    private var status: some View {
        if row.streamingThinkingItem != nil {
            // Reasoning still arriving. Folding a `Thinking` row must not make it
            // look finished, and the reasoning itself is what the fold hides.
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

                    Text(title)
                        .font(isThinking ? .callout : .callout.monospaced())
                        .foregroundStyle(isHovering ? Color.primary : Color.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

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
                QuietStepContent(item: item, controller: controller)
                    .padding(.leading, ConversationLayout.nestedIndent)
            }
        }
    }

    private var family: QuietFamily? { QuietFamily.of(item) }

    private var isThinking: Bool { family == .thinking }

    /// The line's own text: the command or the path for a call, the family's name
    /// for reasoning.
    private var title: String {
        isThinking ? "Thinking" : item.foldedSummary
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

/// What one quiet step has under its line when it is opened: the call's arguments,
/// changes and output, or the reasoning itself.
///
/// Both `ToolGroupView` and `ToolActionRow` draw it — a run of one step opens
/// straight into it, a run of several opens into rows that open into it — so the
/// two cannot drift apart.
struct QuietStepContent: View {
    var item: TranscriptItem
    var controller: PiSessionController

    var body: some View {
        if QuietFamily.of(item) == .thinking {
            reasoning.contextMenu {
                Button("Copy Reasoning") { WorkspaceLauncher.copyToPasteboard(item.text) }
                if let entryId = item.forkEntryId {
                    Button("Branch from the message above…") {
                        Task { await controller.fork(fromEntryId: entryId) }
                    }
                }
            }
        } else {
            ToolCallContent(item: item, controller: controller)
        }
    }

    /// Reasoning is plain text, dimmed, and selectable: it is the model's own words
    /// rather than output, so it gets no output box and no copy button beyond the
    /// menu — the whole block is what one would copy.
    @ViewBuilder
    private var reasoning: some View {
        if item.text.isEmpty {
            Text("No reasoning text")
                .font(.callout)
                .foregroundStyle(.tertiary)
        } else {
            SyntaxText(text: item.text, language: .plain)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
