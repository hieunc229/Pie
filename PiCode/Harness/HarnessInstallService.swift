//
//  HarnessInstallService.swift
//  PiCode
//
//  Runs a harness's install command through the user's login shell and streams
//  its output so the Settings window can show what happened. Installation is
//  always an explicit, user-initiated action; nothing here runs on its own.
//

import Foundation
import Observation

@Observable
@MainActor
final class HarnessInstallService {
    struct Run: Identifiable {
        let id = UUID()
        var harnessID: HarnessID
        var methodLabel: String
        var command: String
        var output: String = ""
        var isRunning = true
        var exitCode: Int32?
        var startedAt = Date()

        var succeeded: Bool { exitCode == 0 }
    }

    /// The most recent (or in-flight) install per harness.
    private(set) var runs: [HarnessID: Run] = [:]
    private var processes: [HarnessID: Process] = [:]

    func run(for id: HarnessID) -> Run? { runs[id] }

    func isInstalling(_ id: HarnessID) -> Bool { runs[id]?.isRunning == true }

    /// Appends one line to the run's visible log, capped so a chatty installer
    /// cannot grow memory without bound.
    private func append(_ line: String, to id: HarnessID) {
        guard var run = runs[id] else { return }
        run.output += line + "\n"
        if run.output.count > 200_000 {
            run.output = String(run.output.suffix(160_000))
        }
        runs[id] = run
    }

    @discardableResult
    func install(_ descriptor: HarnessDescriptor, using method: HarnessInstallMethod) async -> Bool {
        guard !isInstalling(descriptor.id) else { return false }

        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        runs[descriptor.id] = Run(
            harnessID: descriptor.id,
            methodLabel: method.label,
            command: method.command
        )
        append("$ \(method.command)", to: descriptor.id)
        append("Running in \(shell)…", to: descriptor.id)

        let plan = HarnessInstallEnvironment.plan(for: method)
        for note in plan.notes {
            append(note, to: descriptor.id)
        }

        let exitCode = await runInstall(
            harnessID: descriptor.id,
            script: plan.script,
            shell: shell,
            workingDirectory: URL(fileURLWithPath: NSHomeDirectory()),
            onLine: { [weak self] line in
                guard let self else { return }
                Task { @MainActor in self.append(line, to: descriptor.id) }
            }
        )

        if var run = runs[descriptor.id] {
            run.isRunning = false
            run.exitCode = exitCode
            runs[descriptor.id] = run
        }
        processes[descriptor.id] = nil
        append(exitCode == 0 ? "✓ Finished." : "✗ Exited with status \(exitCode).", to: descriptor.id)
        return exitCode == 0
    }

    func cancel(_ id: HarnessID) {
        guard let process = processes[id], process.isRunning else { return }
        append("Cancelling…", to: id)
        process.terminate()
    }

    func clear(_ id: HarnessID) {
        guard isInstalling(id) == false else { return }
        runs[id] = nil
    }

    // MARK: - Process plumbing

    /// Runs `loginShell -lc <script>`, merging stdout and stderr into lines.
    /// The login shell is what makes `npm`/`bun`/`brew` resolve the same way they
    /// do in the user's terminal.
    private func runInstall(harnessID: HarnessID,
                            script: String,
                            shell: String,
                            workingDirectory: URL,
                            onLine: @escaping @Sendable (String) -> Void) async -> Int32 {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: shell)
            process.arguments = ["-lc", script]
            process.currentDirectoryURL = workingDirectory
            process.environment = ProcessInfo.processInfo.environment

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            process.standardInput = FileHandle.nullDevice

            var buffer = Data()
            let lock = NSLock()

            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                lock.lock()
                buffer.append(data)
                var lines: [String] = []
                while let range = buffer.range(of: Data([0x0A])) {
                    let lineData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
                    buffer.removeSubrange(buffer.startIndex...range.lowerBound)
                    if let line = String(data: lineData, encoding: .utf8) {
                        lines.append(line)
                    }
                }
                lock.unlock()
                for line in lines { onLine(line) }
            }

            process.terminationHandler = { process in
                pipe.fileHandleForReading.readabilityHandler = nil
                lock.lock()
                let remaining = buffer
                buffer.removeAll()
                lock.unlock()
                if !remaining.isEmpty, let line = String(data: remaining, encoding: .utf8) {
                    onLine(line)
                }
                continuation.resume(returning: process.terminationStatus)
            }

            do {
                self.processes[harnessID] = process
                try process.run()
            } catch {
                onLine("Could not start installer: \(error.localizedDescription)")
                continuation.resume(returning: -1)
            }
        }
    }
}
