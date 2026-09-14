//
//  PiSessionController.swift
//  PiCode
//
//  Owns exactly one `pi --mode rpc` child process and translates its protocol
//  into the state the UI renders.
//
//  Principles:
//   - Pi is the runtime. PiCode never edits prompt context, tool behavior, or
//     session files; it sends documented RPC commands and renders what comes back.
//   - The transcript is derived, never authoritative. `get_messages` and
//     `message_end` win over anything assembled from streaming deltas.
//   - Live execution state (tool status, bash output, retries) is kept in
//     side tables keyed by Pi's own ids so rows stay stable while streaming.
//   - Every error surfaces in the UI instead of being swallowed.
//

import Foundation
import Observation

@Observable
@MainActor
final class PiSessionController {
    // MARK: - Identity

    /// Canonical working directory for this session.
    let projectPath: String
    private let installation: PiInstallation
    private let preferences: PreferencesStore
    let drafts: DraftStore
    private let trustService = ProjectTrustService()
    private let gitService = GitStatusService()

    private(set) var sessionFile: String?
    private(set) var sessionId: String?
    private(set) var sessionName: String?

    /// Draft key: sessions Pi has not written to disk yet fall back to a
    /// project-scoped key so a draft survives process start.
    var draftKey: String { sessionFile ?? "new:\(projectPath)" }

    // MARK: - Connection

    private(set) var connection: ConnectionState = .idle
    private(set) var runtime: AgentRuntimeState = .idle
    private(set) var piVersion: String
    private(set) var lastError: String?
    private(set) var protocolWarnings: [String] = []
    private var client: PiRPCClient?
    private var exitReason: String?

    // MARK: - Transcript

    private var baseMessages: [PiMessage] = []
    private var baseItems: [TranscriptItem] = []
    private var optimisticUserItems: [TranscriptItem] = []
    private(set) var items: [TranscriptItem] = []
    private(set) var isStreaming = false
    private(set) var isCompacting = false
    private(set) var streamingModel: String?
    private(set) var streamingStartedAt: Date?
    private(set) var currentTurnStartedAt: Date?
    private(set) var lastTurnDuration: TimeInterval?

    private struct LiveToolCall {
        var id: String
        var name: String
        var argumentJSON: String = ""
    }

    private struct LiveTurn {
        var textByIndex: [Int: String] = [:]
        var thinkingByIndex: [Int: String] = [:]
        var toolCallsByIndex: [Int: LiveToolCall] = [:]
        var messageIndex: Int
        var model: String?
        var provider: String?
    }

    private var liveTurn: LiveTurn?

    private struct ToolRuntime {
        var status: ToolStatus = .pending
        var output: String?
        var startedAt: Date?
        var endedAt: Date?
        var details: JSONValue?
        var fullOutputPath: String?
        var arguments: JSONValue?
    }

    private struct BashRuntime {
        var id: String
        var command: String
        var output: String = ""
        var exitCode: Int?
        var isError = false
        var finished = false
    }

    private var toolRuntime: [String: ToolRuntime] = [:]
    private var bashRuntime: [String: BashRuntime] = [:]
    private var liveCompaction = false
    private var optimisticCounter = 0

    // MARK: - Session data

    private(set) var state: PiSessionState?
    private(set) var entries: [PiSessionEntry] = []
    private(set) var tree: [PiTreeNode] = []
    private(set) var leafId: String?
    /// Last entry id PiCode has seen; the cursor for cheap incremental refreshes.
    private var lastEntryId: String?
    /// True while Pi is walking a long session history. The tree pane shows this
    /// because a first load on a big session takes tens of seconds.
    private(set) var isLoadingEntries = false
    private(set) var stats: PiSessionStats?
    private(set) var availableModels: [PiModel] = []
    private(set) var thinkingLevels: [String] = []
    private(set) var forkPoints: [PiForkPoint] = []
    private(set) var commands: [PiCommand] = []
    private(set) var queue = QueueSnapshot()
    private(set) var lastAssistantText: String?

    var model: PiModel? { state?.model }
    var thinkingLevel: String? { state?.thinkingLevel }

    // MARK: - Workspace

    private(set) var git = GitRepositoryState(isRepository: false)
    private(set) var trustState: ProjectTrustState = .unknown
    /// Session-only trust override chosen in the UI; never persisted.
    private(set) var trustOverride: Bool?
    private var gitRefreshTask: Task<Void, Never>?
    private(set) var recentFileChanges: [FileChange] = []

    // MARK: - Extension UI

    private(set) var dialogs: [ExtensionDialog] = []
    private(set) var extensionStatuses: [String: String] = [:]
    /// Pending local deadlines for dialogs Pi will resolve on its own.
    private var dialogTimeouts: [String: Task<Void, Never>] = [:]
    private(set) var extensionWidgets: [WidgetPlacement: [String: [String]]] = [:]
    private(set) var notifications: [ExtensionNotification] = []
    private(set) var compatibilityNotices: [ExtensionCompatibilityNotice] = []
    private(set) var windowTitle: String?
    var composerPrefill: String?

    var activeDialog: ExtensionDialog? { dialogs.first }

    // MARK: - Activity

    private(set) var activity: [ActivityEntry] = []
    private let activityLimit = 300
    private(set) var retryDescription: String?
    private(set) var summarizationNote: String?

    /// Live execution counters surfaced in the inspector header.
    private(set) var toolCallCount = 0
    private(set) var subagentCount = 0

    // MARK: - Init

    init(projectPath: String,
         sessionFile: String?,
         installation: PiInstallation,
         preferences: PreferencesStore,
         drafts: DraftStore) {
        self.projectPath = CanonicalPath.of(projectPath)
        self.sessionFile = sessionFile
        self.installation = installation
        self.preferences = preferences
        self.drafts = drafts
        self.piVersion = installation.version
        self.sessionId = sessionFile.flatMap { Self.sessionID(fromFile: $0) }
        self.trustState = trustService.state(for: self.projectPath)
    }

    private static func sessionID(fromFile path: String) -> String? {
        let name = (path as NSString).lastPathComponent
        guard name.contains("_") else { return nil }
        return name.split(separator: "_").last.map { String($0).replacingOccurrences(of: ".jsonl", with: "") }
    }

    var projectName: String { URL(fileURLWithPath: projectPath).lastPathComponent }

    var displayTitle: String {
        if let sessionName, !sessionName.isEmpty { return sessionName }
        return projectName
    }

    // MARK: - Lifecycle

    func start() async {
        guard !connection.isConnected else { return }
        connection = .starting
        runtime = .starting
        lastError = nil
        exitReason = nil

        var arguments = ["--mode", "rpc"]
        if let sessionFile {
            arguments.append(contentsOf: ["--session", sessionFile])
        }
        arguments.append(contentsOf: trustLaunchArguments())
        if let model = preferences.defaultModelQualifiedID, !model.isEmpty, sessionFile == nil {
            arguments.append(contentsOf: ["--model", model])
        }
        let extra = preferences.extraLaunchArguments
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        arguments.append(contentsOf: extra)

        // Pi is a Node script: its own bin directory must win on PATH so the
        // Node version it was installed with is the one that runs it.
        let environment = PiDiscoveryService.launchEnvironment(
            executable: installation.executableURL,
            shellPath: installation.shellPath
        )

        let client = PiRPCClient(
            executableURL: installation.executableURL,
            workingDirectory: URL(fileURLWithPath: projectPath),
            arguments: arguments,
            environment: environment
        )
        client.recordsPayloads = preferences.recordRPCPayloads
        client.onEvent = { [weak self] event, raw in
            Self.deliver { self?.handle(event: event, raw: raw) }
        }
        client.onExit = { [weak self] code, reason in
            Self.deliver { self?.handleExit(code: code, reason: reason) }
        }
        client.onStderr = { [weak self] line in
            Self.deliver { self?.handleStderr(line) }
        }
        client.onProtocolError = { [weak self] message in
            Self.deliver { self?.handleProtocolError(message) }
        }
        client.onResponseWithoutID = { [weak self] response in
            Self.deliver { self?.handleUnmatchedResponse(response) }
        }
        client.onPayloadRecord = { message in
            PiDiagnosticsLog.shared.append(message)
        }

        self.client = client

        do {
            try client.start()
        } catch {
            connection = .failed(message: error.localizedDescription)
            runtime = .disconnected
            lastError = error.localizedDescription
            record(kind: .connection, title: "Could not start Pi",
                   detail: error.localizedDescription, isError: true)
            return
        }

        connection = .connected
        runtime = .idle
        record(kind: .connection, title: "Connected to Pi \(piVersion)",
               detail: arguments.joined(separator: " "))
        await refreshAll()
        await refreshGit(immediately: true)
    }

    func stop() {
        gitRefreshTask?.cancel()
        client?.stop()
        client = nil
        connection = .disconnected(reason: "Stopped")
        runtime = .disconnected
    }

    func restart() async {
        stop()
        try? await Task.sleep(nanoseconds: 250_000_000)
        toolRuntime.removeAll()
        bashRuntime.removeAll()
        liveTurn = nil
        liveCompaction = false
        isStreaming = false
        isCompacting = false
        await start()
    }

    /// Arguments that pin Pi's project trust behavior for this run so the loaded
    /// resources always match the trust state shown in the UI.
    private func trustLaunchArguments() -> [String] {
        if let trustOverride { return [trustOverride ? "--approve" : "--no-approve"] }
        return trustService.launchArguments(cwd: projectPath)
    }

    // MARK: - Trust

    func setTrust(_ decision: Bool, remember: Bool) {
        trustOverride = decision
        if remember {
            do {
                try trustService.setDecision(cwd: projectPath, decision: decision)
                trustState = trustService.state(for: projectPath)
                record(kind: .sessionChange,
                       title: decision ? "Project trusted" : "Project not trusted",
                       detail: "Saved to Pi's trust store")
            } catch {
                lastError = "Could not update Pi's trust store: \(error.localizedDescription)"
                record(kind: .error, title: "Trust store not updated",
                       detail: error.localizedDescription, isError: true)
            }
        } else {
            trustState = decision ? .trusted : .untrusted
            record(kind: .sessionChange,
                   title: decision ? "Trusted for this session" : "Not trusted for this session")
        }
        Task { await self.restart() }
    }

    func trustParentFolder() {
        do {
            try trustService.trustParentFolder(of: projectPath)
            trustState = trustService.state(for: projectPath)
            trustOverride = nil
            record(kind: .sessionChange, title: "Parent folder trusted")
        } catch {
            lastError = "Could not update Pi's trust store: \(error.localizedDescription)"
            return
        }
        Task { await self.restart() }
    }

    // MARK: - Sending prompts

    enum PromptDelivery {
        case automatic
        case steer
        case followUp

        var label: String {
            switch self {
            case .automatic: return "Send"
            case .steer: return "Queue as steering"
            case .followUp: return "Queue as follow-up"
            }
        }
    }

    @discardableResult
    func send(text: String, attachments: [Attachment] = [], delivery: PromptDelivery = .automatic) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let textParts = attachments.compactMap(\.promptSnippet)
        var body = trimmed
        if !textParts.isEmpty {
            let header = textParts.joined(separator: "\n\n")
            body = body.isEmpty ? header : body + "\n\n" + header
        }
        let images = attachments.compactMap(\.imagePayload)
        guard !body.isEmpty || !images.isEmpty else { return false }

        let busy = runtime.isBusy
        addOptimisticUserItem(text: body)

        do {
            switch delivery {
            case .steer:
                try await request(.steer(message: body, images: images))
            case .followUp:
                try await request(.followUp(message: body, images: images))
            case .automatic:
                try await request(.prompt(
                    message: body,
                    images: images,
                    behavior: busy ? .steer : nil
                ), timeout: promptTimeout(for: body))
            }
            drafts.clear(for: draftKey)
            return true
        } catch {
            removeOptimisticUserItem(matching: body)
            report(error, context: "Sending the prompt failed")
            return false
        }
    }

    /// Pi answers `prompt` only once the text has been handled, and an extension
    /// command is handled *by its own handler* — which may legitimately sit there
    /// waiting for a dialog the user has not answered yet. A normal prompt keeps
    /// the 60s preflight budget; an extension command gets the patient budget
    /// `bash` uses, so a long dialog cannot fake a "prompt failed" error.
    private func promptTimeout(for text: String) -> TimeInterval {
        let name = text
            .drop(while: { $0 == "/" })
            .split(whereSeparator: \.isWhitespace)
            .first
            .map(String.init)
        guard let name,
              commands.contains(where: { $0.name == name && $0.source == .extension })
        else { return PiRPCClient.defaultTimeout }
        return 3600
    }

    private func addOptimisticUserItem(text: String) {
        optimisticCounter += 1
        optimisticUserItems.append(TranscriptItem(
            id: "optimistic-user-\(optimisticCounter)",
            kind: .user,
            text: text,
            isStreaming: true,
            timestamp: Date()
        ))
        recomposeItems()
    }

    private func removeOptimisticUserItem(matching text: String) {
        guard let index = optimisticUserItems.firstIndex(where: { $0.text == text }) else { return }
        optimisticUserItems.remove(at: index)
        recomposeItems()
    }

    /// Drops everything Pi has queued without pulling it back into the composer.
    func clearQueue() async {
        guard (try? await request(.clearQueue)) != nil else { return }
        queue = QueueSnapshot()
    }

    /// Esc behavior from Pi's documentation: pull queued messages back into the
    /// composer, then abort.
    func interrupt() async {
        var restored: [String] = []
        if let response = try? await request(.clearQueue) {
            let steering = response.data?.array("steering")?.compactMap(\.stringValue) ?? []
            let followUp = response.data?.array("followUp")?.compactMap(\.stringValue) ?? []
            restored = steering + followUp
        }
        if !restored.isEmpty {
            let existing = drafts.text(for: draftKey)
            let combined = ([existing] + restored)
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n\n")
            drafts.setText(combined, for: draftKey)
            queue = QueueSnapshot()
        }
        await abort()
    }

    func abort() async {
        guard runtime.isBusy else { return }
        runtime = .stopping
        do {
            try await request(.abort, timeout: 120)
            record(kind: .agentEnd, title: "Aborted by you")
        } catch {
            report(error, context: "Aborting failed")
        }
        await refreshAll()
    }

    func abortRetry() async {
        do {
            try await request(.abortRetry)
            record(kind: .retry, title: "Retry cancelled")
        } catch {
            report(error, context: "Cancelling the retry failed")
        }
    }

    // MARK: - Session commands

    func newSession() async {
        do {
            let response = try await request(.newSession(parentSession: sessionFile))
            if response.data?.bool("cancelled") == true {
                record(kind: .sessionChange, title: "New session cancelled by an extension")
                return
            }
            resetSessionState()
            record(kind: .sessionChange, title: "Started a new session")
            await refreshAll()
        } catch {
            report(error, context: "Starting a new session failed")
        }
    }

    func cloneSession() async {
        do {
            let response = try await request(.clone)
            if response.data?.bool("cancelled") == true {
                record(kind: .sessionChange, title: "Clone cancelled by an extension")
                return
            }
            resetSessionState()
            record(kind: .sessionChange, title: "Cloned the current branch")
            await refreshAll()
        } catch {
            report(error, context: "Cloning the session failed")
        }
    }

    func fork(fromEntryId entryId: String) async {
        do {
            let response = try await request(.fork(entryId: entryId))
            if response.data?.bool("cancelled") == true {
                record(kind: .sessionChange, title: "Fork cancelled by an extension")
                return
            }
            resetSessionState()
            if let text = response.data?.string("text"), !text.isEmpty {
                drafts.setText(text, for: draftKey)
            }
            record(kind: .sessionChange, title: "Forked from an earlier message")
            await refreshAll()
        } catch {
            report(error, context: "Forking failed")
        }
    }

    func switchSession(to path: String) async {
        do {
            let response = try await request(.switchSession(path: path))
            if response.data?.bool("cancelled") == true {
                record(kind: .sessionChange, title: "Session switch cancelled by an extension")
                return
            }
            resetSessionState()
            sessionFile = path
            sessionId = Self.sessionID(fromFile: path)
            record(kind: .sessionChange, title: "Opened \(URL(fileURLWithPath: path).lastPathComponent)")
            await refreshAll()
        } catch {
            report(error, context: "Switching sessions failed")
        }
    }

    func setSessionName(_ name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await request(.setSessionName(name: trimmed))
            sessionName = trimmed.isEmpty ? nil : trimmed
            record(kind: .sessionChange,
                   title: trimmed.isEmpty ? "Cleared the session name" : "Named the session \(trimmed)")
            await refreshState()
        } catch {
            report(error, context: "Naming the session failed")
        }
    }

    func compact(customInstructions: String? = nil) async {
        let trimmed = customInstructions?.trimmingCharacters(in: .whitespacesAndNewlines)
        isCompacting = true
        runtime = .compacting
        do {
            let response = try await request(
                .compact(customInstructions: (trimmed?.isEmpty ?? true) ? nil : trimmed),
                timeout: 3600
            )
            if let data = response.data {
                let result = PiCompactionResult(json: data)
                record(kind: .compaction, title: "Compacted context",
                       detail: "\(Format.tokens(result.tokensBefore ?? 0)) → \(Format.tokens(result.estimatedTokensAfter ?? 0)) tokens")
            }
        } catch {
            report(error, context: "Compaction failed")
        }
        isCompacting = false
        runtime = .idle
        await refreshAll()
    }

    func exportHTML(to path: String? = nil) async -> String? {
        do {
            let response = try await request(.exportHTML(outputPath: path), timeout: 600)
            let outputPath = response.data?.string("path")
            if let outputPath {
                record(kind: .sessionChange, title: "Exported the session", detail: outputPath)
            }
            return outputPath
        } catch {
            report(error, context: "Exporting the session failed")
            return nil
        }
    }

    func runBash(_ command: String) async {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let key = "bash-\(UUID().uuidString.prefix(8))"
        bashRuntime[key] = BashRuntime(id: key, command: trimmed)
        recomposeItems()
        do {
            let response = try await request(.bash(command: trimmed), timeout: 3600)
            let data = response.data
            bashRuntime[key]?.output = data?.string("output") ?? ""
            bashRuntime[key]?.exitCode = data?.int("exitCode")
            bashRuntime[key]?.isError = (data?.int("exitCode") ?? 0) != 0
            bashRuntime[key]?.finished = true
            appendSynthesizedBashMessage(key: key, data: data)
        } catch {
            bashRuntime[key]?.output = error.localizedDescription
            bashRuntime[key]?.isError = true
            bashRuntime[key]?.finished = true
            report(error, context: "Running the command failed")
        }
        recomposeItems()
    }

    func abortBash() async {
        do {
            try await request(.abortBash)
        } catch {
            report(error, context: "Aborting the command failed")
        }
    }

    /// Direct `bash` RPC results become `bashExecution` messages in Pi's session,
    /// so PiCode mirrors one into the local list instead of inventing a separate
    /// transcript concept.
    private func appendSynthesizedBashMessage(key: String, data: JSONValue?) {
        guard let runtime = bashRuntime[key] else { return }
        var object: [String: JSONValue] = [
            "role": .string("bashExecution"),
            "command": .string(runtime.command),
            "output": .string(runtime.output),
            "exitCode": .number(Double(runtime.exitCode ?? 0)),
            "cancelled": .bool(false),
            "truncated": .bool(data?.bool("truncated") ?? false),
            "timestamp": .number(Date().timeIntervalSince1970 * 1000)
        ]
        if let full = data?.string("fullOutputPath") { object["fullOutputPath"] = .string(full) }
        baseMessages.append(PiMessage(raw: .object(object)))
        bashRuntime[key] = nil
        rebuildBaseItems()
    }

    // MARK: - Model and thinking

    func setModel(_ model: PiModel) async {
        do {
            try await request(.setModel(provider: model.provider, modelId: model.id))
            preferences.defaultModelQualifiedID = model.qualifiedID
            preferences.persist()
            record(kind: .sessionChange, title: "Model set to \(model.displayName)")
            await refreshState()
            await refreshThinkingLevels()
        } catch {
            report(error, context: "Switching models failed")
        }
    }

    func cycleModel() async {
        do {
            let response = try await request(.cycleModel)
            if let modelJSON = response.data?["model"], let model = PiModel(json: modelJSON) {
                record(kind: .sessionChange, title: "Model cycled to \(model.displayName)")
            } else if response.data?["model"]?.isNull ?? true {
                record(kind: .sessionChange, title: "Only one model is available")
            }
            await refreshState()
            await refreshThinkingLevels()
        } catch {
            report(error, context: "Cycling models failed")
        }
    }

    func setThinkingLevel(_ level: String) async {
        do {
            try await request(.setThinkingLevel(level: level))
            preferences.defaultThinkingLevel = level
            preferences.persist()
            await refreshState()
            record(kind: .sessionChange, title: "Thinking level set to \(level)")
        } catch {
            report(error, context: "Setting the thinking level failed")
        }
    }

    func cycleThinkingLevel() async {
        do {
            let response = try await request(.cycleThinkingLevel)
            if let level = response.data?.string("level") {
                record(kind: .sessionChange, title: "Thinking level cycled to \(level)")
            }
            await refreshState()
        } catch {
            report(error, context: "Cycling thinking levels failed")
        }
    }

    func setSteeringMode(_ mode: String) async {
        do {
            try await request(.setSteeringMode(mode: mode))
            await refreshState()
        } catch {
            report(error, context: "Changing the steering mode failed")
        }
    }

    func setFollowUpMode(_ mode: String) async {
        do {
            try await request(.setFollowUpMode(mode: mode))
            await refreshState()
        } catch {
            report(error, context: "Changing the follow-up mode failed")
        }
    }

    func setAutoCompaction(_ enabled: Bool) async {
        do {
            try await request(.setAutoCompaction(enabled: enabled))
            await refreshState()
            record(kind: .sessionChange, title: "Auto-compaction \(enabled ? "enabled" : "disabled")")
        } catch {
            report(error, context: "Changing auto-compaction failed")
        }
    }

    func setAutoRetry(_ enabled: Bool) async {
        do {
            try await request(.setAutoRetry(enabled: enabled))
            await refreshState()
            record(kind: .sessionChange, title: "Auto-retry \(enabled ? "enabled" : "disabled")")
        } catch {
            report(error, context: "Changing auto-retry failed")
        }
    }

    // MARK: - Extension dialog responses

    func respond(to dialog: ExtensionDialog, value: String) {
        client?.sendRaw(dialog.request.valueResponse(value))
        dismiss(dialog.id)
    }

    func confirm(_ dialog: ExtensionDialog, confirmed: Bool) {
        client?.sendRaw(dialog.request.confirmResponse(confirmed))
        dismiss(dialog.id)
    }

    func cancel(_ dialog: ExtensionDialog) {
        client?.sendRaw(dialog.request.cancelResponse())
        dismiss(dialog.id)
    }

    private func dismiss(_ id: String) {
        dialogTimeouts.removeValue(forKey: id)?.cancel()
        dialogs.removeAll { $0.id == id }
    }

    /// Pi resolves a timed dialog itself but never says so, so a dialog left on
    /// screen would invite the user to answer a question that no longer exists —
    /// Pi has already continued with the default. Mirror the deadline locally, a
    /// quarter second early so the answer PiCode would send can never race Pi's
    /// own resolution, and say in the activity timeline why it disappeared.
    private func scheduleDialogTimeout(id: String, seconds: TimeInterval) {
        dialogTimeouts[id]?.cancel()
        let delay = max(0.4, seconds - 0.25)
        dialogTimeouts[id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.expireDialog(id: id, seconds: seconds)
        }
    }

    private func expireDialog(id: String, seconds: TimeInterval) {
        dialogTimeouts.removeValue(forKey: id)
        guard dialogs.contains(where: { $0.id == id }) else { return }
        dialogs.removeAll { $0.id == id }
        record(kind: .extensionRequest,
               title: "Extension request expired",
               detail: "Nobody answered, so Pi resolved it after \(Format.duration(seconds)).")
    }

    func dismissNotification(_ id: UUID) {
        notifications.removeAll { $0.id == id }
    }

    func dismissAllNotifications() {
        notifications.removeAll()
    }

    // MARK: - Refresh

    private var refreshTask: Task<Void, Never>?

    /// Refreshes everything the UI needs after a launch, a session switch, or a
    /// fork. Ordering matters: the cheap calls that fill the transcript come
    /// first, and the session history walk (which can take tens of seconds on a
    /// long session) happens last so the conversation is readable immediately.
    func refreshAll() async {
        guard connection.isConnected else { return }
        refreshTask?.cancel()
        let task = Task { [weak self] in
            guard let self else { return }
            await self.refreshState()
            await self.refreshMessages()
            await self.refreshModels()
            await self.refreshThinkingLevels()
            await self.refreshCommands()
            await self.refreshStats()
            await self.refreshForkPoints()
            await self.refreshEntries()
        }
        refreshTask = task
        await task.value
    }

    func refreshState() async {
        guard let response = try? await request(.getState) else { return }
        let newState = PiSessionState(json: response.data)
        state = newState
        sessionFile = newState.sessionFile ?? sessionFile
        sessionId = newState.sessionId ?? sessionId
        sessionName = newState.sessionName
        isStreaming = newState.isStreaming
        isCompacting = newState.isCompacting
        if !newState.isStreaming, case .working = runtime { runtime = .idle }
        recomposeItems()
    }

    func refreshMessages() async {
        guard let response = try? await request(.getMessages) else { return }
        let messages = response.data?.array("messages")?.map(PiMessage.init(raw:)) ?? []
        applyAuthoritativeMessages(messages)
    }

    /// Replaces the message list with Pi's authoritative copy. Streaming state is
    /// cleared only when Pi reports nothing in flight, so a refresh mid-stream
    /// cannot erase an in-progress row.
    private func applyAuthoritativeMessages(_ messages: [PiMessage]) {
        baseMessages = messages
        if !isStreaming { liveTurn = nil }
        dropSatisfiedOptimisticItems()
        rebuildBaseItems()
    }

    /// Optimistic rows exist only until Pi echoes the same user message back.
    /// Matching is by text so a refresh cannot leave a duplicate on screen.
    private func dropSatisfiedOptimisticItems() {
        guard !optimisticUserItems.isEmpty else { return }
        var remaining: [TranscriptItem] = []
        for item in optimisticUserItems {
            let satisfied = baseMessages.contains { $0.isUser && $0.textContent == item.text }
            if !satisfied { remaining.append(item) }
        }
        optimisticUserItems = remaining
    }

    func refreshModels() async {
        guard let response = try? await request(.getAvailableModels) else { return }
        availableModels = response.data?.array("models")?.compactMap(PiModel.init(json:)) ?? []
    }

    func refreshThinkingLevels() async {
        guard let response = try? await request(.getAvailableThinkingLevels) else { return }
        thinkingLevels = response.data?.array("levels")?.compactMap(\.stringValue) ?? []
    }

    func refreshCommands() async {
        guard let response = try? await request(.getCommands) else { return }
        commands = response.data?.array("commands")?.map(PiCommand.init(json:)) ?? []
    }

    func refreshStats() async {
        guard let response = try? await request(.getSessionStats) else { return }
        stats = PiSessionStats(json: response.data)
    }

    /// Loads the session's entries and rebuilds the tree from them.
    ///
    /// PiCode deliberately never calls `get_tree`: it is derived here instead.
    /// Pi's `get_tree` walks the whole session and took ~32s on a 787-entry
    /// session, and because Pi answers one request at a time that stall also
    /// delays the user's next prompt.
    ///
    /// A *full* `get_entries` is expensive too (~20s for the same 787 entries,
    /// and Pi does not cache it), so it only happens once per session — after
    /// that the durable cursor from the last entry id makes each refresh
    /// effectively free (measured at 0.01s). That matters because this runs after
    /// every settled turn. If the cursor is rejected, the full fetch is retried.
    func refreshEntries() async {
        guard !isLoadingEntries else { return }
        isLoadingEntries = true
        defer { isLoadingEntries = false }

        if let cursor = lastEntryId, !entries.isEmpty {
            if let response = try? await request(.getEntries(since: cursor), timeout: 120),
               let data = response.data {
                let newEntries = data.array("entries")?.map(PiSessionEntry.init(json:)) ?? []
                if !newEntries.isEmpty {
                    entries.append(contentsOf: newEntries)
                    lastEntryId = newEntries.last?.id
                }
                leafId = data.string("leafId") ?? leafId
                tree = PiTreeNode.buildTree(from: entries, leafId: leafId)
                rebuildBaseItems()
                return
            }
            // The cursor failed (for example Pi restarted with a different
            // session); fall through to a full reload.
        }
        await loadAllEntries()
    }

    /// One full read of the session history. Called once per session, then kept
    /// up to date with `get_entries(since:)`.
    private func loadAllEntries() async {
        guard let response = try? await request(.getEntries(since: nil), timeout: 120) else { return }
        entries = response.data?.array("entries")?.map(PiSessionEntry.init(json:)) ?? []
        leafId = response.data?.string("leafId")
        lastEntryId = entries.last?.id
        tree = PiTreeNode.buildTree(from: entries, leafId: leafId)
        rebuildBaseItems()
    }

    func refreshForkPoints() async {
        guard let response = try? await request(.getForkMessages) else { return }
        forkPoints = response.data?.array("messages")?.map(PiForkPoint.init(json:)) ?? []
    }

    func refreshLastAssistantText() async {
        guard let response = try? await request(.getLastAssistantText) else { return }
        lastAssistantText = response.data?.string("text")
    }

    // MARK: - Git

    func refreshGit(immediately: Bool = false) async {
        gitRefreshTask?.cancel()
        let path = projectPath
        let service = gitService
        let task = Task { [weak self] in
            if !immediately {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                if Task.isCancelled { return }
            }
            let state = await service.repositoryState(for: path)
            if Task.isCancelled { return }
            self?.git = state
        }
        gitRefreshTask = task
        await task.value
    }

    func diff(for change: GitFileChange) async -> String {
        await gitService.diff(directory: projectPath, path: change.path, staged: change.isStaged)
    }

    func fullGitDiff() async -> String {
        await gitService.fullDiff(directory: projectPath)
    }

    // MARK: - Request plumbing

    @discardableResult
    private func request(_ command: RPCCommand,
                         timeout: TimeInterval = PiRPCClient.defaultTimeout) async throws -> RPCResponse {
        guard let client, connection.isConnected else { throw PiRPCError.notRunning }
        return try await client.send(command, timeout: timeout)
    }

    /// Delivers work to the main actor in the order the process emitted it.
    private static func deliver(_ body: @escaping @MainActor () -> Void) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { body() }
        }
    }

    // MARK: - Process-level failures

    private func handleExit(code: Int32, reason: Process.TerminationReason) {
        let reasonText = exitReason ?? (reason == .uncaughtSignal ? "signal" : "exit code \(code)")
        connection = .disconnected(reason: reasonText)
        runtime = .disconnected
        isStreaming = false
        isCompacting = false
        liveTurn = nil
        liveCompaction = false
        recomposeItems()
        record(kind: .connection, title: "Pi stopped (\(reasonText))",
               detail: exitReason, isError: code != 0)
    }

    private func handleStderr(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        exitReason = trimmed
        if trimmed.localizedCaseInsensitiveContains("error") || trimmed.localizedCaseInsensitiveContains("fatal") {
            lastError = trimmed.oneLinePreview(limit: 300)
        }
    }

    private func handleProtocolError(_ message: String) {
        protocolWarnings.append(message)
        if protocolWarnings.count > 40 { protocolWarnings.removeFirst() }
        record(kind: .error, title: "Protocol problem", detail: message, isError: true)
    }

    private func handleUnmatchedResponse(_ response: RPCResponse) {
        if !response.success {
            record(kind: .error, title: "`\(response.command)` failed",
                   detail: response.error, isError: true)
        }
    }

    private func report(_ error: Error, context: String) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        lastError = message
        record(kind: .error, title: context, detail: message, isError: true)
        notifications.append(ExtensionNotification(message: "\(context): \(message)", level: .error))
    }

    // MARK: - Event handling

    private func handle(event: PiEvent, raw: JSONValue) {
        switch event {
        case .agentStart:
            runtime = .working
            isStreaming = true
            currentTurnStartedAt = Date()
            beginLiveTurn()
            record(kind: .agentStart, title: "Agent started")

        case .agentEnd(let messages, let willRetry):
            lastTurnDuration = currentTurnStartedAt.map { Date().timeIntervalSince($0) }
            currentTurnStartedAt = nil
            if !willRetry {
                isStreaming = false
            }
            if !messages.isEmpty {
                baseMessages = messages
                rebuildBaseItems()
            }
            record(kind: .agentEnd, title: "Agent finished",
                   detail: willRetry ? "A retry will follow" : nil)

        case .agentSettled:
            runtime = .idle
            isStreaming = false
            liveTurn = nil
            streamingModel = nil
            streamingStartedAt = nil
            liveCompaction = false
            isCompacting = false
            retryDescription = nil
            summarizationNote = nil
            record(kind: .settled, title: "Session settled")
            recomposeItems()
            Task { [weak self] in
                guard let self else { return }
                await self.refreshMessages()
                await self.refreshState()
                await self.refreshStats()
                await self.refreshEntries()
                await self.refreshForkPoints()
                await self.refreshLastAssistantText()
                await self.refreshGit()
            }

        case .turnStart:
            currentTurnStartedAt = currentTurnStartedAt ?? Date()
            record(kind: .turn, title: "Turn started")

        case .turnEnd(_, let toolResults):
            lastTurnDuration = currentTurnStartedAt.map { Date().timeIntervalSince($0) }
            record(kind: .turn, title: "Turn finished",
                   detail: toolResults.isEmpty ? nil : "\(toolResults.count) tool result(s)")

        case .messageStart(let message):
            if message.isAssistant {
                beginLiveTurn()
                streamingModel = message.model
                streamingStartedAt = streamingStartedAt ?? Date()
            }

        case .messageUpdate(let usage, let delta):
            apply(delta: delta, usage: usage)

        case .messageEnd(let message):
            fold(message: message)

        case .bashExecutionUpdate(let id, let delta):
            guard let id, var runtime = bashRuntime[id] else { break }
            runtime.output += delta
            bashRuntime[id] = runtime
            recomposeItems()

        case .toolExecutionStart(let toolCallId, let toolName, let args):
            toolCallCount += 1
            if toolName.lowercased().contains("agent") || toolName.lowercased() == "task" {
                subagentCount += 1
            }
            var runtime = toolRuntime[toolCallId] ?? ToolRuntime()
            runtime.status = .running
            runtime.startedAt = Date()
            if let args { runtime.arguments = args }
            toolRuntime[toolCallId] = runtime
            ensureLiveToolCall(id: toolCallId, name: toolName, arguments: args)
            recomposeItems()

        case .toolExecutionUpdate(let toolCallId, let toolName, let partialResult):
            var runtime = toolRuntime[toolCallId] ?? ToolRuntime()
            runtime.status = .running
            runtime.startedAt = runtime.startedAt ?? Date()
            runtime.output = partialResult.text
            if let truncation = partialResult.truncation, truncation.truncated {
                runtime.fullOutputPath = truncation.fullOutputPath
            }
            toolRuntime[toolCallId] = runtime
            ensureLiveToolCall(id: toolCallId, name: toolName, arguments: nil)
            recomposeItems()

        case .toolExecutionEnd(let toolCallId, let toolName, let result, let isError):
            var runtime = toolRuntime[toolCallId] ?? ToolRuntime()
            runtime.status = (isError || (result?.isError ?? false)) ? .failure : .success
            runtime.endedAt = Date()
            runtime.startedAt = runtime.startedAt ?? runtime.endedAt
            if let result {
                runtime.output = result.text.isEmpty ? runtime.output : result.text
                runtime.details = result.details
                if let truncation = result.truncation, truncation.truncated {
                    runtime.fullOutputPath = truncation.fullOutputPath
                }
            }
            toolRuntime[toolCallId] = runtime
            ensureLiveToolCall(id: toolCallId, name: toolName, arguments: nil)
            recomposeItems()

        case .queueUpdate(let steering, let followUp):
            queue.update(steering: steering, followUp: followUp)
            record(kind: .queue, title: "Queue changed",
                   detail: "\(steering.count) steering, \(followUp.count) follow-up")

        case .compactionStart(let reason):
            isCompacting = true
            liveCompaction = true
            runtime = .compacting
            record(kind: .compaction, title: "Compacting context", detail: "Reason: \(reason)")
            recomposeItems()

        case .compactionEnd(let reason, let result, let aborted, let errorMessage, let willRetry):
            isCompacting = false
            liveCompaction = false
            runtime = willRetry ? .working : .idle
            if let errorMessage {
                record(kind: .error, title: "Compaction failed", detail: errorMessage, isError: true)
                notifications.append(ExtensionNotification(message: "Compaction failed: \(errorMessage)", level: .error))
            } else if aborted {
                record(kind: .compaction, title: "Compaction aborted", detail: "Reason: \(reason)")
            } else if let result {
                record(kind: .compaction, title: "Compacted context",
                       detail: "\(Format.tokens(result.tokensBefore ?? 0)) → \(Format.tokens(result.estimatedTokensAfter ?? 0)) tokens")
            }
            recomposeItems()
            Task { [weak self] in
                guard let self else { return }
                await self.refreshMessages()
                await self.refreshEntries()
                await self.refreshStats()
                await self.refreshState()
            }

        case .autoRetryStart(let attempt, let maxAttempts, let delayMs, let errorMessage):
            let until = Date().addingTimeInterval(Double(delayMs) / 1000)
            runtime = .retrying(attempt: attempt, maxAttempts: maxAttempts, until: until)
            retryDescription = "Attempt \(attempt) of \(maxAttempts) in \(Format.duration(Double(delayMs) / 1000))"
            record(kind: .retry, title: "Retrying after a transient error",
                   detail: errorMessage?.oneLinePreview(limit: 240))
            if let errorMessage {
                notifications.append(ExtensionNotification(
                    message: "Retrying (\(attempt)/\(maxAttempts)): \(errorMessage.oneLinePreview(limit: 160))",
                    level: .warning
                ))
            }

        case .autoRetryEnd(let success, let attempt, let finalError):
            retryDescription = nil
            if success {
                runtime = .working
                record(kind: .retry, title: "Retry succeeded", detail: "Attempt \(attempt)")
            } else {
                runtime = .idle
                isStreaming = false
                let detail = finalError ?? "Pi stopped retrying."
                record(kind: .error, title: "Retry failed", detail: detail, isError: true)
                notifications.append(ExtensionNotification(message: detail, level: .error))
            }

        case .summarizationRetryScheduled(let attempt, let maxAttempts, let delayMs, let errorMessage):
            summarizationNote = "Summarization retry \(attempt)/\(maxAttempts) in \(Format.duration(Double(delayMs) / 1000))"
            record(kind: .summarizationRetry, title: "Summarization retry scheduled",
                   detail: errorMessage?.oneLinePreview(limit: 240))

        case .summarizationRetryAttemptStart(let source, let reason):
            summarizationNote = "Retrying \(source ?? "summarization")\(reason.map { " (\($0))" } ?? "")"
            record(kind: .summarizationRetry, title: "Summarization retry started",
                   detail: [source, reason].compactMap { $0 }.joined(separator: " • "))

        case .summarizationRetryFinished:
            summarizationNote = nil
            record(kind: .summarizationRetry, title: "Summarization retry finished")

        case .extensionError(let extensionPath, let event, let error):
            let name = extensionPath.map { ($0 as NSString).lastPathComponent } ?? "extension"
            record(kind: .extensionError, title: "\(name) reported an error",
                   detail: "\(event ?? "unknown event"): \(error)", isError: true)
            notifications.append(ExtensionNotification(
                message: "\(name): \(error.oneLinePreview(limit: 200))",
                level: .error,
                extensionPath: extensionPath
            ))

        case .extensionUIRequest(let request):
            handleExtensionRequest(request)

        case .unknown(let type):
            protocolWarnings.append("Unhandled event type `\(type)`")
            if protocolWarnings.count > 40 { protocolWarnings.removeFirst() }
        }
    }

    // MARK: - Live streaming assembly

    private func beginLiveTurn() {
        if liveTurn == nil {
            liveTurn = LiveTurn(messageIndex: baseMessages.count, model: nil, provider: nil)
        }
    }

    private func apply(delta: AssistantDelta, usage: PiUsage?) {
        beginLiveTurn()
        guard var turn = liveTurn else { return }

        switch delta {
        case .textStart:
            break
        case .textDelta(let index, let text):
            turn.textByIndex[index, default: ""] += text
        case .textEnd(let index, let content):
            if !content.isEmpty { turn.textByIndex[index] = content }
        case .thinkingStart:
            break
        case .thinkingDelta(let index, let text):
            turn.thinkingByIndex[index, default: ""] += text
        case .thinkingEnd(let index, let content):
            if !content.isEmpty { turn.thinkingByIndex[index] = content }
        case .toolCallStart(let index, let id, let name):
            turn.toolCallsByIndex[index] = LiveToolCall(id: id, name: name)
        case .toolCallDelta(let index, let fragment):
            guard var call = turn.toolCallsByIndex[index] else { break }
            call.argumentJSON += fragment
            turn.toolCallsByIndex[index] = call
        case .toolCallEnd(let index, let block):
            if let id = block.toolCallId {
                turn.toolCallsByIndex[index] = LiveToolCall(
                    id: id,
                    name: block.toolName ?? turn.toolCallsByIndex[index]?.name ?? "tool",
                    argumentJSON: turn.toolCallsByIndex[index]?.argumentJSON ?? ""
                )
            }
        case .other:
            break
        }

        if let usage, !usage.isEmpty {
            // Usage arrives before the authoritative message; the transcript row
            // picks it up on `message_end`, so nothing to store here.
            _ = usage
        }

        liveTurn = turn
        if isStreaming == false { isStreaming = true }
        recomposeItems()
    }

    private func ensureLiveToolCall(id: String, name: String, arguments: JSONValue?) {
        beginLiveTurn()
        guard var turn = liveTurn else { return }
        if turn.toolCallsByIndex.values.contains(where: { $0.id == id }) { return }
        let nextIndex = (turn.toolCallsByIndex.keys.max() ?? -1) + 1
        turn.toolCallsByIndex[nextIndex] = LiveToolCall(id: id, name: name)
        liveTurn = turn
    }

    /// Folds an authoritative message into the transcript and clears any live
    /// rows it replaces.
    private func fold(message: PiMessage) {
        switch message.role {
        case "assistant":
            liveTurn = nil
            streamingModel = nil
            streamingStartedAt = nil
            appendIfNew(message)
        case "user":
            if let index = optimisticUserItems.firstIndex(where: { $0.text == message.textContent }) {
                optimisticUserItems.remove(at: index)
                baseMessages.append(message)
                rebuildBaseItems()
                return
            }
            appendIfNew(message)
        default:
            appendIfNew(message)
        }
    }

    private func appendIfNew(_ message: PiMessage) {
        if message.isToolResult, let id = message.toolCallId,
           baseMessages.contains(where: { $0.isToolResult && $0.toolCallId == id }) {
            rebuildBaseItems()
            return
        }
        if let last = baseMessages.last,
           last.role == message.role,
           last.timestamp == message.timestamp,
           last.textContent == message.textContent {
            rebuildBaseItems()
            return
        }
        baseMessages.append(message)
        rebuildBaseItems()
    }

    // MARK: - Extension UI requests

    private func handleExtensionRequest(_ request: ExtensionUIRequest) {
        switch request.method {
        case .select, .confirm, .input, .editor:
            var dialog = ExtensionDialog(id: request.id, request: request)
            dialog.draftText = request.prefill ?? ""
            if request.method == .select, let first = request.options.first {
                dialog.selection = first
            }
            if let last = dialogs.last { dialog.queuedBehind = last.id }
            dialogs.append(dialog)
            if let seconds = request.timeoutSeconds, seconds > 0 {
                scheduleDialogTimeout(id: request.id, seconds: seconds)
            }
            record(kind: .extensionRequest,
                   title: "\(dialog.title) requested by an extension",
                   detail: request.timeoutSeconds.map { "Pi will resolve this itself after \(Format.duration($0)) if nobody answers." })

        case .notify:
            let level = ExtensionNotification.Level(rawValue: request.notifyType ?? "info") ?? .info
            let message = request.message ?? request.text ?? ""
            guard !message.isEmpty else { break }
            notifications.append(ExtensionNotification(message: message, level: level))
            record(kind: .notify, title: message.oneLinePreview(limit: 160))

        case .setStatus:
            guard let key = request.statusKey else { break }
            if let text = request.statusText, !text.isEmpty {
                extensionStatuses[key] = text
            } else {
                extensionStatuses.removeValue(forKey: key)
            }

        case .setWidget:
            guard let key = request.widgetKey else { break }
            let placement = WidgetPlacement(rawValue: request.widgetPlacement ?? "") ?? .aboveEditor
            let lines = request.widgetLines ?? []
            if lines.isEmpty || lines.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                extensionWidgets[placement]?.removeValue(forKey: key)
            } else {
                var byKey = extensionWidgets[placement] ?? [:]
                byKey[key] = lines
                extensionWidgets[placement] = byKey
            }

        case .setTitle:
            windowTitle = request.title

        case .setEditorText:
            composerPrefill = request.text

        case .unsupported(let name):
            if !compatibilityNotices.contains(where: { $0.surface == name }) {
                compatibilityNotices.append(ExtensionCompatibilityNotice(
                    surface: name,
                    detail: "Pi sent an extension UI request PiCode does not render yet. The extension keeps running; this request was ignored."
                ))
            }
            record(kind: .extensionError, title: "Unsupported extension request `\(name)`",
                   detail: "Ignored. Pi's TUI may support this surface.", isError: false)
        }
    }

    // MARK: - Transcript composition

    private func rebuildBaseItems() {
        let userIds = TranscriptBuilder.userEntryIds(entries: entries, leafId: leafId)
        baseItems = TranscriptBuilder.items(messages: baseMessages, userEntryIds: userIds)
        applyToolRuntime(to: &baseItems)
        recomposeItems()
    }

    private func recomposeItems() {
        var result = baseItems
        var live = liveItems()
        applyToolRuntime(to: &live)
        result.append(contentsOf: live)
        result.append(contentsOf: optimisticUserItems)
        items = result
        recentFileChanges = aggregateFileChanges()
    }

    private func applyToolRuntime(to items: inout [TranscriptItem]) {
        guard !toolRuntime.isEmpty else { return }
        for index in items.indices {
            guard let id = items[index].toolCallId, let runtime = toolRuntime[id] else { continue }
            items[index].toolStatus = runtime.status
            if let output = runtime.output, !output.isEmpty { items[index].toolOutput = output }
            items[index].toolStartedAt = runtime.startedAt
            items[index].toolEndedAt = runtime.endedAt
            if let details = runtime.details { items[index].toolDetails = details }
            if let path = runtime.fullOutputPath { items[index].fullOutputPath = path }
            if items[index].toolArguments == nil, let arguments = runtime.arguments {
                items[index].toolArguments = arguments
            }
        }
    }

    /// Rows assembled from streaming deltas. The assistant message index is
    /// predicted so ids match the durable rows `message_end` produces and SwiftUI
    /// keeps row identity across the handoff (no scroll jump, no flicker).
    private func liveItems() -> [TranscriptItem] {
        var result: [TranscriptItem] = []

        if liveCompaction {
            var item = TranscriptItem(id: "live-compaction", kind: .compaction)
            item.text = "Compacting conversation context…"
            item.isStreaming = true
            result.append(item)
        }

        if let turn = liveTurn {
            for (index, text) in turn.thinkingByIndex.sorted(by: { $0.key < $1.key }) where !text.isEmpty {
                var item = TranscriptItem(id: "msg-\(turn.messageIndex)-thinking-\(index)", kind: .thinking)
                item.text = text
                item.isStreaming = true
                item.timestamp = streamingStartedAt
                item.modelName = turn.model
                item.provider = turn.provider
                result.append(item)
            }

            for (index, text) in turn.textByIndex.sorted(by: { $0.key < $1.key }) where !text.isEmpty {
                var item = TranscriptItem(id: "msg-\(turn.messageIndex)-assistant-\(index)", kind: .assistant)
                item.text = text
                item.isStreaming = true
                item.timestamp = streamingStartedAt
                item.modelName = turn.model
                item.provider = turn.provider
                result.append(item)
            }

            for (_, call) in turn.toolCallsByIndex.sorted(by: { $0.key < $1.key }) {
                var item = TranscriptItem(id: "tool-\(call.id)", kind: .toolCall)
                item.text = call.name
                item.toolCallId = call.id
                item.toolName = call.name
                item.toolArguments = decodeArguments(call.argumentJSON)
                item.toolStatus = toolRuntime[call.id]?.status ?? .pending
                item.toolStartedAt = toolRuntime[call.id]?.startedAt
                item.isStreaming = !(item.toolStatus.isTerminal)
                result.append(item)
            }
        }

        for runtime in bashRuntime.values.sorted(by: { $0.id < $1.id }) {
            var item = TranscriptItem(id: runtime.id, kind: .toolCall)
            item.text = runtime.command
            item.toolCallId = runtime.id
            item.toolName = "bash"
            item.toolArguments = .object(["command": .string(runtime.command)])
            item.toolOutput = runtime.output
            item.toolStatus = runtime.finished ? (runtime.isError ? .failure : .success) : .running
            item.isStreaming = !runtime.finished
            result.append(item)
        }

        return result
    }

    private func decodeArguments(_ text: String) -> JSONValue? {
        guard !text.isEmpty else { return nil }
        return try? JSONCoding.decode(Data(text.utf8))
    }

    private func aggregateFileChanges() -> [FileChange] {
        var order: [String: Int] = [:]
        var result: [FileChange] = []
        for item in baseItems {
            for change in item.fileChanges {
                if let index = order[change.path] {
                    result[index] = change
                } else {
                    order[change.path] = result.count
                    result.append(change)
                }
            }
        }
        return result
    }

    // MARK: - Activity log

    private func record(kind: ActivityEntry.Kind,
                        title: String,
                        detail: String? = nil,
                        isError: Bool = false) {
        activity.append(ActivityEntry(kind: kind, title: title, detail: detail, isError: isError))
        if activity.count > activityLimit {
            activity.removeFirst(activity.count - activityLimit)
        }
        if isError {
            lastError = detail ?? title
        }
    }

    // MARK: - Reset

    /// Clears everything that belongs to the previous session so a new, cloned,
    /// forked, or switched session cannot inherit stale rows.
    private func resetSessionState() {
        baseMessages = []
        baseItems = []
        optimisticUserItems = []
        toolRuntime.removeAll()
        bashRuntime.removeAll()
        liveTurn = nil
        liveCompaction = false
        entries = []
        tree = []
        leafId = nil
        lastEntryId = nil
        stats = nil
        forkPoints = []
        queue = QueueSnapshot()
        lastAssistantText = nil
        isStreaming = false
        isCompacting = false
        streamingModel = nil
        streamingStartedAt = nil
        currentTurnStartedAt = nil
        lastTurnDuration = nil
        retryDescription = nil
        summarizationNote = nil
        extensionWidgets = [:]
        extensionStatuses = [:]
        for task in dialogTimeouts.values { task.cancel() }
        dialogTimeouts = [:]
        dialogs = []
        runtime = .idle
        items = []
        recentFileChanges = []
    }

    // MARK: - Presentation helpers

    /// Only true while Pi says a request is in flight; used by the composer to
    /// decide between Send and Queue.
    var canSendImmediately: Bool { runtime.canAcceptPrompt }

    var contextUsagePercent: Double? {
        stats?.contextUsage?.percent
    }

    var hasPendingWork: Bool { isStreaming || isCompacting || runtime.isBusy }
}
