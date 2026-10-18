//
//  MuseRuntime.swift
//  PiCode
//
//  Drives Muse Code over `muse exec --json`.
//
//  `muse exec` runs one turn per process, so follow-ups reuse the session id
//  with `--session-id`. Each stdout line is one MSP record:
//
//    {"stream":{"kind":"session","id":…},"payload_type":"run.output.delta",
//     "payload":{…}}
//
//  Records PiCode renders: run.lifecycle.started · run.output.delta ·
//  tool.execution.started/terminal · run.terminal.<completed|failed|cancelled>.
//  Everything else (task lifecycle, command acks) is bookkeeping and ignored.
//

import Foundation

final class MuseRuntime: BufferedAgentRuntime, @unchecked Sendable {
    private static let efforts = ["none", "minimal", "low", "medium", "high", "xhigh", "ultra"]
    private static let defaultModelID = "default"

    private var process: PiProcess?
    private var sessionID: String?
    private var turnActive = false
    private var turnStarted = false
    private var messageOpen = false
    private var producedText = false
    private var messageText = ""
    private var openTools: [String: String] = [:]

    override var thinkingLevelNames: [String] { Self.efforts }

    override func start() throws {
        if sessionID == nil { sessionID = sessionFile ?? UUID().uuidString.lowercased() }
        stateFields.sessionId = sessionID
        stateFields.sessionFile = sessionID
        stateFields.thinkingLevel = stateFields.thinkingLevel ?? "high"
        guard FileManager.default.isExecutableFile(atPath: installation.executableURL.path) else {
            throw AgentRuntimeError.failed("Muse Code executable not found at \(installation.displayPath).")
        }
    }

    override func stop() {
        process?.terminate()
        process = nil
    }

    // MARK: - Commands

    override func send(_ command: RPCCommand, timeout: TimeInterval) async throws -> RPCResponse {
        switch command {
        case .prompt(_, _, _), .steer(_, _), .followUp(_, _):
            try runTurn(promptText(command))
            return response(command)

        case .abort, .abortRetry:
            process?.terminate()
            finishTurn()
            return response(command)

        case .getAvailableModels:
            return response(command, data: .object(["models": .array([
                AgentWire.model(id: Self.defaultModelID, name: "Muse default", provider: "meta",
                                reasoning: true, images: true)
            ])]))

        case .setModel(let provider, let modelId):
            modelOverride = "\(provider)/\(modelId)"
            stateFields.model = PiModel(id: modelId, provider: provider, name: modelId, reasoning: true)
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

    private func runTurn(_ prompt: String) throws {
        process?.terminate()
        recordUser(prompt)
        turnActive = true
        turnStarted = false
        messageOpen = false
        producedText = false
        messageText = ""
        openTools = [:]

        var arguments = ["exec", "--json", "--workspace", projectPath]
        if let sessionID { arguments.append(contentsOf: ["--session-id", sessionID]) }
        if let model = cliModelName, !model.isEmpty, model != Self.defaultModelID {
            arguments.append(contentsOf: ["--model", model])
        }
        if let level = stateFields.thinkingLevel, Self.efforts.contains(level) {
            arguments.append(contentsOf: ["--reasoning-effort", level])
        }
        arguments.append(contentsOf: extraArguments)
        // A leading `--` keeps a prompt that starts with `-` from parsing as a flag.
        arguments.append(contentsOf: ["--", prompt])

        let configuration = PiProcess.Configuration(
            executableURL: installation.executableURL,
            arguments: arguments,
            workingDirectory: URL(fileURLWithPath: projectPath),
            environment: environment
        )
        let process = PiProcess(configuration: configuration)
        process.onEvent = { [weak self] event in
            self?.handle(processEvent: event)
        }
        try process.start()
        self.process = process
    }

    // MARK: - Turn lifecycle

    private func beginTurnIfNeeded() {
        guard !turnStarted else { return }
        turnStarted = true
        stateFields.isStreaming = true
        emit(.agentStart)
    }

    private var providerName: String {
        HarnessProviderCatalog.providerID(for: modelOverride, fallback: "meta")
    }

    private func openMessageIfNeeded() {
        guard !messageOpen else { return }
        messageOpen = true
        messageText = ""
        emit(.messageStart(AgentWire.assistantMessage(text: "", model: cliModelName, provider: providerName)))
    }

    private func closeMessage() {
        guard messageOpen else { return }
        messageOpen = false
        let message = AgentWire.assistantMessage(text: messageText, model: cliModelName, provider: providerName)
        messages.append(message)
        stateFields.messageCount = messages.count
        emit(.messageEnd(message))
    }

    private func finishTurn() {
        guard turnActive else { return }
        closeMessage()
        turnActive = false
        turnStarted = false
        stateFields.isStreaming = false
        emit(.agentEnd(messages: messages, willRetry: false))
        emit(.agentSettled)
    }

    // MARK: - Incoming

    private func handle(processEvent: PiProcess.Event) {
        switch processEvent {
        case .stdoutRecord(let data):
            guard let json = try? JSONCoding.decode(data) else { return }
            if recordsPayloads { onPayloadRecord?("← \(json.prettyDescription)") }
            handle(record: json)
        case .stderrLine(let line):
            // Muse prints informational notices (workspace root, etc.) on stderr.
            onStderr?(line)
        case .exited(let code, _):
            process = nil
            if turnActive {
                if code != 0 { onStderr?("Muse Code exited with status \(code).") }
                finishTurn()
            }
        case .writeFailed(let message):
            onProtocolError?("Failed to write to Muse Code: \(message)")
        case .protocolOverflow:
            onProtocolError?("A Muse Code record exceeded the maximum size.")
        }
    }

    private func handle(record: JSONValue) {
        if sessionID == nil || stateFields.sessionId == nil,
           let id = record.object("stream")?.string("id"),
           record.object("stream")?.string("kind") == "session" {
            sessionID = id
            stateFields.sessionId = id
            stateFields.sessionFile = id
        }
        let payload = record.object("payload")
        guard let type = record.string("payload_type") else { return }

        switch type {
        case "run.lifecycle.started":
            beginTurnIfNeeded()

        case "run.output.delta":
            beginTurnIfNeeded()
            guard let text = payload?.string("text"), !text.isEmpty else { return }
            openMessageIfNeeded()
            producedText = true
            messageText += text
            streamText(text)

        case "tool.execution.started":
            beginTurnIfNeeded()
            closeMessage()
            let (id, name) = toolIdentity(payload)
            openTools[id] = name
            startTool(id: id, name: name, arguments: payload?["arguments"] ?? payload?["input"] ?? payload?["args"])

        case "tool.execution.terminal":
            let (id, fallbackName) = toolIdentity(payload)
            let name = openTools.removeValue(forKey: id) ?? fallbackName
            let output = toolOutput(payload)
            endTool(id: id, name: name, output: output, isError: toolFailed(payload))

        default:
            if type.hasPrefix("run.terminal.") { handleTerminal(type: type, payload: payload) }
        }
    }

    private func handleTerminal(type: String, payload: JSONValue?) {
        beginTurnIfNeeded()
        let terminal = payload?.string("terminal") ?? String(type.dropFirst("run.terminal.".count))
        let text = payload?.string("text") ?? ""
        // Some runs report their answer only on the terminal record.
        if terminal == "completed", !producedText, !text.isEmpty {
            openMessageIfNeeded()
            messageText = text
            streamText(text)
        }
        if terminal != "completed" {
            let reason = payload?.string("reason")
            onStderr?("Muse Code run \(terminal)" + (reason.map { ": \($0)" } ?? "."))
        }
        finishTurn()
    }

    // MARK: - Tool record decoding

    private func toolIdentity(_ payload: JSONValue?) -> (id: String, name: String) {
        let id = payload?.string("tool_call_id") ?? payload?.string("call_id")
            ?? payload?.string("execution_id") ?? payload?.string("id") ?? UUID().uuidString
        let name = payload?.string("tool_name") ?? payload?.string("tool")
            ?? payload?.string("name") ?? "tool"
        return (id, name)
    }

    private func toolOutput(_ payload: JSONValue?) -> String {
        for key in ["output", "result", "text", "stdout", "message"] {
            if let text = payload?.string(key), !text.isEmpty { return text }
            if let nested = payload?.object(key) {
                if let text = nested.string("text") ?? nested.string("output") { return text }
            }
        }
        return ""
    }

    private func toolFailed(_ payload: JSONValue?) -> Bool {
        let outcome = (payload?.string("outcome") ?? payload?.string("status")
            ?? payload?.object("terminal")?.string("kind") ?? "").lowercased()
        if ["failure", "failed", "error", "denied", "timed_out", "cancelled"].contains(outcome) { return true }
        return payload?.bool("is_error") ?? false
    }
}
