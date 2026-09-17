//
//  RootView.swift
//  PiCode
//
//  Window layout: sessions sidebar, conversation, contextual inspector.
//
//  The inspector is laid out as a plain pane beside the conversation rather
//  than through the system `.inspector` column. The system column spans the full
//  window height — toolbar included — so it stands a toolbar taller than the
//  sidebar and conversation, which start below the toolbar. Laid out here, it is
//  exactly as tall as they are and nothing about them moves when it opens.
//

import SwiftUI

struct RootView: View {
    @Bindable var state: AppState

    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var composerFocusTick = 0
    @State private var sheet: RootSheet?
    @State private var inspectorWidth: CGFloat = 360
    @State private var inspectorWidthAtDragStart: CGFloat?

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                state: state,
                onOpenPalette: {
                    state.openPalette()
                    sheet = .palette
                },
                onOpenSettings: { sheet = .settings }
            )
            .navigationSplitViewColumnWidth(min: 234, ideal: 268, max: 360)
        } detail: {
            detailPane
        }
        .background(SidebarToggleStyler(iconSize: SidebarStyle.topBarIconSize))
        .task {
            if state.phase == .starting { await state.launch() }
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
            case .settings:
                ProviderSettingsModal(state: state) { self.sheet = nil }
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
        .overlay(alignment: .bottom) { toast }
        .overlay(alignment: .top) { errorBanner }
        .overlay { ExtensionDialogHost(state: state) }
    }

    // MARK: - Detail column

    /// The conversation and, when it is open, the inspector beside it. The two
    /// share the detail column's height, so opening the panel never resizes or
    /// shifts the sidebar or the transcript.
    private var detailPane: some View {
        Group {
            // The package browser owns the whole detail column: the inspector is
            // about a session's facts, and there is no session on screen.
            if state.phase == .ready && state.isPackagesVisible {
                PackagesView(state: state, isSidebarVisible: columnVisibility != .detailOnly)
            } else {
                HStack(spacing: 0) {
                    mainContentColumn
                        .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)

                    if state.isInspectorVisible {
                        HStack(spacing: 0) {
                            Rectangle()
                                .fill(Color(nsColor: .separatorColor))
                                .frame(width: 1)
                                .contentShape(Rectangle().inset(by: -3))
                                .gesture(
                                    DragGesture()
                                        .onChanged { value in
                                            if inspectorWidthAtDragStart == nil {
                                                inspectorWidthAtDragStart = inspectorWidth
                                            }
                                            let startingWidth = inspectorWidthAtDragStart ?? inspectorWidth
                                            inspectorWidth = min(560, max(280, startingWidth - value.translation.width))
                                        }
                                        .onEnded { _ in inspectorWidthAtDragStart = nil }
                                )

                            InspectorView(state: state)
                                .frame(width: inspectorWidth)
                                .frame(maxHeight: .infinity)
                        }
                        .transition(.move(edge: .trailing))
                    }
                }
                .offset(y: -ContentHeaderMetrics.contentLift)
                .clipped()
                .background(AppTheme.background)
                .animation(.easeInOut(duration: 0.22), value: state.isInspectorVisible)
                // The header is deliberately attached after pane clipping. Its
                // titlebar portion must remain outside the detail safe area.
                .overlay(alignment: .top) {
                    if state.phase == .ready, let controller = state.activeController {
                        ContentHeader(
                            projectName: state.selectedProject?.name ?? controller.projectName,
                            isSidebarVisible: columnVisibility != .detailOnly,
                            unreadNotificationCount: state.unreadNotificationCount,
                            isShowingNotifications: state.isShowingNotifications,
                            onToggleNotifications: { state.toggleNotifications() },
                            isInspectorVisible: state.isInspectorVisible && !state.isNotificationsVisible,
                            onToggleInspector: { state.toggleInspector() },
                            onOpenInTerminal: { state.openTerminal(at: controller.projectPath) },
                            onOpenInFinder: { WorkspaceLauncher.reveal(controller.projectPath) },
                            onOpenInVSCode: { openProjectInVSCode(controller.projectPath) }
                        )
                        .ignoresSafeArea(.container, edges: .top)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The visible header is attached to the complete detail split above. The
    /// column itself stays content-only to avoid a second titlebar row.
    @ViewBuilder
    private var mainContentColumn: some View {
        detail
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
        columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
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
                Task { try? await state.delete(session: session) }
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
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)

        case .providersSettings:
            state.openSettings(tab: .providers)
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)

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
    case settings
    case rename(String)
    case renameChat(SessionRef)
    case compact
    case fork
    case delete(SessionRef)
    case projectSettings(ProjectGroup)

    var id: String {
        switch self {
        case .palette: return "palette"
        case .settings: return "settings"
        case .rename: return "rename"
        case .renameChat(let session): return "rename-\(session.id)"
        case .compact: return "compact"
        case .fork: return "fork"
        case .delete(let session): return "delete-\(session.id)"
        case .projectSettings(let project): return "project-settings-\(project.id)"
        }
    }
}
