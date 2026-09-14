//
//  TranscriptRowView.swift
//  PiCode
//
//  One transcript row. Every Pi message role has an explicit presentation; the
//  default is to show the raw role rather than guess.
//

import SwiftUI

struct TranscriptRowView: View {
    var item: TranscriptItem
    var controller: PiSessionController

    var body: some View {
        Group {
            switch item.kind {
            case .user: userRow
            case .assistant: assistantRow
            // Reasoning is folded, and folded by `TranscriptRows` like any other
            // quiet step: a `Thinking` between two commands is part of that run,
            // and a `Thinking` on its own is a run of one. The row it draws is
            // `ToolGroupView`'s, so there is one implementation of the line.
            case .thinking: ToolGroupView(items: [item], controller: controller)
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

    private var userRow: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 6) {
                rowActions
                Text("You")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Image(systemName: "person.fill")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
            }
            Text(item.text)
                .font(.body)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
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

    private var assistantRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
                Text(item.modelName ?? controller.model?.displayName ?? "Assistant")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if item.isStreaming {
                    StatusPill(text: "streaming", tint: .secondary)
                }
                Spacer(minLength: 0)
                rowActions
            }

            MarkdownView(text: item.text, isStreaming: item.isStreaming)

            if let usage = item.usage, !usage.isEmpty, !item.isStreaming {
                HStack(spacing: 10) {
                    if usage.totalTokens > 0 {
                        Label(Format.tokens(usage.totalTokens), systemImage: "number")
                    }
                    if usage.cost > 0 {
                        Label(usage.cost.currencyString, systemImage: "dollarsign.circle")
                    }
                    if let stopReason = item.stopReason, stopReason != "stop" {
                        Label(stopReason, systemImage: "flag")
                    }
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
        }
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
                    .font(.caption.weight(.semibold))
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
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(MarkdownInline.attributed(item.text))
                    .font(.callout)
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
                    .font(.callout.weight(.semibold))
                Text(item.errorMessage ?? item.text)
                    .font(.callout)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if let stopReason = item.stopReason {
                    Text("stop reason: \(stopReason)")
                        .font(.caption.monospaced())
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
                .font(.callout)
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
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    private var turnRow: some View {
        HStack(spacing: 8) {
            Rectangle().fill(.separator).frame(height: 1)
            Text(item.text)
                .font(.caption)
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
