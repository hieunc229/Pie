//
//  ToolCallCard.swift
//  PiCode
//
//  The card a tool call gets when it is *not* one of the quiet, repeating actions.
//
//  A `bash`, an `edit` or a `read` used to be a card too, which is what the
//  transcript's folding exists to fix: five cards in a row bury the conversation.
//  Those three families are drawn as one dimmed, collapsed line instead
//  (`ToolGroupView`), and this card is what everything else keeps — a `grep`, a
//  `webfetch`, a `task`, a `todo`, and any tool PiCode does not know.
//
//  Tool rows are keyed by Pi's `toolCallId`, so this card keeps updating in place
//  while the tool runs and then again when the authoritative tool result arrives.
//

import SwiftUI

struct ToolCallCard: View {
    var item: TranscriptItem
    var controller: PiSessionController

    @State private var isInputExpanded = false
    @State private var isDetailsExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if !isInputExpanded, !item.toolInputSummary.isEmpty {
                Text(item.toolInputSummary)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Arguments, the files it touched, the output and the structured
            // result — the same view the folded rows draw, so the two cannot
            // describe the same call differently.
            ToolCallContent(item: item,
                            controller: controller,
                            showsArguments: isInputExpanded,
                            showsDetails: isDetailsExpanded)
        }
        .padding(11)
        .background(background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(borderColor)
        )
        .contextMenu {
            if let output = item.toolOutput, !output.isEmpty {
                Button("Copy Output") { WorkspaceLauncher.copyToPasteboard(output) }
            }
            if let arguments = item.toolArguments {
                Button("Copy Arguments") { WorkspaceLauncher.copyToPasteboard(arguments.prettyDescription) }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: toolIcon)
                .imageScale(.medium)
                .foregroundStyle(statusTint)

            Text(item.toolName ?? "tool")
                .font(.callout.weight(.semibold))

            statusPill

            if let duration = item.duration, item.toolStatus.isTerminal || item.toolStatus == .running {
                Text(Format.duration(duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)

            if item.toolArguments != nil {
                Button {
                    isInputExpanded.toggle()
                } label: {
                    Image(systemName: isInputExpanded ? "chevron.up" : "chevron.down")
                        .imageScale(.small)
                }
                .buttonStyle(.borderless)
                .help(isInputExpanded ? "Hide arguments" : "Show arguments")
            }

            if item.toolDetails != nil, !(item.toolDetails?.isNull ?? true) {
                Button {
                    isDetailsExpanded.toggle()
                } label: {
                    Image(systemName: "curlybraces")
                        .imageScale(.small)
                }
                .buttonStyle(.borderless)
                .help(isDetailsExpanded ? "Hide structured result" : "Show structured result")
            }

            CopyButton(text: copyText, help: "Copy tool output")
        }
    }

    @ViewBuilder
    private var statusPill: some View {
        switch item.toolStatus {
        case .pending:
            StatusPill(text: "Queued", systemImage: "clock", tint: .secondary)
        case .running:
            StatusPill(text: "Running", systemImage: "arrow.triangle.2.circlepath", tint: .accentColor, isProminent: true)
        case .success:
            StatusPill(text: "Done", systemImage: "checkmark", tint: .green)
        case .failure:
            StatusPill(text: "Failed", systemImage: "xmark", tint: .red, isProminent: true)
        case .cancelled:
            StatusPill(text: "Cancelled", systemImage: "slash.circle", tint: .orange)
        }
    }

    // MARK: - Derived

    private var isError: Bool {
        item.toolStatus == .failure || item.toolStatus == .cancelled
    }

    private var statusTint: Color {
        switch item.toolStatus {
        case .running: return .accentColor
        case .success: return .green
        case .failure: return .red
        case .cancelled: return .orange
        case .pending: return .secondary
        }
    }

    private var background: Color {
        if isError { return Color.red.opacity(0.08) }
        return Color.secondary.opacity(0.08)
    }

    private var borderColor: Color {
        switch item.toolStatus {
        case .failure: return .red.opacity(0.35)
        case .running: return .accentColor.opacity(0.35)
        default: return Color(nsColor: .separatorColor)
        }
    }

    private var toolIcon: String {
        switch (item.toolName ?? "").lowercased() {
        case "grep", "glob", "search", "find": return "magnifyingglass"
        case "webfetch", "websearch", "fetch": return "globe"
        case "task", "agent", "subagent": return "person.2"
        case "todo", "todoread", "todowrite": return "checklist"
        default: return "wrench.and.screwdriver"
        }
    }

    private var copyText: String {
        if let output = item.toolOutput, !output.isEmpty { return output }
        return item.toolInputSummary
    }
}
