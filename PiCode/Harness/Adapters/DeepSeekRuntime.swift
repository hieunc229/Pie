//
//  DeepSeekRuntime.swift
//  PiCode
//
//  Drives DeepSeek Harness (`dsh`) over the SDK profile's newline-delimited
//  JSON-RPC 2.0 server:
//
//    dsh --profile sdk
//
//  Methods: `initialize`, `session/prompt`, `shutdown`.
//  Notifications: `session.event` (durable facts), `session.status`
//  (whole-agent running/idle), and subagent lifecycle frames.
//
//  The profile streams whole-agent status and durable session events rather than
//  token deltas, and it has no cancel method: a turn is abandoned by closing the
//  runtime process.
//

import Foundation

final class DeepSeekRuntime: BufferedAgentRuntime {
    private var process: PiProcess?
    private var requestCounter = 0
    private var pending: [Int: CheckedContinuation<JSONValue, Error>] = [:]
    private let pendingLock = NSLock()
    private var initialized = false
    private var isRunning = false
    private let sessionId = "picode-" + UUID().uuidString.lowercased()

    override func start() throws {
        let providers = HarnessProviderCatalog.providers(for: .deepseekHarness)
        try DSHProviderService.saveCustomProviders(providers)
        var arguments = HarnessLaunch.sessionModeArguments(for: .deepseekHarness)
        if !providers.isEmpty {
            arguments.append(contentsOf: ["--patch", DSHProviderService.patchFile.path])
        }
        arguments.append(contentsOf: extraArguments)

        var launchEnvironment = environment
        for (key, value) in DSHProviderService.launchEnvironment(providers) {
            launchEnvironment[key] = value
        }

        // The SDK/CLI stores profiles, plugins, and sessions under DSH_HOME. If
        // the user has not set one, `dsh` auto-initializes its own default.
        let configuration = PiProcess.Configuration(
            executableURL: installation.executableURL,
            arguments: arguments,
            workingDirectory: URL(fileURLWithPath: projectPath),
            environment: launchEnvironment
        )
        let process = PiProcess(configuration: configuration)
        process.onEvent = { [weak self, weak process] event in
            guard let process else { return }
            self?.handle(processEvent: event, from: process)
        }
        try process.start()
        self.process = process
    }

    override func stop() {
        process?.closeStdin()
        process?.terminate()
        process = nil
        initialized = false
        failAllPending(AgentRuntimeError.notRunning)
    }

    // MARK: - Commands

    override func send(_ command: RPCCommand, timeout: TimeInterval) async throws -> RPCResponse {
        switch command {
        case .prompt(_, _, _), .steer(_, _), .followUp(_, _):
            try await ensureInitialized(timeout: timeout)
            let messageId = try await sessionPrompt(promptText(command), timeout: timeout)
            return response(command, data: .object(["messageId": .string(messageId)]))

        case .abort, .abortRetry:
            // No cancel method exists; abandoning the turn means ending the process.
            process?.terminate()
            process = nil
            initialized = false
            isRunning = false
            stateFields.isStreaming = false
            emit(.agentEnd(messages: messages, willRetry: false))
            emit(.agentSettled)
            return response(command)

        case .getAvailableModels:
            return response(command, data: .object(["models": .array(Self.modelCatalog(modelOverride))]))

        case .setModel(let provider, let modelId):
            modelOverride = modelId.isEmpty ? provider : "\(provider)/\(modelId)"
            stateFields.model = PiModel(id: modelId, provider: provider, name: modelId)
            if initialized {
                stop()
                try start()
            }
            return response(command)

        case .getSessionStats:
            return response(command, data: .object([
                "totalMessages": .number(Double(messages.count)),
                "userMessages": .number(Double(messages.filter { $0.isUser }.count)),
                "assistantMessages": .number(Double(messages.filter { $0.isAssistant }.count))
            ]))

        default:
            return try await super.send(command, timeout: timeout)
        }
    }

    private func promptText(_ command: RPCCommand) -> String {
        switch command {
        case .prompt(let message, _, _), .steer(let message, _), .followUp(let message, _):
            return message
        default:
            return ""
        }
    }

    // MARK: - JSON-RPC

    private func ensureInitialized(timeout: TimeInterval) async throws {
        guard !initialized else { return }
        let (provider, model) = Self.route(modelOverride)
        var params: [String: JSONValue] = [
            "provider": .string(provider),
            "model": .string(model)
        ]
        if let prompt = systemPrompt, !prompt.isEmpty {
            params["systemPrompt"] = .string(prompt)
        }
        _ = try await request(method: "initialize", params: .object(params), timeout: timeout)
        initialized = true
    }

    private func sessionPrompt(_ text: String, timeout: TimeInterval) async throws -> String {
        recordUser(text)
        let params: JSONValue = .object([
            "sessionId": .string(sessionId),
            "contentBlocks": .array([
                .object(["type": .string("text"), "text": .string(text)])
            ])
        ])
        let result = try await request(method: "session/prompt", params: params, timeout: timeout)
        return result.string("messageId") ?? UUID().uuidString
    }

    private func request(method: String, params: JSONValue, timeout: TimeInterval) async throws -> JSONValue {
        guard let process else { throw AgentRuntimeError.notRunning }
        requestCounter += 1
        let id = requestCounter
        let payload: JSONValue = .object([
            "jsonrpc": .string("2.0"),
            "id": .number(Double(id)),
            "method": .string(method),
            "params": params
        ])
        if recordsPayloads { onPayloadRecord?("→ \(payload.prettyDescription)") }

        return try await withCheckedThrowingContinuation { continuation in
            pendingLock.lock()
            pending[id] = continuation
            pendingLock.unlock()
            do {
                try process.writeLine(payload)
            } catch {
                failPending(id: id, error: error)
                return
            }
            if timeout.isFinite {
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) { [weak self] in
                    self?.failPending(id: id, error: AgentRuntimeError.failed("`\(method)` timed out."))
                }
            }
        }
    }

    private func complete(id: Int, result: JSONValue?, error: JSONValue?) {
        pendingLock.lock()
        let continuation = pending.removeValue(forKey: id)
        pendingLock.unlock()
        guard let continuation else { return }
        if let error {
            continuation.resume(throwing: AgentRuntimeError.failed(error.string("message") ?? "JSON-RPC error"))
        } else {
            continuation.resume(returning: result ?? .null)
        }
    }

    private func failPending(id: Int, error: Error) {
        pendingLock.lock()
        let continuation = pending.removeValue(forKey: id)
        pendingLock.unlock()
        continuation?.resume(throwing: error)
    }

    private func failAllPending(_ error: Error) {
        pendingLock.lock()
        let continuations = pending.values
        pending.removeAll()
        pendingLock.unlock()
        for continuation in continuations { continuation.resume(throwing: error) }
    }

    // MARK: - Incoming

    private func handle(processEvent: PiProcess.Event, from source: PiProcess) {
        guard process === source else { return }
        switch processEvent {
        case .stdoutRecord(let data):
            guard let json = try? JSONCoding.decode(data) else {
                onProtocolError?("DeepSeek Harness emitted a non-JSON line.")
                return
            }
            if recordsPayloads { onPayloadRecord?("← \(json.prettyDescription)") }
            handle(json: json)
        case .stderrLine(let line):
            onStderr?(line)
        case .exited(let code, let reason):
            process = nil
            initialized = false
            failAllPending(AgentRuntimeError.notRunning)
            onExit?(code, reason)
        case .writeFailed(let message):
            onProtocolError?("Failed to write to DeepSeek Harness: \(message)")
        case .protocolOverflow:
            onProtocolError?("A DeepSeek Harness record exceeded the maximum size.")
        }
    }

    private func handle(json: JSONValue) {
        // A response carries an id and no method; a notification carries a method.
        if let id = json.int("id"), json.string("method") == nil {
            complete(id: id, result: json["result"], error: json["error"])
            return
        }
        guard let method = json.string("method") else { return }
        let params = json.object("params") ?? .null
        switch method {
        case "session.status":
            handleStatus(params)
        case "session.event":
            handleSessionEvent(params)
        default:
            break
        }
    }

    private func handleStatus(_ params: JSONValue) {
        let status = params.string("status") ?? params.string("state")
        switch status {
        case "running":
            if !isRunning {
                isRunning = true
                stateFields.isStreaming = true
                emit(.agentStart)
            }
        case "idle":
            isRunning = false
            stateFields.isStreaming = false
            emit(.agentEnd(messages: messages, willRetry: false))
            emit(.agentSettled)
        default:
            break
        }
    }

    /// `session.event` payloads depend on the harness's session vocabulary. This
    /// extracts committed assistant text defensively: a whole-agent status frame
    /// is the source of truth for liveness, and any text found is appended.
    private func handleSessionEvent(_ params: JSONValue) {
        guard let text = Self.extractAssistantText(params), !text.isEmpty else { return }
        if isRunning == false {
            isRunning = true
            stateFields.isStreaming = true
            emit(.agentStart)
        }
        let route = Self.route(modelOverride)
        emit(.messageStart(AgentWire.assistantMessage(text: "", model: route.model, provider: route.provider)))
        streamText(text)
        let message = AgentWire.assistantMessage(text: text, model: route.model, provider: route.provider)
        messages.append(message)
        emit(.messageEnd(message))
    }

    private static func extractAssistantText(_ value: JSONValue) -> String? {
        for key in ["text", "content", "message", "delta"] {
            if let text = value.string(key), !text.isEmpty { return text }
        }
        if let content = value.object("content") {
            if let text = content.string("text") { return text }
        }
        if let event = value.object("event"), let text = extractAssistantText(event) { return text }
        return nil
    }

    static func route(_ model: String?) -> (provider: String, model: String) {
        guard let model, !model.isEmpty else { return ("deepseek-official", "deepseek-chat") }
        if let slash = model.firstIndex(of: "/") {
            return (String(model[..<slash]), String(model[model.index(after: slash)...]))
        }
        return ("deepseek-official", model)
    }

    static func modelCatalog(_ override: String?) -> [JSONValue] {
        let configured = HarnessProviderCatalog.models(for: .deepseekHarness)
        let (provider, model) = route(override)
        let selectedIsConfigured = HarnessProviderCatalog.providers(for: .deepseekHarness)
            .contains { $0.id == provider && $0.models.contains { $0.id == model } }
        let native = selectedIsConfigured
            ? AgentWire.model(id: "deepseek-chat", name: "DeepSeek Chat", provider: "deepseek-official",
                              reasoning: true, images: false)
            : AgentWire.model(id: model, name: model, provider: provider, reasoning: true, images: false)
        return [native] + configured
    }
}
