//
//  ToolCallContent.swift
//  PiCode
//
//  Everything a tool call has to show once it is open: what it asked for, which
//  files it touched, and what came back.
//
//  It is separate from `ToolCallCard` because two different rows draw it: the card
//  a `grep`, a `task` or an unknown tool gets, and the folded line an orphaned
//  result gets. The three repeating actions — a command, a read and an edit — are
//  not drawn here; they get their own shape in `ActionContent` rather than the
//  generic arguments-and-output form.
//

import SwiftUI

struct ToolCallContent: View {
    var item: TranscriptItem
    var controller: PiSessionController
    /// The raw arguments block. The card asks for it only when its own chevron is
    /// open; a folded row is *already* the open state, so it asks for it always.
    var showsArguments = true
    /// The structured result. Same arrangement, same reason.
    var showsDetails = true

    @Environment(\.piCodeOpenChange) private var openChange

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsArguments, let arguments = item.toolArguments {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Arguments")
                        .font(Typography.bodySemibold)
                        .foregroundStyle(.secondary)
                    SyntaxText(text: arguments.prettyDescription, language: SyntaxLanguage(identifier: "json"))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 7))
                }
            }

            if !item.fileChanges.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(item.fileChanges) { change in
                        HStack(spacing: 8) {
                            Image(systemName: change.kind.systemImage)
                                .imageScale(.small)
                                .foregroundStyle(tint(for: change.kind))
                            // Selecting the row opens the diff for that file; the
                            // reveal button next to it is the shortcut out to
                            // Finder, which is a different intent.
                            Button {
                                openChange(change.path)
                            } label: {
                                Text(change.path)
                                    .font(Typography.code)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .foregroundStyle(.primary)
                            }
                            .buttonStyle(.plain)
                            .help("Show this file's diff in the inspector")
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
                        .font(Typography.body)
                    }
                }
            }

            if let output = item.toolOutput, !output.isEmpty {
                outputSection(output)
            } else if item.isStreaming {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Running…")
                        .font(Typography.body)
                        .foregroundStyle(.secondary)
                }
            }

            if let path = item.fullOutputPath {
                HStack(spacing: 6) {
                    Image(systemName: "doc.badge.ellipsis")
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                    Text("Pi truncated this output. Full text saved at \(path.abbreviatingHomeDirectory).")
                        .font(Typography.body)
                        .foregroundStyle(.secondary)
                    Button("Reveal") { WorkspaceLauncher.reveal(path) }
                        .buttonStyle(.borderless)
                        .font(Typography.body)
                }
            }

            // A failure with nothing to show is the one thing a folded row must not
            // be able to hide, so the sentence is part of the content and not of the
            // header.
            if isFailure, item.toolOutput.map(\.isEmpty) ?? true {
                Text("This tool reported a failure without output.")
                    .font(Typography.body)
                    .foregroundStyle(.red)
            }

            if showsDetails, let details = item.toolDetails, !details.isNull {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Structured result")
                        .font(Typography.bodySemibold)
                        .foregroundStyle(.secondary)
                    SyntaxText(text: details.prettyDescription, language: SyntaxLanguage(identifier: "json"))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 7))
                }
            }
        }
    }

    // MARK: - Output

    private func outputSection(_ output: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Output")
                        .font(Typography.bodySemibold)
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

    private var isFailure: Bool {
        item.toolStatus == .failure || item.toolStatus == .cancelled
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
