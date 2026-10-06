//
//  AppState.swift
//  PiCode
//
//  Root application state: Pi discovery, the project/session index, open
//  session controllers, and window-level presentation flags.
//
//  PiCode keeps Pi as the runtime. This object never writes Pi configuration; it
//  reads Pi's session directory and hands each open session to exactly one
//  `PiSessionController`.
//

import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class AppState {
    enum LaunchPhase: Equatable {
        case starting
        case needsPi(detail: String?)
        case ready

        var isReady: Bool { self == .ready }
    }

    // MARK: - Dependencies

    let preferences = PreferencesStore()
    let drafts = DraftStore()
    /// Detects and remembers every coding-agent harness on this Mac.
    let harnesses = HarnessRegistry()
    /// Runs user-initiated harness installs and streams their output.
    let installs = HarnessInstallService()
    /// Newest published versions of the installed harnesses.
    let harnessUpdates = HarnessUpdateChecker()
    private let index = SessionIndex()
    /// Fast, rebuildable cache of the session list. The sidebar reads it at
    /// launch so chats appear before the disk scan finishes.
    private let catalog = SessionCatalogDatabase()

    // MARK: - Launch

    private(set) var phase: LaunchPhase = .starting
    /// The harness new sessions use and whose version the UI reports.
    private(set) var activeHarness: HarnessDescriptor = .descriptor(for: .pi)
    /// The active harness's executable, when it is installed.
    var installation: PiInstallation? { harnesses.installation(for: activeHarness.id) }
    private(set) var discoveryDetail: String?
    private(set) var searchedPaths: [String] = []

    // MARK: - Index

    private(set) var projects: [ProjectGroup] = []
    private(set) var isIndexing = false
    private(set) var lastIndexedAt: Date?
    private var controllers: [String: PiSessionController] = [:]
    private var lastAccess: [String: Date] = [:]

    var selectedProjectPath: String?
    private(set) var selectedSessionKey: String?
    private(set) var sessionOpenRevision = 0
    private(set) var sessionOpenCompletedRevision = 0
    private(set) var sessionOpeningKey: String?

    // MARK: - Navigation history

    /// A chat the user was looking at, so Back / Forward can return to it.
    struct NavigationEntry: Equatable {
        var key: String
        var projectPath: String?
    }

    private(set) var navigationBack: [NavigationEntry] = []
    private(set) var navigationForward: [NavigationEntry] = []
    private var isNavigatingHistory = false
    var canGoBack: Bool { !navigationBack.isEmpty }
    var canGoForward: Bool { !navigationForward.isEmpty }

    /// Remember the chat on screen before the selection moves to `key`.
    private func recordNavigation(to key: String) {
        guard !isNavigatingHistory, let current = selectedSessionKey, current != key else { return }
        navigationBack.append(NavigationEntry(key: current, projectPath: selectedProjectPath))
        if navigationBack.count > 50 { navigationBack.removeFirst() }
        navigationForward.removeAll()
    }

    func goBack() async { await navigate(from: \.navigationBack, to: \.navigationForward) }
    func goForward() async { await navigate(from: \.navigationForward, to: \.navigationBack) }

    /// Pops entries off `source` until one still resolves to a chat, pushing the
    /// chat being left onto `destination`.
    private func navigate(
        from source: ReferenceWritableKeyPath<AppState, [NavigationEntry]>,
        to destination: ReferenceWritableKeyPath<AppState, [NavigationEntry]>
    ) async {
        let leaving = selectedSessionKey.map { NavigationEntry(key: $0, projectPath: selectedProjectPath) }
        while let entry = self[keyPath: source].popLast() {
            isNavigatingHistory = true
            defer { isNavigatingHistory = false }
            if let session = projects.lazy.flatMap(\.sessions).first(where: { $0.controllerKey == entry.key }) {
                await open(session: session)
            } else if controllers[entry.key] != nil {
                selectedSessionKey = entry.key
                if let path = entry.projectPath { selectProject(path) }
                isPackagesVisible = false
                lastAccess[entry.key] = Date()
            } else {
                continue
            }
            if let leaving { self[keyPath: destination].append(leaving) }
            return
        }
    }

    // MARK: - Search

    var paletteQuery = ""
    var isPalettePresented = false
    private(set) var paletteResults: [(project: ProjectGroup, session: SessionRef)] = []
    /// Projects whose name (or path) matches the palette query. Kept beside the
    /// session results so a project with no chats — or one whose name is what the
    /// user remembers — is still reachable from the palette.
    private(set) var paletteProjectResults: [ProjectGroup] = []
    private var paletteTask: Task<Void, Never>?

    // MARK: - Presentation

    /// Whether the right panel is open for the current window. This is
    /// intentionally session-only: switching chats keeps an open inspector, but
    /// closing and reopening the window always starts with the panel closed.
    var isInspectorVisible = false
    /// What the right panel is showing. It is a single viewer, not a set of tabs:
    /// whatever the user last clicked in the conversation — a file's contents, an
    /// edit's diff, a command's output, or any other tool's result — is rendered
    /// there, with its path (or a title when there is no path) along the top.
    enum InspectorArtifact: Equatable {
        /// A tool call from the transcript, matched by item id so the panel keeps
        /// up while the call is still streaming.
        case tool(id: String)
        /// A file on disk, optionally highlighted at a line.
        case file(path: String, line: Int?)
        /// A file the agent changed, shown as a working-tree diff.
        case change(path: String)
    }

    var inspectorArtifact: InspectorArtifact?

    /// Whether the right panel is showing the notification list instead of the
    /// selected artifact. The bell in the content header toggles it; opening a
    /// file, diff, or tool result switches it back to the artifact.
    var isNotificationsVisible = false
    /// Notification ids the user has already looked at. In-memory only: a badge
    /// means "new since you last opened the bell", not a fact stored about Pi.
    private var readNotificationIDs: Set<UUID> = []

    /// The last `path:line` a Markdown link named, and the last path a change chip
    /// named. Kept beside the artifact so the pane views still compile; the
    /// artifact is what the panel actually renders.
    var selectedFilePath: String?
    var selectedFileLine: Int?
    var selectedChangePath: String?

    /// Whether the detail column is showing the package browser instead of a
    /// session. It is a page, not a session: the selection below is kept while it
    /// is open, so leaving the page returns to whatever chat was showing.
    private(set) var isPackagesVisible = false

    /// Show the package browser in the detail column.
    func showPackages() {
        isPackagesVisible = true
        isSettingsPresented = false
        isPalettePresented = false
    }

    /// Leave the package browser and return to whatever chat was showing.
    func hidePackages() {
        isPackagesVisible = false
        isSettingsPresented = false
    }

    /// Text the inspector wants appended to the composer (e.g. an `@path`
    /// reference). The composer consumes it and clears it.
    var composerInsertion: String?

    func openInInspector(path: String, line: Int? = nil) {
        selectedFilePath = path
        selectedFileLine = line
        inspectorArtifact = .file(path: path, line: line)
        isNotificationsVisible = false
        isInspectorVisible = true
    }

    /// Opens the diff for a file the agent changed.
    func openInChanges(path: String) {
        selectedChangePath = path
        inspectorArtifact = .change(path: path)
        isNotificationsVisible = false
        isInspectorVisible = true
    }

    /// Opens a tool call's own content — a command's transcript, a read's file, an
    /// edit's diff, or a generic tool's output — in the right panel.
    func openInInspector(toolId: String) {
        inspectorArtifact = .tool(id: toolId)
        isNotificationsVisible = false
        isInspectorVisible = true
    }

    /// Toggle the artifact viewer. If notifications currently own the one right
    /// panel, switch that panel to the artifact instead of closing and reopening
    /// two independent surfaces.
    func toggleInspector() {
        if isShowingNotifications {
            markNotificationsRead()
            isNotificationsVisible = false
            isInspectorVisible = true
            return
        }
        isInspectorVisible.toggle()
        if !isInspectorVisible {
            isNotificationsVisible = false
        }
    }

    // MARK: - Notifications

    /// Whether the right panel is actually on screen and showing notifications.
    /// `isNotificationsVisible` alone can be true while the panel itself is closed,
    /// so this is the fact the bell's tint and the badge read.
    var isShowingNotifications: Bool { isInspectorVisible && isNotificationsVisible }

    /// Show or hide the notification list in the right panel. Showing it also opens
    /// the panel — otherwise the bell would flip a flag on a closed column and
    /// appear to do nothing. Opening marks everything read, which clears the badge.
    func toggleNotifications() {
        if isShowingNotifications {
            markNotificationsRead()
            isNotificationsVisible = false
            isInspectorVisible = false
        } else {
            isNotificationsVisible = true
            isInspectorVisible = true
            markNotificationsRead()
        }
    }

    /// Mark every notification in memory as read. Not just the active session's:
    /// while the list is open the user is looking at notifications, and a switch
    /// between sessions must not make a seen message look new again. Ids are
    /// session-independent UUIDs, so one set covers them all.
    func markNotificationsRead() {
        for controller in controllers.values {
            for notification in controller.notifications {
                readNotificationIDs.insert(notification.id)
            }
        }
    }

    /// How many notifications the bell should badge. While the list is on screen
    /// every message counts as read, so one that arrives during a visit does not
    /// badge the bell the user is already looking at.
    var unreadNotificationCount: Int {
        guard !isShowingNotifications, let controller = activeController else { return 0 }
        return controller.notifications.filter { !readNotificationIDs.contains($0.id) }.count
    }

    // MARK: - Terminal panel

    /// Whether the terminal panel is open under the conversation. Like the two
    /// panels above it, this is a remembered window-layout fact.
    ///
    /// The panel is Pi's *bash* surface (`TerminalPane`), not a second shell:
    /// PiCode does not start a login shell and give it a pty (§6). Commands run
    /// through Pi's own bash tool, so they land in the session the user is
    /// already in, and an interactive shell is still one click away in the
    /// panel's own “Open in Terminal”.
    var isTerminalVisible: Bool {
        get { preferences.showTerminal }
        set { preferences.showTerminal = newValue; preferences.persist() }
    }

    /// The open terminal panel's height in points. Not persisted: it is a
    /// per-visit adjustment, and the default is the measured comfortable size.
    var terminalHeight: CGFloat = 220

    func toggleTerminal() { isTerminalVisible.toggle() }

    /// Replaces the window content with Settings, on a specific tab.
    func openSettings(tab: SettingsTab) {
        settingsTab = tab
        isSettingsPresented = true
    }

    /// Pi reads `models.json` and its model catalog when a process starts, so a
    /// provider change only takes effect in a new `pi` process. Restarting is
    /// explicit because it interrupts whatever the session was doing.
    func restartSessionsForConfigurationChange() {
        let connected = controllers.values.filter { $0.connection.isConnected }
        guard !connected.isEmpty else {
            showToast("No running session to restart. New sessions pick this up already.")
            return
        }
        for controller in connected {
            Task { await controller.restart() }
        }
        showToast("Restarting \(connected.count) session(s) to apply the provider change.")
    }

    /// Applies a provider-catalog change end to end: mirror the neutral registry
    /// into every installed harness that needs a native file, then restart all
    /// provider-aware sessions. Each adapter either reads its catalog at process
    /// startup or supplies provider-specific launch configuration.
    func providersDidChange() {
        synchronizeProviders()
        let affected: Set<HarnessID> = [.pi, .ohMyPi, .deepseekHarness, .claudeCode, .codex]
        let connected = controllers.values.filter {
            $0.connection.isConnected && affected.contains($0.harness.id)
        }
        guard !connected.isEmpty else { return }
        for controller in connected {
            Task { await controller.restart() }
        }
        showToast("Restarting \(connected.count) session(s) so the new providers appear.")
    }
    var isSettingsPresented = false
    /// Which settings tab is showing, so a command can open the relevant one.
    var settingsTab: SettingsTab = .general
    var isOnboardingPresented = false
    var isAboutPresented = false
    var isRenameSheetPresented = false
    var isDeleteConfirmationPresented = false
    var sessionPendingDeletion: SessionRef?
    var errorBanner: String?
    var toast: String?
    private var toastTask: Task<Void, Never>?

    // MARK: - Dock badge

    /// Completions that arrived while the app was not frontmost. The red dock
    /// badge is the one signal that reaches the user when PiCode is behind another
    /// window, and it is cleared the moment the app comes back to the front — the
    /// badge is a nudge, not an inbox.
    private(set) var completionBadgeCount = 0
    /// The observer token is torn down from `deinit`, which is not actor-isolated,
    /// so the storage is marked unsafe rather than isolated. The token itself is
    /// immutable once set in `init` and only removed once, from `deinit`.
    nonisolated(unsafe) private var activationObserver: NSObjectProtocol?

    /// Incremented whenever a menu command should reach the focused view.
    private(set) var commandTick = 0
    private(set) var lastCommand: PaletteCommand?

    init() {
        expandedProjects = preferences.expandedProjects
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.clearCompletionBadge() }
        }
    }

    // MARK: - Launch sequence

    func launch() async {
        phase = .starting
        await harnesses.refresh()
        synchronizeProviders()

        if let descriptor = preferredHarness() {
            activeHarness = descriptor
            // Older builds allowed an installed harness with no adapter to be
            // saved as the default, then silently launched Pi instead.  Repair
            // that stale preference so Settings and new chats agree.
            if preferences.defaultHarnessID != descriptor.id,
               !harnesses.usableHarnesses.contains(where: { $0.id == preferences.defaultHarnessID }) {
                preferences.defaultHarnessID = descriptor.id
                preferences.persist()
            }
            discoveryDetail = nil
            searchedPaths = []
            phase = .ready
            installCachedIndex()
            await refreshIndex()
            restoreLastSession()
        } else {
            let detail = harnesses.missingDetail[.pi]
                ?? "No coding-agent harness with a PiCode adapter is installed."
            discoveryDetail = detail
            searchedPaths = []
            phase = .needsPi(detail: detail)
            isOnboardingPresented = true
        }
    }

    /// The harness new sessions should use: the user's default when it is
    /// installed with a working adapter, otherwise Pi, otherwise any usable one.
    private func preferredHarness() -> HarnessDescriptor? {
        let usable = harnesses.usableHarnesses
        if let preferred = usable.first(where: { $0.id == preferences.defaultHarnessID }) {
            return preferred
        }
        if let pi = usable.first(where: { $0.id == .pi }) { return pi }
        return usable.first
    }

    /// The harness a new chat in `projectPath` should run on, honouring a
    /// project override when that harness is installed.
    func harness(forProject path: String) -> HarnessDescriptor? {
        let settings = preferences.projectSettings(for: CanonicalPath.of(path))
        let desired = settings.harness ?? preferences.defaultHarnessID
        let usable = harnesses.usableHarnesses
        if let match = usable.first(where: { $0.id == desired }) { return match }
        return preferredHarness()
    }

    func retryDiscovery() async {
        isOnboardingPresented = true
        await launch()
    }

    /// Re-export the neutral provider registry whenever installed harnesses
    /// change. A newly installed runtime receives every existing provider.
    func synchronizeProviders() {
        do {
            try ProviderRegistry.synchronize(
                ProviderRegistry.providers(),
                with: harnesses.installedHarnessIDs
            )
        } catch {
            present(error: "Provider sync failed: \(error.localizedDescription)")
        }
    }

    /// The project's chosen model as a `provider/model` id. A model picked from a
    /// custom provider arrives unqualified and is paired with its provider; a
    /// qualified id is passed through untouched.
    private func qualifiedModel(for path: String, harness: HarnessDescriptor) -> String? {
        let settings = preferences.projectSettings(for: CanonicalPath.of(path))
        guard let model = settings.modelID, !model.isEmpty else { return nil }
        if model.contains("/") { return model }
        guard let provider = settings.providerID, !provider.isEmpty else { return model }
        guard HarnessProviderCatalog.supports(providerID: provider, on: harness.id) else { return nil }
        return "\(provider)/\(model)"
    }

    // MARK: - Index maintenance

    func refreshIndex() async {
        guard phase.isReady else { return }
        isIndexing = true
        let loaded = await index.loadAllProjects()
        // Reconcile newly persisted sessions with their existing controllers.
        // Native IDs and file paths are different for Claude Code and Codex.
        for session in loaded.flatMap(\.sessions) {
            guard let oldKey = controllers.first(where: {
                $0.value.harness.id == session.harnessID
                    && ($0.value.sessionFile == session.resumeIdentifier
                        || (session.sessionId != nil && $0.value.sessionId == session.sessionId))
            })?.key, oldKey != session.controllerKey else { continue }
            controllers[session.controllerKey] = controllers.removeValue(forKey: oldKey)
            lastAccess[session.controllerKey] = lastAccess.removeValue(forKey: oldKey)
            if selectedSessionKey == oldKey { selectedSessionKey = session.controllerKey }
        }
        projects = sort(decorate(loaded))
        catalog.save(projects: projects)
        isIndexing = false
        lastIndexedAt = Date()
    }

    /// Draws the last persisted list the instant a disk scan begins. The scan
    /// replaces it moments later, so this only removes the empty sidebar that
    /// used to sit there while `refreshIndex()` read every file.
    private func installCachedIndex() {
        let cached = catalog.loadProjects()
        guard !cached.isEmpty else { return }
        projects = sort(decorate(cached))
    }

    /// Applies PiCode-owned decorations (pins, hidden flags, renames, launch
    /// folder, trust) to a freshly loaded or cached session list.
    private func decorate(_ loaded: [ProjectGroup]) -> [ProjectGroup] {
        loaded.map { project in
            var project = project
            project.isPinned = preferences.pinnedProjects.contains(project.path)
            project.trustState = ProjectTrustService().state(for: project.path)
            let settings = preferences.projectSettings(for: project.path)
            if !settings.name.isEmpty { project.name = settings.name }
            if !settings.directory.isEmpty { project.workingDirectory = CanonicalPath.of(settings.directory) }
            var sessions = project.sessions.filter { !preferences.hiddenSessions.contains($0.id) }
            for sessionIndex in sessions.indices {
                sessions[sessionIndex].name = SessionCatalogMetadata.title(for: sessions[sessionIndex])
                    ?? sessions[sessionIndex].name
                sessions[sessionIndex].isPinned = preferences.pinnedSessions.contains(sessions[sessionIndex].id)
            }
            project.sessions = sessions
            return project
        }
    }

    private func sort(_ projects: [ProjectGroup]) -> [ProjectGroup] {
        projects
            .map { project -> ProjectGroup in
                var copy = project
                copy.sessions.sort { lhs, rhs in
                    if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
                    return lhs.updatedAt > rhs.updatedAt
                }
                return copy
            }
            .sorted { lhs, rhs in
                if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
                return lhs.mostRecentActivity > rhs.mostRecentActivity
            }
    }

    func project(for path: String) -> ProjectGroup? {
        let canonical = CanonicalPath.of(path)
        return projects.first { $0.path == canonical }
    }

    var selectedProject: ProjectGroup? {
        selectedProjectPath.flatMap(project(for:))
    }

    var activeController: PiSessionController? {
        selectedSessionKey.flatMap { controllers[$0] }
    }

    var isActiveSessionBusy: Bool { activeController?.hasPendingWork ?? false }

    // MARK: - Session lifecycle

    /// Draft key used before a session file exists.
    static func ephemeralKey(projectPath: String, id: String) -> String {
        "new:\(CanonicalPath.of(projectPath)):\(id)"
    }

    static func key(forSessionPath path: String) -> String { "session:\(path)" }

    func open(session: SessionRef) async {
        if session.isEphemeral, activeController?.harness.id == session.harnessID { return }
        guard session.harnessID != .deepseekHarness else {
            present(error: "DeepSeek's installed JSON-RPC adapter cannot resume saved sessions yet. Open this conversation in DeepSeek Harness: \(session.sessionId ?? session.id).")
            return
        }
        let harness = HarnessDescriptor.descriptor(for: session.harnessID)
        guard harnesses.isInstalled(harness.id) else {
            present(error: "Install \(harness.displayName) to resume this session.")
            return
        }
        let path = session.resumeIdentifier
        let key = session.controllerKey
        sessionOpenRevision += 1
        let openingRevision = sessionOpenRevision
        sessionOpeningKey = key
        let canonical = CanonicalPath.of(session.cwd)
        recordNavigation(to: key)
        // An existing session keeps the folder it was created in. Only the
        // system prompt is a property of the project rather than of the session,
        // so it follows the session when it is resumed.
        let settings = preferences.projectSettings(for: canonical)
        selectedProjectPath = canonical
        selectedSessionKey = key
        isPackagesVisible = false
        preferences.lastProjectPath = selectedProjectPath
        preferences.persist()
        await activate(key: key,
                       projectPath: session.cwd,
                       sessionFile: path,
                       systemPrompt: settings.systemPrompt,
                       harness: harness)
        if sessionOpenRevision == openingRevision, selectedSessionKey == key {
            sessionOpenCompletedRevision = openingRevision
        }
    }

    /// Starts a new chat. `harnessOverride` opens the chat on a specific runtime
    /// instead of the project/app default — used when the user picks another
    /// harness from the composer's model menu.
    func startNewSession(projectPath: String, harnessOverride: HarnessDescriptor? = nil) async {
        let canonical = CanonicalPath.of(projectPath)
        guard let harness = harnessOverride ?? harness(forProject: canonical) else { return }
        let settings = preferences.projectSettings(for: canonical)
        // New chats honour the project's chosen folder; the sidebar still groups
        // them under the project the user clicked.
        let launchDirectory = settings.directory.isEmpty ? canonical : CanonicalPath.of(settings.directory)
        let key = AppState.ephemeralKey(projectPath: canonical, id: UUID().uuidString.prefix(8).description)
        recordNavigation(to: key)
        selectedProjectPath = canonical
        selectedSessionKey = key
        isPackagesVisible = false
        preferences.lastProjectPath = canonical
        preferences.persist()
        if project(for: canonical) == nil {
            await refreshIndex()
        }
        await activate(key: key,
                       projectPath: launchDirectory,
                       sessionFile: nil,
                       systemPrompt: settings.systemPrompt,
                       harness: harness)
    }

    /// Start a chat in the project the user is already working in. The project
    /// *identity* comes first (the path the sidebar groups by), not the running
    /// controller's folder: a project can be pointed at a different launch folder,
    /// and the next chat must still be the same project. Only when there is no
    /// project at all does this fall back to the folder picker, because a picker is
    /// a different action than the button promises.
    func newChatInCurrentProject() async {
        if let path = selectedProjectPath ?? selectedProject?.path ?? activeController?.projectPath {
            await startNewSession(projectPath: path)
        } else {
            await addProject()
        }
    }

    /// Opening a project from the palette: go to its most recent chat, or start a
    /// new one when the project has none yet. Selecting the project first means the
    /// sidebar and header follow even if the chat open fails.
    func open(project: ProjectGroup) async {
        selectProject(project.path)
        if let mostRecent = project.sessions.first {
            await open(session: mostRecent)
        } else {
            await startNewSession(projectPath: project.path)
        }
    }

    private func activate(key: String,
                          projectPath: String,
                          sessionFile: String?,
                          systemPrompt: String?,
                          harness: HarnessDescriptor) async {
        if let existing = controllers[key] {
            existing.onAgentCompleted = { [weak self] in self?.noteAssistantResponseCompleted() }
            lastAccess[key] = Date()
            await existing.refreshAll()
            pruneControllers()
            return
        }
        guard let installation = harnesses.installation(for: harness.id) else {
            present(error: "\(harness.displayName) is not installed.")
            return
        }
        let controller = PiSessionController(
            projectPath: projectPath,
            sessionFile: sessionFile,
            installation: installation,
            preferences: preferences,
            drafts: drafts,
            systemPrompt: systemPrompt,
            modelOverride: qualifiedModel(for: projectPath, harness: harness),
            harness: harness
        )
        controller.onAgentCompleted = { [weak self] in self?.noteAssistantResponseCompleted() }
        controllers[key] = controller
        controller.onSessionForked = { [weak self, weak controller] in
            guard let self, let controller, let path = controller.sessionFile else { return }
            let newKey = AppState.key(forSessionPath: path)
            let oldKeys = self.controllers.filter { $0.value === controller }.map(\.key)
            let wasSelected = oldKeys.contains { $0 == self.selectedSessionKey }
            for oldKey in oldKeys where oldKey != newKey {
                self.controllers.removeValue(forKey: oldKey)
                self.lastAccess.removeValue(forKey: oldKey)
            }
            self.controllers[newKey] = controller
            self.lastAccess[newKey] = Date()
            if wasSelected { self.selectedSessionKey = newKey }
            self.showToast("Branched — you are now in the new chat")
            Task { await self.refreshIndex() }
        }
        lastAccess[key] = Date()
        await controller.start()
        pruneControllers()
    }

    func selectProject(_ path: String) {
        selectedProjectPath = CanonicalPath.of(path)
        preferences.lastProjectPath = selectedProjectPath
        preferences.persist()
    }

    // MARK: - Project settings

    /// Project a settings sheet was requested for. The sidebar owns the request
    /// (it is where the menu lives) and the window owns the sheet, so the two
    /// meet here rather than one reaching into the other's view state.
    var pendingProjectSettings: ProjectGroup?

    /// A project whose first chat is waiting on a harness/provider/model choice.
    /// The window owns the sheet; this is the request that opens it.
    var pendingNewProjectPath: String?

    func projectSettings(for project: ProjectGroup) -> ProjectSettings {
        preferences.projectSettings(for: project.path)
    }

    func presentProjectSettings(_ project: ProjectGroup) {
        pendingProjectSettings = project
    }

    /// Saves the project's PiCode-only settings and rebuilds the index so the
    /// sidebar and header pick up the new name at once.
    func updateProjectSettings(_ settings: ProjectSettings, for project: ProjectGroup) async {
        preferences.setProjectSettings(settings, for: project.path)
        await refreshIndex()
    }

    // MARK: - Session rename

    /// Session a rename was requested for. The sidebar owns the request — its
    /// context menu is where the action lives — and the window owns the sheet, so
    /// the two meet here rather than one reaching into the other's view state.
    var pendingSessionRename: SessionRef?

    func presentRename(session: SessionRef) {
        pendingSessionRename = session
    }

    /// Ask Pi to name a session. A chat that is not on screen is opened just far
    /// enough to talk to it: `set_session_name` acts on the session Pi has loaded,
    /// so a controller has to exist (it is pruned like any other idle one
    /// afterwards). Pi owns the session file, so the name is Pi's write; PiCode
    /// never edits the file itself.
    func rename(session: SessionRef, to name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if session.harnessID != .pi && session.harnessID != .ohMyPi {
            guard !trimmed.isEmpty else { return }
            SessionCatalogMetadata.rename(session, to: trimmed)
            await refreshIndex()
            return
        }
        let harness = HarnessDescriptor.descriptor(for: session.harnessID)
        guard !trimmed.isEmpty, harnesses.isInstalled(harness.id) else { return }

        let controller: PiSessionController?
        if let path = session.resumeIdentifier {
            let key = session.controllerKey
            if controllers[key] == nil {
                let canonical = CanonicalPath.of(session.cwd)
                let settings = preferences.projectSettings(for: canonical)
                await activate(key: key,
                               projectPath: session.cwd,
                               sessionFile: path,
                               systemPrompt: settings.systemPrompt,
                               harness: harness)
            }
            controller = controllers[key]
        } else {
            // A session that exists only in memory is the one on screen; its row
            // is only drawn while its controller is the active one.
            controller = activeController
        }
        await controller?.setSessionName(trimmed)
        await refreshIndex()
    }

    /// Keeps at most `limit` child processes alive so idle sessions do not
    /// accumulate `pi` processes. A session with work in flight is never pruned:
    /// switching away from a running task must not stop it.
    private func pruneControllers(limit: Int = 4) {
        guard controllers.count > limit else { return }
        let ordered = lastAccess.sorted { $0.value < $1.value }
        for (key, _) in ordered where key != selectedSessionKey {
            if controllers.count <= limit { break }
            guard controllers[key]?.hasPendingWork != true else { continue }
            controllers[key]?.stop()
            controllers[key] = nil
            lastAccess[key] = nil
        }
    }

    /// Whether the Pi process for a session has work in flight, even when that
    /// session is not the one on screen. The process is not stopped on a switch,
    /// so the sidebar can say "still working" from any tab.
    ///
    /// A session on disk only runs while a controller for *it* is alive. Sessions
    /// whose process was never started — or was pruned — have no work, however busy
    /// the one on screen is, which is what stops every unloaded row from showing a
    /// spinner whenever any one session runs.
    func isRunning(_ session: SessionRef) -> Bool {
        if !session.isEphemeral {
            return controllers[session.controllerKey]?.hasPendingWork ?? false
        }
        // A session that exists only in memory is the one being viewed.
        return activeController?.hasPendingWork ?? false
    }

    func closeSession(key: String) {
        controllers[key]?.stop()
        controllers[key] = nil
        lastAccess[key] = nil
        if selectedSessionKey == key {
            selectedSessionKey = nil
        }
    }

    func stopAllSessions() {
        for controller in controllers.values { controller.stop() }
        controllers.removeAll()
        lastAccess.removeAll()
    }

    /// Removes a session by first asking Pi to end it, then deleting the file.
    /// Session files are never modified by the indexer; deletion is the only
    /// mutation and only after explicit confirmation.
    ///
    /// The answer is the whole decision, so it takes effect at once: the session
    /// leaves the index the sidebar draws — and the sheet that asked the question
    /// closes with it — before the disk is asked anything. Only the rescan that
    /// follows runs in the background, because that is the part that takes as
    /// long as Pi's session folder takes to walk, and a delete still in flight is
    /// not something the user has to sit and watch. The file itself is unlinked
    /// here, on the main actor, so that no later rescan can disagree with the row
    /// already gone; a failure reports itself in the window's banner instead of a
    /// sheet that is no longer on screen, and the row returns by itself, because
    /// the rescan only drops what the file system no longer has.
    func delete(session: SessionRef) {
        if let path = session.filePath {
            let key = AppState.key(forSessionPath: path)
            if let controller = controllers[key] {
                controller.stop()
                controllers[key] = nil
                lastAccess[key] = nil
            }
            if selectedSessionKey == key { selectedSessionKey = nil }
            dropFromIndex(session.id)
            do {
                try FileManager.default.removeItem(atPath: path)
            } catch {
                present(error: "Could not delete \(session.displayName): \(error.localizedDescription)")
            }
            Task { await refreshIndex() }
        } else {
            preferences.hiddenSessions.insert(session.id)
            preferences.persist()
            dropFromIndex(session.id)
            Task { await refreshIndex() }
        }
    }

    /// Takes a session out of the index the sidebar draws, without touching disk.
    /// A project keeps its row: its folder is still there, and that is what the
    /// rescan finds a moment later.
    private func dropFromIndex(_ sessionID: String) {
        guard let projectIndex = projects.firstIndex(where: { project in
            project.sessions.contains { $0.id == sessionID }
        }) else { return }
        projects[projectIndex].sessions.removeAll { $0.id == sessionID }
    }

    func hide(session: SessionRef) async {
        closeSession(key: session.isEphemeral ? (selectedSessionKey ?? session.controllerKey) : session.controllerKey)
        preferences.hiddenSessions.insert(session.id)
        preferences.persist()
        await refreshIndex()
    }

    /// Projects whose chats the sidebar shows, mirrored from preferences so the
    /// sidebar redraws when it changes (`PreferencesStore` is not observable).
    /// The sidebar opens as a list of projects: a project is folded until it is in
    /// this set, so an untouched install shows every chat hidden behind its
    /// project's row.
    private(set) var expandedProjects: Set<String>

    func isCollapsed(project: ProjectGroup) -> Bool {
        !expandedProjects.contains(project.path)
    }

    /// Fold a project's chats away, or bring them back. The sidebar is a
    /// projection of Pi's session directory, so this hides rows and nothing else:
    /// no session file is read, written or deleted, and the project row stays put.
    func toggleCollapsed(project: ProjectGroup) {
        if expandedProjects.contains(project.path) {
            expandedProjects.remove(project.path)
        } else {
            expandedProjects.insert(project.path)
        }
        preferences.expandedProjects = expandedProjects
        preferences.persist()
    }

    /// Whether a project's chats are on screen. A fold is a fold: clicking a
    /// project always hides or shows its chats. The sidebar no longer filters in
    /// place — search lives in the palette, which searches names *and* transcript
    /// text — so a click can never be turned into a no-op by a query.
    func showsChats(of project: ProjectGroup) -> Bool {
        !isCollapsed(project: project)
    }

    func togglePin(project: ProjectGroup) {
        if preferences.pinnedProjects.contains(project.path) {
            preferences.pinnedProjects.remove(project.path)
        } else {
            preferences.pinnedProjects.insert(project.path)
        }
        preferences.persist()
        projects = sort(projects.map { current in
            var copy = current
            if copy.path == project.path { copy.isPinned = preferences.pinnedProjects.contains(project.path) }
            return copy
        })
    }

    func togglePin(session: SessionRef) {
        if preferences.pinnedSessions.contains(session.id) {
            preferences.pinnedSessions.remove(session.id)
        } else {
            preferences.pinnedSessions.insert(session.id)
        }
        preferences.persist()
        projects = sort(projects.map { project in
            var copy = project
            for index in copy.sessions.indices where copy.sessions[index].id == session.id {
                copy.sessions[index].isPinned = preferences.pinnedSessions.contains(session.id)
            }
            return copy
        })
    }

    func addProject() async {
        guard let path = WorkspaceLauncher.chooseDirectory() else { return }
        await addProject(path: path)
    }

    /// Register a folder supplied without the picker (for example, a Finder
    /// drop), then ask for the harness/provider/model before the first chat.
    func addProject(path: String) async {
        let canonical = CanonicalPath.of(path)
        await refreshIndex()
        if project(for: canonical) == nil {
            // A folder with no sessions yet still belongs in the sidebar, so
            // PiCode shows it immediately with an empty session list.
            let settings = preferences.projectSettings(for: canonical)
            let placeholder = ProjectGroup(
                id: canonical,
                path: canonical,
                name: settings.name.isEmpty ? URL(fileURLWithPath: canonical).lastPathComponent : settings.name,
                sessions: [],
                isPinned: false,
                trustState: ProjectTrustService().state(for: canonical),
                workingDirectory: settings.directory.isEmpty ? nil : CanonicalPath.of(settings.directory)
            )
            projects.insert(placeholder, at: 0)
        }
        selectProject(canonical)
        // A brand-new project asks which harness, provider, and model its chats
        // should use before the first session starts.
        pendingNewProjectPath = canonical
    }

    /// Applies the harness/provider/model chosen for a new project and starts its
    /// first chat.
    func createProject(path: String, harness: HarnessDescriptor, provider: String?, model: String?) async {
        let canonical = CanonicalPath.of(path)
        var settings = preferences.projectSettings(for: canonical)
        settings.harness = harness.id
        settings.providerID = provider
        settings.modelID = model
        preferences.setProjectSettings(settings, for: canonical)
        pendingNewProjectPath = nil
        await startNewSession(projectPath: canonical)
    }

    private func restoreLastSession() {
        guard selectedSessionKey == nil else { return }
        let target = preferences.lastProjectPath.flatMap(project(for:))
            ?? projects.first(where: { !$0.sessions.isEmpty })
        guard let project = target else { return }
        selectedProjectPath = project.path
        if let mostRecent = project.sessions.first {
            Task { await open(session: mostRecent) }
        }
    }

    // MARK: - Command palette

    func openPalette() {
        isPalettePresented = true
        paletteQuery = ""
        paletteResults = []
        paletteProjectResults = []
    }

    func closePalette() {
        isPalettePresented = false
        paletteTask?.cancel()
    }

    func updatePaletteQuery() {
        let query = paletteQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            paletteTask?.cancel()
            paletteResults = []
            paletteProjectResults = []
            return
        }
        // Project matches are a cheap local filter, so they do not wait on the
        // debounced transcript search below.
        let needle = query.lowercased()
        paletteProjectResults = Array(
            projects
                .filter { $0.name.lowercased().contains(needle) || $0.path.lowercased().contains(needle) }
                .prefix(8)
        )
        let snapshot = projects
        paletteTask?.cancel()
        paletteTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            let service = SessionIndex()
            let matches = service.search(query, in: snapshot)
            var rows: [(ProjectGroup, SessionRef)] = []
            for project in matches {
                for session in project.sessions.prefix(5) {
                    rows.append((project, session))
                }
            }
            self?.paletteResults = Array(rows.prefix(40))
        }
    }

    // MARK: - Dock badge

    /// A chat message completed. The badge is only useful when the user is looking
    /// at another app, so a completion on screen is not counted; the transcript
    /// already shows it.
    func noteAssistantResponseCompleted() {
        Task { await refreshIndex() }
        guard !NSApp.isActive else { return }
        completionBadgeCount += 1
        updateDockBadge()
    }

    /// The user is back. The badge has done its job, so it goes away even if some
    /// of the completions were never read.
    func clearCompletionBadge() {
        guard completionBadgeCount != 0 || NSApp.dockTile.badgeLabel != nil else { return }
        completionBadgeCount = 0
        updateDockBadge()
    }

    private func updateDockBadge() {
        NSApp.dockTile.badgeLabel = completionBadgeCount > 0 ? "\(completionBadgeCount)" : nil
    }

    // MARK: - Presentation helpers

    func showToast(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    func present(error: String) {
        errorBanner = error
    }

    func run(_ command: PaletteCommand) {
        lastCommand = command
        commandTick += 1
    }

    func copyToPasteboard(_ text: String) {
        WorkspaceLauncher.copyToPasteboard(text)
        showToast("Copied")
    }

    func openTerminal(at path: String) {
        if WorkspaceLauncher.openTerminal(at: path) == nil {
            present(error: "Could not open Terminal. Check that Terminal.app is available.")
        }
    }
}
