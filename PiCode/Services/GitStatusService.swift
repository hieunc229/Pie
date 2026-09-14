//
//  GitStatusService.swift
//  PiCode
//
//  Read-only git inspection for the Changes inspector. PiCode never stages,
//  reverts, or commits: git remains the source of truth for repository state and
//  the agent remains responsible for edits.
//

import Foundation

struct GitStatusService {
    var executable: URL = URL(fileURLWithPath: "/usr/bin/git")
    /// Diff output is truncated for display; the full text stays available
    /// through "Show All".
    var maxDiffBytes = 2 * 1024 * 1024

    // MARK: - Repository state

    func repositoryState(for directory: String) async -> GitRepositoryState {
        guard FileManager.default.fileExists(atPath: directory) else {
            return GitRepositoryState(isRepository: false, error: "Project folder is missing.")
        }

        let inside = await git(["-C", directory, "rev-parse", "--is-inside-work-tree"])
        guard inside.exitCode == 0, inside.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "true" else {
            return GitRepositoryState(isRepository: false)
        }

        async let rootResult = git(["-C", directory, "rev-parse", "--show-toplevel"])
        async let branchResult = git(["-C", directory, "rev-parse", "--abbrev-ref", "HEAD"])
        async let statusResult = git(["-C", directory, "status", "--porcelain=v1", "-z", "--untracked-files=all"])
        async let unstaged = git(["-C", directory, "diff", "--numstat", "-z"])
        async let staged = git(["-C", directory, "diff", "--cached", "--numstat", "-z"])

        let root = await rootResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        var branch = await branchResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let status = await statusResult
        let unstagedStats = Self.parseNumstat(await unstaged.stdout)
        let stagedStats = Self.parseNumstat(await staged.stdout)

        if branch.isEmpty || branch == "HEAD" {
            let short = await git(["-C", directory, "rev-parse", "--short", "HEAD"])
            let sha = short.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            branch = sha.isEmpty ? "(no commits)" : "detached @ \(sha)"
        }

        var changes = Self.parsePorcelain(status.stdout)
        for index in changes.indices {
            let stats = changes[index].isStaged ? stagedStats : unstagedStats
            if let stat = stats[changes[index].path] {
                changes[index].additions = stat.additions
                changes[index].deletions = stat.deletions
            }
        }

        return GitRepositoryState(
            isRepository: true,
            root: root.isEmpty ? directory : root,
            branch: branch,
            changes: changes,
            error: status.exitCode == 0 ? nil : status.stderr.oneLinePreview(limit: 200),
            lastUpdated: Date()
        )
    }

    // MARK: - Diffs

    func diff(directory: String, path: String, staged: Bool) async -> String {
        var arguments = ["-C", directory, "diff", "--no-color"]
        if staged { arguments.append("--cached") }
        arguments.append(contentsOf: ["--", path])
        let result = await git(arguments)
        if result.exitCode != 0, !result.stderr.isEmpty {
            return "Could not read the diff for \(path):\n\(result.stderr)"
        }
        return truncate(result.stdout)
    }

    func fullDiff(directory: String) async -> String {
        async let unstaged = git(["-C", directory, "diff", "--no-color"])
        async let staged = git(["-C", directory, "diff", "--cached", "--no-color"])
        var text = ""
        let stagedText = await staged.stdout
        let unstagedText = await unstaged.stdout
        if !stagedText.isEmpty {
            text += "# Staged\n" + stagedText
        }
        if !unstagedText.isEmpty {
            if !text.isEmpty { text += "\n" }
            text += "# Working tree\n" + unstagedText
        }
        if text.isEmpty {
            let status = await git(["-C", directory, "status", "--porcelain=v1", "--untracked-files=all"])
            let untracked = Self.parsePorcelain(status.stdout).filter { $0.status == .untracked }
            if !untracked.isEmpty {
                text = "Untracked files are not part of the diff view:\n"
                    + untracked.map { "  \($0.path)" }.joined(separator: "\n")
            }
        }
        return truncate(text)
    }

    // MARK: - Parsing

    /// Parses `git status --porcelain=v1 -z` output.
    static func parsePorcelain(_ output: String) -> [GitFileChange] {
        var changes: [GitFileChange] = []
        var tokens = output.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
        if tokens.last?.isEmpty == true { tokens.removeLast() }

        var index = 0
        while index < tokens.count {
            let entry = tokens[index]
            index += 1
            guard entry.count > 3 else { continue }
            let statusField = String(entry.prefix(2))
            let path = String(entry.dropFirst(3))

            var oldPath: String?
            if statusField.contains("R") || statusField.contains("C") {
                if index < tokens.count {
                    oldPath = tokens[index]
                    index += 1
                }
            }

            let indexStatus = statusField.first.map(String.init) ?? " "
            let worktreeStatus = statusField.last.map(String.init) ?? " "
            let isStaged = indexStatus != " " && indexStatus != "?"
            let code = isStaged ? indexStatus : worktreeStatus

            changes.append(GitFileChange(
                path: path,
                oldPath: oldPath,
                status: Self.status(from: code),
                isStaged: isStaged
            ))
        }
        return changes.sorted { $0.path < $1.path }
    }

    /// Parses `git diff --numstat -z` output into `[path: (additions, deletions)]`.
    static func parseNumstat(_ output: String) -> [String: (additions: Int, deletions: Int)] {
        var result: [String: (Int, Int)] = [:]
        var tokens = output.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
        if tokens.last?.isEmpty == true { tokens.removeLast() }

        for token in tokens {
            let parts = token.split(separator: "\t", omittingEmptySubsequences: false)
            guard parts.count >= 3 else { continue }
            let additions = Int(parts[0]) ?? 0
            let deletions = Int(parts[1]) ?? 0
            let path = String(parts[2])
            guard !path.isEmpty else { continue }
            result[path] = (additions, deletions)
        }
        return result
    }

    static func status(from code: String) -> GitFileChange.Status {
        switch code {
        case "M": return .modified
        case "A": return .added
        case "D": return .deleted
        case "R": return .renamed
        case "C": return .copied
        case "?": return .untracked
        case "U": return .conflicted
        case "T": return .typeChanged
        default: return .modified
        }
    }

    private func truncate(_ text: String) -> String {
        guard text.utf8.count > maxDiffBytes else { return text }
        let prefix = text.prefix(maxDiffBytes)
        return prefix + "\n\n[Diff truncated at \(maxDiffBytes / 1024) KB. Use Open in Editor for the full file.]"
    }

    // MARK: - Process

    private func git(_ arguments: [String]) async -> PiDiscoveryService.CommandResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = self.executable
                process.arguments = arguments
                process.standardInput = FileHandle.nullDevice
                let out = Pipe()
                let err = Pipe()
                process.standardOutput = out
                process.standardError = err

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: PiDiscoveryService.CommandResult(
                        stdout: "",
                        stderr: error.localizedDescription,
                        exitCode: -1
                    ))
                    return
                }

                let outData = (try? out.fileHandleForReading.readToEnd()) ?? Data()
                let errData = (try? err.fileHandleForReading.readToEnd()) ?? Data()
                process.waitUntilExit()
                continuation.resume(returning: PiDiscoveryService.CommandResult(
                    stdout: String(data: outData, encoding: .utf8) ?? "",
                    stderr: String(data: errData, encoding: .utf8) ?? "",
                    exitCode: process.terminationStatus
                ))
            }
        }
    }
}
