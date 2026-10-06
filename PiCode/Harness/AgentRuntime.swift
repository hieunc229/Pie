//
//  AgentRuntime.swift
//  PiCode
//
//  The seam between a session controller and a coding-agent harness.
//
//  A controller owns exactly one `AgentRuntime`. The runtime owns the child
//  process (or process group) and speaks the harness's wire protocol. The
//  controller only ever sends the app's canonical commands and renders the
//  canonical events, so a new harness is a new adapter rather than a change to
//  the session UI.
//
//  Pi and Oh My Pi implement this directly over their shared RPC transport.
//  Claude Code, Codex, and DeepSeek Harness translate their own protocols into
//  the same command/event surface here.
//

import Foundation

/// One running harness. Not actor-isolated: adapters serialize their own I/O and
/// the controller hops to the main actor before touching UI state.
protocol AgentRuntime: AnyObject, Sendable {
    var descriptor: HarnessDescriptor { get }

    /// Unsolicited events, delivered on a background queue.
    var onEvent: ((PiEvent, JSONValue) -> Void)? { get set }
    /// Process exit.
    var onExit: ((Int32, Process.TerminationReason) -> Void)? { get set }
    /// Diagnostics on stderr. Never protocol data.
    var onStderr: ((String) -> Void)? { get set }
    /// A framing/decoding problem worth surfacing.
    var onProtocolError: ((String) -> Void)? { get set }
    /// A response that could not be matched to a request.
    var onResponseWithoutID: ((RPCResponse) -> Void)? { get set }
    /// Raw payload capture for the diagnostics log. Off by default.
    var onPayloadRecord: ((String) -> Void)? { get set }
    var recordsPayloads: Bool { get set }

    func start() throws
    func stop()
    func send(_ command: RPCCommand, timeout: TimeInterval) async throws -> RPCResponse
    func sendRaw(_ payload: JSONValue)
}

enum AgentRuntimeError: LocalizedError, Equatable {
    case notRunning
    case unsupported(command: String, harness: String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .notRunning:
            return "The agent process is not running."
        case .unsupported(let command, let harness):
            return "\(harness) does not support `\(command)`."
        case .failed(let message):
            return message
        }
    }
}

/// Builds the right runtime for a harness.
enum AgentRuntimeFactory {
    static func make(descriptor: HarnessDescriptor,
                     installation: HarnessInstallation,
                     projectPath: String,
                     sessionFile: String?,
                     systemPrompt: String?,
                     model: String?,
                     trustArguments: [String],
                     extraArguments: [String],
                     environment: [String: String]) -> any AgentRuntime {
        switch descriptor.id {
        case .pi, .ohMyPi:
            let arguments = HarnessLaunch.piFamilyArguments(
                for: descriptor,
                sessionFile: sessionFile,
                systemPrompt: systemPrompt,
                model: model,
                trustArguments: trustArguments,
                extra: extraArguments
            )
            let client = PiRPCClient(
                executableURL: installation.executableURL,
                workingDirectory: URL(fileURLWithPath: projectPath),
                arguments: arguments,
                environment: environment
            )
            client.descriptor = descriptor
            return client
        case .claudeCode:
            return ClaudeCodeRuntime(
                descriptor: descriptor,
                installation: installation,
                projectPath: projectPath,
                sessionFile: sessionFile,
                systemPrompt: systemPrompt,
                model: model,
                extraArguments: extraArguments,
                environment: environment
            )
        case .codex:
            return CodexRuntime(
                descriptor: descriptor,
                installation: installation,
                projectPath: projectPath,
                sessionFile: sessionFile,
                systemPrompt: systemPrompt,
                model: model,
                extraArguments: extraArguments,
                environment: environment
            )
        case .deepseekHarness:
            return DeepSeekRuntime(
                descriptor: descriptor,
                installation: installation,
                projectPath: projectPath,
                sessionFile: sessionFile,
                systemPrompt: systemPrompt,
                model: model,
                extraArguments: extraArguments,
                environment: environment
            )
        case .opencode:
            return OpenCodeRuntime(
                descriptor: descriptor,
                installation: installation,
                projectPath: projectPath,
                sessionFile: sessionFile,
                systemPrompt: systemPrompt,
                model: model,
                extraArguments: extraArguments,
                environment: environment
            )
        }
    }
}

/// Placeholder runtime for harnesses whose adapter is not implemented. It starts
/// nothing and fails every command with a clear reason instead of pretending.
final class UnsupportedRuntime: AgentRuntime, @unchecked Sendable {
    let descriptor: HarnessDescriptor
    private let installation: HarnessInstallation

    var onEvent: ((PiEvent, JSONValue) -> Void)?
    var onExit: ((Int32, Process.TerminationReason) -> Void)?
    var onStderr: ((String) -> Void)?
    var onProtocolError: ((String) -> Void)?
    var onResponseWithoutID: ((RPCResponse) -> Void)?
    var onPayloadRecord: ((String) -> Void)?
    var recordsPayloads = false

    init(descriptor: HarnessDescriptor, installation: HarnessInstallation) {
        self.descriptor = descriptor
        self.installation = installation
    }

    func start() throws {
        throw AgentRuntimeError.unsupported(command: "start", harness: descriptor.displayName)
    }

    func stop() {}

    func send(_ command: RPCCommand, timeout: TimeInterval) async throws -> RPCResponse {
        throw AgentRuntimeError.unsupported(command: command.name, harness: descriptor.displayName)
    }

    func sendRaw(_ payload: JSONValue) {}
}
