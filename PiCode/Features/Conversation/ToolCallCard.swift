//
//  ToolCallCard.swift
//  PiCode
//
//  Presentation for one Pi tool call: what was asked, what happened, and what
//  the model received.
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

            if isInputExpanded, let arguments = item.toolArguments {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Arguments")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    SyntaxText(text: arguments.prettyDescription, language: SyntaxLanguage(identifier: "json"))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 7))
                }
            } else if !item.toolInputSummary.isEmpty {
                Text(item.toolInputSummary)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !item.fileChanges.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(item.fileChanges) { change in
                        HStack(spacing: 8) {
                            Image(systemName: change.kind.systemImage)
                                .imageScale(.small)
                                .foregroundStyle(tint(for: change.kind))
                            PathLabel(path: change.path, emphasizeLastComponent: false)
                            Spacer(minLength: 0)
                            DiffStatView(additions: change.additions, deletions: change.deletions)
                            Button {
                                WorkspaceLauncher.reveal(resolved(change.path))
                            } label: {
                                Image(systemName: "arrow.up.forward.app")
                                    .imageScale(.small)
                            }
                            .buttonStyle(.borderless)
                            .help("Reveal in Finder")
                        }
                        .font(.callout)
                    }
                }
            }

            if let output = item.toolOutput, !output.isEmpty {
                outputSection(output)
            } else if item.isStreaming {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Running…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            if let path = item.fullOutputPath {
                HStack(spacing: 6) {
                    Image(systemName: "doc.badge.ellipsis")
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                    Text("Pi truncated this output. Full text saved at \(path.abbreviatingHomeDirectory).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Reveal") { WorkspaceLauncher.reveal(path) }
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
            }

            if isError, let output = item.toolOutput, output.isEmpty {
                Text("This tool reported a failure without output.")
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            if isDetailsExpanded, let details = item.toolDetails, !details.isNull {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Structured result")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    SyntaxText(text: details.prettyDescription, language: SyntaxLanguage(identifier: "json"))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 7))
                }
            }
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

    // MARK: - Output

    private func outputSection(_ output: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Output")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    if controller.isStreaming, item.toolStatus == .running {
                        StatusPill(text: "streaming", tint: .secondary)
                    }
                }
                CollapsibleText(text: output, lineLimit: outputLanguage == .diff ? 40 : 16, language: outputLanguage)
            }
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
        case "read": return "doc.text"
        case "write": return "square.and.pencil"
        case "edit", "multiedit", "patch", "apply_patch": return "pencil.and.outline"
        case "bash": return "terminal"
        case "grep", "glob", "search", "find": return "magnifyingglass"
        case "webfetch", "websearch", "fetch": return "globe"
        case "task", "agent", "subagent": return "person.2"
        case "todo", "todoread", "todowrite": return "checklist"
        default: return "wrench.and.screwdriver"
        }
    }

    private var outputLanguage: SyntaxLanguage {
        switch (item.toolName ?? "").lowercased() {
        case "bash": return .shell
        case "read", "write", "edit", "multiedit":
            if let path = item.toolArguments?.string("file_path") ?? item.toolArguments?.string("path") {
                return SyntaxLanguage(path: path)
            }
            return .plain
        default:
            if let output = item.toolOutput, output.hasPrefix("diff --git") || output.hasPrefix("@@") {
                return .diff
            }
            return .plain
        }
    }

    private var copyText: String {
        if let output = item.toolOutput, !output.isEmpty { return output }
        return item.toolInputSummary
    }

    private func tint(for kind: FileChange.Kind) -> Color {
        switch kind {
        case .created: return .green
        case .modified: return .blue
        case .deleted: return .red
        case .read: return .secondary
        }
    }

    /// Tool arguments may be relative to the project; the reveal/open actions
    /// need an absolute path.
    private func resolved(_ path: String) -> String {
        if path.isAbsolutePath { return path }
        return controller.projectPath + "/" + path
    }
}
