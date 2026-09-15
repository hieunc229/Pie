//
//  InspectorView.swift
//  PiCode
//
//  The right panel: a single viewer, not a tab bar. Whatever the user last
//  selected in the conversation — a file's contents, an edit's diff, a command's
//  output, or any other tool's result — is shown here, with its path (or a title
//  when there is no path) along the top.
//
//  Everything here is read from Pi or from the working tree on disk. The panel
//  never edits files; Pi is the only actor that changes a project.
//

import SwiftUI

struct InspectorView: View {
    @Bindable var state: AppState
    @AppStorage("inspectorTextWrap") private var wrapsText = true

    var body: some View {
        Group {
            if state.isNotificationsVisible {
                NotificationsPanel(state: state)
            } else if let controller = state.activeController, let artifact = state.inspectorArtifact {
                VStack(spacing: 0) {
                    ArtifactHeader(artifact: artifact, controller: controller, wrapsText: $wrapsText)
                    Divider()
                    ArtifactContentView(artifact: artifact, controller: controller, wrapsText: wrapsText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                EmptyStateView(
                    systemImage: "sidebar.right",
                    title: "Nothing selected",
                    message: "Click a change, a file, a command, or a tool result in the conversation to open it here."
                )
            }
        }
        .frame(maxHeight: .infinity)
        .background(AppTheme.background)
    }
}

// MARK: - Notifications

/// The notification list, shown where an artifact would be when the content
/// header's bell is on. It is the same data `PiSessionController` already keeps;
/// the panel only draws it and lets the user dismiss entries.
struct NotificationsPanel: View {
    @Bindable var state: AppState

    private var controller: PiSessionController? { state.activeController }
    private var notifications: [ExtensionNotification] { controller?.notifications ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Mirrors `ArtifactHeader`: this contextual line sits directly beneath the
    /// shared content header, with the title left and actions right.
    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "bell")
                .imageScale(.small)
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .center)

            Text("Notifications")
                .font(Typography.body)
                .lineLimit(1)

            Spacer(minLength: 0)

            if !notifications.isEmpty {
                Button("Clear All") { controller?.dismissAllNotifications() }
                    .font(.caption)
                    .buttonStyle(.borderless)
                    .help("Dismiss every notification in this session")
            }
        }
        .padding(.horizontal, 12)
        // A contextual row beneath the shared content header.
        .padding(.vertical, 15.5)
        .background(AppTheme.background)
    }

    @ViewBuilder
    private var content: some View {
        if notifications.isEmpty {
            EmptyStateView(
                systemImage: "bell.slash",
                title: "No notifications",
                message: "Messages Pi extensions send with `notify` appear here instead of over the conversation."
            )
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(notifications.reversed()) { notification in
                        row(notification)
                        Divider().padding(.leading, 38)
                    }
                }
            }
            .background(AppTheme.background)
        }
    }

    private func row(_ notification: ExtensionNotification) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: notification.level.systemImage)
                .imageScale(.small)
                .foregroundStyle(tint(notification.level))
                .frame(width: 16, alignment: .center)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(notification.message)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                HStack(spacing: 6) {
                    if let source = notification.sourceName {
                        Text(source)
                    }
                    Text(Format.relativeTime(notification.timestamp))
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            Button {
                controller?.dismissNotification(notification.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.tertiary)
            .help("Dismiss")
            .accessibilityLabel("Dismiss notification")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }

    private func tint(_ level: ExtensionNotification.Level) -> Color {
        switch level {
        case .info: return .accentColor
        case .warning: return .orange
        case .error: return .red
        }
    }
}

/// The contextual line beneath the shared header: what is open, and where it lives. A
/// file's path is the title; a call with no file gets its own name instead. It is
/// one line only — the panel's own header is context, not a place for a second
/// summary that the content below already says.
struct ArtifactHeader: View {
    var artifact: AppState.InspectorArtifact
    var controller: PiSessionController
    @Binding var wrapsText: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .imageScale(.small)
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .center)

            Text(title)
                .font(Typography.body)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(title)

            Spacer(minLength: 0)

            Menu {
                Toggle(isOn: $wrapsText) {
                    Label("Text Wrap", systemImage: "text.justify.left")
                }
            } label: {
                Image(systemName: "gearshape")
                    .imageScale(.medium)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Viewer settings")
            .accessibilityLabel("Viewer settings")
        }
        .padding(.horizontal, 12)
        // A contextual row beneath the shared content header.
        .padding(.vertical, 15.5)
        .background(AppTheme.background)
    }

    /// The file the artifact is about, when it has one.
    private var path: String? {
        switch artifact {
        case .file(let path, _): return path
        case .change(let path): return path
        case .tool(let id):
            guard let item = item(id), item.kind == .toolCall else { return nil }
            return item.toolFilePath
        }
    }

    private var title: String {
        if let path { return path.abbreviatingHomeDirectory }
        switch artifact {
        case .file(let path, _), .change(let path):
            return (path as NSString).lastPathComponent
        case .tool(let id):
            guard let item = item(id) else { return "Tool" }
            if item.kind == .toolCall {
                return item.commandText == nil ? (item.toolName ?? "Tool") : "Command"
            }
            return item.toolName ?? "Tool result"
        }
    }

    private var systemImage: String {
        switch artifact {
        case .change: return "plusminus.circle"
        case .file: return "doc.text"
        case .tool(let id):
            guard let item = item(id) else { return "wrench.and.screwdriver" }
            return QuietFamily.of(item)?.systemImage ?? "wrench.and.screwdriver"
        }
    }

    private func item(_ id: String) -> TranscriptItem? {
        controller.items.first { $0.id == id }
    }
}

/// The body of the panel: the selected call, file, or diff, with all the room the
/// column has.
struct ArtifactContentView: View {
    var artifact: AppState.InspectorArtifact
    var controller: PiSessionController
    var wrapsText: Bool

    var body: some View {
        switch artifact {
        case .tool(let id):
            if let item = controller.items.first(where: { $0.id == id }) {
                InspectorToolArtifactView(item: item, wrapsText: wrapsText)
            } else {
                EmptyStateView(
                    systemImage: "questionmark.folder",
                    title: "Not available",
                    message: "This call is no longer part of the conversation."
                )
            }
        case .file(let path, let line):
            FileArtifactView(path: path, line: line, wrapsText: wrapsText)
        case .change(let path):
            ChangeArtifactView(path: path, controller: controller, wrapsText: wrapsText)
        }
    }
}

/// A file on disk, in the same numbered, highlighted viewer the file browser used.
struct FileArtifactView: View {
    var path: String
    var line: Int?
    var wrapsText: Bool

    @State private var preview: FilePreview?

    var body: some View {
        Group {
            if let preview {
                if let error = preview.error {
                    BannerView(level: .error, title: "Cannot preview this file", message: error, onDismiss: nil)
                        .padding(12)
                    Spacer(minLength: 0)
                } else {
                    CodeViewer(
                        text: preview.text,
                        language: preview.language,
                        highlightLine: line,
                        wrapsText: wrapsText
                    )
                }
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .task(id: path) { preview = FilePreviewLoader.load(path: path) }
    }
}

/// A file the agent changed, as a working-tree diff. It is resolved against the
/// same lists the Changes pane used — the session's own writes first, then git —
/// so a path Pi reported relative to the project still finds its status.
struct ChangeArtifactView: View {
    var path: String
    var controller: PiSessionController
    var wrapsText: Bool

    @State private var diff: String?
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView().controlSize(.small).padding(16)
            } else if let diff, !diff.isEmpty {
                DiffView(diff: diff, wrapsText: wrapsText)
            } else {
                EmptyStateView(
                    systemImage: "doc.text.magnifyingglass",
                    title: "No text diff",
                    message: "This file is binary, untracked, or unchanged on disk. Open the edit call itself to see the change Pi made."
                )
            }
        }
        .task(id: path) { await load() }
    }

    private func load() async {
        isLoading = true
        diff = await controller.diff(for: resolvedChange())
        isLoading = false
    }

    private func resolvedChange() -> GitFileChange {
        let absolute = path.isAbsolutePath
            ? path
            : (controller.projectPath as NSString).appendingPathComponent(path)
        let candidates = controller.git.changes + controller.recentFileChanges.map {
            GitFileChange(path: $0.path, oldPath: nil, status: $0.kind.gitStatus, isStaged: false,
                          additions: $0.additions, deletions: $0.deletions)
        }
        if let match = candidates.first(where: { $0.path == path || $0.path == absolute }) {
            return match
        }
        return GitFileChange(path: path, oldPath: nil, status: .modified, isStaged: false,
                             additions: nil, deletions: nil)
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
    var wrapsText = false

    var body: some View {
        GeometryReader { geometry in
            ScrollView(wrapsText ? .vertical : [.vertical, .horizontal]) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(lines) { line in
                        HStack(alignment: .firstTextBaseline, spacing: 0) {
                            Text(line.oldLine.map { String($0) } ?? "")
                                .frame(width: 42, alignment: .trailing)
                                .padding(.trailing, 8)
                                .foregroundStyle(.tertiary)
                                .background(line.gutterBackground)

                            Text(line.newLine.map { String($0) } ?? "")
                                .frame(width: 42, alignment: .trailing)
                                .padding(.trailing, 8)
                                .foregroundStyle(.tertiary)
                                .background(line.gutterBackground)

                            Text(line.marker)
                                .frame(width: 20, alignment: .center)
                                .foregroundStyle(line.markerColor)

                            Text(line.text)
                                .foregroundStyle(line.foreground)
                                .fixedSize(horizontal: !wrapsText, vertical: false)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.trailing, 12)
                        }
                        .font(Typography.codeBlockCompact)
                        .frame(maxWidth: .infinity, minHeight: 19, alignment: .leading)
                        .background(line.background)
                        .textSelection(.enabled)
                    }
                }
                .frame(minWidth: geometry.size.width, alignment: .leading)
            }
        }
        .background(AppTheme.background)
    }

    private var lines: [GitDiffLine] { InspectorArtifactRendering.parseDiff(diff) }
}
