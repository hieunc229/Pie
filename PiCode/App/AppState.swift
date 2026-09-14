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

    var sidebarQuery = ""
    var paletteQuery = ""
    var isPalettePresented = false
    private(set) var paletteResults: [(project: ProjectGroup, session: SessionRef)] = []
    private var paletteTask: Task<Void, Never>?

    // MARK: - Presentation

    var isInspectorVisible: Bool {
        get { preferences.showInspector }
        set { preferences.showInspector = newValue; preferences.persist() }
    }
    var inspectorTab: InspectorTab = .changes
    /// File highlighted by a `path:line` link in assistant Markdown.
    var selectedFilePath: String?
    var selectedFileLine: Int?
    /// File the Changes pane should select, set by a tool card's change chip.
    var selectedChangePath: String?

    /// Text the inspector wants appended to the composer (e.g. an `@path`
    /// reference). The composer consumes it and clears it.
    var composerInsertion: String?

    func openInInspector(path: String, line: Int? = nil) {
        selectedFilePath = path
        selectedFileLine = line
        inspectorTab = .files
        isInspectorVisible = true
    }

    /// Opens the diff for a file the agent changed. The Changes pane owns the
    /// selection, so this only hands it the path and reveals the pane.
    func openInChanges(path: String) {
        selectedChangePath = path
        inspectorTab = .changes
        isInspectorVisible = true
    }
    var isSettingsPresented = false
    var isOnboardingPresented = false
    var isAboutPresented = false
    var isRenameSheetPresented = false
    var isDeleteConfirmationPresented = false
    var sessionPendingDeletion: SessionRef?
    var errorBanner: String?
    var toast: String?
    private var toastTask: Task<Void, Never>?

    /// Incremented whenever a menu command should reach the focused view.
    private(set) var commandTick = 0
    private(set) var lastCommand: PaletteCommand?

    enum InspectorTab: String, CaseIterable, Identifiable {
        case changes
        case files
        case terminal
        case tree
        case context

        var id: String { rawValue }

        var label: String {
            switch self {
            case .changes: return "Changes"
            case .files: return "Files"
            case .terminal: return "Terminal"
            case .tree: return "Tree"
            case .context: return "Context"
            }
        }

        var systemImage: String {
            switch self {
            case .changes: return "plusminus.circle"
            case .files: return "folder"
            case .terminal: return "terminal"
            case .tree: return "point.topleft.down.to.point.bottomright.curvepath"
            case .context: return "chart.pie"
            }
        }
    }

    init() {}

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

    var filteredProjects: [ProjectGroup] {
        let query = sidebarQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return projects }
        return index.search(query, in: projects)
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
        selectedProjectPath = CanonicalPath.of(session.cwd)
        selectedSessionKey = key
        preferences.lastProjectPath = selectedProjectPath
        preferences.persist()
        await activate(key: key, projectPath: session.cwd, sessionFile: path, installation: installation)
    }

    func startNewSession(projectPath: String) async {
        guard let installation else { return }
        let canonical = CanonicalPath.of(projectPath)
        let key = AppState.ephemeralKey(projectPath: canonical, id: UUID().uuidString.prefix(8).description)
        selectedProjectPath = canonical
        selectedSessionKey = key
        preferences.lastProjectPath = canonical
        preferences.persist()
        if project(for: canonical) == nil {
            await refreshIndex()
        }
        await activate(key: key, projectPath: canonical, sessionFile: nil, installation: installation)
    }

    private func activate(key: String,
                          projectPath: String,
                          sessionFile: String?,
                          installation: PiInstallation) async {
        if let existing = controllers[key] {
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
            drafts: drafts
        )
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

    /// Keeps at most `limit` child processes alive so idle sessions do not
    /// accumulate `pi` processes.
    private func pruneControllers(limit: Int = 4) {
        guard controllers.count > limit else { return }
        let ordered = lastAccess.sorted { $0.value < $1.value }
        for (key, _) in ordered where key != selectedSessionKey {
            if controllers.count <= limit { break }
            controllers[key]?.stop()
            controllers[key] = nil
            lastAccess[key] = nil
        }
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
        let canonical = CanonicalPath.of(path)
        await refreshIndex()
        if project(for: canonical) == nil {
            // A folder with no Pi sessions yet still belongs in the sidebar, so
            // PiCode shows it immediately with an empty session list.
            let placeholder = ProjectGroup(
                id: canonical,
                path: canonical,
                name: URL(fileURLWithPath: canonical).lastPathComponent,
                sessions: [],
                isPinned: false,
                trustState: ProjectTrustService().state(for: canonical)
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
    }

    func closePalette() {
        isPalettePresented = false
        paletteTask?.cancel()
    }

    func updatePaletteQuery() {
        let query = paletteQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            paletteResults = []
            return
        }
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
