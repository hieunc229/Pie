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
    static let rowTextOpacity = 0.94
    /// Inset for the sidebar's highlight shapes and trailing controls. Leading
    /// row glyphs use `trafficLightColumn` so they align with the window.
    static let sidebarMargin: CGFloat = 10
    /// The close traffic light's horizontal column in the compact title bar.
    /// Sidebar glyphs and standalone labels share this mark so every line starts
    /// on the same vertical axis as the window controls above it.
    static let trafficLightColumn: CGFloat = 20
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
    /// …and then back to the right until its leading edge meets the close traffic
    /// light above it. Drawing-only too, so the label does not move. Measured, not
    /// derived:
    /// `run-sidebar-align.sh` fails if the glyph's ink is not
    /// `sidebarMargin + projectIconRightShift` from the sidebar's edge.
    static var projectIconRightShift: CGFloat { trafficLightColumn - sidebarMargin }
    /// What `.offset(x:)` actually applies. One name for the drawn position, so the
    /// view and the harness cannot disagree about which number is in force.
    static var projectIconOffset: CGFloat { projectIconShift - projectIconRightShift }
    /// Gap between the folder glyph and the project name.
    static let iconTextSpacing: CGFloat = 14
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
    static let rowHighlightFill = AppTheme.sidebarRowHighlight
    /// The highlight pill's corners. Shared by both row types through
    /// `sidebarRow(fill:)`, so a project's pill and a chat's cannot be two shapes.
    static let rowHighlightRadius: CGFloat = 9
    /// The floor under a row's content, so both row types are one height.
    ///
    /// The list holds a row to `defaultMinListRowHeight` — 20pt here, measured —
    /// so a pill is `max(23, content) + 8` — a 31pt pitch — whatever the row holds. Set explicitly
    /// rather than leaning on the list, because "a project's highlight is a chat's
    /// highlight" is an invariant of this design and not a coincidence of the
    /// platform: if that minimum ever changes, it changes for both.
    static let rowMinHeight: CGFloat = 23
    /// Air above a group heading ("Pinned", "Projects"). A heading has to read as
    /// the start of a group, and air is the only thing that can say that without a
    /// rule or a weight; 24pt is enough to break the list's pitch and leave the
    /// rows themselves untouched. This is the one air the sidebar allows.
    static let sectionLabelTopPadding: CGFloat = 12
    /// Air below a group heading: none, the same as between two chats. The label is
    /// a row like any other on its bottom side, so the first project under it keeps
    /// the list's own pitch rather than inheriting a second margin from its heading.
    static let sectionLabelBottomPadding: CGFloat = 4
    /// How many rows a group draws before the rest go behind a "Show more…": a
    /// project's chats, and the projects under one heading. Ten rows is a screenful
    /// at the sidebar's own pitch — enough to see the shape of a project without
    /// the column turning into a directory listing, and the rest is one click away
    /// rather than gone. Both lists are already sorted newest-first
    /// (`AppState.sort`), so the ten a group draws are its ten most recent.
    static let visibleRowLimit = 10
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
    /// The ink of a row's trailing controls while the pointer is on the row but
    /// not yet on the control: primary at just over half, so the glyph reads as
    /// something to aim at on the sidebar's dark surface instead of as state.
    /// Hovering the control itself lifts it to full.
    ///
    /// An `opacity` on the control rather than a colour inside its label, for two
    /// measured reasons (§10): a `borderlessButton` menu snapshots its label as a
    /// template image, so a colour set on the image is discarded, and a literal
    /// `NSColor` there resolves against whichever appearance the body is
    /// evaluated in — which is how these glyphs came out black on a dark sidebar.
    static let actionIdleOpacity = 0.55
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
                    // A point at each end of the pill. The rows themselves are
                    // still one cell tall and so still one pitch; the fill simply
                    // stops short, which leaves a two-point gap between two
                    // touching highlights and lets the sidebar show through.
                    .padding(.vertical, 1)
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

/// Which sidebar row the pointer is on — one value for the whole list.
///
/// Each row used to keep its own `@State` hover flag, set by `onHover`. A list
/// recycles and re-lays-out its rows while it scrolls, and a menu opening takes the
/// pointer without sending the row an exit, so a row could miss its "left" event
/// and stay lit. With one shared id, entering any row replaces a stale one, and the
/// list leaving or scrolling clears it.
@Observable
final class SidebarHover {
    var rowID: String?

    func set(_ id: String, hovering: Bool) {
        if hovering {
            if rowID != id { rowID = id }
        } else if rowID == id {
            rowID = nil
        }
    }

    func clear() { if rowID != nil { rowID = nil } }
}

struct SidebarView: View {
    @Bindable var state: AppState
    @State private var hover = SidebarHover()
    /// Raises the command palette, whose search covers both sessions and
    /// commands. The sheet lives on `RootView`, so the closure is passed down
    /// rather than reached for.
    var onOpenPalette: () -> Void
    /// Presents the window-owned settings modal from the fixed footer row.
    var onOpenSettings: () -> Void

    @State private var isNewChatHovering = false
    /// The projects whose chat lists are past `SidebarStyle.visibleRowLimit`: a
    /// project's list is capped until its own "Show more…" is clicked, and folding
    /// the project drops it from here again, so reopening one shows the first ten
    /// chats the way it did before. See the `onChange` on `list`.
    @State private var expandedChatLists: Set<String> = []
    /// The two project headings, capped the same way. They have no fold to be
    /// reset by, so once a heading is opened it stays open for the session.
    @State private var showsAllProjects = false
    @State private var showsAllPinnedProjects = false

    var body: some View {
        VStack(spacing: 0) {
            SidebarHeader(state: state, onOpenPalette: onOpenPalette)
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
        }
        .frame(maxHeight: .infinity)
        // The column's own fill: the system material in the light appearance, the
        // palette's elevated surface in the dark one. See `SidebarColumnBackground`.
        .modifier(SidebarColumnBackground())
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
                IconsaxIcon(name: "edit-2")
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

    // MARK: - List

    private var list: some View {
        List {
            newChatRow
            // Pinned projects get their own group above the rest, and only when
            // there is one: an empty "Pinned" heading would be a section that says
            // nothing. Projects keep one heading of their own either way. Each
            // heading draws `SidebarStyle.visibleRowLimit` projects — the list is
            // sorted newest-first, so those are the ten most recently worked in —
            // and puts the rest behind one "Show more…" row.
            if !state.projects.isEmpty {
                if !pinnedProjects.isEmpty {
                    let pinned = capped(pinnedProjects, showingAll: showsAllPinnedProjects)
                    sectionLabel("Pinned")
                    ForEach(pinned.rows) { project in
                        ProjectRow(state: state, project: project, showsPin: false)
                        chats(of: project)
                    }
                    if pinned.hidden > 0 {
                        ShowMoreRow(hiddenCount: pinned.hidden, noun: "projects") {
                            showsAllPinnedProjects = true
                        }
                    }
                }
                let rest = capped(unpinnedProjects, showingAll: showsAllProjects)
                projectsSectionLabel
                ForEach(rest.rows) { project in
                    ProjectRow(state: state, project: project)
                    chats(of: project)
                }
                if rest.hidden > 0 {
                    ShowMoreRow(hiddenCount: rest.hidden, noun: "projects") {
                        showsAllProjects = true
                    }
                }
            }
        }
        .listStyle(.sidebar)
        // A fold forgets the expansion, so clicking a project away and back shows
        // its first ten chats again — the fold is what says "not now" to the whole
        // group, including the part that was opened. Read from the expanded set
        // rather than from the click, so every way of folding a project resets it
        // the same way.
        .onChange(of: state.expandedProjects) { _, expanded in
            expandedChatLists.formIntersection(expanded)
        }
        .environment(hover)
        // Leaving the list, or the list changing under a still pointer (scroll,
        // fold, a deleted row), drops the highlight instead of trusting every row
        // to have seen its own exit.
        .onHover { if !$0 { hover.clear() } }
        .modifier(ClearHoverOnScroll(hover: hover))
        .overlay {
            if state.projects.isEmpty {
                VStack(spacing: 8) {
                    IconsaxIcon(name: "folder-2", size: 26)
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
        harnessProjects.filter(\.isPinned)
    }

    /// The sidebar speaks for one harness at a time — the one in its title. Every
    /// project stays (a folder is not owned by a harness, and a new chat can start
    /// in any of them); only the chats under it are narrowed to that harness.
    private var harnessProjects: [ProjectGroup] {
        let harnessID = state.preferences.defaultHarnessID
        return state.projects.map { project in
            var project = project
            project.sessions = project.sessions.filter { $0.harnessID == harnessID }
            return project
        }
    }

    /// …and everything else, under the "Projects" heading. When nothing is pinned
    /// this is simply every project, so the plain list is unchanged.
    private var unpinnedProjects: [ProjectGroup] {
        harnessProjects.filter { !$0.isPinned }
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
            .fontWeight(.regular)
            .foregroundStyle(.secondary)
            .opacity(0.90)
            .offset(x: -SidebarStyle.projectIconOffset)
            .accessibilityAddTraits(.isHeader)
//            .font(SidebarStyle.rowFont)
//            .foregroundStyle(.secondary)
//            .offset(x: -SidebarStyle.projectIconOffset)
            .padding(.top, SidebarStyle.sectionLabelTopPadding)
            .padding(.bottom, SidebarStyle.sectionLabelBottomPadding)
//            .frame(maxWidth: .infinity, alignment: .leading)
//            .accessibilityAddTraits(.isHeader)
    }

    /// The refresh action belongs to the project collection, so it sits at the
    /// trailing end of that collection's label instead of occupying a footer row.
    private var projectsSectionLabel: some View {
        HStack(spacing: 8) {
            Text("Projects")
                .font(SidebarStyle.rowFont)
                .fontWeight(.regular)
                .foregroundStyle(.secondary)
                .opacity(0.90)
                .offset(x: -SidebarStyle.projectIconOffset)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)

            if state.isIndexing {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                Task { await state.refreshIndex() }
            } label: {
                IconsaxIcon(name: "refresh")
                    .foregroundStyle(.white)
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
            let tree = SessionBranchTree(sessions: project.sessions)
            let shown = capped(tree.roots, showingAll: expandedChatLists.contains(project.path))
            ForEach(shown.rows.flatMap { tree.rows(from: $0) }) { entry in
                SessionRow(
                    state: state,
                    session: entry.session,
                    isSelected: state.selectedSessionKey == entry.session.controllerKey,
                    depth: entry.depth,
                    guides: entry.guides
                )
            }
            if shown.hidden > 0 {
                ShowMoreRow(hiddenCount: shown.hidden, noun: "chats") {
                    expandedChatLists.insert(project.path)
                }
            }
            if project.sessions.isEmpty && ephemeral == nil {
                Text("No sessions yet")
                    .font(SidebarStyle.rowFont)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, SidebarStyle.titleIndent)
                    .padding(.bottom, 4)
            }
        }
    }

    // MARK: - Helpers

    /// The rows a group draws, and how many are still behind its "Show more…": the
    /// first `SidebarStyle.visibleRowLimit` of a list that is already sorted
    /// newest-first, or all of it once the group has been opened. One rule for a
    /// project's chats and for the projects under a heading, so the two cannot
    /// disagree about what "ten" means or about when the row appears.
    private func capped<T>(_ items: [T], showingAll: Bool) -> (rows: [T], hidden: Int) {
        guard !showingAll, items.count > SidebarStyle.visibleRowLimit else { return (items, 0) }
        let limit = SidebarStyle.visibleRowLimit
        return (Array(items.prefix(limit)), items.count - limit)
    }

    /// A session that exists only in memory because Pi has not written it yet.
    private func ephemeralSession(for project: ProjectGroup) -> SessionRef? {
        guard let controller = state.activeController,
              controller.harness.id == state.preferences.defaultHarnessID,
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
            isEphemeral: true,
            harnessID: controller.harness.id
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

    @Environment(SidebarHover.self) private var hover
    @State private var rowToken = UUID().uuidString
    private var isHovering: Bool { hover.rowID == rowToken }
    @State private var isNewChatHovering = false
    @State private var isMenuHovering = false

    var body: some View {
        Button {
            state.toggleCollapsed(project: project)
        } label: {
            HStack(spacing: SidebarStyle.iconTextSpacing) {
                IconsaxIcon(name: state.isCollapsed(project: project) ? "folder-2" : "folder-open")
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
                    IconsaxIcon(name: "bookmark-2")
                        .imageScale(.small)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
            // The two trailing controls are drawn only while the pointer is on
            // the row, so the room they need is reserved only then: a quiet
            // project's name (and its pin) run to the row's own trailing edge
            // instead of stopping a two-button gap short of it. See `SessionRow`.
            .padding(.trailing, isHovering ? SidebarStyle.topBarButtonSize * 2 : 0)
            .foregroundStyle(.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .trailing) {
            HStack(spacing: 0) {
                Menu {
                    ProjectRowMenu(state: state, project: project)
                } label: {
                    // `Text(Image(…))`, not a bare `Image`: a sidebar `List`
                    // draws a `borderlessButton` menu by snapshotting its label,
                    // and an image-only label comes out of that snapshot empty —
                    // a text-wrapped one draws. Measured in a render lab: the
                    // same menu beside the same sidebar list shows nothing with
                    // an `Image` label and a visible glyph with this one.
                    Text(iconsaxImage("more"))
                        .font(.system(size: SidebarStyle.projectIconSize, weight: .regular))
                        .frame(
                            width: SidebarStyle.topBarButtonSize,
                            height: SidebarStyle.rowMinHeight
                        )
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .foregroundStyle(.primary)
                .opacity(isMenuHovering ? 1 : SidebarStyle.actionIdleOpacity)
                .onHover { isMenuHovering = $0 }
                .help("Project actions")
                .accessibilityLabel("Project actions for \(project.name)")

                Button {
                    Task { await state.startNewSession(projectPath: project.path) }
                } label: {
                    IconsaxIcon(name: "edit-2")
                        .font(.system(size: SidebarStyle.projectIconSize, weight: .regular))
                        .frame(
                            width: SidebarStyle.topBarButtonSize,
                            height: SidebarStyle.rowMinHeight
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.primary)
                .opacity(isNewChatHovering ? 1 : SidebarStyle.actionIdleOpacity)
                .onHover { isNewChatHovering = $0 }
                .help("New chat in \(project.name)")
                .accessibilityLabel("New chat in \(project.name)")
            }
            .opacity(isHovering ? 1 : 0)
            .allowsHitTesting(isHovering)
        }
        // A project is highlighted exactly like a chat: one fill, one shape, one
        // height. See `SidebarRowChrome`.
        .sidebarRow(fill: isHovering ? SidebarStyle.rowHighlightFill : .clear)
        .onHover { hover.set(rowToken, hovering: $0) }
        .onChange(of: isHovering) { _, now in
            if !now { isMenuHovering = false; isNewChatHovering = false }
        }
        .accessibilityValue(state.isCollapsed(project: project) ? "chats hidden" : "chats shown")
        .contextMenu { ProjectRowMenu(state: state, project: project) }
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
    /// How many branches deep this chat is. A branch is drawn under the chat it
    /// was forked from, indented, with a curved guide on its left.
    var depth: Int = 0
    /// One flag per ancestor level plus this row's own as the last entry: whether
    /// a later sibling at that level still follows (so its line carries on).
    var guides: [Bool] = []

    @Environment(SidebarHover.self) private var hover
    @State private var rowToken = UUID().uuidString
    private var isHovering: Bool { hover.rowID == rowToken }
    @State private var isMenuHovering = false
    @State private var isTrashHovering = false

    var body: some View {
        Button {
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

                // A name too long for the row ends in an ellipsis rather than
                // running to the row's edge and stopping mid-letter: one line is
                // all the row has, so the ellipsis is what says the rest is in
                // the chat itself. It takes the slack before the pin so the pin
                // and the actions stay on the row's trailing edge.
                Text(session.displayName)
                    .font(SidebarStyle.rowFont)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.primary)
                    .opacity(SidebarStyle.rowTextOpacity)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if session.isPinned {
                    IconsaxIcon(name: "bookmark-2")
                        .imageScale(.small)
                        .foregroundStyle(.tertiary)
                } else if isEphemeral {
                    Text("in memory")
                        .font(SidebarStyle.captionFont)
                        .foregroundStyle(.tertiary)
                }
            }
            // The actions' room is reserved only while the actions are drawn, so
            // a quiet chat's title — and the pin beside it — reach the row's own
            // trailing edge. See `ProjectRow`.
            .padding(.trailing, isHovering ? actionWidth : 0)
            .padding(.leading, CGFloat(depth) * BranchGuides.step)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .trailing) {
            HStack(spacing: 0) {
                Menu {
                    SessionRowMenu(state: state, session: session, isEphemeral: isEphemeral)
                } label: {
                    // `Text(Image(…))`, not a bare `Image`: a sidebar `List`
                    // draws a `borderlessButton` menu by snapshotting its label,
                    // and an image-only label comes out of that snapshot empty —
                    // a text-wrapped one draws. Measured in a render lab: the
                    // same menu beside the same sidebar list shows nothing with
                    // an `Image` label and a visible glyph with this one.
                    Text(iconsaxImage("more"))
                        .font(.system(size: SidebarStyle.projectIconSize, weight: .regular))
                        .frame(
                            width: SidebarStyle.topBarButtonSize,
                            height: SidebarStyle.rowMinHeight
                        )
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .foregroundStyle(.primary)
                .opacity(isMenuHovering ? 1 : SidebarStyle.actionIdleOpacity)
                .onHover { isMenuHovering = $0 }
                .help("Chat actions")
                .accessibilityLabel("Chat actions for \(session.displayName)")

                // The row's own action sits at the trailing edge, in the order a
                // project row already uses — menu, then the action — so the two row
                // types put their controls in the same two places. A chat with
                // nothing on disk has nothing to delete, so the button is absent
                // rather than disabled: the same condition the menu item uses.
                if session.filePath != nil {
                    Button {
                        state.sessionPendingDeletion = session
                        state.run(.deleteSession)
                    } label: {
                        IconsaxIcon(name: "trash")
                            .font(.system(size: SidebarStyle.projectIconSize, weight: .regular))
                            .frame(
                                width: SidebarStyle.topBarButtonSize,
                                height: SidebarStyle.rowMinHeight
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.primary)
                    .opacity(isTrashHovering ? 1 : SidebarStyle.actionIdleOpacity)
                    .onHover { isTrashHovering = $0 }
                    .help("Delete this chat")
                    .accessibilityLabel("Delete \(session.displayName)")
                }
            }
            .opacity(isHovering ? 1 : 0)
            .allowsHitTesting(isHovering)
        }
        .sidebarRow(fill: (isSelected || isHovering) ? SidebarStyle.rowHighlightFill : .clear)
        .background(alignment: .leading) {
            if depth > 0 { BranchGuides(guides: guides).allowsHitTesting(false) }
        }
        .onHover { hover.set(rowToken, hovering: $0) }
        .onChange(of: isHovering) { _, now in
            if !now { isMenuHovering = false; isTrashHovering = false }
        }
        .contextMenu {
            SessionRowMenu(state: state, session: session, isEphemeral: isEphemeral)
        }
        .help(helpText)
    }

    /// The room the trailing controls take on the row while they are drawn: the
    /// menu, plus the trash button when this chat has a file to delete. One number
    /// the row and its controls both read, so the title cannot be pushed by a
    /// control the row did not reserve for.
    private var actionWidth: CGFloat {
        session.filePath == nil ? SidebarStyle.topBarButtonSize : SidebarStyle.topBarButtonSize * 2
    }

    private var helpText: String {
        let location = session.filePath?.abbreviatingHomeDirectory ?? session.cwd.abbreviatingHomeDirectory
        guard !isEphemeral else { return "\(location) — in memory, not on disk yet" }
        let messages = session.messageCount > 0 ? "\(session.messageCount) message(s)" : "no messages"
        return "\(location) — \(messages), updated \(Format.relativeTime(session.updatedAt))"
    }

}

// MARK: - Show more

/// The row that uncovers the rest of a long list: a project's chats, or the
/// projects under a heading.
///
/// It is a row, not a footer. The sidebar has one pitch and one column, and the
/// control that says "there is more of this list" belongs in the list, on the
/// names' own column, reading as the continuation of what is above it — a footer
/// would sit at the bottom of the whole sidebar, which is a different statement
/// about a different thing. It is dimmed because it is not a name, and it lights
/// the same pill every other row lights on hover, which is what says it can be
/// clicked.
struct ShowMoreRow: View {
    /// How many rows are still hidden — what the tooltip counts out.
    var hiddenCount: Int
    /// What is hidden: "chats" or "projects". Always plural: a group only offers
    /// this row once it is past `SidebarStyle.visibleRowLimit`.
    var noun: String
    var action: () -> Void

    @Environment(SidebarHover.self) private var hover
    @State private var rowToken = UUID().uuidString
    private var isHovering: Bool { hover.rowID == rowToken }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Text("Show more…")
                    .font(SidebarStyle.rowFont)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            // The names' column, not the rows': this row continues the list above
            // it, so it has to start where those titles start.
            .padding(.leading, SidebarStyle.titleIndent)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sidebarRow(fill: isHovering ? SidebarStyle.rowHighlightFill : .clear)
        .onHover { hover.set(rowToken, hovering: $0) }
        .help("Show all \(hiddenCount) more \(noun)")
    }
}


// MARK: - Branches

/// A project's chats as a forest: a chat whose session header names a
/// `parentSession` that is also in the project hangs under that parent. Pi writes
/// that header when a chat is forked or cloned, so the sidebar needs nothing of
/// its own to know where a branch came from. A parent that is missing (deleted,
/// or in another folder) leaves its child at the top level.
struct SessionBranchTree {
    struct Entry: Identifiable {
        var session: SessionRef
        var depth: Int
        var guides: [Bool]
        var id: String { session.id }
    }

    let roots: [SessionRef]
    private let children: [String: [SessionRef]]

    init(sessions: [SessionRef]) {
        let byPath = Dictionary(sessions.compactMap { s in s.filePath.map { ($0, s.id) } },
                                uniquingKeysWith: { first, _ in first })
        var children: [String: [SessionRef]] = [:]
        var roots: [SessionRef] = []
        for session in sessions {
            if let parent = session.parentSession, parent != session.filePath, byPath[parent] != nil {
                children[parent, default: []].append(session)
            } else {
                roots.append(session)
            }
        }
        // Branches read in the order they were made, under their parent.
        self.children = children.mapValues { $0.sorted { $0.createdAt < $1.createdAt } }
        self.roots = roots
    }

    /// `root` followed by all of its branches, depth first.
    func rows(from root: SessionRef) -> [Entry] {
        var out: [Entry] = []
        var seen: Set<String> = []
        func visit(_ session: SessionRef, depth: Int, guides: [Bool]) {
            guard seen.insert(session.id).inserted else { return }
            out.append(Entry(session: session, depth: depth, guides: guides))
            let kids = session.filePath.flatMap { children[$0] } ?? []
            for (index, kid) in kids.enumerated() {
                visit(kid, depth: depth + 1, guides: guides + [index < kids.count - 1])
            }
        }
        visit(root, depth: 0, guides: [])
        return out
    }
}

/// The curved connector to the left of a branch: a line down from the parent, a
/// rounded elbow into the row, and — while later siblings follow — the line
/// carrying on below.
struct BranchGuides: View {
    /// Horizontal room one level of nesting takes.
    static let step: CGFloat = 16
    var guides: [Bool]

    var body: some View {
        Canvas { context, size in
            let ink = GraphicsContext.Shading.color(.primary.opacity(0.28))
            let style = StrokeStyle(lineWidth: 1, lineCap: .round)
            let mid = size.height / 2
            let radius: CGFloat = 6
            for (level, continues) in guides.enumerated() {
                // Entry `level` is the line one step right of the ancestor's title.
                let x = SidebarStyle.titleIndent + 4 + CGFloat(level) * Self.step
                if level == guides.count - 1 {
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: mid - radius))
                    path.addQuadCurve(to: CGPoint(x: x + radius, y: mid),
                                      control: CGPoint(x: x, y: mid))
                    path.addLine(to: CGPoint(x: x + Self.step - 4, y: mid))
                    context.stroke(path, with: ink, style: style)
                    if continues {
                        var rest = Path()
                        rest.move(to: CGPoint(x: x, y: mid - radius))
                        rest.addLine(to: CGPoint(x: x, y: size.height))
                        context.stroke(rest, with: ink, style: style)
                    }
                } else if continues {
                    var line = Path()
                    line.move(to: CGPoint(x: x, y: 0))
                    line.addLine(to: CGPoint(x: x, y: size.height))
                    context.stroke(line, with: ink, style: style)
                }
            }
        }
    }
}

/// Clears the sidebar highlight while the list scrolls (macOS 15+; earlier systems
/// rely on the list-level exit and on the next row's entry replacing it).
private struct ClearHoverOnScroll: ViewModifier {
    var hover: SidebarHover

    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.onScrollPhaseChange { _, phase in
                if phase != .idle { hover.clear() }
            }
        } else {
            content
        }
    }
}
