//
//  InspectorPanes.swift
//  PiCode
//
//  Files, Terminal, Tree, and Context inspector panes.
//
//  Files and Tree are strictly read-only views of the project and of Pi's
//  session tree. Terminal runs commands through Pi's own `bash` RPC so the
//  output is part of the session Pi and PiCode both see.
//

import AppKit
import SwiftUI

// MARK: - Files

struct FilesPane: View {
    @Bindable var state: AppState
    var controller: PiSessionController

    @State private var expanded: Set<String> = []
    @State private var selection: String?
    @State private var preview: FilePreview?
    @State private var showsHiddenFiles = false

    var body: some View {
        VSplitView {
            tree
                .frame(minHeight: 140)
            previewPane
                .frame(minHeight: 160)
        }
        .task(id: selection) { loadPreview() }
        .onAppear {
            if let path = state.selectedFilePath {
                selection = path
            }
        }
        .onChange(of: state.selectedFilePath) { _, newValue in
            if let newValue { selection = newValue }
        }
    }

    private var tree: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                PathLabel(path: controller.projectPath, emphasizeLastComponent: true)
                Spacer(minLength: 0)
                Toggle(isOn: $showsHiddenFiles) {
                    Image(systemName: "eye")
                }
                .toggleStyle(.button)
                .controlSize(.small)
                .help("Show hidden files")
                Button {
                    state.copyToPasteboard(controller.projectPath)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy project path")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(ProjectFileTree.children(of: controller.projectPath, includeHidden: showsHiddenFiles)) { node in
                        FileTreeRow(
                            node: node,
                            root: controller.projectPath,
                            depth: 0,
                            includeHidden: showsHiddenFiles,
                            selection: $selection,
                            expanded: $expanded
                        )
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private var previewPane: some View {
        if let selection, let preview {
            VStack(spacing: 0) {
                header(path: selection, preview: preview)
                Divider()
                if let error = preview.error {
                    BannerView(level: .error, title: "Cannot preview this file", message: error, onDismiss: nil)
                        .padding(10)
                    Spacer(minLength: 0)
                } else {
                    CodeViewer(text: preview.text, language: preview.language, highlightLine: state.selectedFileLine)
                }
            }
        } else {
            EmptyStateView(
                systemImage: "doc.text",
                title: "No file selected",
                message: "Pick a file to preview it. Pi can open the same file from a `path:line` link in its answer."
            )
        }
    }

    private func header(path: String, preview: FilePreview) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text((path as NSString).lastPathComponent)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                StatusPill(text: preview.language.label, tint: .secondary)
                if preview.truncated {
                    StatusPill(text: "preview truncated", tint: .orange)
                }
                Spacer(minLength: 0)
                CopyButton(text: path, help: "Copy path")
                Button {
                    state.composerInsertion = "@" + ProjectFileTree.relativePath(of: path, from: controller.projectPath) + " "
                } label: {
                    Image(systemName: "text.badge.plus")
                }
                .buttonStyle(.borderless)
                .help("Reference this file in the composer as @path")
                Button {
                    WorkspaceLauncher.open(path)
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                }
                .buttonStyle(.borderless)
                .help("Open with the default application")
                Button {
                    WorkspaceLauncher.reveal(path)
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .help("Reveal in Finder")
            }
            HStack(spacing: 8) {
                Text(ProjectFileTree.relativePath(of: path, from: controller.projectPath))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if preview.byteSize > 0 {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(preview.byteSize), countStyle: .file))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    private func loadPreview() {
        guard let selection else {
            preview = nil
            return
        }
        preview = FilePreviewLoader.load(path: selection)
    }
}

/// One lazily expanded directory row in the Files tree.
struct FileTreeRow: View {
    var node: FileNode
    var root: String
    var depth: Int
    var includeHidden: Bool
    @Binding var selection: String?
    @Binding var expanded: Set<String>

    @State private var children: [FileNode]?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if node.isDirectory {
                    toggle()
                } else {
                    selection = node.path
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: icon)
                        .imageScale(.small)
                        .foregroundStyle(node.isDirectory ? Color.accentColor : Color.secondary)
                        .frame(width: 14)
                    Text(node.name)
                        .font(.callout)
                        .lineLimit(1)
                        .foregroundStyle(selection == node.path ? Color.accentColor : Color.primary)
                    Spacer(minLength: 0)
                }
                .padding(.leading, CGFloat(depth) * 13 + 8)
                .padding(.trailing, 8)
                .padding(.vertical, 2)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(selection == node.path ? Color.accentColor.opacity(0.14) : .clear)
                        .padding(.horizontal, 4)
                )
            }
            .buttonStyle(.plain)
            .help(node.path.abbreviatingHomeDirectory)

            if let children {
                ForEach(children) { child in
                    FileTreeRow(
                        node: child,
                        root: root,
                        depth: depth + 1,
                        includeHidden: includeHidden,
                        selection: $selection,
                        expanded: $expanded
                    )
                }
            }
        }
        .onAppear { syncExpansion() }
    }

    private var icon: String {
        if node.isDirectory {
            return expanded.contains(node.path) ? "folder.fill" : "folder"
        }
        return node.path.hasSuffix(".swift") ? "swift" : "doc.text"
    }

    private func toggle() {
        if expanded.contains(node.path) {
            expanded.remove(node.path)
            children = nil
        } else {
            expanded.insert(node.path)
            syncExpansion()
        }
    }

    private func syncExpansion() {
        guard node.isDirectory, expanded.contains(node.path), children == nil else { return }
        children = ProjectFileTree.children(of: node.path, includeHidden: includeHidden)
    }
}

/// Line-numbered, syntax-highlighted, read-only file view.
struct CodeViewer: View {
    var text: String
    var language: SyntaxLanguage
    var highlightLine: Int?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView([.vertical, .horizontal]) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(index + 1)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.tertiary)
                                .frame(width: 42, alignment: .trailing)
                            Text(SyntaxHighlighter.highlight(line, language: language))
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .padding(.vertical, 0.5)
                        .padding(.trailing, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(highlightLine == index + 1 ? Color.accentColor.opacity(0.12) : .clear)
                        .id(index + 1)
                    }
                }
                .padding(.vertical, 6)
            }
            .onAppear { scroll(proxy) }
            .onChange(of: highlightLine) { _, _ in scroll(proxy) }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var lines: [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    private func scroll(_ proxy: ScrollViewProxy) {
        guard let highlightLine else { return }
        proxy.scrollTo(highlightLine, anchor: .center)
    }
}

// MARK: - Terminal

struct TerminalPane: View {
    var controller: PiSessionController

    @State private var command = ""
    @State private var expandedIds: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            history
            Divider()
            input
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Label("Direct bash", systemImage: "terminal")
                    .font(.callout.weight(.semibold))
                if isRunning {
                    StatusPill(text: "running", tint: .accentColor, isProminent: true)
                }
                Spacer(minLength: 0)
                Button("Open in Terminal") {
                    WorkspaceLauncher.openTerminal(at: controller.projectPath)
                }
                .controlSize(.small)
            }
            Text("Commands run through Pi's bash tool, in the project directory, and are appended to this session.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var history: some View {
        Group {
            if commands.isEmpty {
                EmptyStateView(
                    systemImage: "terminal",
                    title: "No commands yet",
                    message: "Run a command here, or let Pi run one — both show up in this list."
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(commands.reversed()) { item in
                            bashCard(item)
                        }
                    }
                    .padding(10)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func bashCard(_ item: TranscriptItem) -> some View {
        let id = item.toolCallId ?? item.id
        let isExpanded = expandedIds.contains(id)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: statusIcon(item.toolStatus))
                    .foregroundStyle(statusColor(item.toolStatus))
                    .imageScale(.small)
                Text("$ " + item.text)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(isExpanded ? nil : 1)
                    .textSelection(.enabled)
                Spacer(minLength: 0)
                if let exitCode = exitCode(from: item) {
                    Text("exit \(exitCode)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(exitCode == 0 ? Color.secondary : Color.red)
                }
                CopyButton(text: item.toolOutput ?? "", help: "Copy output")
            }
            if let output = item.toolOutput, !output.isEmpty {
                Text(ANSIParser.plainText(output))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(isExpanded ? nil : 5)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button(isExpanded ? "Show less" : "Show all") {
                if isExpanded { expandedIds.remove(id) } else { expandedIds.insert(id) }
            }
            .buttonStyle(.link)
            .font(.caption2)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
    }

    private var input: some View {
        HStack(spacing: 8) {
            Text("$")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.tertiary)
            TextField("ls -la", text: $command)
                .textFieldStyle(.plain)
                .font(.system(.body, design: .monospaced))
                .onSubmit(run)
            if isRunning {
                Button("Stop") { Task { await controller.abortBash() } }
                    .controlSize(.small)
            }
            Button("Run", action: run)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(command.trimmingCharacters(in: .whitespaces).isEmpty || isRunning)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var commands: [TranscriptItem] {
        controller.items.filter { $0.toolName == "bash" }
    }

    private var isRunning: Bool {
        commands.contains { !$0.toolStatus.isTerminal }
    }

    private func run() {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isRunning else { return }
        command = ""
        Task { await controller.runBash(trimmed) }
    }

    private func exitCode(from item: TranscriptItem) -> Int? {
        guard let details = item.toolDetails else { return nil }
        return details.int("exitCode") ?? details.int("exit_code")
    }

    private func statusIcon(_ status: ToolStatus) -> String {
        switch status {
        case .pending: return "clock"
        case .running: return "circle.dotted"
        case .success: return "checkmark.circle"
        case .failure: return "xmark.circle"
        case .cancelled: return "slash.circle"
        }
    }

    private func statusColor(_ status: ToolStatus) -> Color {
        switch status {
        case .success: return .green
        case .failure: return .red
        case .cancelled: return .orange
        default: return .secondary
        }
    }
}

// MARK: - Tree

struct TreePane: View {
    @Bindable var state: AppState
    var controller: PiSessionController

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if controller.tree.isEmpty && controller.isLoadingEntries {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Reading this session's history…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Pi walks the whole session for this list, so long sessions take a while.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if controller.tree.isEmpty {
                EmptyStateView(
                    systemImage: "arrow.triangle.branch",
                    title: "No tree yet",
                    message: "Pi builds the session tree as messages are exchanged."
                )
            } else {
                List {
                    OutlineGroup(controller.tree, children: \.outlineChildren) { node in
                        TreeNodeRow(state: state, controller: controller, node: node)
                    }
                }
                .listStyle(.sidebar)
            }
            Divider()
            footer
        }
        .task {
            if controller.tree.isEmpty && !controller.isLoadingEntries {
                await controller.refreshEntries()
            }
            if controller.forkPoints.isEmpty { await controller.refreshForkPoints() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Label("Session tree", systemImage: "arrow.triangle.branch")
                    .font(.callout.weight(.semibold))
                StatusPill(text: "\(count(controller.tree)) entries", tint: .secondary)
                Spacer(minLength: 0)
                if controller.isLoadingEntries {
                    ProgressView()
                        .controlSize(.small)
                        .help("Pi is reading the session history")
                }
                Button {
                    Task { await controller.refreshEntries() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Reload the tree from Pi")
            }
            Text("Read-only: Pi's `/tree` navigation is TUI-only. Fork from any message to branch here instead.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let leafId = controller.leafId {
                Text("Current leaf: \(leafId)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            Button("Fork…") { state.run(.forkLatest) }
                .controlSize(.small)
                .disabled(controller.forkPoints.isEmpty)
            Button("Clone") { Task { await controller.cloneSession() } }
                .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    private func count(_ nodes: [PiTreeNode]) -> Int {
        nodes.reduce(0) { $0 + 1 + count($1.children) }
    }
}

struct TreeNodeRow: View {
    @Bindable var state: AppState
    var controller: PiSessionController
    var node: PiTreeNode

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: node.entry.systemImage)
                .imageScale(.small)
                .foregroundStyle(isCurrentLeaf ? Color.accentColor : Color.secondary)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 1) {
                Text(node.label ?? node.entry.displayLabel)
                    .font(.callout)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(node.entry.type)
                        .font(.caption2.monospaced())
                    if let timestamp = node.entry.timestamp {
                        Text(Format.relativeTime(timestamp))
                    }
                    if let tokens = node.entry.tokensBefore {
                        Text("\(Format.tokens(tokens)) tokens")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)

            if isCurrentLeaf {
                StatusPill(text: "leaf", tint: .accentColor)
            }
            if node.children.count > 1 {
                StatusPill(text: "\(node.children.count) branches", tint: .secondary)
            }
        }
        .padding(.vertical, 2)
        .onHover { isHovering = $0 }
        .contextMenu {
            if node.entry.type == "message" {
                Button("Fork from This Message") {
                    Task { await controller.fork(fromEntryId: node.entry.id) }
                }
            }
            Button("Copy Entry ID") { state.copyToPasteboard(node.entry.id) }
            if let parentId = node.entry.parentId {
                Button("Copy Parent ID") { state.copyToPasteboard(parentId) }
            }
        }
        .help(node.entry.displayLabel)
    }

    private var isCurrentLeaf: Bool { controller.leafId == node.entry.id }
}

extension PiTreeNode {
    /// `OutlineGroup` wants `nil` for leaves.
    var outlineChildren: [PiTreeNode]? { children.isEmpty ? nil : children }
}

// MARK: - Context

struct ContextPane: View {
    @Bindable var state: AppState
    var controller: PiSessionController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !controller.compatibilityNotices.isEmpty {
                    InspectorSection(title: "Compatibility", systemImage: "exclamationmark.triangle") {
                        ForEach(controller.compatibilityNotices) { notice in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(notice.surface)
                                    .font(.callout.weight(.medium))
                                Text(notice.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                sessionSection
                modelSection
                usageSection
                messageSection

                if !controller.queue.isEmpty {
                    queueSection
                }

                modeSection

                if !controller.extensionStatuses.isEmpty || !controller.extensionWidgets.isEmpty {
                    extensionSection
                }

                activitySection
            }
            .padding(12)
        }
    }

    // MARK: Sections

    private var sessionSection: some View {
        InspectorSection(title: "Session", systemImage: "bubble.left.and.text.bubble.right") {
            KeyValueRow(key: "Name", value: controller.sessionName ?? "—")
            KeyValueRow(key: "Session id", value: controller.sessionId ?? "—", isMonospaced: true)
            KeyValueRow(key: "Project", value: controller.projectPath, isMonospaced: true)
            KeyValueRow(key: "Messages", value: "\(controller.state?.messageCount ?? 0)")
            KeyValueRow(key: "Pending", value: "\(controller.state?.pendingMessageCount ?? 0)")
            if let file = controller.sessionFile {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Session file")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(file.abbreviatingHomeDirectory)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                    Spacer(minLength: 0)
                    CopyButton(text: file, help: "Copy session file path")
                    Button {
                        WorkspaceLauncher.reveal(file)
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.borderless)
                }
            } else {
                KeyValueRow(key: "Session file", value: "not written yet")
            }
        }
    }

    private var modelSection: some View {
        InspectorSection(title: "Model", systemImage: "cpu") {
            Menu {
                ForEach(controller.availableModels) { model in
                    Button("\(model.provider)/\(model.id)") {
                        Task { await controller.setModel(model) }
                    }
                }
            } label: {
                KeyValueRow(key: "Model", value: controller.model?.displayName ?? "default")
            }
            .menuStyle(.borderlessButton)
            KeyValueRow(key: "Provider", value: controller.model?.provider ?? "—")
            KeyValueRow(key: "Thinking", value: controller.thinkingLevel ?? "—")
            if let window = controller.model?.contextWindow {
                KeyValueRow(key: "Context window", value: Format.tokens(window) + " tokens")
            }
        }
    }

    private var usageSection: some View {
        InspectorSection(title: "Usage", systemImage: "chart.bar") {
            if let stats = controller.stats {
                if let usage = stats.contextUsage {
                    ContextUsageBar(usage: usage)
                }
                // These counters come from `get_session_stats` and cover the whole
                // session history — every branch, including messages that were
                // compacted away. `contextUsage` above is the live context window,
                // the only number that reflects what the model sees right now.
                Text("Session totals")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                KeyValueRow(key: "Input", value: Format.tokens(stats.tokens.input))
                KeyValueRow(key: "Output", value: Format.tokens(stats.tokens.output))
                KeyValueRow(key: "Cache read", value: Format.tokens(stats.tokens.cacheRead))
                KeyValueRow(key: "Cache write", value: Format.tokens(stats.tokens.cacheWrite))
                KeyValueRow(key: "Cost", value: stats.cost.currencyString)
                Text("Totals include compacted history and abandoned branches.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Pi has not reported usage yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var messageSection: some View {
        InspectorSection(title: "Activity", systemImage: "wrench.and.screwdriver") {
            KeyValueRow(key: "Tool calls (session)", value: "\(controller.toolCallCount)")
            KeyValueRow(key: "Subagents", value: "\(controller.subagentCount)")
            if let stats = controller.stats {
                KeyValueRow(key: "User messages", value: "\(stats.userMessages)")
                KeyValueRow(key: "Assistant messages", value: "\(stats.assistantMessages)")
            }
            if let duration = controller.lastTurnDuration {
                KeyValueRow(key: "Last turn", value: Format.duration(duration))
            }
        }
    }

    private var queueSection: some View {
        InspectorSection(title: "Queue", systemImage: "list.bullet.rectangle") {
            if !controller.queue.steering.isEmpty {
                Text("Steering")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(controller.queue.steering) { message in
                    Text(message.text.oneLinePreview(limit: 200))
                        .font(.caption)
                }
            }
            if !controller.queue.followUp.isEmpty {
                Text("Follow-up")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(controller.queue.followUp) { message in
                    Text(message.text.oneLinePreview(limit: 200))
                        .font(.caption)
                }
            }
            HStack {
                Button("Clear Queue") { Task { await controller.clearQueue() } }
                    .controlSize(.small)
            }
        }
    }

    private var modeSection: some View {
        InspectorSection(title: "Modes", systemImage: "switch.2") {
            Picker("Steering", selection: Binding(
                get: { controller.state?.steeringMode ?? "one-at-a-time" },
                set: { value in Task { await controller.setSteeringMode(value) } }
            )) {
                Text("One at a time").tag("one-at-a-time")
                Text("All").tag("all")
            }
            Picker("Follow-up", selection: Binding(
                get: { controller.state?.followUpMode ?? "one-at-a-time" },
                set: { value in Task { await controller.setFollowUpMode(value) } }
            )) {
                Text("One at a time").tag("one-at-a-time")
                Text("All").tag("all")
            }
            Toggle("Auto-compaction", isOn: Binding(
                get: { controller.state?.autoCompactionEnabled ?? true },
                set: { value in Task { await controller.setAutoCompaction(value) } }
            ))
            Toggle("Auto-retry", isOn: Binding(
                get: { controller.state?.autoRetryEnabled ?? true },
                set: { value in Task { await controller.setAutoRetry(value) } }
            ))
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }

    private var extensionSection: some View {
        InspectorSection(title: "Extensions", systemImage: "puzzlepiece.extension") {
            if controller.extensionStatuses.isEmpty && controller.extensionWidgets.isEmpty {
                Text("No extension UI is active.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(controller.extensionStatuses.keys.sorted(), id: \.self) { key in
                KeyValueRow(key: key, value: controller.extensionStatuses[key] ?? "")
            }
            ForEach(WidgetPlacement.allCases, id: \.self) { placement in
                let widgets = controller.extensionWidgets[placement] ?? [:]
                if !widgets.isEmpty {
                    Text(placement.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(widgets.keys.sorted(), id: \.self) { key in
                        KeyValueRow(key: key, value: (widgets[key] ?? []).joined(separator: " · "))
                    }
                }
            }
        }
    }

    private var activitySection: some View {
        InspectorSection(title: "Timeline", systemImage: "list.bullet.indent") {
            if controller.activity.isEmpty {
                Text("Nothing has happened yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(controller.activity.suffix(40).reversed()) { entry in
                    ActivityRowView(entry: entry, showsTimestamp: true)
                }
            }
        }
    }
}

// MARK: - Shared rows

struct KeyValueRow: View {
    var key: String
    var value: String
    var isMonospaced = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(key)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value.isEmpty ? "—" : value)
                .font(isMonospaced ? .caption.monospaced() : .caption)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
                .lineLimit(3)
                .truncationMode(.middle)
        }
    }
}

struct ContextUsageBar: View {
    var usage: PiContextUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Context")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(label)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: fraction)
                .tint(fraction > 0.85 ? .red : (fraction > 0.6 ? .orange : .accentColor))
        }
    }

    private var fraction: Double {
        min(max((usage.percent ?? 0) / 100, 0), 1)
    }

    private var label: String {
        var parts: [String] = []
        if let tokens = usage.tokens { parts.append(Format.tokens(tokens)) }
        if let window = usage.contextWindow { parts.append("of " + Format.tokens(window)) }
        if let percent = usage.percent { parts.append("(\(Int(percent.rounded()))%)") }
        return parts.joined(separator: " ")
    }
}
