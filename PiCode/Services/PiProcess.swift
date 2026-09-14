//
//  PiProcess.swift
//  PiCode
//
//  Owns one child `pi --mode rpc` process: stdin/stdout/stderr pipes, strict
//  JSONL framing of stdout, stderr diagnostics, and exit reporting.
//
//  The pi executable is launched directly (never through `sh -c`) so the process
//  tree and signals stay predictable.
//

import Foundation

final class PiProcess: @unchecked Sendable {
    struct Configuration {
        var executableURL: URL
        var arguments: [String]
        var workingDirectory: URL
        /// Extra environment merged over the inherited environment. Used to
        /// forward the login-shell PATH so `pi` can find `node`.
        var environment: [String: String] = [:]
        /// Fail loudly if the process emits a record bigger than this. Defaults
        /// to the JSONL decoder's guard.
        var maxRecordBytes: Int = JSONLDecoder.maxRecordBytes
    }

    enum Event: Sendable {
        case stdoutRecord(Data)
        case stderrLine(String)
        case exited(code: Int32, reason: Process.TerminationReason)
        case writeFailed(message: String)
        case protocolOverflow
    }

    /// Delivered on `callbackQueue` (a private serial queue), never on the main
    /// thread. Owners hop to the main actor themselves.
    var onEvent: ((Event) -> Void)?

    private let configuration: Configuration
    private let callbackQueue = DispatchQueue(label: "dev.picode.pi-process.callbacks")
    private let writeQueue = DispatchQueue(label: "dev.picode.pi-process.stdin")

    private let process = Process()
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()

    private var stdoutDecoder = JSONLDecoder()
    private var stderrAccumulator = LineAccumulator()
    private var stdinClosed = false
    private var finished = false
    private let stateLock = NSLock()

    private(set) var isRunning = false

    init(configuration: Configuration) {
        self.configuration = configuration
    }

    var processIdentifier: Int32 { process.processIdentifier }

    /// Launches the process. Throws when the executable cannot be started.
    func start() throws {
        process.executableURL = configuration.executableURL
        process.arguments = configuration.arguments
        process.currentDirectoryURL = configuration.workingDirectory

        var environment = ProcessInfo.processInfo.environment
        for (key, value) in configuration.environment {
            environment[key] = value
        }
        // Keep Pi's own output stable and avoid interactive-only behavior.
        environment["TERM"] = environment["TERM"] ?? "dumb"
        environment["NO_COLOR"] = environment["NO_COLOR"] ?? "1"
        process.environment = environment

        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self else { return }
            if data.isEmpty {
                self.handleStdoutEOF()
                return
            }
            self.stateLock.lock()
            let records = self.stdoutDecoder.append(data)
            let overflowed = self.stdoutDecoder.consumeOverflowFlag()
            self.stateLock.unlock()
            var events = records.map { Event.stdoutRecord($0) }
            if overflowed { events.append(.protocolOverflow) }
            self.emit(events)
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self else { return }
            if data.isEmpty {
                self.stderrPipe.fileHandleForReading.readabilityHandler = nil
                return
            }
            self.stateLock.lock()
            let lines = self.stderrAccumulator.append(data)
            self.stateLock.unlock()
            self.emit(lines.map { .stderrLine($0) })
        }

        process.terminationHandler = { [weak self] process in
            guard let self else { return }
            self.stdoutPipe.fileHandleForReading.readabilityHandler = nil
            self.stderrPipe.fileHandleForReading.readabilityHandler = nil
            self.stateLock.lock()
            let remaining = self.stdoutDecoder.flush()
            let trailing = self.stderrAccumulator.flush()
            self.finished = true
            self.isRunning = false
            self.stateLock.unlock()
            var events: [Event] = []
            if let remaining, !remaining.isEmpty { events.append(.stdoutRecord(remaining)) }
            events.append(contentsOf: trailing.map { .stderrLine($0) })
            events.append(.exited(code: process.terminationStatus, reason: process.terminationReason))
            self.emit(events)
        }

        try process.run()
        isRunning = true
    }

    /// Serializes one JSONL record to stdin. All writes funnel through a single
    /// serial queue so records cannot interleave.
    func write(_ data: Data) {
        stateLock.lock()
        let closed = stdinClosed || finished
        stateLock.unlock()
        guard !closed else { return }

        writeQueue.async { [weak self] in
            guard let self else { return }
            do {
                try self.stdinPipe.fileHandleForWriting.write(contentsOf: data)
            } catch {
                self.emit([.writeFailed(message: error.localizedDescription)])
            }
        }
    }

    func writeLine(_ value: JSONValue) throws {
        write(try JSONCoding.line(value))
    }

    /// Closes stdin, which asks Pi to exit cleanly.
    func closeStdin() {
        stateLock.lock()
        let alreadyClosed = stdinClosed
        stdinClosed = true
        stateLock.unlock()
        guard !alreadyClosed else { return }
        writeQueue.async { [weak self] in
            guard let self else { return }
            try? self.stdinPipe.fileHandleForWriting.close()
        }
    }

    /// Terminates the child process, escalating to SIGKILL if it does not exit.
    func terminate(gracePeriod: TimeInterval = 4) {
        stateLock.lock()
        let alreadyFinished = finished
        stateLock.unlock()
        guard !alreadyFinished, process.isRunning else { return }

        process.terminate()
        let pid = process.processIdentifier
        callbackQueue.asyncAfter(deadline: .now() + gracePeriod) { [weak self] in
            guard let self else { return }
            self.stateLock.lock()
            let done = self.finished
            self.stateLock.unlock()
            if !done, self.process.isRunning {
                kill(pid, SIGKILL)
            }
        }
    }

    private func handleStdoutEOF() {
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stateLock.lock()
        let remaining = stdoutDecoder.flush()
        stateLock.unlock()
        if let remaining, !remaining.isEmpty {
            emit([.stdoutRecord(remaining)])
        }
    }

    private func emit(_ events: [Event]) {
        guard !events.isEmpty, let onEvent else { return }
        callbackQueue.async {
            for event in events { onEvent(event) }
        }
    }
}
