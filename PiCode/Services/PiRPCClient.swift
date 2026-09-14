//
//  PiRPCClient.swift
//  PiCode
//
//  Typed request/response + event client over one `pi --mode rpc` process.
//
//  Responsibilities:
//   - correlate command responses by request id,
//   - route unsolicited events independently of responses,
//   - keep stderr out of the protocol path,
//   - redact nothing but never log full payloads unless the user asks.
//

import Foundation

enum PiRPCError: LocalizedError, Equatable {
    case notRunning
    case encodingFailed(String)
    case timeout(command: String)
    case processExited(code: Int32)
    case commandFailed(command: String, message: String)

    var errorDescription: String? {
        switch self {
        case .notRunning:
            return "The Pi process is not running."
        case .encodingFailed(let detail):
            return "Could not encode the RPC command: \(detail)"
        case .timeout(let command):
            return "Pi did not answer `\(command)` in time."
        case .processExited(let code):
            return "Pi exited with status \(code)."
        case .commandFailed(let command, let message):
            return "`\(command)` failed: \(message)"
        }
    }
}

final class PiRPCClient: @unchecked Sendable {
    /// Default timeout for commands that should answer promptly. Long-running
    /// commands (bash, compact, export) opt out with `timeout: .infinity`.
    static let defaultTimeout: TimeInterval = 60

    private let process: PiProcess
    private let lock = NSLock()
    private var pending: [String: CheckedContinuation<RPCResponse, Error>] = [:]
    private var timeouts: [String: DispatchWorkItem] = [:]
    private var isStopped = false
    private var requestCounter = 0

    /// Raw RPC records, for the diagnostics log. Never enabled by default.
    var recordsPayloads = false

    var onEvent: ((PiEvent, JSONValue) -> Void)?
    var onResponseWithoutID: ((RPCResponse) -> Void)?
    var onStderr: ((String) -> Void)?
    var onExit: ((Int32, Process.TerminationReason) -> Void)?
    var onProtocolError: ((String) -> Void)?
    var onPayloadRecord: ((String) -> Void)?

    init(executableURL: URL,
         workingDirectory: URL,
         arguments: [String],
         environment: [String: String]) {
        process = PiProcess(configuration: PiProcess.Configuration(
            executableURL: executableURL,
            arguments: arguments,
            workingDirectory: workingDirectory,
            environment: environment
        ))
    }

    func start() throws {
        process.onEvent = { [weak self] event in
            self?.handleProcessEvent(event)
        }
        try process.start()
    }

    // MARK: - Commands

    func send(_ command: RPCCommand, timeout: TimeInterval = PiRPCClient.defaultTimeout) async throws -> RPCResponse {
        let id = nextRequestID()
        return try await sendAwaitingResponse(command.json(id: id), timeout: timeout)
    }

    /// Sends an already-built request object and waits for the response carrying
    /// the same `id`.
    ///
    /// `send(_:)` is the typed path the app uses. This exists so diagnostics and
    /// `Tools/SmokeTest` can probe the documented wire format directly — useful
    /// because Pi ignores unknown or misspelled fields instead of failing.
    func sendAwaitingResponse(_ payload: JSONValue,
                              timeout: TimeInterval = PiRPCClient.defaultTimeout) async throws -> RPCResponse {
        let id = payload.string("id") ?? nextRequestID()
        let name = payload.string("type") ?? "unknown"
        let data: Data
        do {
            data = try JSONCoding.line(payload)
        } catch {
            throw PiRPCError.encodingFailed(String(describing: error))
        }

        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if isStopped {
                lock.unlock()
                continuation.resume(throwing: PiRPCError.notRunning)
                return
            }
            pending[id] = continuation
            lock.unlock()

            if timeout.isFinite {
                let work = DispatchWorkItem { [weak self] in
                    self?.failPending(id: id, error: .timeout(command: name))
                }
                lock.lock()
                timeouts[id] = work
                lock.unlock()
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: work)
            }

            if recordsPayloads {
                onPayloadRecord?("→ \(payload.prettyDescription)")
            }
            process.write(data)
        }
    }

    /// Fire-and-forget write used for `extension_ui_response` and other messages
    /// that have no response.
    func sendRaw(_ payload: JSONValue) {
        guard let data = try? JSONCoding.line(payload) else {
            onProtocolError?("Could not encode an outgoing RPC message.")
            return
        }
        if recordsPayloads {
            onPayloadRecord?("→ \(payload.prettyDescription)")
        }
        process.write(data)
    }

    func stop() {
        failAllPending(error: .notRunning)
        process.closeStdin()
        process.terminate()
    }

    // MARK: - Incoming

    private func handleProcessEvent(_ event: PiProcess.Event) {
        switch event {
        case .stdoutRecord(let data):
            handleRecord(data)
        case .stderrLine(let line):
            onStderr?(line)
        case .exited(let code, let reason):
            lock.lock()
            isStopped = true
            lock.unlock()
            failAllPending(error: .processExited(code: code))
            onExit?(code, reason)
        case .writeFailed(let message):
            onProtocolError?("Failed to write to Pi: \(message)")
        case .protocolOverflow:
            onProtocolError?("A Pi RPC record exceeded the maximum record size and was discarded.")
        }
    }

    private func handleRecord(_ data: Data) {
        guard let json = try? JSONCoding.decode(data) else {
            let preview = String(data: data.prefix(200), encoding: .utf8) ?? "<binary>"
            onProtocolError?("Could not decode an RPC record: \(preview)")
            return
        }

        if recordsPayloads {
            onPayloadRecord?("← \(json.prettyDescription)")
        }

        if json.string("type") == "response" {
            let response = RPCResponse(json: json)
            if let id = response.id {
                complete(id: id, response: response)
            } else {
                onResponseWithoutID?(response)
            }
            return
        }

        let event = PiEvent(json: json)
        onEvent?(event, json)
    }

    // MARK: - Continuation bookkeeping

    private func complete(id: String, response: RPCResponse) {
        lock.lock()
        let continuation = pending.removeValue(forKey: id)
        let timeout = timeouts.removeValue(forKey: id)
        lock.unlock()
        timeout?.cancel()
        guard let continuation else { return }
        if response.success {
            continuation.resume(returning: response)
        } else {
            continuation.resume(throwing: PiRPCError.commandFailed(
                command: response.command,
                message: response.error ?? "Unknown error"
            ))
        }
    }

    private func failPending(id: String, error: PiRPCError) {
        lock.lock()
        let continuation = pending.removeValue(forKey: id)
        let timeout = timeouts.removeValue(forKey: id)
        lock.unlock()
        timeout?.cancel()
        continuation?.resume(throwing: error)
    }

    private func failAllPending(error: PiRPCError) {
        lock.lock()
        let continuations = pending.values
        let workItems = timeouts.values
        pending.removeAll()
        timeouts.removeAll()
        lock.unlock()
        for item in workItems { item.cancel() }
        for continuation in continuations { continuation.resume(throwing: error) }
    }

    private func nextRequestID() -> String {
        lock.lock()
        requestCounter += 1
        let counter = requestCounter
        lock.unlock()
        return "picode-\(counter)-\(UUID().uuidString.prefix(8))"
    }
}
