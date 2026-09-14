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

/// Sidebar row metrics and colours.
///
/// A project and its chats are the same rank of information, so they share one
/// text size, one weight and one colour. That has to be an explicit size:
/// semantic styles do not line up here (macOS puts `.callout` and `.body` at the
/// same 13pt while a section header at `.caption` is smaller).
enum SidebarStyle {
    /// One size for a project and for every chat under it. 13pt regular: a menu of
    /// names, not a document, and nothing in it is a heading.
    static let rowFont = Font.system(size: 13, weight: .regular)
    /// Left edge of the sidebar's own content: the search field's fill and the
    /// project glyph both start here.
    static let sidebarMargin: CGFloat = 10
    /// Slightly larger than the text, the way a Finder folder glyph sits next to
    /// its name. Fixed width *and* height so the glyph cannot make a project row
    /// taller than a chat row — the two must keep the same vertical rhythm.
    static let projectIconSize: CGFloat = 15
    /// How far left of its row the project glyph is drawn. The list style insets
    /// rows about 19pt from the sidebar edge while the search field sits at 10, so
    /// the glyph is shifted by the difference to line up with the field; 9pt puts
    /// its ink exactly on the field's edge. The shift is drawing-only, which leaves
    /// the project name (and therefore every chat title under it) exactly where it
    /// was.
    static let projectIconShift: CGFloat = 9
    /// …and then 6pt back to the right, which is where the glyph sits now: hard
    /// against the search field's edge it read as drifting away from its own name.
    /// Drawing-only too, so the label does not move. Measured, not derived:
    /// `run-sidebar-align.sh` fails if the glyph's ink is not
    /// `sidebarMargin + projectIconRightShift` from the sidebar's edge.
    static let projectIconRightShift: CGFloat = 6
    /// What `.offset(x:)` actually applies. One name for the drawn position, so the
    /// view and the harness cannot disagree about which number is in force.
    static var projectIconOffset: CGFloat { projectIconShift - projectIconRightShift }
    /// Gap between the folder glyph and the project name.
    static let iconTextSpacing: CGFloat = 10
    /// Not a metric, but the rule the two below encode: there is **no vertical
    /// margin anywhere** in this list. One chat sits as far below the previous chat
    /// as below a project, and a project sits as far below the chat above it as a
    /// chat does. The rhythm is the list's, and the folder glyph — not air — is what
    /// says where one project's chats end and the next one begins. (A 12pt
    /// `projectTopMargin` used to sit here; it made a project read as a heading, and
    /// it is gone. Do not bring it back as padding: `listRowBackground` fills the
    /// row's cell, so padding a row also makes its highlight taller.)
    static let rowHighlightInset: CGFloat = sidebarMargin
    /// The fill of a highlighted row — the *only* one. Hover and the active row are
    /// the same neutral grey: the pointer and the selection are the same statement
    /// ("this is the row you mean"), so they do not need two colours, and a grey
    /// rather than `accentColor` means the highlight does not change colour when the
    /// window loses focus. Add `SidebarStyle.rowHighlightFill` to `.clear`, never a
    /// new literal.
    static let rowHighlightFill = Color.primary.opacity(0.08)
    /// The highlight pill's corners. Shared by both row types through
    /// `sidebarRow(fill:)`, so a project's pill and a chat's cannot be two shapes.
    static let rowHighlightRadius: CGFloat = 6
    /// The floor under a row's content, so both row types are one height.
    ///
    /// The list holds a row to `defaultMinListRowHeight` — 20pt here, measured —
    /// so a pill is `max(20, content) + 8` whatever the row holds. Set explicitly
    /// rather than leaning on the list, because "a project's highlight is a chat's
    /// highlight" is an invariant of this design and not a coincidence of the
    /// platform: if that minimum ever changes, it changes for both.
    static let rowMinHeight: CGFloat = 20
    /// Secondary and empty-state text. Regular weight, like everything else in this
    /// menu: there is no bold, medium or semibold type anywhere in it, and the
    /// semantic styles are avoided here because they drag a weight along with their
    /// size. `run-sidebar-align.sh` fails on a heavier weight appearing in this
    /// file.
    static let captionFont = Font.system(size: 11, weight: .regular)
    static let messageFont = Font.system(size: 13, weight: .regular)
    /// How far a chat title is inset so it starts where its project's *name*
    /// starts rather than under the folder glyph. Exact because a project is a
    /// row like a chat is, so both get the same leading inset (a `Section` header
    /// does not: it sits two points further left, which is why this used to need
    /// a correction). `Tools/SmokeTest/run-sidebar-align.sh` measures it.
    static var titleIndent: CGFloat { projectIconSize + iconTextSpacing }

    /// The search field's fill. It must read *darker* than the sidebar material
    /// in either appearance; `.quaternary` would go the wrong way in dark mode,
    /// so this is a translucent black with a different alpha per appearance.
    static let searchFieldFill = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return NSColor(white: 0, alpha: isDark ? 0.35 : 0.06)
    })
    static let searchFieldRadius: CGFloat = 8
}

/// The highlight pill behind a sidebar row. Every row paints it through here, so a
/// project's highlight and a chat's can only differ in colour — which is the point:
/// the two are the same rank of information and must hover alike.
///
/// `listRowBackground` fills the row's whole cell — measured, the full column width
/// and the full cell height, any padding and `listRowInsets` included — so **nothing
/// here may pad the row vertically**: a row that pads itself inside also makes its
/// own pill taller. The project row did, and its highlight came out 37pt against a
/// chat's 28pt, which made one of them look like a heading.
///
/// The horizontal inset is on the *shape* for the same reason the vertical one is
/// absent: the pill has to sit on the sidebar's margin (where the search field and
/// the folder glyph are) while the row itself runs the full width.
/// `SidebarClickTest` measures the pills against each other.
struct SidebarRowChrome: ViewModifier {
    var fill: Color

    func body(content: Content) -> some View {
        content
            .frame(minHeight: SidebarStyle.rowMinHeight)
            .listRowBackground(
                RoundedRectangle(cornerRadius: SidebarStyle.rowHighlightRadius, style: .continuous)
                    .fill(fill)
                    .padding(.horizontal, SidebarStyle.rowHighlightInset)
            )
    }
}

extension View {
    /// Give a sidebar row its highlight: `SidebarStyle.rowHighlightFill` while it is
    /// hovered or active, `.clear` otherwise. See `SidebarRowChrome`.
    func sidebarRow(fill: Color) -> some View {
        modifier(SidebarRowChrome(fill: fill))
    }
}

struct SidebarView: View {
    @Bindable var state: AppState
    @FocusState private var isSearching: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchField
            if state.phase.isReady {
                list
            } else {
                VStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Indexing sessions…")
                        .font(SidebarStyle.messageFont)
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
                .font(SidebarStyle.rowFont)
                .focused($isSearching)
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
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(SidebarStyle.searchFieldFill,
                    in: RoundedRectangle(cornerRadius: SidebarStyle.searchFieldRadius, style: .continuous))
        // The custom fill replaces AppKit's field chrome, so the focus ring has to
        // be drawn back on: keyboard focus must stay visible.
        .overlay {
            RoundedRectangle(cornerRadius: SidebarStyle.searchFieldRadius, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(isSearching ? 0.9 : 0), lineWidth: 2)
        }
        .padding(.horizontal, SidebarStyle.sidebarMargin)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    // MARK: - List

    private var list: some View {
        List {
            ForEach(state.filteredProjects) { project in
                ProjectRow(state: state, project: project)
                chats(of: project)
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if state.filteredProjects.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: state.sidebarQuery.isEmpty ? "folder" : "magnifyingglass")
                        .font(.system(size: 26, weight: .regular))
                        .foregroundStyle(.tertiary)
                    Text(state.sidebarQuery.isEmpty ? "No projects yet" : "No matches")
                        .font(SidebarStyle.messageFont)
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

    /// The rows belonging to one project.
    ///
    /// These are plain rows rather than a `Section`: the sidebar list style turns
    /// a section into a collapsible group with a disclosure chevron, and a project
    /// is folded by clicking it instead (see `ProjectRow`). Rows also share the
    /// project's leading inset, which is what lets a chat title line up with the
    /// project's name.
    @ViewBuilder
    private func chats(of project: ProjectGroup) -> some View {
        let ephemeral = ephemeralSession(for: project)
        if state.showsChats(of: project) {
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
                    .font(SidebarStyle.captionFont)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, SidebarStyle.titleIndent)
                    .padding(.bottom, 4)
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
                    .font(SidebarStyle.captionFont)
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

// MARK: - Project row

/// A project, as the first row of its own group of chats.
///
/// It reads exactly like a chat — same size, same weight, same primary colour — so
/// the sidebar is one list of places you have worked, not a hierarchy with a
/// shouted heading on top. The folder glyph and the indent are what say which
/// chats belong to it, and clicking the row folds them away, which is why there is
/// no disclosure chevron: the row itself is the disclosure.
struct ProjectRow: View {
    @Bindable var state: AppState
    var project: ProjectGroup

    @State private var isHovering = false

    var body: some View {
        Button {
            state.toggleCollapsed(project: project)
        } label: {
            HStack(spacing: SidebarStyle.iconTextSpacing) {
                Image(systemName: "folder")
                    .font(.system(size: SidebarStyle.projectIconSize, weight: .regular))
                    // Fixed height as well as width: a taller glyph would make the
                    // row taller than a chat row and change the rhythm below it.
                    .frame(width: SidebarStyle.projectIconSize,
                           height: SidebarStyle.projectIconSize,
                           alignment: .leading)
                    // Drawing-only, so the name stays put while the glyph moves to
                    // its own mark beside the search field.
                    .offset(x: -SidebarStyle.projectIconOffset)
                Text(project.name)
                    .font(SidebarStyle.rowFont)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                if project.isPinned {
                    Image(systemName: "pin.fill")
                        .imageScale(.small)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // A project is highlighted exactly like a chat: one fill, one shape, one
        // height. See `SidebarRowChrome`.
        .sidebarRow(fill: isHovering ? SidebarStyle.rowHighlightFill : .clear)
        .onHover { isHovering = $0 }
        .accessibilityValue(state.isCollapsed(project: project) ? "chats hidden" : "chats shown")
        .contextMenu {
            Button(state.isCollapsed(project: project) ? "Show Chats" : "Hide Chats") {
                state.toggleCollapsed(project: project)
            }
            Divider()
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
        .help(helpText)
    }

    private var helpText: String {
        let fold = state.isCollapsed(project: project) ? "Click to show its chats" : "Click to hide its chats"
        let chats = project.sessions.count == 1 ? "1 chat" : "\(project.sessions.count) chats"
        return "\(project.displayPath) — \(chats). \(fold)."
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
                    .font(SidebarStyle.rowFont)
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
                        .font(SidebarStyle.captionFont)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.leading, SidebarStyle.titleIndent)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sidebarRow(fill: (isSelected || isHovering) ? SidebarStyle.rowHighlightFill : .clear)
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
