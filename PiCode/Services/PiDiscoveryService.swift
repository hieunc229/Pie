//
//  PiDiscoveryService.swift
//  PiCode
//
//  Resolves the user's installed `pi` executable and its login-shell PATH.
//
//  Pi may be installed through npm, bun, Homebrew, or a version manager, so the
//  authoritative answer comes from the user's login shell. PiCode never installs
//  or modifies Pi; it only reports what it found and how to install Pi when it is
//  missing.
//

import Foundation

struct PiInstallation: Equatable {
    var executableURL: URL
    var version: String
    /// PATH from the login shell, forwarded to the child process so `pi` can
    /// resolve `node` and other runtime dependencies.
    var shellPath: String?
    var shell: String?
    /// How the executable was located, for diagnostics.
    var origin: String

    var displayPath: String { executableURL.path.abbreviatingHomeDirectory }
}

enum PiDiscoveryResult: Equatable {
    case found(PiInstallation)
    case missing(searched: [String], shellPath: String?, detail: String?)
}

struct PiDiscoveryService {
    /// PATH used to launch Pi: the login-shell PATH with the executable's own
    /// directory first.
    ///
    /// Pi ships as a Node script. If the user's PATH resolves `node` to an older
    /// Node than Pi supports, launching `pi` fails even though the path is
    /// correct — so the directory holding the chosen `pi` wins, because that is
    /// where its matching Node lives. Nothing outside the child's environment is
    /// changed.
    static func launchEnvironment(executable: URL, shellPath: String?) -> [String: String] {
        let fallback = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
        let directory = executable.deletingLastPathComponent().path
        let entries = (shellPath ?? fallback)
            .split(separator: ":")
            .map(String.init)
            .filter { !$0.isEmpty && $0 != directory }
        let path = ([directory] + entries).joined(separator: ":")
        return ["PATH": path]
    }

    /// Candidates used when the login shell cannot answer.
    static var fallbackCandidates: [String] {
        let home = NSHomeDirectory()
        return [
            "/opt/homebrew/bin/pi",
            "/usr/local/bin/pi",
            "\(home)/.bun/bin/pi",
            "\(home)/.local/bin/pi",
            "\(home)/.npm-global/bin/pi",
            "\(home)/.volta/bin/pi",
            "/usr/bin/pi"
        ]
    }

    var timeout: TimeInterval = 20

    func discover() async -> PiDiscoveryResult {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let shellPath = await loginShellPath(shell: shell)

        var searched: [String] = []
        var detail: String?

        if let located = await loginShellWhich(shell: shell) {
            searched.append(located)
            if let installation = await makeInstallation(
                path: located,
                shellPath: shellPath,
                shell: shell,
                origin: "login shell"
            ) {
                return .found(installation)
            }
            detail = "The login shell reported \(located) but it could not be executed."
        } else {
            detail = "The login shell did not report a `pi` executable."
        }

        for candidate in Self.fallbackCandidates + nvmCandidates() {
            guard !searched.contains(candidate) else { continue }
            searched.append(candidate)
            guard FileManager.default.isExecutableFile(atPath: candidate) else { continue }
            if let installation = await makeInstallation(
                path: candidate,
                shellPath: shellPath,
                shell: shell,
                origin: "fallback scan"
            ) {
                return .found(installation)
            }
        }

        return .missing(searched: searched, shellPath: shellPath, detail: detail)
    }

    /// Verifies `pi --version` runs before handing the path to the RPC client.
    private func makeInstallation(path: String,
                                  shellPath: String?,
                                  shell: String,
                                  origin: String) async -> PiInstallation? {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.isExecutableFile(atPath: path) else { return nil }
        guard let version = await version(at: url, shellPath: shellPath) else { return nil }
        return PiInstallation(
            executableURL: url,
            version: version.trimmingCharacters(in: .whitespacesAndNewlines),
            shellPath: shellPath,
            shell: shell,
            origin: origin
        )
    }

    func version(at executable: URL, shellPath: String?) async -> String? {
        let result = await run(
            executable: executable,
            arguments: ["--version"],
            directory: URL(fileURLWithPath: NSHomeDirectory()),
            environment: Self.launchEnvironment(executable: executable, shellPath: shellPath)
        )
        guard result.exitCode == 0 else { return nil }
        let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return output.isEmpty ? nil : output
    }

    // MARK: - Shell probing

    private func loginShellWhich(shell: String) async -> String? {
        let result = await run(
            executable: URL(fileURLWithPath: shell),
            arguments: ["-lc", "command -v pi"],
            directory: URL(fileURLWithPath: NSHomeDirectory()),
            environment: nil
        )
        guard result.exitCode == 0 else { return nil }
        let path = result.stdout
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty }
        guard let path, path.hasPrefix("/") else { return nil }
        return path
    }

    private func loginShellPath(shell: String) async -> String? {
        let result = await run(
            executable: URL(fileURLWithPath: shell),
            arguments: ["-lc", "printf %s \"$PATH\""],
            directory: URL(fileURLWithPath: NSHomeDirectory()),
            environment: nil
        )
        guard result.exitCode == 0 else { return nil }
        let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    private func nvmCandidates() -> [String] {
        let root = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".nvm/versions/node")
        guard let versions = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        ) else { return [] }
        return versions
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .map { $0.appendingPathComponent("bin/pi").path }
    }

    // MARK: - Direct process execution

    struct CommandResult {
        var stdout: String
        var stderr: String
        var exitCode: Int32
    }

    /// Runs a short-lived helper process. Never used for `pi` itself.
    func run(executable: URL,
             arguments: [String],
             directory: URL,
             environment: [String: String]?) async -> CommandResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = executable
                process.arguments = arguments
                process.currentDirectoryURL = directory
                if let environment {
                    var merged = ProcessInfo.processInfo.environment
                    for (key, value) in environment { merged[key] = value }
                    process.environment = merged
                }

                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe
                process.standardInput = FileHandle.nullDevice

                var stdout = Data()
                var stderr = Data()
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global(qos: .utility).async {
                    stdout = (try? outPipe.fileHandleForReading.readToEnd()) ?? Data()
                    group.leave()
                }
                group.enter()
                DispatchQueue.global(qos: .utility).async {
                    stderr = (try? errPipe.fileHandleForReading.readToEnd()) ?? Data()
                    group.leave()
                }

                var exitCode: Int32 = -1
                do {
                    try process.run()
                    process.waitUntilExit()
                    exitCode = process.terminationStatus
                } catch {
                    stderr.append(Data(error.localizedDescription.utf8))
                }
                _ = group.wait(timeout: .now() + 5)

                continuation.resume(returning: CommandResult(
                    stdout: String(data: stdout, encoding: .utf8) ?? "",
                    stderr: String(data: stderr, encoding: .utf8) ?? "",
                    exitCode: exitCode
                ))
            }
        }
    }
}
