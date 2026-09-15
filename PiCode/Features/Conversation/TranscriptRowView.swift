//
//  TranscriptRowView.swift
//  PiCode
//
//  One transcript row. Every Pi message role has an explicit presentation; the
//  default is to show the raw role rather than guess.
//

import SwiftUI
import AppKit

/// The transcript's one fill.
///
/// The user's own message is the only thing in the column that is not the agent's
/// output, so it is the only thing that gets a colour of its own: a pale blue.
/// `.quaternary` cannot do this — it goes the wrong way in dark mode, the same
/// reason the sidebar's search field names its own fill (§12) — so the appearance
/// is asked for explicitly, and in dark mode the hue is kept and the light is
/// dropped, because a fill that pale glares against a dark background.
///
/// It is deliberately *blue* rather than the accent colour: the accent follows the
/// window's focus (and the user's system setting), and a message colour that
/// changes when a window loses focus is not a message colour.
enum TranscriptStyle {
    /// The transcript has **one size** — the app's one reading size, shared with
    /// the sidebar menu and the composer (`Typography.baseSize`). A conversation is
    /// not a document: a heading larger than the paragraph under it, or an action
    /// line smaller than the reply it sits between, makes the reader's eye jump for
    /// no gain — and the reply is the thing being read. Headings keep their weight
    /// and code keeps its monospace, but nothing in this column changes size, so a
    /// turn reads as one piece of writing. Change it here and the content, the
    /// actions and the folded lines all change together.
    static let text: Font = Typography.body

    /// Code, commands, paths and JSON: the same size as prose, in monospace.
    static let code: Font = Typography.code

    /// The transcript is read as prose, and prose wants more air between lines
    /// than the system gives it. The target is 1.6× the base font's natural line
    /// height, but `.lineSpacing` only adds the *extra* points on top of that
    /// natural height — so the extra is derived from `Typography.baseSize` rather
    /// than hardcoded, and stays honest if the reading size changes.
    static let lineHeightMultiple: CGFloat = 1.6

    /// A little more air between lines than the system default, wherever text wraps
    /// — prose, reasoning, output. Monospaced output is the densest thing on the
    /// page and the thing most likely to be read line by line, so it gets it too.
    static var lineSpacing: CGFloat {
        let natural = NSLayoutManager().defaultLineHeight(for: .systemFont(ofSize: Typography.baseSize))
        return max(0, Typography.baseSize * lineHeightMultiple - natural)
    }

    static func userBubbleFill(_ scheme: ColorScheme) -> Color {
        switch scheme {
        case .dark: return Color(.sRGB, red: 0.20, green: 0.42, blue: 0.68, opacity: 0.40)
        default: return Color(.sRGB, red: 0.84, green: 0.91, blue: 0.99, opacity: 1)
        }
    }
}

struct TranscriptRowView: View {
    var item: TranscriptItem
    var controller: PiSessionController

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            switch item.kind {
            case .user: userRow
            case .assistant: assistantRow
            // Reasoning is never drawn. Inside a run it is part of the fold but not
            // one of its steps (`TranscriptRow.visibleSteps`); on its own — which the
            // grouping never produces, but a row built by hand might — it draws
            // nothing at all rather than a line that opens onto a draft.
            case .thinking: EmptyView()
            case .toolCall: ToolCallCard(item: item, controller: controller)
            case .toolResult: toolResultRow
            case .system: systemRow
            case .error: errorRow
            case .compaction: compactionRow
            case .retry: retryRow
            case .turnDuration: turnRow
            }
        }
        .handlesPiCodeLinks()
    }

    // MARK: - User

    /// The user's own message: the text, and a fill, and nothing else.
    ///
    /// It used to carry a `You` badge, an avatar, a timestamp and a copy button,
    /// and a reply used to carry the model's name, the token count, the cost and the
    /// stop reason. None of that is the conversation: the transcript is what was
    /// said, and everything else is a fact about the turn that the inspector's
    /// Context pane and the message's own context menu already hold. Copy and branch
    /// are on that menu, where they cost nothing until asked for.
    private var userRow: some View {
        Text(item.text)
            .font(TranscriptStyle.text)
            .lineSpacing(TranscriptStyle.lineSpacing)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(TranscriptStyle.userBubbleFill(colorScheme),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        // The spec calls for a compact prompt bubble on the trailing edge, so the
        // bubble hugs its text and is capped rather than spanning the transcript.
        .frame(maxWidth: 520, alignment: .trailing)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .opacity(item.isStreaming ? 0.75 : 1)
        .contextMenu {
            Button("Copy Message") { WorkspaceLauncher.copyToPasteboard(item.text) }
            if let entryId = item.forkEntryId {
                Button("Fork from Here…") {
                    Task { await controller.fork(fromEntryId: entryId) }
                }
            }
        }
    }

    // MARK: - Assistant

    /// A reply is its content. No `sparkles`, no model name, no `streaming` pill, no
    /// token/cost/stop-reason line — `toolUse` was the last of those and the least
    /// useful: it named the mechanism of the turn in the middle of the answer.
    private var assistantRow: some View {
        MarkdownView(text: item.text, isStreaming: item.isStreaming)
            .contextMenu {
                Button("Copy Message") { WorkspaceLauncher.copyToPasteboard(item.text) }
                // Pi forks at user messages (`get_fork_messages` returns user entries
                // only), so an assistant reply branches from the message that asked
                // for it — the text Pi hands back is that message, ready to edit.
                if let entryId = item.forkEntryId {
                    Button("Branch from the message above…") {
                        Task { await controller.fork(fromEntryId: entryId) }
                    }
                }
            }
    }

    // MARK: - Tool result without a call

    private var toolResultRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "wrench.and.screwdriver")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
                Text("Tool result\(item.toolName.map { ": \($0)" } ?? "")")
                    .font(TranscriptStyle.text.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                rowActions
            }
            CollapsibleText(text: item.toolOutput ?? item.text, language: .plain)
        }
        .padding(10)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 9))
    }

    // MARK: - System / error / compaction / retry

    private var systemRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .imageScale(.small)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                if let badge = item.badge {
                    Text(badge)
                        .font(TranscriptStyle.text.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                MarkdownInlineText(source: item.text)
                    .font(TranscriptStyle.text)
                    .lineSpacing(TranscriptStyle.lineSpacing)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 9))
    }

    private var errorRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 3) {
                Text("Pi reported an error")
                    .font(TranscriptStyle.text.weight(.semibold))
                Text(item.errorMessage ?? item.text)
                    .font(TranscriptStyle.text)
                    .lineSpacing(TranscriptStyle.lineSpacing)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if let stopReason = item.stopReason {
                    Text("stop reason: \(stopReason)")
                        .font(TranscriptStyle.code)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.red.opacity(0.35)))
    }

    /// A compaction is a fact, not a document: one line saying the context was
    /// folded (or that a branch was summarised) and nothing else. The summary text
    /// is a compression of the conversation that was just replaced — it is not what
    /// anyone is reading the transcript for, and a wall of it in the middle of the
    /// conversation is the noise this row used to be. It stays on the context menu
    /// so it is not unreachable.
    private var compactionRow: some View {
        let kind = item.summaryKind ?? .compaction
        return HStack(spacing: 8) {
            Image(systemName: kind.systemImage)
                .imageScale(.small)
                .foregroundStyle(.secondary)
            Text(kind.label)
                .font(TranscriptStyle.text)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .contextMenu {
            Button("Copy Summary") { WorkspaceLauncher.copyToPasteboard(item.text) }
        }
    }

    private var retryRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.clockwise")
                .imageScale(.small)
                .foregroundStyle(.orange)
            Text(item.text)
                .font(TranscriptStyle.text)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    private var turnRow: some View {
        HStack(spacing: 8) {
            Rectangle().fill(.separator).frame(height: 1)
            Text(item.text)
                .font(TranscriptStyle.text)
                .foregroundStyle(.tertiary)
                .fixedSize()
            Rectangle().fill(.separator).frame(height: 1)
        }
    }

    // MARK: - Row actions

    @ViewBuilder
    private var rowActions: some View {
        HStack(spacing: 8) {
            if let timestamp = item.timestamp {
                Text(Format.timestamp(timestamp))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            CopyButton(text: copyText, help: "Copy this message")
        }
    }

    private var copyText: String {
        switch item.kind {
        case .toolCall, .toolResult: return item.toolOutput ?? item.text
        default: return item.text
        }
    }
}
