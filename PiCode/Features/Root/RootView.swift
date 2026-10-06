//
//  RootView.swift
//  PiCode
//
//  Window layout: an icon rail on the window chrome, then one rounded card
//  holding the sessions sidebar, the conversation and the contextual inspector.
//
//  The panes are laid out here rather than through `NavigationSplitView`, so
//  the card is one surface set into the chrome: the sidebar folds away inside
//  it and the inspector opens inside it, and neither moves the other.
//

import SwiftUI

/// The window's frame: the band the traffic lights sit in, and the inset of
/// the content card from the window's edges.
enum WindowChromeMetrics {
    /// The unified toolbar's band. The traffic lights are centred in it, and the
    /// content card starts just under it.
    static let titlebarHeight: CGFloat = 40
    static let titlebarRowCenter: CGFloat = 19
    /// The card's inset from the window's trailing and bottom edges.
    static let cardInset: CGFloat = 6
    static let cardCornerRadius: CGFloat = 12
    /// Where the sidebar toggle starts: just past the traffic lights.
    static let sidebarToggleLeading: CGFloat = 84
}

struct RootView: View {
    @Bindable var state: AppState

    @State private var isSidebarVisible = true
    @State private var sidebarWidth: CGFloat = 268
    @State private var sidebarWidthAtDragStart: CGFloat?
    @State private var composerFocusTick = 0
    @State private var sheet: RootSheet?
    @State private var inspectorWidth: CGFloat = 360
    @State private var inspectorWidthAtDragStart: CGFloat?

    var body: some View {
        HStack(spacing: 0) {
            AppRail(
                state: state,
                onOpenPalette: openPalette,
                onOpenSettings: { state.openSettings(tab: state.settingsTab) }
            )
            Group {
                if state.isSettingsPresented {
                    settingsCard
                } else {
                    contentCard
                }
            }
                .padding(.trailing, WindowChromeMetrics.cardInset)
                .padding(.bottom, WindowChromeMetrics.cardInset)
        }
        .padding(.top, WindowChromeMetrics.titlebarHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                WindowVibrancy()
                AppTheme.chrome
            }
        }
        .overlay(alignment: .topLeading) { titlebarLeadingControls }
        .overlay(alignment: .topTrailing) { titlebarTrailingControls }
        .ignoresSafeArea()
        // An empty toolbar keeps the window's unified titlebar band, which is
        // what centres the traffic lights on `titlebarRowCenter`. Everything
        // drawn in the band is this view's own, so the toolbar draws nothing.
        .toolbar {
            ToolbarItem(placement: .navigation) { Color.clear.frame(width: 1, height: 1) }
        }
        .toolbarBackground(.hidden, for: .windowToolbar)
        .task {
            if state.phase == .starting { await state.launch() }
            #if DEBUG
            Task { await DebugRenderBench.runIfRequested(state: state) }
            if let wanted = ProcessInfo.processInfo.environment["PICODE_OPEN_SESSION"] {
                // The index fills in asynchronously; wait for the session to show up.
                // Let the restored session settle first so it does not replace this one.
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                for _ in 0..<80 {
                    if let session = state.projects.lazy.flatMap(\.sessions)
                        .first(where: { $0.filePath?.hasSuffix(wanted) == true }) {
                        await state.open(session: session)
                        break
                    }
                    try? await Task.sleep(nanoseconds: 250_000_000)
                }
            }
            if ProcessInfo.processInfo.environment["PICODE_SNAPSHOT_ACTION"] == "newChat" {
                if let project = state.projects.first?.path {
                    await state.startNewSession(projectPath: project)
                }
            }
            #endif
        }
        .onDisappear {
            state.isInspectorVisible = false
            state.isNotificationsVisible = false
        }
        .onChange(of: state.commandTick) { _, _ in
            if let command = state.lastCommand { perform(command) }
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .palette:
                CommandPaletteView(state: state) { command in
                    self.sheet = nil
                    perform(command)
                }
            case .rename(let current):
                RenameSessionSheet(state: state, session: nil, currentName: current) { self.sheet = nil }
            case .renameChat(let session):
                RenameSessionSheet(state: state, session: session, currentName: session.displayName) { self.sheet = nil }
            case .compact:
                CompactSessionSheet(state: state) { self.sheet = nil }
            case .fork:
                ForkSessionSheet(state: state) { self.sheet = nil }
            case .delete(let session):
                DeleteSessionSheet(state: state, session: session) { self.sheet = nil }
            case .projectSettings(let project):
                ProjectSettingsSheet(state: state, project: project) { self.sheet = nil }
            case .newProject(let path):
                NewProjectSheet(state: state, path: path) { self.sheet = nil }
            }
        }
        .onChange(of: state.pendingProjectSettings) { _, project in
            guard let project else { return }
            state.pendingProjectSettings = nil
            sheet = .projectSettings(project)
        }
        .onChange(of: state.pendingSessionRename) { _, session in
            guard let session else { return }
            state.pendingSessionRename = nil
            sheet = .renameChat(session)
        }
        .onChange(of: state.pendingNewProjectPath) { _, path in
            guard let path else { return }
            sheet = .newProject(path)
        }
        .overlay(alignment: .bottom) { toast }
        .overlay(alignment: .top) { errorBanner.padding(.top, WindowChromeMetrics.titlebarHeight) }
        .overlay { ExtensionDialogHost(state: state) }
    }

    private func openPalette() {
        state.openPalette()
        sheet = .palette
    }

    // MARK: - Card

    /// The sidebar and the detail pane, set into the window chrome as one
    /// rounded card. The sidebar is a pane of the card rather than a split-view
    /// column, so it folds away without the card moving.
    private var contentCard: some View {
        HStack(spacing: 0) {
            if isSidebarVisible {
                SidebarView(
                    state: state,
                    onOpenPalette: openPalette,
                    onOpenSettings: { state.openSettings(tab: state.settingsTab) }
                )
                .frame(width: sidebarWidth)
                .layoutPriority(1)
                .transition(.move(edge: .leading).combined(with: .opacity))

                paneDivider { translation in
                    if sidebarWidthAtDragStart == nil { sidebarWidthAtDragStart = sidebarWidth }
                    let start = sidebarWidthAtDragStart ?? sidebarWidth
                    sidebarWidth = min(380, max(220, start + translation))
                } onEnded: {
                    sidebarWidthAtDragStart = nil
                }
            }
            detailPane
                .frame(minWidth: 0, maxWidth: .infinity)
                // Opaque, unlike the chrome and the sidebar around it: the
                // transcript keeps full contrast over the window's vibrancy.
                .background(AppTheme.background)
        }
        .clipShape(RoundedRectangle(cornerRadius: WindowChromeMetrics.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: WindowChromeMetrics.cardCornerRadius, style: .continuous)
                .stroke(AppTheme.cardStroke, lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.2), value: isSidebarVisible)
    }

    /// Settings take the card's place, so they replace the window's content
    /// rather than float over it. The rail stays, as the way back.
    private var settingsCard: some View {
        SettingsView(state: state)
            .clipShape(RoundedRectangle(cornerRadius: WindowChromeMetrics.cardCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: WindowChromeMetrics.cardCornerRadius, style: .continuous)
                    .stroke(AppTheme.cardStroke, lineWidth: 1)
            )
    }

    /// A one-point rule between two panes that can be dragged to resize them.
    private func paneDivider(
        onChanged: @escaping (CGFloat) -> Void,
        onEnded: @escaping () -> Void
    ) -> some View {
        Rectangle()
            .fill(AppTheme.cardStroke)
            .frame(width: 1)
            .contentShape(Rectangle().inset(by: -3))
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture()
                    .onChanged { onChanged($0.translation.width) }
                    .onEnded { _ in onEnded() }
            )
    }

    // MARK: - Titlebar

    /// Back / forward and the sidebar toggle, just past the traffic lights, then
    /// the chat's title after a rule that lines up with the sidebar's edge.
    @ViewBuilder
    private var titlebarLeadingControls: some View {
        if !state.isSettingsPresented {
            let buttonTop = WindowChromeMetrics.titlebarRowCenter - TitlebarIconButton.size / 2
            ZStack(alignment: .topLeading) {
                HStack(spacing: 2) {
                    TitlebarIconButton(systemImage: "sidebar.left", help: "Toggle sidebar (⌃⌘S)") {
                        toggleSidebar()
                    }
                    TitlebarIconButton(systemImage: "arrow.left", help: "Back", isEnabled: state.canGoBack) {
                        Task { await state.goBack() }
                    }
                    TitlebarIconButton(systemImage: "arrow.right", help: "Forward", isEnabled: state.canGoForward) {
                        Task { await state.goForward() }
                    }
                }
                .padding(.leading, WindowChromeMetrics.sidebarToggleLeading)
                .padding(.top, buttonTop)

                if state.phase == .ready, !state.isPackagesVisible, let controller = state.activeController {
                    titlebarTitle(controller)
                        .padding(.leading, titleLeading)
                        .padding(.trailing, titleTrailingReserve)
                        .frame(height: WindowChromeMetrics.titlebarHeight)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    /// Where the title starts: past the sidebar's trailing edge when the sidebar
    /// is open (so the rule sits on the column boundary), else past the buttons.
    private var titleLeading: CGFloat {
        if isSidebarVisible {
            return AppRailMetrics.width + sidebarWidth + 1 + 14
        }
        return WindowChromeMetrics.sidebarToggleLeading + 3 * TitlebarIconButton.size + 12
    }

    /// Room kept free for the trailing controls.
    private var titleTrailingReserve: CGFloat { 150 }

    /// The conversation's own title when it has one — its name, else the opening
    /// message the sidebar shows — and the project's name only before either exists.
    private func headerTitle(for controller: PiSessionController) -> String {
        if let name = controller.sessionName, !name.trimmingCharacters(in: .whitespaces).isEmpty {
            return name
        }
        if let session = fallbackDeletionCandidate, session.isNamed || session.firstUserMessage?.isEmpty == false {
            return session.displayName
        }
        return controller.projectName
    }

    private func titlebarTitle(_ controller: PiSessionController) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Text(headerTitle(for: controller))
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
        .overlay(alignment: .leading) {
            if isSidebarVisible {
                Rectangle()
                    .fill(AppTheme.cardStroke)
                    .frame(width: 1, height: 20)
                    .offset(x: -14 - 1)
            }
        }
        .allowsHitTesting(false)
    }

    /// The project's workspace actions and the right panel's toggle, on the
    /// card's trailing edge.
    @ViewBuilder
    private var titlebarTrailingControls: some View {
        if state.phase == .ready, let controller = state.activeController, !state.isPackagesVisible, !state.isSettingsPresented {
            HStack(spacing: 6) {
                SessionHeaderMenu(
                    isPinned: fallbackDeletionCandidate?.isPinned ?? false,
                    onCommand: perform,
                    onTogglePin: {
                        if let session = fallbackDeletionCandidate { state.togglePin(session: session) }
                    }
                )

                WorkspaceMenuButton(
                    onOpenInTerminal: { state.openTerminal(at: controller.projectPath) },
                    onOpenInFinder: { WorkspaceLauncher.reveal(controller.projectPath) },
                    onOpenInVSCode: { openProjectInVSCode(controller.projectPath) }
                )
                .frame(width: 17, height: 17)
                .frame(width: TitlebarIconButton.size, height: TitlebarIconButton.size)

                TitlebarIconButton(
                    systemImage: "sidebar.right",
                    help: state.isInspectorVisible ? "Hide the inspector (⌥⌘I)" : "Show the inspector (⌥⌘I)",
                    isActive: state.isInspectorVisible && !state.isNotificationsVisible
                ) {
                    state.toggleInspector()
                }
            }
            .padding(.trailing, WindowChromeMetrics.cardInset + 8)
            .padding(.top, WindowChromeMetrics.titlebarRowCenter - TitlebarIconButton.size / 2)
        }
    }

    // MARK: - Detail pane

    /// The conversation and, when it is open, the inspector beside it. The two
    /// share the card's height, so opening the panel never resizes or shifts the
    /// sidebar or the transcript.
    private var detailPane: some View {
        Group {
            // The package browser owns the whole detail pane: the inspector is
            // about a session's facts, and there is no session on screen.
            if state.phase == .ready && state.isPackagesVisible {
                PackagesView(state: state)
            } else {
                HStack(spacing: 0) {
                    detail
                        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                        .layoutPriority(0)

                    if state.isInspectorVisible {
                        HStack(spacing: 0) {
                            paneDivider { translation in
                                if inspectorWidthAtDragStart == nil {
                                    inspectorWidthAtDragStart = inspectorWidth
                                }
                                let startingWidth = inspectorWidthAtDragStart ?? inspectorWidth
                                inspectorWidth = min(560, max(280, startingWidth - translation))
                            } onEnded: {
                                inspectorWidthAtDragStart = nil
                            }

                            InspectorView(state: state)
                                .frame(width: inspectorWidth)
                                .frame(maxHeight: .infinity)
                        }
                        .layoutPriority(1)
                        .transition(.move(edge: .trailing))
                    }
                }
                .clipped()
                .background(AppTheme.background)
                .animation(.easeInOut(duration: 0.22), value: state.isInspectorVisible)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var detail: some View {
        switch state.phase {
        case .starting:
            LaunchingView()
        case .needsPi:
            PiSetupView(state: state)
        case .ready:
            if let controller = state.activeController {
                VStack(spacing: 0) {
                    SessionView(state: state, controller: controller, composerFocusTick: composerFocusTick)
                    if state.isTerminalVisible {
                        TerminalPanel(state: state, controller: controller)
                    }
                }
            } else {
                WelcomeView(state: state)
            }
        }
    }

    /// The menu command (⌃⌘S) and the command palette share one toggle, so the
    /// two cannot disagree about which way the sidebar is going.
    private func toggleSidebar() {
        isSidebarVisible.toggle()
    }

    // MARK: - Overlays

    @ViewBuilder
    private var toast: some View {
        if let toast = state.toast {
            Text(toast)
                .font(.callout)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().stroke(.separator))
                .padding(.bottom, 18)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var errorBanner: some View {
        if let message = state.errorBanner {
            BannerView(
                level: .error,
                title: "Something went wrong",
                message: message,
                onDismiss: { state.errorBanner = nil }
            )
            .padding(.top, 8)
            .frame(maxWidth: 620)
        }
    }

    // MARK: - Command dispatch

    private func perform(_ command: PaletteCommand) {
        let controller = state.activeController
        switch command {
        case .newSession:
            let project = state.selectedProject?.path ?? state.activeController?.projectPath
            guard let project else { return }
            Task { await state.startNewSession(projectPath: project) }

        case .addProject:
            Task { await state.addProject() }

        case .refreshSessions:
            Task { await state.refreshIndex() }

        case .renameSession:
            guard let controller else { return }
            sheet = .rename(controller.sessionName ?? controller.displayTitle)
        case .cloneSession:
            Task { await controller?.cloneSession() }

        case .forkLatest:
            guard controller != nil else { return }
            sheet = .fork

        case .compactContext:
            Task { await controller?.compact() }

        case .compactWithInstructions:
            sheet = .compact

        case .exportSession:
            Task { await exportSession(controller) }

        case .deleteSession:
            guard let session = state.sessionPendingDeletion ?? fallbackDeletionCandidate else { return }
            state.sessionPendingDeletion = nil
            if state.preferences.confirmBeforeDeletingSessions {
                sheet = .delete(session)
            } else {
                state.delete(session: session)
            }

        case .focusComposer:
            composerFocusTick += 1

        case .interrupt:
            Task { await controller?.interrupt() }

        case .abortRun:
            Task { await controller?.abort() }

        case .cycleModel:
            Task { await controller?.cycleModel() }

        case .cycleThinkingLevel:
            Task { await controller?.cycleThinkingLevel() }

        case .toggleInspector:
            state.toggleInspector()

        case .toggleTerminal:
            state.toggleTerminal()

        case .toggleSidebar:
            toggleSidebar()

        case .copyTranscript:
            guard let controller else { return }
            state.copyToPasteboard(TranscriptExporter.plainText(controller.items))

        case .copyLastResponse:
            guard let controller else { return }
            if let text = controller.lastAssistantText, !text.isEmpty {
                state.copyToPasteboard(text)
            } else if let text = controller.items.last(where: { $0.kind == .assistant })?.text {
                state.copyToPasteboard(text)
            }

        case .openInTerminal:
            let path = controller?.projectPath ?? state.selectedProjectPath
            if let path { state.openTerminal(at: path) }

        case .openInVSCode:
            let path = controller?.projectPath ?? state.selectedProjectPath
            if let path { openProjectInVSCode(path) }

        case .revealInFinder:
            let path = controller?.projectPath ?? state.selectedProjectPath
            if let path { WorkspaceLauncher.reveal(path) }

        case .revealPiDirectory:
            let sessions = PiPaths.sessionsDirectory
            try? FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
            WorkspaceLauncher.reveal(PiPaths.agentDirectory.path)

        case .openSettings:
            state.openSettings(tab: state.settingsTab)

        case .providersSettings:
            state.openSettings(tab: .providers)

        case .packages:
            state.showPackages()

        case .showPiSetup:
            state.isOnboardingPresented = true

        case .checkForPiUpdates:
            Task {
                await state.launch()
                if let installation = state.installation {
                    state.showToast("Pi \(installation.version) at \(installation.displayPath)")
                }
            }
        }
    }

    /// The session a menu-driven delete applies to when no row was right-clicked.
    private var fallbackDeletionCandidate: SessionRef? {
        guard let sessionFile = state.activeController?.sessionFile else { return nil }
        return state.selectedProject?.sessions.first { $0.filePath == sessionFile }
    }

    /// Opens a project folder in VS Code (or a compatible fork), telling the user
    /// when no compatible editor is installed rather than failing silently — the
    /// workspace menu offers it as a one-click action, so a click that does
    /// nothing looks like a bug.
    private func openProjectInVSCode(_ path: String) {
        if !WorkspaceLauncher.openInVSCode(at: path) {
            state.showToast("Visual Studio Code isn't installed. Open the folder with another editor.")
        }
    }

    private func exportSession(_ controller: PiSessionController?) async {
        guard let controller else { return }
        let suggested = "\(controller.displayTitle.replacingOccurrences(of: "/", with: "-")).html"
        guard let path = WorkspaceLauncher.chooseSaveLocation(suggestedName: suggested, allowedType: "html") else { return }
        if let output = await controller.exportHTML(to: path) {
            state.showToast("Exported to \(output.abbreviatingHomeDirectory)")
        }
    }
}

/// Sheets that need a value or an action from the current session.
enum RootSheet: Identifiable {
    case palette
    case rename(String)
    case renameChat(SessionRef)
    case compact
    case fork
    case delete(SessionRef)
    case projectSettings(ProjectGroup)
    case newProject(String)

    var id: String {
        switch self {
        case .palette: return "palette"
        case .rename: return "rename"
        case .renameChat(let session): return "rename-\(session.id)"
        case .compact: return "compact"
        case .fork: return "fork"
        case .delete(let session): return "delete-\(session.id)"
        case .projectSettings(let project): return "project-settings-\(project.id)"
        case .newProject(let path): return "new-project-\(path)"
        }
    }
}

/// A plain glyph button for the titlebar band: dimmed until hovered, full ink
/// while its panel is open.
struct TitlebarIconButton: View {
    static let size: CGFloat = 26

    var systemImage: String
    var help: String
    var isActive: Bool = false
    var isEnabled: Bool = true
    var action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .regular))
                .frame(width: Self.size, height: Self.size)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isHovering ? AppTheme.railSelection.opacity(0.6) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .foregroundStyle(isActive || isHovering ? Color.primary : Color.secondary)
        .onHover { isHovering = $0 && isEnabled }
        .help(help)
        .accessibilityLabel(help)
    }
}
