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

    @State private var isThinkingExpanded = false

    var body: some View {
        Group {
            switch item.kind {
            case .user: userRow
            case .assistant: assistantRow
            case .thinking: thinkingRow
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "person.fill")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
                Text("You")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                rowActions
            }
            Text(item.text)
                .font(.body)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
        }
    }

    // MARK: - Thinking

    private var thinkingRow: some View {
        DisclosureGroup(isExpanded: $isThinkingExpanded) {
            SyntaxText(text: item.text, language: .plain)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "brain")
                    .imageScale(.small)
                Text(item.isStreaming ? "Thinking…" : "Thinking")
                    .font(.caption.weight(.semibold))
                if let model = item.modelName {
                    Text(model)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary)
        }
        .onChange(of: item.isStreaming) { _, isStreaming in
            if isStreaming { isThinkingExpanded = true }
        }
        .onAppear {
            if item.isStreaming { isThinkingExpanded = true }
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

    private var compactionRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "arrow.down.right.and.arrow.up.left")
                .imageScale(.small)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.badge ?? "Compaction summary")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(item.text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 9))
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
