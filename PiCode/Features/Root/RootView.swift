//
//  RootView.swift
//  PiCode
//
//  Window layout: sessions sidebar, conversation, contextual inspector.
//
//  The inspector is a macOS inspector so it participates in the system's
//  sidebar/inspector toolbar behavior instead of being a hand-rolled pane.
//

import SwiftUI

struct RootView: View {
    @Bindable var state: AppState

    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var composerFocusTick = 0
    @State private var sheet: RootSheet?

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(state: state)
                .navigationSplitViewColumnWidth(min: 232, ideal: 268, max: 360)
        } detail: {
            detail
                .frame(minWidth: 420)
        }
        .navigationTitle(title)
        .navigationSubtitle(subtitle)
        .inspector(isPresented: $state.isInspectorVisible) {
            InspectorView(state: state)
                .inspectorColumnWidth(min: 280, ideal: 360, max: 560)
        }
        .toolbar { toolbar }
        .task {
            if state.phase == .starting { await state.launch() }
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
                RenameSessionSheet(state: state, currentName: current) { self.sheet = nil }
            case .compact:
                CompactSessionSheet(state: state) { self.sheet = nil }
            case .fork:
                ForkSessionSheet(state: state) { self.sheet = nil }
            case .delete(let session):
                DeleteSessionSheet(state: state, session: session) { self.sheet = nil }
            }
        }
        .overlay(alignment: .bottom) { toast }
        .overlay(alignment: .top) { errorBanner }
        .overlay { ExtensionDialogHost(state: state) }
    }

    // MARK: - Detail column

    @ViewBuilder
    private var detail: some View {
        switch state.phase {
        case .starting:
            LaunchingView()
        case .needsPi:
            PiSetupView(state: state)
        case .ready:
            if let controller = state.activeController {
                SessionView(state: state, controller: controller, composerFocusTick: composerFocusTick)
            } else {
                WelcomeView(state: state)
            }
        }
    }

    private var title: String {
        state.activeController?.displayTitle ?? "PiCode"
    }

    private var subtitle: String {
        guard let controller = state.activeController else { return "" }
        var parts: [String] = [controller.projectName]
        if let model = controller.model { parts.append(model.displayName) }
        parts.append(controller.connection.label)
        return parts.joined(separator: " · ")
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                state.run(.addProject)
            } label: {
                Label("Open Project", systemImage: "folder.badge.plus")
            }
            .help("Open a project folder")
        }

        ToolbarItem {
            Button {
                state.run(.newSession)
            } label: {
                Label("New Session", systemImage: "plus.bubble")
            }
            .help("Start a new session in the selected project (⌘N)")
        }

        ToolbarItem {
            Button {
                state.openPalette()
                sheet = .palette
            } label: {
                Label("Commands", systemImage: "command")
            }
            .help("Command palette (⇧⌘P)")
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                state.isInspectorVisible.toggle()
            } label: {
                Label("Inspector", systemImage: "sidebar.right")
            }
            .help("Toggle the inspector (⌥⌘I)")
        }
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
            state.isInspectorVisible.toggle()

        case .toggleSidebar:
            columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly

        case .showChanges:
            state.inspectorTab = .changes
            state.isInspectorVisible = true
        case .showFiles:
            state.inspectorTab = .files
            state.isInspectorVisible = true
        case .showTerminal:
            state.inspectorTab = .terminal
            state.isInspectorVisible = true
        case .showTree:
            state.inspectorTab = .tree
            state.isInspectorVisible = true
        case .showContext:
            state.inspectorTab = .context
            state.isInspectorVisible = true

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
    case compact
    case fork
    case delete(SessionRef)

    var id: String {
        switch self {
        case .palette: return "palette"
        case .rename: return "rename"
        case .compact: return "compact"
        case .fork: return "fork"
        case .delete(let session): return "delete-\(session.id)"
        }
    }
}
