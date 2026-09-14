//
//  SidebarView.swift
//  PiCode
//
//  Projects and their Pi sessions.
//
//  The sidebar reads Pi's session directory; it never edits a session file.
//  Renaming goes through Pi's own `set_session_name` so the file stays Pi's, and
//  deleting is a separate, confirmed action. Pin/hide state is PiCode-only and
//  lives in app preferences.
//

import SwiftUI

/// Sidebar row metrics.
///
/// A project and its chats are the same rank of information, so they share one
/// text size and one weight. That has to be an explicit size: semantic styles do
/// not line up here (macOS puts `.callout` and `.body` at the same 13pt while a
/// section header at `.caption` is smaller), and the point of the change is that
/// a project reads no differently from the sessions under it.
enum SidebarMetrics {
    static let rowFont = Font.system(size: 14, weight: .regular)
    /// Slightly larger than the text, the way a Finder folder glyph sits next to
    /// its name. Fixed width so `titleIndent` is exact whatever the glyph's own
    /// metrics are.
    static let projectIconSize: CGFloat = 15
    static let iconTextSpacing: CGFloat = 6
    /// In the sidebar list style macOS insets *rows* two points further than it
    /// insets section *headers* (measured at 240/320/400pt wide, macOS 15), so a
    /// session title would sit two points right of its project's name. Subtract
    /// it rather than fudging the icon, and re-measure with
    /// `Tools/SmokeTest/run-sidebar-align.sh` if a macOS update moves it.
    static let headerRowInsetDelta: CGFloat = 2
    /// How far a session title must be inset to start where its project's *name*
    /// starts rather than under the folder glyph.
    static var titleIndent: CGFloat { projectIconSize + iconTextSpacing - headerRowInsetDelta }
}

struct SidebarView: View {
    @Bindable var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            if state.phase.isReady {
                list
            } else {
                VStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Indexing sessions…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            footer
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .imageScale(.small)
            TextField("Search sessions", text: $state.sidebarQuery)
                .textFieldStyle(.plain)
            if !state.sidebarQuery.isEmpty {
                Button {
                    state.sidebarQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    // MARK: - List

    private var list: some View {
        List {
            ForEach(state.filteredProjects) { project in
                Section {
                    let ephemeral = ephemeralSession(for: project)
                    if let ephemeral {
                        SessionRow(
                            state: state,
                            session: ephemeral,
                            controller: state.activeController,
                            isSelected: true,
                            isEphemeral: true
                        )
                    }
                    ForEach(project.sessions) { session in
                        SessionRow(
                            state: state,
                            session: session,
                            controller: controller(for: session),
                            isSelected: state.selectedSessionKey == session.filePath.map(AppState.key(forSessionPath:))
                        )
                    }
                    if project.sessions.isEmpty && ephemeral == nil {
                        Text("No sessions yet")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.leading, SidebarMetrics.titleIndent)
                            .padding(.vertical, 2)
                    }
                } header: {
                    ProjectHeader(state: state, project: project)
                }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if state.filteredProjects.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: state.sidebarQuery.isEmpty ? "folder" : "magnifyingglass")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text(state.sidebarQuery.isEmpty ? "No projects yet" : "No matches")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if state.sidebarQuery.isEmpty {
                        Button("Open Project Folder…") { Task { await state.addProject() } }
                            .controlSize(.small)
                    }
                }
                .padding(16)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                Task { await state.addProject() }
            } label: {
                Label("Open Project", systemImage: "folder.badge.plus")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help("Open a project folder (⇧⌘O)")

            Button {
                if let path = state.selectedProject?.path {
                    Task { await state.startNewSession(projectPath: path) }
                } else {
                    Task { await state.addProject() }
                }
            } label: {
                Label("New Session", systemImage: "plus.bubble")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help("New session (⌘N)")

            Button {
                Task { await state.refreshIndex() }
            } label: {
                Label("Reload", systemImage: "arrow.clockwise")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help("Reload sessions from disk (⌘R)")

            Spacer(minLength: 0)

            if state.isIndexing {
                ProgressView().controlSize(.small)
            } else if let date = state.lastIndexedAt {
                Text("Indexed \(Format.relativeTime(date))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    // MARK: - Helpers

    private func controller(for session: SessionRef) -> PiSessionController? {
        guard let path = session.filePath else { return nil }
        return state.activeController?.sessionFile == path ? state.activeController : nil
    }

    /// A session that exists only in memory because Pi has not written it yet.
    private func ephemeralSession(for project: ProjectGroup) -> SessionRef? {
        guard let controller = state.activeController,
              controller.sessionFile == nil,
              controller.projectPath == project.path,
              state.selectedSessionKey?.hasPrefix("new:") == true else { return nil }
        return SessionRef(
            id: controller.draftKey,
            sessionId: controller.sessionId,
            filePath: nil,
            name: controller.sessionName,
            cwd: project.path,
            createdAt: Date(),
            updatedAt: Date(),
            messageCount: controller.items.filter(\.kind.isMessage).count,
            firstUserMessage: controller.items.first(where: { $0.kind == .user })?.text,
            parentSession: nil,
            isPinned: false,
            isEphemeral: true
        )
    }
}

// MARK: - Project header

struct ProjectHeader: View {
    @Bindable var state: AppState
    var project: ProjectGroup

    var body: some View {
        HStack(spacing: SidebarMetrics.iconTextSpacing) {
            Image(systemName: "folder")
                .font(.system(size: SidebarMetrics.projectIconSize, weight: .regular))
                .frame(width: SidebarMetrics.projectIconSize, alignment: .leading)
                .foregroundStyle(.secondary)
            Text(project.name)
                .font(SidebarMetrics.rowFont)
                .lineLimit(1)
            if project.isPinned {
                Image(systemName: "pin.fill")
                    .imageScale(.small)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            Text("\(project.sessions.count)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .contextMenu {
            Button(project.isPinned ? "Unpin Project" : "Pin Project") {
                state.togglePin(project: project)
            }
            Button("New Session Here") {
                Task { await state.startNewSession(projectPath: project.path) }
            }
            Divider()
            Button("Open in Terminal") { state.openTerminal(at: project.path) }
            Button("Reveal in Finder") { WorkspaceLauncher.reveal(project.path) }
            Button("Copy Path") { state.copyToPasteboard(project.path) }
        }
        .help(project.displayPath)
    }
}

// MARK: - Session row

struct SessionRow: View {
    @Bindable var state: AppState
    var session: SessionRef
    var controller: PiSessionController?
    var isSelected: Bool
    var isEphemeral: Bool = false

    @State private var isHovering = false

    var body: some View {
        Button {
            guard !isSelected || controller == nil else { return }
            Task { await state.open(session: session) }
        } label: {
            // No leading glyph: the chat's title lines up with the project's name
            // so the two read as one list, and the timestamp/message count moved
            // into the tooltip — a sidebar row should say what a session *is*,
            // not re-state metadata the session view already shows.
            HStack(spacing: 8) {
                Text(session.displayName)
                    .font(SidebarMetrics.rowFont)
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)

                if let controller, controller.hasPendingWork {
                    ProgressView()
                        .controlSize(.mini)
                } else if session.isPinned {
                    Image(systemName: "pin.fill")
                        .imageScale(.small)
                        .foregroundStyle(.tertiary)
                } else if isEphemeral {
                    Text("in memory")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.leading, SidebarMetrics.titleIndent)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.14) : (isHovering ? Color.primary.opacity(0.05) : .clear))
        )
        .onHover { isHovering = $0 }
        .contextMenu(menuItems: contextMenu)
        .help(helpText)
    }

    private var helpText: String {
        let location = session.filePath?.abbreviatingHomeDirectory ?? session.cwd.abbreviatingHomeDirectory
        guard !isEphemeral else { return "\(location) — in memory, not on disk yet" }
        let messages = session.messageCount > 0 ? "\(session.messageCount) message(s)" : "no messages"
        return "\(location) — \(messages), updated \(Format.relativeTime(session.updatedAt))"
    }

    @ViewBuilder
    private func contextMenu() -> some View {
        if isEphemeral {
            Button("Keep Working") {
                Task { await state.open(session: session) }
            }
        } else {
            Button("Open") { Task { await state.open(session: session) } }
        }
        Button(session.isPinned ? "Unpin" : "Pin") { state.togglePin(session: session) }
        Divider()
        Button("Copy Session Path") {
            if let path = session.filePath { state.copyToPasteboard(path) }
        }
        .disabled(session.filePath == nil)
        Button("Reveal Session File") {
            if let path = session.filePath { WorkspaceLauncher.reveal(path) }
        }
        .disabled(session.filePath == nil)
        Button("Hide from Sidebar") { Task { await state.hide(session: session) } }
        Divider()
        Button("Delete Session…", role: .destructive) {
            state.sessionPendingDeletion = session
            state.run(.deleteSession)
        }
        .disabled(session.filePath == nil)
    }
}
