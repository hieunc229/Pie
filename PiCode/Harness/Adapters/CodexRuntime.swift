//
//  CodexRuntime.swift
//  PiCode
//
//  Drives OpenAI Codex over `codex exec --json`.
//
//  `codex exec` runs one turn per process, so follow-ups resume the thread id the
//  first run reported. Each stdout line is one JSONL event:
//
//    thread.started · turn.started · item.started/updated/completed ·
//    turn.completed · turn.failed · error
//

import Foundation

final class CodexRuntime: BufferedAgentRuntime {
    private var process: PiProcess?
    private var threadId: String?
    private var turnText = ""
    private var turnActive = false
    private var completedTurn = false

    private var selectedProviderID: String {
        HarnessProviderCatalog.providerID(for: modelOverride, fallback: "openai")
    }

    override func start() throws {
        if threadId == nil { threadId = sessionFile }
        // No long-lived process: each turn is its own `codex exec`. Startup only
        // verifies this adapter can run, so the controller can connect.
        guard FileManager.default.isExecutableFile(atPath: installation.executableURL.path) else {
            throw AgentRuntimeError.failed("Codex executable not found at \(installation.displayPath).")
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
            return response(command, data: .object(["models": .array(Self.modelCatalog(modelOverride))]))

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
        if process != nil { process?.terminate() }
        recordUser(prompt)
        turnText = ""
        turnActive = true
        completedTurn = false

        var arguments: [String] = ["exec"]
        var launchEnvironment = environment
        if let provider = HarnessProviderCatalog.provider(for: modelOverride, harness: .codex) {
            arguments.append(contentsOf: CodexProviderService.configurationArguments(for: provider))
            for (key, value) in CodexProviderService.launchEnvironment(for: provider) {
                launchEnvironment[key] = value
            }
        }
        if let threadId {
            arguments.append(contentsOf: ["resume", "--json"])
            if let model = cliModelName, !model.isEmpty {
                arguments.append(contentsOf: ["--model", model])
            }
            arguments.append(contentsOf: [threadId, prompt])
        } else {
            arguments.append(contentsOf: ["--json", "--skip-git-repo-check"])
            if let model = cliModelName, !model.isEmpty {
                arguments.append(contentsOf: ["--model", model])
            }
            arguments.append(prompt)
        }
        arguments.append(contentsOf: extraArguments)

        let configuration = PiProcess.Configuration(
            executableURL: installation.executableURL,
            arguments: arguments,
            workingDirectory: URL(fileURLWithPath: projectPath),
            environment: launchEnvironment
        )
        let process = PiProcess(configuration: configuration)
        process.onEvent = { [weak self] event in
            self?.handle(processEvent: event)
        }
        try process.start()
        self.process = process
    }

    private func finishTurn() {
        turnActive = false
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
            handle(json: json)
        case .stderrLine(let line):
            onStderr?(line)
        case .exited(let code, let reason):
            process = nil
            // A normal per-turn exit is expected; only an abnormal one is an error.
            if !completedTurn, turnActive, code != 0 {
                onStderr?("Codex exited with status \(code).")
                finishTurn()
            }
            _ = reason
        case .writeFailed(let message):
            onProtocolError?("Failed to write to Codex: \(message)")
        case .protocolOverflow:
            onProtocolError?("A Codex record exceeded the maximum size.")
        }
    }

    private func handle(json: JSONValue) {
        switch json.string("type") {
        case "thread.started":
            if let id = json.string("thread_id") {
                threadId = id
                stateFields.sessionId = id
                stateFields.sessionFile = id
            }
        case "turn.started":
            emit(.agentStart)
        case "item.started":
            handleItem(json.object("item"), completed: false)
        case "item.updated":
            handleItem(json.object("item"), completed: false)
        case "item.completed":
            handleItem(json.object("item"), completed: true)
        case "turn.completed":
            applyUsage(json.object("usage"))
            completedTurn = true
            finishTurn()
        case "turn.failed":
            completedTurn = true
            onStderr?(json.object("error")?.string("message") ?? "Codex turn failed.")
            finishTurn()
        case "error":
            onStderr?(json.string("message") ?? "Codex reported an error.")
        default:
            break
        }
    }

    private func handleItem(_ item: JSONValue?, completed: Bool) {
        guard let item else { return }
        let id = item.string("id") ?? UUID().uuidString
        switch item.string("type") {
        case "agent_message":
            guard completed else { return }
            let text = item.string("text") ?? ""
            turnText = text
            emit(.messageStart(AgentWire.assistantMessage(text: "", model: cliModelName,
                                                          provider: selectedProviderID)))
            streamText(text)
            let message = AgentWire.assistantMessage(text: text, model: cliModelName,
                                                     provider: selectedProviderID)
            messages.append(message)
            emit(.messageEnd(message))

        case "reasoning":
            guard completed else { return }
            let text = item.string("text") ?? ""
            let message = PiMessage(raw: .object([
                "role": .string("assistant"),
                "content": .array([.object(["type": .string("thinking"), "thinking": .string(text)])]),
                "model": cliModelName.map(JSONValue.string) ?? .null,
                "provider": .string(selectedProviderID)
            ]))
            messages.append(message)
            emit(.messageEnd(message))

        case "command_execution":
            let command = item.string("command") ?? ""
            if completed {
                let output = item.string("aggregated_output") ?? ""
                let exit = item.int("exit_code") ?? 0
                endTool(id: id, name: "bash", output: output, isError: exit != 0)
            } else {
                startTool(id: id, name: "bash", arguments: .object(["command": .string(command)]))
            }

        case "file_change":
            guard completed else { return }
            startTool(id: id, name: "edit", arguments: item["changes"])
            endTool(id: id, name: "edit", output: item.string("status") ?? "completed", isError: false)

        case "mcp_tool_call":
            let name = item.string("tool") ?? "mcp_tool"
            if completed {
                let output = item.object("result")?.array("content")?.compactMap { $0.string("text") }.joined() ?? ""
                let failed = item.string("status") == "failed"
                endTool(id: id, name: name, output: item.object("error")?.string("message") ?? output, isError: failed)
            } else {
                startTool(id: id, name: name, arguments: item["arguments"])
            }

        case "web_search":
            guard completed else { return }
            startTool(id: id, name: "web_search", arguments: .object(["query": item["query"] ?? .null]))
            endTool(id: id, name: "web_search", output: item.string("query") ?? "", isError: false)

        default:
            break
        }
    }

    private func applyUsage(_ usage: JSONValue?) {
        guard let usage else { return }
        _ = usage.int("input_tokens")
        _ = usage.int("output_tokens")
    }

    static func modelCatalog(_ override: String?) -> [JSONValue] {
        var models = [
            AgentWire.model(id: "gpt-5-codex", name: "GPT-5 Codex", provider: "openai", reasoning: true, images: false),
            AgentWire.model(id: "gpt-5", name: "GPT-5", provider: "openai", reasoning: true, images: true),
            AgentWire.model(id: "o3", name: "o3", provider: "openai", reasoning: true, images: false)
        ]
        models.append(contentsOf: HarnessProviderCatalog.models(for: .codex))
        if let override, !override.isEmpty {
            let provider = HarnessProviderCatalog.providerID(for: override, fallback: "openai")
            let model: String
            if let slash = override.firstIndex(of: "/") {
                model = String(override[override.index(after: slash)...])
            } else {
                model = override
            }
            let isKnown = provider == "openai" || HarnessProviderCatalog.providers(for: .codex)
                .contains { $0.id == provider && $0.models.contains { $0.id == model } }
            if !isKnown {
                models.append(AgentWire.model(id: model, name: model, provider: provider,
                                              reasoning: true, images: false))
            }
        }
        return models
    }
}
