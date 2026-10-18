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
    private var assistantOpen = false
    private var streamedText = ""
    private var toolNames: [String: String] = [:]
    /// A resumed chat keeps the id `dsh` saved it under; a new one gets a fresh id.
    private lazy var sessionId = sessionFile ?? "picode-" + UUID().uuidString.lowercased()
    /// Set once a prompt created the session, so a restart (model change) resumes
    /// it instead of failing with "already exists".
    private var sessionCreated = false
    private var needsResume: Bool { sessionFile != nil || sessionCreated }

    override func start() throws {
        // A resumed chat's history was read by `prepare`, off the main actor.
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
        // `cwd` is the session's workspace root. Newer `dsh` builds resolve it
        // unconditionally, so leaving it out fails the handshake with Node's
        // `"paths[0]" argument must be of type string`.
        var params: [String: JSONValue] = [
            "provider": .string(provider),
            "model": .string(model),
            "cwd": .string(projectPath)
        ]
        if let prompt = systemPrompt, !prompt.isEmpty {
            params["systemPrompt"] = .string(prompt)
        }
        _ = try await request(method: "initialize", params: .object(params), timeout: timeout)
        if needsResume {
            // Restores the saved agent state; history is rebuilt from the log.
            _ = try await request(method: "session/resume",
                                  params: .object(["sessionId": .string(sessionId)]),
                                  timeout: timeout)
        }
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
        sessionCreated = true
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
            closeOpenAssistant()
            isRunning = false
            stateFields.isStreaming = false
            emit(.agentEnd(messages: messages, willRetry: false))
            emit(.agentSettled)
        default:
            break
        }
    }

    // MARK: Session events
    //
    // `session.event` carries `{ event: { type, seq, data } }`. The frames that
    // matter here: `assistant/live-chunk` (streamed text and reasoning),
    // `assistant/message` (the finished message), `tool/call` + `tool/result`,
    // and `turn/end` (whose `reason` is an error when the model call failed,
    // e.g. a missing API key). Everything else is bookkeeping.

    private func handleSessionEvent(_ params: JSONValue) {
        guard let event = params.object("event"), let type = event.string("type") else { return }
        let data = event.object("data") ?? .null
        let route = Self.route(modelOverride)
        switch type {
        case "assistant/live-chunk":
            guard let chunk = data.object("chunk"), let kind = chunk.string("type") else { return }
            let index = chunk.int("index") ?? 0
            switch kind {
            case "text-delta":
                openAssistant(route)
                streamedText += chunk.string("text") ?? ""
                streamText(chunk.string("text") ?? "", index: index)
            case "reasoning-delta":
                openAssistant(route)
                streamThinking(chunk.string("text") ?? "", index: index)
            default:
                break
            }
        case "assistant/message":
            let content = data.object("message")?.array("content") ?? []
            let text = content.filter { $0.string("type") == "text" }
                .compactMap { $0.string("text") }.joined()
            let thinking = content.filter { $0.string("type") == "reasoning" }
                .compactMap { $0.string("text") }.joined()
            if !assistantOpen {
                // Nothing streamed (non-streaming model path): show the whole message.
                if text.isEmpty && thinking.isEmpty { return }
                openAssistant(route)
                streamThinking(thinking)
                streamText(text, index: thinking.isEmpty ? 0 : 1)
            }
            finishAssistant(text: text, route)
        case "tool/call":
            closeOpenAssistant()
            let id = data.string("callId") ?? UUID().uuidString
            let args = (data.string("arguments")?.data(using: .utf8)).flatMap { try? JSONCoding.decode($0) }
            toolNames[id] = data.string("name") ?? "tool"
            startTool(id: id, name: toolNames[id] ?? "tool", arguments: args)
        case "tool/result":
            let message = data.object("message")
            let id = message?.object("source")?.string("callId") ?? ""
            let output = (message?.array("content") ?? []).compactMap { $0.string("text") }.joined(separator: "\n")
            endTool(id: id, name: toolNames[id] ?? "tool", output: output,
                    isError: message?.bool("isError") == true)
        case "turn/end":
            if let reason = data.object("reason"), reason.string("kind") == "error" {
                let detail = reason.object("error")?.string("message") ?? "The turn failed."
                openAssistant(route)
                streamText("DeepSeek Harness error: \(detail)")
                finishAssistant(text: "DeepSeek Harness error: \(detail)", route)
                onStderr?(detail)
            }
        default:
            break
        }
    }

    private func openAssistant(_ route: (provider: String, model: String)) {
        guard !assistantOpen else { return }
        if !isRunning {
            isRunning = true
            stateFields.isStreaming = true
            emit(.agentStart)
        }
        assistantOpen = true
        emit(.messageStart(AgentWire.assistantMessage(text: "", model: route.model, provider: route.provider)))
    }

    private func finishAssistant(text: String, _ route: (provider: String, model: String)) {
        let message = AgentWire.assistantMessage(text: text, model: route.model, provider: route.provider)
        messages.append(message)
        stateFields.messageCount = messages.count
        assistantOpen = false
        streamedText = ""
        emit(.messageEnd(message))
    }

    /// A message left open when the turn moves on (tool call, idle) is ended with
    /// whatever has been streamed so it never stays on "Thinking…".
    private func closeOpenAssistant() {
        guard assistantOpen else { return }
        finishAssistant(text: streamedText, Self.route(modelOverride))
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
