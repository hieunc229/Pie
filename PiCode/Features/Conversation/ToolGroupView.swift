//
//  ToolGroupView.swift
//  PiCode
//
//  The dimmed, folded line that the quiet tool calls get instead of a card.
//
//  One line — "Run command", "Edited files", "Read files" — with the call's own
//  summary beside it, closed by default. Clicking it opens the content; for a run
//  of several calls, clicking it opens a *list* of those calls, and clicking one of
//  them opens that call's output. Two levels, because a turn that ran six commands
//  has six outputs and showing all of them on one click is the noise this exists to
//  remove.
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
//  pointer lifts the dimming, and the tooltip names what will happen. The same is
//  true of the `Thinking` line in `TranscriptRowView`, so the transcript has one
//  way of saying "there is more under this".
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
                    // One call: the content *is* the list, so it opens directly
                    // under the line rather than behind a second click.
                    ToolCallContent(item: item, controller: controller)
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
        .help(isExpanded ? "Hide the details of these calls" : "Show the details of these calls")
        .accessibilityLabel("\(row.groupTitle), \(items.count) call\(items.count == 1 ? "" : "s")")
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
            Text("\(items.count) calls")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    /// Running, failed or done — the folded line still has to carry the state, since
    /// it is all the user sees until they open it.
    @ViewBuilder
    private var status: some View {
        if let running = items.last(where: { $0.toolStatus == .running }) {
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

/// One call inside an opened run: its own dimmed line, and its own content.
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

                    Text(item.foldedSummary)
                        .font(.callout.monospaced())
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
                    } else if item.toolStatus == .running {
                        ProgressView().controlSize(.small)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }

            if isExpanded {
                ToolCallContent(item: item, controller: controller)
                    .padding(.leading, ConversationLayout.nestedIndent)
            }
        }
    }

    private var familyIcon: String {
        ToolFamily.of(item.toolName)?.systemImage ?? "wrench.and.screwdriver"
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
