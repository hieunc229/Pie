//
//  InspectorView.swift
//  PiCode
//
//  The contextual inspector: Changes, Files, Terminal, Tree, Context.
//
//  Everything here is read from Pi or from the working tree on disk. The
//  inspector never edits files; Pi is the only actor that changes a project.
//

import SwiftUI

struct InspectorView: View {
    @Bindable var state: AppState

    var body: some View {
        Group {
            if let controller = state.activeController {
                VStack(spacing: 0) {
                    tabPicker
                    Divider()
                    pane(controller)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                EmptyStateView(
                    systemImage: "sidebar.right",
                    title: "No session selected",
                    message: "Open a session to inspect its changes, files, and context."
                )
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var tabPicker: some View {
        Picker("Inspector", selection: $state.inspectorTab) {
            ForEach(AppState.InspectorTab.allCases, id: \.self) { tab in
                Label(tab.label, systemImage: tab.systemImage)
                    .labelStyle(.iconOnly)
                    .help(tab.label)
                    .tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    @ViewBuilder
    private func pane(_ controller: PiSessionController) -> some View {
        switch state.inspectorTab {
        case .changes: ChangesPane(state: state, controller: controller)
        case .files: FilesPane(state: state, controller: controller)
        case .terminal: TerminalPane(controller: controller)
        case .tree: TreePane(state: state, controller: controller)
        case .context: ContextPane(state: state, controller: controller)
        }
    }
}

// MARK: - Changes

struct ChangesPane: View {
    @Bindable var state: AppState
    var controller: PiSessionController

    @State private var selectedPath: String?
    @State private var diffText: String?
    @State private var isLoadingDiff = false
    @State private var showsSessionChanges = true

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .task(id: selectedPath) { await loadDiff() }
        .onAppear { applyRequestedSelection() }
        // The selection lives here, not in the tool card, so a request from the
        // transcript has to be matched against this pane's own change list —
        // Pi reports paths relative to the project and the list may hold either
        // form.
        .onChange(of: state.selectedChangePath) { _, _ in applyRequestedSelection() }
    }

    private func applyRequestedSelection() {
        guard let requested = state.selectedChangePath else { return }
        let match = changes.first { change in
            change.path == requested || absolutePath(for: change) == requested
        }
        selectedPath = match?.path ?? requested
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Source", selection: $showsSessionChanges) {
                Text("Session").tag(true)
                Text("Git").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack(spacing: 8) {
                if let branch = controller.git.branch {
                    Label(branch, systemImage: "arrow.triangle.branch")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                DiffStatView(additions: additions, deletions: deletions)
                Spacer(minLength: 0)
                Button {
                    Task { await refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh changes")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    @ViewBuilder
    private var content: some View {
        if changes.isEmpty {
            EmptyStateView(
                systemImage: showsSessionChanges ? "checkmark.circle" : "checkmark.circle",
                title: showsSessionChanges ? "No files touched yet" : "Working tree clean",
                message: showsSessionChanges
                    ? "Files Pi edits during this session appear here."
                    : "Nothing to commit in this project."
            )
        } else {
            VStack(spacing: 0) {
                List(selection: $selectedPath) {
                    ForEach(changes) { change in
                        ChangeRow(change: change, occurrences: occurrences[change.path] ?? 1)
                            .tag(change.path)
                    }
                }
                .listStyle(.inset)
                .frame(minHeight: 140)

                Divider()
                diffView
            }
        }
    }

    @ViewBuilder
    private var diffView: some View {
        if let selectedPath, let change = changes.first(where: { $0.path == selectedPath }) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(change.path)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                    CopyButton(text: diffText ?? "")
                    Button {
                        state.openInInspector(path: absolutePath(for: change))
                    } label: {
                        Image(systemName: "doc.text.magnifyingglass")
                    }
                    .buttonStyle(.borderless)
                    .help("Show this file in the Files tab")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)

                if isLoadingDiff {
                    ProgressView().controlSize(.small).padding(10)
                } else if let diffText, !diffText.isEmpty {
                    DiffView(diff: diffText)
                } else {
                    Text("No text diff available (binary file, untracked file, or no changes on disk).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(10)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        } else {
            Text("Select a file to see its diff.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Data

    private var changes: [GitFileChange] {
        if showsSessionChanges {
            return sessionChanges
        }
        return controller.git.changes
    }

    /// Files Pi wrote during this session. Reads are intentionally excluded: a
    /// "changes" list that includes reads is not a changes list.
    private var sessionChanges: [GitFileChange] {
        let writes = controller.recentFileChanges.filter { $0.kind != .read }
        let gitByPath = Dictionary(controller.git.changes.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        var seen: Set<String> = []
        var result: [GitFileChange] = []
        for fileChange in writes.reversed() {
            guard !seen.contains(fileChange.path) else { continue }
            seen.insert(fileChange.path)
            if let match = gitByPath[fileChange.path] {
                var merged = match
                if merged.additions == nil { merged.additions = fileChange.additions }
                if merged.deletions == nil { merged.deletions = fileChange.deletions }
                result.append(merged)
            } else {
                result.append(GitFileChange(
                    path: fileChange.path,
                    oldPath: nil,
                    status: fileChange.kind.gitStatus,
                    isStaged: false,
                    additions: fileChange.additions,
                    deletions: fileChange.deletions
                ))
            }
        }
        return result.sorted { $0.path < $1.path }
    }

    private var occurrences: [String: Int] {
        var counts: [String: Int] = [:]
        for change in controller.recentFileChanges where change.kind != .read {
            counts[change.path, default: 0] += 1
        }
        return counts
    }

    private var additions: Int? {
        let values = changes.compactMap(\.additions)
        return values.isEmpty ? nil : values.reduce(0, +)
    }

    private var deletions: Int? {
        let values = changes.compactMap(\.deletions)
        return values.isEmpty ? nil : values.reduce(0, +)
    }

    private func absolutePath(for change: GitFileChange) -> String {
        (change.path as NSString).isAbsolutePath
            ? change.path
            : (controller.projectPath as NSString).appendingPathComponent(change.path)
    }

    private func refresh() async {
        await controller.refreshGit()
        await loadDiff()
    }

    private func loadDiff() async {
        guard let selectedPath, let change = changes.first(where: { $0.path == selectedPath }) else {
            diffText = nil
            return
        }
        isLoadingDiff = true
        diffText = await controller.diff(for: change)
        isLoadingDiff = false
    }
}

struct ChangeRow: View {
    var change: GitFileChange
    var occurrences: Int = 1

    var body: some View {
        HStack(spacing: 8) {
            Text(change.status.rawValue)
                .font(.caption.monospaced().weight(.semibold))
                .foregroundStyle(statusColor)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(fileName)
                    .font(.callout)
                    .lineLimit(1)
                Text(directory)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 0)
            DiffStatView(additions: change.additions, deletions: change.deletions)
            if change.isStaged {
                Image(systemName: "checkmark.seal")
                    .imageScale(.small)
                    .foregroundStyle(.tertiary)
                    .help("Staged")
            }
            if occurrences > 1 {
                Text("×\(occurrences)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .help("Pi touched this file \(occurrences) times this session")
            }
        }
        .padding(.vertical, 1)
        .help(change.status.label)
    }

    private var fileName: String { (change.path as NSString).lastPathComponent }
    private var directory: String { (change.path as NSString).deletingLastPathComponent }

    private var statusColor: Color {
        switch change.status {
        case .added, .untracked: return .green
        case .deleted: return .red
        case .conflicted: return .orange
        case .renamed, .copied: return .blue
        default: return .secondary
        }
    }
}

// MARK: - Diff rendering

struct DiffView: View {
    var diff: String

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line.text)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(line.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 0.5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(line.background)
                        .textSelection(.enabled)
                }
            }
            .padding(.vertical, 4)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private struct Line {
        var text: String
        var color: Color
        var background: Color
    }

    private var lines: [Line] {
        diff.split(separator: "\n", omittingEmptySubsequences: false).map { rawLine in
            let line = String(rawLine)
            if line.hasPrefix("+++") || line.hasPrefix("---") {
                return Line(text: line, color: .secondary, background: .clear)
            }
            if line.hasPrefix("@@") {
                return Line(text: line, color: .accentColor, background: Color.accentColor.opacity(0.08))
            }
            if line.hasPrefix("+") {
                return Line(text: line, color: .primary, background: Color.green.opacity(0.13))
            }
            if line.hasPrefix("-") {
                return Line(text: line, color: .primary, background: Color.red.opacity(0.13))
            }
            if line.hasPrefix("diff ") || line.hasPrefix("index ") || line.hasPrefix("new file") || line.hasPrefix("deleted file") {
                return Line(text: line, color: .secondary, background: .clear)
            }
            return Line(text: line, color: .primary, background: .clear)
        }
    }
}
