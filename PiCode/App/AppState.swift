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
    private let discovery = PiDiscoveryService()
    private let index = SessionIndex()

    // MARK: - Launch

    private(set) var phase: LaunchPhase = .starting
    private(set) var installation: PiInstallation?
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

    var isInspectorVisible: Bool {
        get { preferences.showInspector }
        set { preferences.showInspector = newValue; preferences.persist() }
    }
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
        isPalettePresented = false
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

    /// Opens the settings window on a specific tab. The window itself is raised
    /// by the view layer, which owns the AppKit call.
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
        collapsedProjects = preferences.collapsedProjects
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
        switch await discovery.discover() {
        case .found(let installation):
            self.installation = installation
            discoveryDetail = nil
            searchedPaths = []
            phase = .ready
            await refreshIndex()
            restoreLastSession()
        case .missing(let searched, _, let detail):
            installation = nil
            discoveryDetail = detail
            searchedPaths = searched
            phase = .needsPi(detail: detail)
            isOnboardingPresented = true
        }
    }

    func retryDiscovery() async {
        isOnboardingPresented = true
        await launch()
    }

    // MARK: - Index maintenance

    func refreshIndex() async {
        guard phase.isReady else { return }
        isIndexing = true
        let loaded = await index.loadAllProjects()
        var adjusted: [ProjectGroup] = []
        for var project in loaded {
            project.isPinned = preferences.pinnedProjects.contains(project.path)
            project.trustState = ProjectTrustService().state(for: project.path)
            let settings = preferences.projectSettings(for: project.path)
            if !settings.name.isEmpty { project.name = settings.name }
            if !settings.directory.isEmpty { project.workingDirectory = CanonicalPath.of(settings.directory) }
            var sessions = project.sessions.filter { !preferences.hiddenSessions.contains($0.id) }
            for sessionIndex in sessions.indices {
                sessions[sessionIndex].isPinned = preferences.pinnedSessions.contains(sessions[sessionIndex].id)
            }
            project.sessions = sessions
            adjusted.append(project)
        }
        projects = sort(adjusted)
        isIndexing = false
        lastIndexedAt = Date()
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
        guard let installation else { return }
        let path = session.filePath
        let key = path.map(AppState.key(forSessionPath:)) ?? AppState.ephemeralKey(projectPath: session.cwd, id: session.id)
        let canonical = CanonicalPath.of(session.cwd)
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
                       installation: installation)
    }

    func startNewSession(projectPath: String) async {
        guard let installation else { return }
        let canonical = CanonicalPath.of(projectPath)
        let settings = preferences.projectSettings(for: canonical)
        // New chats honour the project's chosen folder; the sidebar still groups
        // them under the project the user clicked.
        let launchDirectory = settings.directory.isEmpty ? canonical : CanonicalPath.of(settings.directory)
        let key = AppState.ephemeralKey(projectPath: canonical, id: UUID().uuidString.prefix(8).description)
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
                       installation: installation)
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
                          installation: PiInstallation) async {
        if let existing = controllers[key] {
            existing.onAgentCompleted = { [weak self] in self?.noteAssistantResponseCompleted() }
            lastAccess[key] = Date()
            await existing.refreshAll()
            pruneControllers()
            return
        }
        let controller = PiSessionController(
            projectPath: projectPath,
            sessionFile: sessionFile,
            installation: installation,
            preferences: preferences,
            drafts: drafts,
            systemPrompt: systemPrompt
        )
        controller.onAgentCompleted = { [weak self] in self?.noteAssistantResponseCompleted() }
        controllers[key] = controller
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
        guard !trimmed.isEmpty, let installation else { return }

        let controller: PiSessionController?
        if let path = session.filePath {
            let key = AppState.key(forSessionPath: path)
            if controllers[key] == nil {
                let canonical = CanonicalPath.of(session.cwd)
                let settings = preferences.projectSettings(for: canonical)
                await activate(key: key,
                               projectPath: session.cwd,
                               sessionFile: path,
                               systemPrompt: settings.systemPrompt,
                               installation: installation)
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
        if let path = session.filePath {
            return controllers[AppState.key(forSessionPath: path)]?.hasPendingWork ?? false
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
    func delete(session: SessionRef) async throws {
        if let path = session.filePath {
            let key = AppState.key(forSessionPath: path)
            if let controller = controllers[key] {
                controller.stop()
                controllers[key] = nil
                lastAccess[key] = nil
            }
            if selectedSessionKey == key { selectedSessionKey = nil }
            try FileManager.default.removeItem(atPath: path)
        } else {
            preferences.hiddenSessions.insert(session.id)
            preferences.persist()
        }
        await refreshIndex()
    }

    func hide(session: SessionRef) async {
        closeSession(key: session.filePath.map(AppState.key(forSessionPath:))
            ?? AppState.ephemeralKey(projectPath: session.cwd, id: session.id))
        preferences.hiddenSessions.insert(session.id)
        preferences.persist()
        await refreshIndex()
    }

    /// Projects whose chats are folded away, mirrored from preferences so the
    /// sidebar redraws when it changes (`PreferencesStore` is not observable).
    private(set) var collapsedProjects: Set<String>

    func isCollapsed(project: ProjectGroup) -> Bool {
        collapsedProjects.contains(project.path)
    }

    /// Fold a project's chats away, or bring them back. The sidebar is a
    /// projection of Pi's session directory, so this hides rows and nothing else:
    /// no session file is read, written or deleted, and the project row stays put.
    func toggleCollapsed(project: ProjectGroup) {
        if collapsedProjects.contains(project.path) {
            collapsedProjects.remove(project.path)
        } else {
            collapsedProjects.insert(project.path)
        }
        preferences.collapsedProjects = collapsedProjects
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
    /// drop), then open a fresh chat there just like “Open Project Folder…”.
    func addProject(path: String) async {
        let canonical = CanonicalPath.of(path)
        await refreshIndex()
        if project(for: canonical) == nil {
            // A folder with no Pi sessions yet still belongs in the sidebar, so
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
