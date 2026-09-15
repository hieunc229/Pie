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

import Foundation
import SwiftUI

/// Sidebar row metrics and colours.
///
/// A project and its chats are the same rank of information, so they share one
/// text size, one weight and one colour. That has to be an explicit size:
/// semantic styles do not line up here (macOS puts `.callout` and `.body` at the
/// same 13pt while a section header at `.caption` is smaller).
enum SidebarStyle {
    /// One size for a project and for every chat under it — the app's one reading
    /// size (`Typography.baseSize`). 13pt regular: a menu of names, not a document,
    /// and nothing in it is a heading.
    static let rowFont = Typography.body
    /// Project and chat names sit slightly below full label ink so the sidebar
    /// stays quieter than the active conversation without becoming secondary.
    static let rowTextOpacity = 0.85
    /// Left edge of the sidebar's own content: the search field's fill and the
    /// project glyph both start here.
    static let sidebarMargin: CGFloat = 10
    /// Slightly larger than the text, the way a Finder folder glyph sits next to
    /// its name. Fixed width *and* height so the glyph cannot make a project row
    /// taller than a chat row — the two must keep the same vertical rhythm.
    static let projectIconSize: CGFloat = 11
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
    /// Not a metric, but the rule the two below encode: **no row carries vertical
    /// margin**. One chat sits as far below the previous chat as below a project,
    /// and a project sits as far below the chat above it as a chat does. The rhythm
    /// is the list's, and the folder glyph — not air — is what says where one
    /// project's chats end and the next one begins. (A 12pt `projectTopMargin` used
    /// to sit here; it made a project read as a heading, and it is gone. Do not
    /// bring it back as padding: `listRowBackground` fills the row's cell, so
    /// padding a row also makes its highlight taller.) The one place air is allowed
    /// is above a group heading — a label, not a row, and the only thing in the
    /// column that is meant to stand apart from the list's pitch.
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
    /// Air above a group heading ("Pinned", "Projects"). A heading has to read as
    /// the start of a group, and air is the only thing that can say that without a
    /// rule or a weight; 24pt is enough to break the list's pitch and leave the
    /// rows themselves untouched. This is the one air the sidebar allows.
    static let sectionLabelTopPadding: CGFloat = 12
    /// Air below a group heading: none, the same as between two chats. The label is
    /// a row like any other on its bottom side, so the first project under it keeps
    /// the list's own pitch rather than inheriting a second margin from its heading.
    static let sectionLabelBottomPadding: CGFloat = 0
    /// Secondary and empty-state text. Regular weight, like everything else in this
    /// menu: there is no bold, medium or semibold type anywhere in it, and the
    /// semantic styles are avoided here because they drag a weight along with their
    /// size. `run-sidebar-align.sh` fails on a heavier weight appearing in this
    /// file.
    static let captionFont = Font.system(size: 11, weight: .regular)
    static let messageFont = Typography.body
    /// How far a chat title is inset from the row's leading edge so it starts where
    /// its project's *name* starts rather than under the folder glyph. Exact because
    /// a project is a row like a chat is, so both get the same leading inset (a
    /// `Section` header does not: it sits two points further left, which is why this
    /// used to need a correction). A chat supplies it with its leading mark slot —
    /// `projectIconSize` plus `iconTextSpacing` — and the empty-state line uses the
    /// number directly. `Tools/SmokeTest/run-sidebar-align.sh` measures it.
    static var titleIndent: CGFloat { projectIconSize + iconTextSpacing }

    /// The window's titlebar row — where macOS draws the traffic lights and the
    /// toolbar's own buttons, and therefore where the sidebar's search icon now
    /// lives. The unified toolbar configured by `PiCodeApp` is 52pt tall, so its
    /// centre is 26pt below the window's top edge; that strip is *above* the safe
    /// area the sidebar's own
    /// content starts in, which is why the button has to `ignoresSafeArea` to be
    /// drawn there. The toolbar's buttons (traffic lights included) are centred on
    /// the same 26pt, so the icon reads as one row with them instead of as the top
    /// of the list. Measured against the running window; a compact toolbar would
    /// put the lights at 19pt instead. `run-sidebar-align.sh` checks the wiring
    /// that puts a button here.
    static let titlebarRowCenter: CGFloat = 26
    /// The square a top-bar icon button draws in. Fixed so the row's geometry is
    /// known and the icon cannot change the row it shares with the traffic lights.
    static let topBarButtonSize: CGFloat = 22
    /// The rendered symbol inside both titlebar controls. Their hit areas stay at
    /// `topBarButtonSize`; only the glyph is reduced.
    static let topBarIconSize: CGFloat = 13
    /// The button's inset from the sidebar's trailing edge, the same margin the
    /// footer uses so the icon's edge lines up with the column.
    static var topBarTrailingInset: CGFloat { sidebarMargin }
    /// The top padding that centres a `topBarButtonSize` square on
    /// `titlebarRowCenter`. One name for the drawn position, so the view and a
    /// harness cannot disagree about which number is in force.
    static var topBarTopInset: CGFloat { titlebarRowCenter - topBarButtonSize / 2 }
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
/// The horizontal inset is on the *shape*: the pill has to sit on the sidebar's
/// margin (where the folder glyph is) while the row itself runs the full width.
/// Vertical padding on the *row* stays absent for the reason above; the half-point
/// on the shape below is different — it shrinks the pill rather than growing the
/// cell, which is what gives two rows a one-point gap. `SidebarClickTest` measures
/// the pills against each other.
struct SidebarRowChrome: ViewModifier {
    var fill: Color

    func body(content: Content) -> some View {
        content
            .frame(minHeight: SidebarStyle.rowMinHeight)
            .listRowBackground(
                RoundedRectangle(cornerRadius: SidebarStyle.rowHighlightRadius, style: .continuous)
                    .fill(fill)
                    .padding(.horizontal, SidebarStyle.rowHighlightInset)
                    // Half a point at each end of the pill. The rows themselves are
                    // still one cell tall and so still one pitch; the fill simply
                    // stops a hair short, which leaves a one-point gap between two
                    // touching highlights and lets the sidebar show through.
                    .padding(.vertical, 0.5)
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
    /// Raises the command palette, whose search covers both sessions and
    /// commands. The sheet lives on `RootView`, so the closure is passed down
    /// rather than reached for.
    var onOpenPalette: () -> Void
    /// Presents the window-owned settings modal from the fixed footer row.
    var onOpenSettings: () -> Void

    @State private var isNewChatHovering = false
    @State private var isPackagesHovering = false

    var body: some View {
        VStack(spacing: 0) {
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
            settingsFooter
        }
        .frame(maxHeight: .infinity)
        // The column's own fill: the system material in the light appearance, the
        // palette's elevated surface in the dark one. See `SidebarColumnBackground`.
        .modifier(SidebarColumnBackground())
        // Search is not part of the list; it is an icon in the window's titlebar
        // row on the sidebar's trailing edge, level with the traffic lights and
        // the sidebar toggle. See `searchButton`.
        .overlay(alignment: .topTrailing) { searchButton }
        .dropDestination(for: URL.self) { urls, _ in
            guard let folder = urls.first(where: { url in
                var isDirectory = ObjCBool(false)
                return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                    && isDirectory.boolValue
            }) else { return false }
            Task { await state.addProject(path: folder.path) }
            return true
        }
    }

    // MARK: - New chat

    /// *New chat* is a row in the list, not a bar above it: it is drawn with the
    /// same glyph size, spacing and highlight as a project, and sits in the same
    /// column, so it reads as the first place in the list rather than as chrome.
    ///
    /// The search *field* that used to live in a bar here is gone. A field filtered
    /// the list in place, which meant finding an older chat depended on a list that
    /// had already changed under you, and the prompt text Pi indexed was not
    /// searched at all. The palette searches the whole index — project names,
    /// session names and prompt/response text — so search is now a single icon in
    /// the titlebar row (`searchButton`).
    private var newChatRow: some View {
        Button {
            Task { await state.newChatInCurrentProject() }
        } label: {
            HStack(spacing: SidebarStyle.iconTextSpacing) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: SidebarStyle.projectIconSize + 2, weight: .regular))
                    .frame(width: SidebarStyle.projectIconSize,
                           height: SidebarStyle.projectIconSize,
                           alignment: .leading)
                    .offset(x: -SidebarStyle.projectIconOffset)
                Text("New chat")
                    .font(SidebarStyle.rowFont)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sidebarRow(fill: isNewChatHovering ? SidebarStyle.rowHighlightFill : .clear)
        .onHover { isNewChatHovering = $0 }
        .help("Start a chat in the current project (⌘N)")
    }

    // MARK: - Packages

    /// *Packages* sits directly under *New chat* and is drawn with the same glyph
    /// size, spacing and highlight, so the two read as the list's two doors: one
    /// into a conversation, one into the package browser. It stays lit while the
    /// browser is showing, which is the only selection state the sidebar has.
    private var packagesRow: some View {
        Button {
            state.showPackages()
        } label: {
            HStack(spacing: SidebarStyle.iconTextSpacing) {
                Image(systemName: "shippingbox")
                    .font(.system(size: SidebarStyle.projectIconSize + 2, weight: .regular))
                    .frame(width: SidebarStyle.projectIconSize,
                           height: SidebarStyle.projectIconSize,
                           alignment: .leading)
                    .offset(x: -SidebarStyle.projectIconOffset)
                Text("Packages")
                    .font(SidebarStyle.rowFont)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sidebarRow(fill: highlightFill(for: state.isPackagesVisible, hovering: isPackagesHovering))
        .onHover { isPackagesHovering = $0 }
        .help("Browse and install pi packages")
    }

    /// Hover and selection are the same neutral grey here as everywhere in the
    /// sidebar: the pointer and the open page say the same thing.
    private func highlightFill(for isActive: Bool, hovering: Bool) -> Color {
        (isActive || hovering) ? SidebarStyle.rowHighlightFill : .clear
    }

    /// Search, drawn in the window's titlebar row on the sidebar's trailing edge.
    ///
    /// It is the only control in the sidebar that leaves the safe area: the row it
    /// belongs to is the toolbar's, above the sidebar's content, so it is pulled
    /// up with `.ignoresSafeArea` and centred on `titlebarRowCenter` — the same
    /// 26pt the traffic lights and the sidebar toggle sit on. It is a plain icon
    /// in the toolbar's own weightless style, not a filled control, because it is
    /// a window control first and a menu control second.
    private var searchButton: some View {
        Button(action: onOpenPalette) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: SidebarStyle.topBarIconSize, weight: .regular))
                .frame(width: SidebarStyle.topBarButtonSize, height: SidebarStyle.topBarButtonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help("Search sessions and commands (⇧⌘P)")
        .accessibilityLabel("Search")
        .padding(.top, SidebarStyle.topBarTopInset)
        .padding(.trailing, SidebarStyle.topBarTrailingInset)
        .ignoresSafeArea(.container, edges: .top)
    }

    /// Settings is a window-level destination, so it stays fixed at the bottom
    /// instead of scrolling with projects and chats.
    private var settingsFooter: some View {
        Button(action: onOpenSettings) {
            HStack(spacing: SidebarStyle.iconTextSpacing) {
                Image(systemName: "gearshape")
                    .font(.system(size: SidebarStyle.projectIconSize, weight: .regular))
                    .frame(
                        width: SidebarStyle.projectIconSize,
                        height: SidebarStyle.projectIconSize,
                        alignment: .leading
                    )
                Text("Settings")
                    .font(SidebarStyle.rowFont)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, SidebarStyle.sidebarMargin + SidebarStyle.projectIconRightShift)
        .padding(.trailing, SidebarStyle.sidebarMargin)
        .padding(.vertical, 9)
        .help("Open provider settings")
    }

    // MARK: - List

    private var list: some View {
        List {
            newChatRow
            packagesRow
            // Pinned projects get their own group above the rest, and only when
            // there is one: an empty "Pinned" heading would be a section that says
            // nothing. Projects keep one heading of their own either way.
            if !state.projects.isEmpty {
                if !pinnedProjects.isEmpty {
                    sectionLabel("Pinned")
                    ForEach(pinnedProjects) { project in
                        ProjectRow(state: state, project: project, showsPin: false)
                        chats(of: project)
                    }
                }
                projectsSectionLabel
                ForEach(unpinnedProjects) { project in
                    ProjectRow(state: state, project: project)
                    chats(of: project)
                }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if state.projects.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "folder")
                        .font(.system(size: 26, weight: .regular))
                        .foregroundStyle(.tertiary)
                    Text("No projects yet")
                        .font(SidebarStyle.messageFont)
                        .foregroundStyle(.secondary)
                    Button("Open Project Folder…") { Task { await state.addProject() } }
                        .controlSize(.small)
                }
                .padding(16)
            }
        }
    }

    // MARK: - Group headings

    /// The projects shown under the "Pinned" heading. `AppState` sorts pinned
    /// projects first, but the two groups are drawn as separate sections now, so
    /// they are split here instead of leaning on that order.
    private var pinnedProjects: [ProjectGroup] {
        state.projects.filter(\.isPinned)
    }

    /// …and everything else, under the "Projects" heading. When nothing is pinned
    /// this is simply every project, so the plain list is unchanged.
    private var unpinnedProjects: [ProjectGroup] {
        state.projects.filter { !$0.isPinned }
    }

    /// A group heading, drawn as a row rather than a `Section` header: the sidebar
    /// list style turns those into a collapsible group with a chevron, and these
    /// groups do not fold. It stands on the project glyph's own mark — the same
    /// `projectIconOffset` every row's leading slot uses — so it labels the folder
    /// column rather than the names beside it. At the row size and dimmed, it is a
    /// quiet label and not a heading; it takes air above and none below, so the
    /// first project under it keeps the list's own pitch, the same as between two
    /// chats.
    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(SidebarStyle.rowFont)
            .foregroundStyle(.secondary)
            .offset(x: -SidebarStyle.projectIconOffset)
            .padding(.top, SidebarStyle.sectionLabelTopPadding)
            .padding(.bottom, SidebarStyle.sectionLabelBottomPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }

    /// The refresh action belongs to the project collection, so it sits at the
    /// trailing end of that collection's label instead of occupying a footer row.
    private var projectsSectionLabel: some View {
        HStack(spacing: 8) {
            Text("Projects")
                .font(SidebarStyle.rowFont)
                .foregroundStyle(.secondary)
                .offset(x: -SidebarStyle.projectIconOffset)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)

            if state.isIndexing {
                ProgressView().controlSize(.small)
            }

            Button {
                Task { await state.refreshIndex() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Reload sessions from disk (⌘R)")
            .accessibilityLabel("Reload sessions from disk")
        }
        .padding(.top, SidebarStyle.sectionLabelTopPadding)
        .padding(.bottom, SidebarStyle.sectionLabelBottomPadding)
        .frame(maxWidth: .infinity)
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
                    isSelected: true,
                    isEphemeral: true
                )
            }
            ForEach(project.sessions) { session in
                SessionRow(
                    state: state,
                    session: session,
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

    // MARK: - Helpers

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
    /// Whether to draw the pin glyph. A project under the "Pinned" heading is
    /// already in the pin's section, so repeating the glyph there would say the
    /// same thing twice; a project under "Projects" carries it, which is what
    /// makes a pinned project recognisable at a glance.
    var showsPin: Bool = true

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
                    .opacity(SidebarStyle.rowTextOpacity)
                    .accessibilityAddTraits(.isHeader)
                if showsPin && project.isPinned {
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
            Button("New chat") {
                Task { await state.startNewSession(projectPath: project.path) }
            }
            Divider()
            Button("Open in Terminal") { state.openTerminal(at: project.path) }
            Button("Reveal in Finder") { WorkspaceLauncher.reveal(project.path) }
            Button("Copy Path") { state.copyToPasteboard(project.path) }
            
            Button(project.isPinned ? "Unpin Project" : "Pin Project") {
                state.togglePin(project: project)
            }
            
            Divider()
            
            Button("Settings…") {
                state.presentProjectSettings(project)
            }
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
    var isSelected: Bool
    var isEphemeral: Bool = false

    @State private var isHovering = false

    var body: some View {
        Button {
            guard !isSelected || state.activeController == nil else { return }
            Task { await state.open(session: session) }
        } label: {
            // The leading slot is a project's own mark, not a chat glyph: it stays
            // empty for a quiet chat so the title lines up with the project's name
            // and the two read as one list, and a *running* chat fills it with its
            // spinner. Reserving the slot either way is what keeps the title from
            // shifting when a chat starts or stops working. The timestamp and
            // message count live in the tooltip — a sidebar row should say what a
            // session *is*, not re-state metadata the session view already shows.
            HStack(spacing: SidebarStyle.iconTextSpacing) {
                // The spinner is read from the session's own live process, not
                // from the controller for the tab on screen, so a chat that keeps
                // working in the background still says so while another is open.
                //
                // It is drawn in the folder glyph's slot — the same 11pt mark, at
                // the same `projectIconOffset` — so a working chat's spinner sits
                // exactly where the folder above it sits.
                Group {
                    if state.isRunning(session) {
                        ProgressView()
                            .controlSize(.mini)
                            .accessibilityLabel("Working")
                    } else {
                        Color.clear
                    }
                }
                .frame(width: SidebarStyle.projectIconSize,
                       height: SidebarStyle.projectIconSize,
                       alignment: .leading)
                .offset(x: -SidebarStyle.projectIconOffset)

                Text(session.displayName)
                    .font(SidebarStyle.rowFont)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                    .opacity(SidebarStyle.rowTextOpacity)

                Spacer(minLength: 0)

                if session.isPinned {
                    Image(systemName: "pin.fill")
                        .imageScale(.small)
                        .foregroundStyle(.tertiary)
                } else if isEphemeral {
                    Text("in memory")
                        .font(SidebarStyle.captionFont)
                        .foregroundStyle(.tertiary)
                }
            }
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
        Button("Rename…") { state.presentRename(session: session) }
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
