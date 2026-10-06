//
//  ClaudeCodeRuntime.swift
//  PiCode
//
//  Drives Claude Code over its stream-json control protocol:
//
//    claude --print --input-format stream-json --output-format stream-json
//           --verbose --include-partial-messages
//
//  One long-lived process handles many turns: a user message is one NDJSON line
//  on stdin, and assistant text, tool calls, tool results, and the final result
//  arrive as NDJSON on stdout.
//

import Foundation

final class ClaudeCodeRuntime: BufferedAgentRuntime {
    private var process: PiProcess?
    private var sessionIdentifier: String?
    private var sawStreamEventsThisTurn = false
    private var assistantText = ""
    private var isTurnActive = false
    private var requestCounter = 0
    private var processProviderID: String?

    private var selectedProviderID: String {
        HarnessProviderCatalog.providerID(for: modelOverride, fallback: "anthropic")
    }

    override func start() throws {
        // A stored session id (Claude ids are UUIDs, not file paths) resumes the
        // prior conversation; otherwise this starts a fresh thread.
        if sessionIdentifier == nil, let sessionFile, !sessionFile.isEmpty {
            sessionIdentifier = sessionFile
        }
        try launchProcess()
    }

    private func launchProcess() throws {
        var arguments = [
            "--print",
            "--input-format", "stream-json",
            "--output-format", "stream-json",
            "--verbose",
            "--include-partial-messages",
            // PiCode's project-trust decision stands in for the interactive
            // permission prompt; headless streams cannot answer one.
            "--permission-mode", "bypassPermissions"
        ]

        if let model = cliModelName, !model.isEmpty {
            arguments.append(contentsOf: ["--model", model])
        }
        if let systemPrompt, !systemPrompt.isEmpty {
            arguments.append(contentsOf: ["--append-system-prompt", systemPrompt])
        }
        if let sessionIdentifier, !sessionIdentifier.isEmpty {
            arguments.append(contentsOf: ["--resume", sessionIdentifier])
        }
        arguments.append(contentsOf: extraArguments)

        var launchEnvironment = environment
        if let provider = HarnessProviderCatalog.provider(for: modelOverride, harness: .claudeCode) {
            if let baseURL = provider.baseURL { launchEnvironment["ANTHROPIC_BASE_URL"] = baseURL }
            if let apiKey = HarnessProviderCatalog.apiKey(provider) {
                launchEnvironment["ANTHROPIC_AUTH_TOKEN"] = apiKey
                launchEnvironment["ANTHROPIC_API_KEY"] = apiKey
            }
        }

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
        processProviderID = selectedProviderID
    }

    override func stop() {
        process?.closeStdin()
        process?.terminate()
        process = nil
        processProviderID = nil
    }

    // MARK: - Commands

    override func send(_ command: RPCCommand, timeout: TimeInterval) async throws -> RPCResponse {
        switch command {
        case .prompt(_, _, _), .steer(_, _), .followUp(_, _):
            try sendUserMessage(promptText(command))
            return response(command)

        case .abort, .abortRetry:
            sendControlRequest(subtype: "interrupt")
            isTurnActive = false
            stateFields.isStreaming = false
            emit(.agentEnd(messages: messages, willRetry: false))
            return response(command)

        case .getAvailableModels:
            return response(command, data: .object(["models": .array(Self.modelCatalog())]))

        case .setModel(let provider, let modelId):
            modelOverride = "\(provider)/\(modelId)"
            stateFields.model = PiModel(id: modelId, provider: provider, name: modelId)
            if processProviderID != provider {
                let previous = process
                process = nil
                previous?.terminate()
                try launchProcess()
            } else {
                sendControlRequest(subtype: "set_model", extra: ["model": .string(modelId)])
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

    private func sendUserMessage(_ text: String) throws {
        guard let process else { throw AgentRuntimeError.notRunning }
        recordUser(text)
        isTurnActive = true
        sawStreamEventsThisTurn = false
        assistantText = ""
        let message: JSONValue = .object([
            "type": .string("user"),
            "message": .object([
                "role": .string("user"),
                "content": .array([.object(["type": .string("text"), "text": .string(text)])])
            ]),
            "parent_tool_use_id": .null,
            "session_id": .string(sessionIdentifier ?? "")
        ])
        try process.writeLine(message)
    }

    private func sendControlRequest(subtype: String, extra: [String: JSONValue] = [:]) {
        requestCounter += 1
        var request: [String: JSONValue] = ["subtype": .string(subtype)]
        for (key, value) in extra { request[key] = value }
        let payload: JSONValue = .object([
            "type": .string("control_request"),
            "request_id": .string("picode-\(requestCounter)"),
            "request": .object(request)
        ])
        try? process?.writeLine(payload)
    }

    // MARK: - Incoming

    private func handle(processEvent: PiProcess.Event, from source: PiProcess) {
        guard process === source else { return }
        switch processEvent {
        case .stdoutRecord(let data):
            guard let json = try? JSONCoding.decode(data) else {
                onProtocolError?("Claude Code emitted a non-JSON line.")
                return
            }
            if recordsPayloads { onPayloadRecord?("← \(json.prettyDescription)") }
            handle(json: json)
        case .stderrLine(let line):
            onStderr?(line)
        case .exited(let code, let reason):
            onExit?(code, reason)
        case .writeFailed(let message):
            onProtocolError?("Failed to write to Claude Code: \(message)")
        case .protocolOverflow:
            onProtocolError?("A Claude Code record exceeded the maximum size.")
        }
    }

    private func handle(json: JSONValue) {
        switch json.string("type") {
        case "system":
            handleSystem(json)
        case "stream_event":
            handleStreamEvent(json.object("event"))
        case "assistant":
            handleAssistant(json)
        case "user":
            handleUser(json)
        case "result":
            handleResult(json)
        case "control_response", "control_request":
            // Permission and lifecycle control traffic; not rendered.
            break
        default:
            break
        }
    }

    private func handleSystem(_ json: JSONValue) {
        if let sessionId = json.string("session_id") {
            sessionIdentifier = sessionId
            stateFields.sessionId = sessionId
            stateFields.sessionFile = sessionId
        }
        if let model = json.string("model") {
            let provider = selectedProviderID
            modelOverride = "\(provider)/\(model)"
            stateFields.model = PiModel(id: model, provider: provider, name: model)
        }
        if json.string("subtype") == "compact_boundary" {
            emit(.compactionStart(reason: "auto"))
            emit(.compactionEnd(reason: "auto", result: nil, aborted: false,
                                errorMessage: nil, willRetry: false))
        }
    }

    private func handleStreamEvent(_ event: JSONValue?) {
        guard let event else { return }
        switch event.string("type") {
        case "message_start":
            sawStreamEventsThisTurn = true
            beginAssistant(model: cliModelName, provider: selectedProviderID)
        case "content_block_delta":
            let delta = event.object("delta")
            switch delta?.string("type") {
            case "text_delta":
                let text = delta?.string("text") ?? ""
                assistantText += text
                streamText(text)
            case "thinking_delta":
                streamThinking(delta?.string("thinking") ?? "")
            default:
                break
            }
        default:
            break
        }
    }

    /// The complete assistant message. Tools and final text are authoritative
    /// here; live text came from the stream events above.
    private func handleAssistant(_ json: JSONValue) {
        let message = json.object("message") ?? .null
        if !sawStreamEventsThisTurn {
            beginAssistant(model: message.string("model") ?? cliModelName, provider: selectedProviderID)
            assistantText = ""
        }
        for block in message.array("content") ?? [] {
            switch block.string("type") {
            case "text":
                let text = block.string("text") ?? ""
                if sawStreamEventsThisTurn, text.hasPrefix(assistantText) {
                    // Already streamed; nothing new to add.
                } else if !sawStreamEventsThisTurn {
                    assistantText += text
                }
            case "tool_use":
                let id = block.string("id") ?? UUID().uuidString
                let name = block.string("name") ?? "tool"
                startTool(id: id, name: name, arguments: block["input"])
            default:
                break
            }
        }
        if !sawStreamEventsThisTurn, !assistantText.isEmpty {
            endAssistant(text: assistantText, model: message.string("model") ?? cliModelName,
                         provider: selectedProviderID)
        } else {
            // Close the streamed assistant message without ending the whole turn:
            // tool calls may follow.
            let complete = AgentWire.assistantMessage(text: assistantText,
                                                      model: cliModelName,
                                                      provider: selectedProviderID)
            messages.append(complete)
            stateFields.messageCount = messages.count
            emit(.messageEnd(complete))
        }
    }

    private func handleUser(_ json: JSONValue) {
        let content = json.object("message")?.array("content") ?? []
        for block in content where block.string("type") == "tool_result" {
            let id = block.string("tool_use_id") ?? ""
            let isError = block.bool("is_error") ?? false
            endTool(id: id, name: "", output: Self.toolResultText(block), isError: isError)
        }
    }

    private func handleResult(_ json: JSONValue) {
        isTurnActive = false
        stateFields.isStreaming = false
        let isError = json.bool("is_error") ?? (json.string("subtype") != "success")
        if let text = json.string("result"), !text.isEmpty, assistantText.isEmpty {
            assistantText = text
        }
        if isError, let text = json.string("result") {
            onStderr?(text)
        }
        emit(.agentEnd(messages: messages, willRetry: false))
        emit(.agentSettled)
    }

    private static func toolResultText(_ block: JSONValue) -> String {
        if let text = block.string("content") { return text }
        let blocks = block.array("content") ?? []
        return blocks.compactMap { $0.string("text") }.joined()
    }

    static func modelCatalog() -> [JSONValue] {
        let native = [
            AgentWire.model(id: "opus", name: "Claude Opus", provider: "anthropic", reasoning: true, images: true),
            AgentWire.model(id: "sonnet", name: "Claude Sonnet", provider: "anthropic", reasoning: true, images: true),
            AgentWire.model(id: "haiku", name: "Claude Haiku", provider: "anthropic", reasoning: false, images: true)
        ]
        return native + HarnessProviderCatalog.models(for: .claudeCode)
    }
}
