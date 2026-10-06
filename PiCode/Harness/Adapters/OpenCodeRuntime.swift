//
//  OpenCodeRuntime.swift
//  PiCode
//
//  Drives OpenCode one turn at a time over `opencode run --format json`.
//  OpenCode owns provider authentication and reads its existing local accounts.
//

import Foundation

final class OpenCodeRuntime: BufferedAgentRuntime, @unchecked Sendable {
    private var process: PiProcess?
    private var sessionIdentifier: String?
    private var turnActive = false
    private var turnMessages: [PiMessage] = []

    override func start() throws {
        if sessionIdentifier == nil { sessionIdentifier = sessionFile }
        guard FileManager.default.isExecutableFile(atPath: installation.executableURL.path) else {
            throw AgentRuntimeError.failed("OpenCode executable not found at \(installation.displayPath).")
        }
    }

    override func stop() {
        process?.terminate()
        process = nil
    }

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
            let models = await availableModels()
            return response(command, data: .object(["models": .array(models)]))
        case .setModel(let provider, let modelId):
            modelOverride = "\(provider)/\(modelId)"
            stateFields.model = PiModel(id: modelId, provider: provider, name: modelId)
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
        turnMessages = []
        turnActive = true
        stateFields.isStreaming = true
        emit(.agentStart)

        var arguments = ["run", "--format", "json", "--auto", "--thinking"]
        if let sessionIdentifier, !sessionIdentifier.isEmpty {
            arguments.append(contentsOf: ["--session", sessionIdentifier])
        }
        if let modelOverride, !modelOverride.isEmpty {
            arguments.append(contentsOf: ["--model", modelOverride])
        }
        if let effort = stateFields.thinkingLevel, !effort.isEmpty {
            arguments.append(contentsOf: ["--variant", effort])
        }
        arguments.append(contentsOf: extraArguments)
        arguments.append(prompt)

        let configuration = PiProcess.Configuration(
            executableURL: installation.executableURL,
            arguments: arguments,
            workingDirectory: URL(fileURLWithPath: projectPath),
            environment: environment
        )
        let process = PiProcess(configuration: configuration)
        process.onEvent = { [weak self, weak process] event in
            guard let process else { return }
            self?.handle(processEvent: event, from: process)
        }
        try process.start()
        self.process = process
    }

    private func handle(processEvent: PiProcess.Event, from source: PiProcess) {
        guard process === source else { return }
        switch processEvent {
        case .stdoutRecord(let data):
            guard let json = try? JSONCoding.decode(data) else { return }
            if recordsPayloads { onPayloadRecord?("← \(json.prettyDescription)") }
            handle(json: json)
        case .stderrLine(let line):
            onStderr?(line)
        case .exited(let code, let reason):
            process = nil
            if turnActive && code != 0 {
                onStderr?("OpenCode exited with status \(code).")
            }
            if turnActive { finishTurn() }
            _ = reason
        case .writeFailed(let message):
            onProtocolError?("Failed to communicate with OpenCode: \(message)")
        case .protocolOverflow:
            onProtocolError?("An OpenCode event exceeded the maximum size.")
        }
    }

    private func handle(json: JSONValue) {
        if let id = json.string("sessionID"), !id.isEmpty {
            sessionIdentifier = id
            stateFields.sessionId = id
            stateFields.sessionFile = id
        }

        let part = json.object("part")
        switch json.string("type") {
        case "text":
            let text = part?.string("text") ?? ""
            guard !text.isEmpty else { return }
            let model = selectedModel
            emit(.messageStart(AgentWire.assistantMessage(text: "", model: model.id,
                                                          provider: model.provider)))
            streamText(text)
            let message = AgentWire.assistantMessage(text: text,
                                                     model: model.id,
                                                     provider: model.provider)
            messages.append(message)
            turnMessages.append(message)
            stateFields.messageCount = messages.count
            emit(.messageEnd(message))

        case "reasoning":
            let text = part?.string("text") ?? ""
            guard !text.isEmpty else { return }
            let message = PiMessage(raw: .object([
                "role": .string("assistant"),
                "content": .array([.object(["type": .string("thinking"), "thinking": .string(text)])])
            ]))
            messages.append(message)
            turnMessages.append(message)
            emit(.messageEnd(message))

        case "tool_use":
            handleTool(part)

        case "step_finish":
            break

        case "error":
            onStderr?(json.object("error")?.string("message") ?? json.string("error") ?? "OpenCode reported an error.")

        default:
            break
        }
    }

    private func handleTool(_ part: JSONValue?) {
        guard let part else { return }
        let state = part.object("state")
        let id = part.string("callID") ?? part.string("id") ?? UUID().uuidString
        let name = part.string("tool") ?? "tool"
        let input = state?.object("input") ?? state?["input"]
        let status = state?.string("status") ?? "completed"
        startTool(id: id, name: name, arguments: input)
        let output = state?.string("output") ?? state?.string("error") ?? status
        endTool(id: id, name: name, output: output, isError: status == "error")
    }

    private func finishTurn() {
        guard turnActive else { return }
        turnActive = false
        stateFields.isStreaming = false
        emit(.agentEnd(messages: turnMessages, willRetry: false))
        emit(.agentSettled)
    }

    private var selectedModel: (provider: String, id: String?) {
        guard let modelOverride, let slash = modelOverride.firstIndex(of: "/") else {
            return ("opencode", nil)
        }
        return (String(modelOverride[..<slash]), String(modelOverride[modelOverride.index(after: slash)...]))
    }

    private func availableModels() async -> [JSONValue] {
        let result = await HarnessDiscoveryService(descriptor: descriptor).run(
            executable: installation.executableURL,
            arguments: ["models"],
            directory: URL(fileURLWithPath: projectPath),
            environment: environment
        )
        var seen = Set<String>()
        var models = result.stdout.split(whereSeparator: \.isNewline).compactMap { line -> JSONValue? in
            let qualified = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !qualified.isEmpty,
                  !qualified.contains(" "),
                  let slash = qualified.firstIndex(of: "/"),
                  seen.insert(qualified).inserted else { return nil }
            let provider = String(qualified[..<slash])
            let id = String(qualified[qualified.index(after: slash)...])
            guard !provider.isEmpty, !id.isEmpty else { return nil }
            return AgentWire.model(id: id, name: id, provider: provider,
                                   reasoning: false, images: false)
        }
        if models.isEmpty, let modelOverride,
           let slash = modelOverride.firstIndex(of: "/") {
            models = [AgentWire.model(
                id: String(modelOverride[modelOverride.index(after: slash)...]),
                name: String(modelOverride[modelOverride.index(after: slash)...]),
                provider: String(modelOverride[..<slash]),
                reasoning: false,
                images: false
            )]
        }
        return models
    }
}
