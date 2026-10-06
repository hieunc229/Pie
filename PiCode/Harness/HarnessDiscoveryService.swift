//
//  HarnessDiscoveryService.swift
//  PiCode
//
//  Resolves an installed harness executable and its login-shell PATH.
//
//  A harness may be installed through npm, bun, pnpm, Homebrew, or a version
//  manager, so the authoritative answer comes from the user's login shell.
//  PiCode never installs silently; when a harness is missing it reports what it
//  searched and how to add it.
//

import Foundation

enum HarnessDiscoveryResult: Equatable {
    case found(HarnessInstallation)
    case missing(searched: [String], detail: String?)
}

struct HarnessDiscoveryService {
    let descriptor: HarnessDescriptor
    var timeout: TimeInterval = 20

    /// PATH used to launch a harness: the login-shell PATH with the executable's
    /// own directory first, so the Node/Bun runtime it was installed with wins.
    static func launchEnvironment(executable: URL, shellPath: String?) -> [String: String] {
        let fallback = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
        let directory = executable.deletingLastPathComponent().path
        let runtimeDirectory = HarnessInstallEnvironment.preferredNodeBinDirectory()
        let entries = (shellPath ?? fallback)
            .split(separator: ":")
            .map(String.init)
            .filter { !$0.isEmpty && $0 != directory && $0 != runtimeDirectory }
        let path = ([directory] + [runtimeDirectory].compactMap { $0 } + entries)
            .joined(separator: ":")
        return ["PATH": path]
    }

    func discover() async -> HarnessDiscoveryResult {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let shellPath = await loginShellPath(shell: shell)

        var searched: [String] = []
        var detail: String?

        if let located = await loginShellWhich(binary: descriptor.binaryName, shell: shell) {
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
            detail = "The login shell did not report a `\(descriptor.binaryName)` executable."
        }

        for candidate in fallbackCandidates(shellPath: shellPath) {
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

        return .missing(searched: searched, detail: detail)
    }

    /// Verifies `--version` runs before handing the path to a runtime adapter.
    private func makeInstallation(path: String,
                                  shellPath: String?,
                                  shell: String,
                                  origin: String) async -> HarnessInstallation? {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.isExecutableFile(atPath: path) else { return nil }
        // A name collision is common for short binaries such as `pi`.  Do not
        // accept an executable merely because it exists: a stale Python `pi`
        // launcher, for example, can be executable while failing immediately at
        // import time.  Keep scanning until a candidate answers `--version`.
        guard let version = await version(at: url, shellPath: shellPath) else { return nil }
        return HarnessInstallation(
            harnessID: descriptor.id,
            executableURL: url,
            version: version.trimmingCharacters(in: .whitespacesAndNewlines),
            shellPath: shellPath,
            shell: shell,
            origin: origin
        )
    }

    func version(at executable: URL, shellPath: String?) async -> String? {
        guard !descriptor.versionArguments.isEmpty else { return nil }
        let result = await run(
            executable: executable,
            arguments: descriptor.versionArguments,
            directory: URL(fileURLWithPath: NSHomeDirectory()),
            environment: Self.launchEnvironment(executable: executable, shellPath: shellPath)
        )
        guard result.exitCode == 0 else { return nil }
        let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return output.isEmpty ? nil : output
    }

    // MARK: - Shell probing

    private func loginShellWhich(binary: String, shell: String) async -> String? {
        let result = await run(
            executable: URL(fileURLWithPath: shell),
            arguments: ["-lc", "command -v \(binary)"],
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

    /// GUI apps often start before a version manager or package manager has
    /// amended PATH. Search their user-owned bin directories as well as every
    /// directory the login shell reported, so a later `bun install -g` (for
    /// example) is visible without relaunching PiCode.
    private func fallbackCandidates(shellPath: String?) -> [String] {
        let home = NSHomeDirectory()
        let userBinDirectories = [
            "\(home)/.bun/bin",
            "\(home)/.local/bin",
            "\(home)/.npm-global/bin",
            "\(home)/.volta/bin",
            "\(home)/.yarn/bin",
            "\(home)/.config/yarn/global/node_modules/.bin",
            "\(home)/Library/pnpm"
        ]
        let shellBinDirectories = (shellPath ?? "")
            .split(separator: ":")
            .map(String.init)
        let discovered = (userBinDirectories + shellBinDirectories)
            .map { URL(fileURLWithPath: $0).appendingPathComponent(descriptor.binaryName).path }
        return (descriptor.fallbackBinaries + discovered + nvmCandidates())
            .reduce(into: []) { paths, path in
                if !paths.contains(path) { paths.append(path) }
            }
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
            .map { $0.appendingPathComponent("bin/\(descriptor.binaryName)").path }
    }

    // MARK: - Direct process execution

    struct CommandResult {
        var stdout: String
        var stderr: String
        var exitCode: Int32
    }

    /// Runs a short-lived helper process. Never used for a harness itself.
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
