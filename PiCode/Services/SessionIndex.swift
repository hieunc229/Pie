//
//  SessionIndex.swift
//  PiCode
//
//  Read-only index of Pi's session files. Pi owns session storage; PiCode only
//  discovers, groups, and searches metadata so the sidebar can render quickly.
//
//  Files are never modified here. Deleting a session file is a separate,
//  explicitly confirmed action.
//

import Foundation

/// Well-known locations under Pi's agent directory. Credentials live here and
/// are read only to detect whether authentication exists; secrets are never
/// copied into PiCode storage or logs.
///
/// Pi can be relocated, so these paths **must** resolve the way Pi's own
/// `config.js` resolves them (`getAgentDir`, `getSessionsDir`):
///
/// 1. `PI_CODING_AGENT_DIR` (tilde-expanded) replaces `~/.pi/agent`.
/// 2. The session directory is `PI_CODING_AGENT_SESSION_DIR`, else Pi's own
///    `settings.json` `sessionDir`, else `<agent>/sessions`.
///
/// Getting this wrong is not cosmetic: PiCode writes trust decisions into
/// `trust.json`, so if Pi reads a different file the user's answer is silently
/// ignored while PiCode claims the project is trusted. PiCode also launches `pi`
/// with the inherited environment, so these variables apply to the child too.
enum PiPaths {
    static var home: URL { URL(fileURLWithPath: NSHomeDirectory()) }

    static var agentDirectory: URL {
        if let override = directory(fromEnvironment: "PI_CODING_AGENT_DIR") { return override }
        return home.appendingPathComponent(".pi/agent")
    }

    static var sessionsDirectory: URL {
        if let override = directory(fromEnvironment: "PI_CODING_AGENT_SESSION_DIR") { return override }
        if let configured = configuredSessionDirectory { return configured }
        return agentDirectory.appendingPathComponent("sessions")
    }

    static var settingsFile: URL { agentDirectory.appendingPathComponent("settings.json") }
    static var trustFile: URL { agentDirectory.appendingPathComponent("trust.json") }
    static var authFile: URL { agentDirectory.appendingPathComponent("auth.json") }
    static var modelsFile: URL { agentDirectory.appendingPathComponent("models.json") }
    /// Pi's cache of provider model lists. Read-only for PiCode.
    static var modelsStoreFile: URL { agentDirectory.appendingPathComponent("models-store.json") }

    /// `sessionDir` from Pi's `settings.json`, if the user set one. PiCode only
    /// reads this file, never writes it. Relative paths are ignored: Pi resolves
    /// them against the working directory, which changes per project, so PiCode
    /// cannot know which directory they mean.
    private static let configuredSessionDirectory: URL? = {
        guard let data = try? Data(contentsOf: settingsFile),
              let root = try? JSONCoding.decode(data),
              let raw = root["sessionDir"]?.stringValue
        else { return nil }
        return directory(fromUserPath: raw)
    }()

    /// Expands an environment override the way Pi does: `~`, `$HOME`, `file://`
    /// and absolute paths are understood; anything else is rejected rather than
    /// guessed at.
    private static func directory(fromEnvironment key: String) -> URL? {
        guard let raw = ProcessInfo.processInfo.environment[key], !raw.isEmpty else { return nil }
        return directory(fromUserPath: raw)
    }

    private static func directory(fromUserPath raw: String) -> URL? {
        var path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }
        if path.hasPrefix("file://"), let url = URL(string: path) { return url.standardizedFileURL }
        path = (path as NSString).expandingTildeInPath
        guard path.isAbsolutePath else { return nil }
        return URL(fileURLWithPath: path).standardizedFileURL
    }
}

/// Reads Pi's session directory. This type is safe to use off the main actor:
/// it holds only byte limits set at construction time and a `FileManager`,
/// which is itself thread-safe.
struct SessionIndex: @unchecked Sendable {
    /// Bytes read from the head of a session file when scanning.
    var headBytes = 512 * 1024
    /// Bytes read from the tail, which is where the newest name/activity lives.
    var tailBytes = 128 * 1024

    private let fileManager = FileManager.default

    // MARK: - Directory discovery

    func sessionDirectories() -> [URL] {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: PiPaths.sessionsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return contents.filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
    }

    func sessionFileURLs() -> [URL] {
        var files: [URL] = []
        for directory in sessionDirectories() {
            guard let entries = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            files.append(contentsOf: entries.filter { $0.pathExtension == "jsonl" })
        }
        return files
    }

    // MARK: - Loading

    /// Loads every session and groups it by canonical working directory.
    func loadAllProjects() async -> [ProjectGroup] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let refs = self.loadAllSessions()
                continuation.resume(returning: self.group(refs))
            }
        }
    }

    func loadSessions(in directory: URL) async -> [SessionRef] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let entries = try? self.fileManager.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: [.contentModificationDateKey],
                    options: [.skipsHiddenFiles]
                ) else {
                    continuation.resume(returning: [])
                    return
                }
                let refs = entries
                    .filter { $0.pathExtension == "jsonl" }
                    .compactMap { self.parse(fileURL: $0) }
                    .sorted { $0.updatedAt > $1.updatedAt }
                continuation.resume(returning: refs)
            }
        }
    }

    func loadAllSessions() -> [SessionRef] {
        sessionFileURLs()
            .compactMap { parse(fileURL: $0) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func group(_ refs: [SessionRef]) -> [ProjectGroup] {
        var byPath: [String: [SessionRef]] = [:]
        for ref in refs {
            let canonical = CanonicalPath.of(ref.cwd)
            byPath[canonical, default: []].append(ref)
        }
        return byPath.map { path, sessions in
            ProjectGroup(
                id: path,
                path: path,
                name: URL(fileURLWithPath: path).lastPathComponent,
                sessions: sessions.sorted { $0.updatedAt > $1.updatedAt }
            )
        }
        .sorted { $0.mostRecentActivity > $1.mostRecentActivity }
    }

    // MARK: - Single file parsing

    /// Parses only the metadata the sidebar needs. The full transcript is always
    /// loaded from Pi over RPC, never from the file.
    func parse(fileURL: URL) -> SessionRef? {
        let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path)
        let modified = (attributes?[.modificationDate] as? Date) ?? Date.distantPast
        let size = (attributes?[.size] as? NSNumber)?.intValue ?? 0

        let head = read(url: fileURL, from: 0, length: min(size, headBytes))
        guard !head.isEmpty else { return nil }

        let lines = head.split(separator: UInt8(0x0A), omittingEmptySubsequences: true)
        var tailLines: [Data.SubSequence] = []
        if size > headBytes + tailBytes {
            let tail = read(url: fileURL, from: size - tailBytes, length: tailBytes)
            tailLines = tail.split(separator: UInt8(0x0A), omittingEmptySubsequences: true)
        }

        var sessionId: String?
        var cwd: String?
        var createdAt = modified
        var parentSession: String?
        var name: String?
        var firstUserMessage: String?
        var messageCount = 0

        let decoder = JSONDecoder()

        func ingest(_ line: Data.SubSequence) {
            guard let value = try? decoder.decode(JSONValue.self, from: Data(line)) else { return }
            switch value.string("type") {
            case "session":
                if sessionId == nil {
                    sessionId = value.string("id")
                    cwd = value.string("cwd")
                    parentSession = value.string("parentSession")
                    if let iso = value.string("timestamp"),
                       let date = ISO8601DateFormatter.piCode.date(from: iso) {
                        createdAt = date
                    }
                }
            case "message":
                messageCount += 1
                if firstUserMessage == nil, value.object("message")?.string("role") == "user" {
                    let message = PiMessage(raw: value.object("message") ?? .null)
                    let text = message.textContent
                    if !text.isEmpty { firstUserMessage = text }
                }
            case "session_info":
                if let candidate = value.string("name") { name = candidate }
            default:
                break
            }
        }

        lines.forEach(ingest)
        tailLines.forEach(ingest)

        // Fall back to decoding the directory name when the header is unreadable.
        if cwd == nil {
            let directoryName = fileURL.deletingLastPathComponent().lastPathComponent
            cwd = Self.decodeDirectoryName(directoryName)
        }
        guard let cwd else { return nil }

        return SessionRef(
            id: sessionId ?? fileURL.deletingPathExtension().lastPathComponent,
            sessionId: sessionId,
            filePath: fileURL.path,
            name: name,
            cwd: cwd,
            createdAt: createdAt,
            updatedAt: modified,
            messageCount: messageCount,
            firstUserMessage: firstUserMessage,
            parentSession: parentSession
        )
    }

    /// Reconstructs an absolute path from Pi's session directory naming scheme
    /// (`--Users-name-project--`). Lossy when the path contains `-`, so it is
    /// only used when the session header is unavailable.
    static func decodeDirectoryName(_ name: String) -> String {
        var trimmed = name
        if trimmed.hasPrefix("--") { trimmed.removeFirst(2) }
        if trimmed.hasSuffix("--") { trimmed.removeLast(2) }
        guard !trimmed.isEmpty else { return "/" }
        let path = "/" + trimmed.replacingOccurrences(of: "-", with: "/")
        return path
    }

    private func read(url: URL, from offset: Int, length: Int) -> Data {
        guard length > 0, let handle = try? FileHandle(forReadingFrom: url) else { return Data() }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: UInt64(offset))
            return try handle.read(upToCount: length) ?? Data()
        } catch {
            return Data()
        }
    }

    // MARK: - Search

    /// Local substring search across names, project paths, and prompt text.
    func search(_ query: String, in projects: [ProjectGroup]) -> [ProjectGroup] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return projects }
        return projects.compactMap { project in
            var project = project
            let projectMatches = project.name.lowercased().contains(needle)
                || project.path.lowercased().contains(needle)
            let sessions = project.sessions.filter { ref in
                projectMatches
                    || (ref.name ?? "").lowercased().contains(needle)
                    || (ref.firstUserMessage ?? "").lowercased().contains(needle)
            }
            guard projectMatches || !sessions.isEmpty else { return nil }
            project.sessions = sessions
            return project
        }
    }
}

/// Canonical path helper. Uses `resolvingSymlinksInPath` so a project reached
/// through a symlink groups with the same sessions Pi recorded.
enum CanonicalPath {
    static func of(_ path: String) -> String {
        URL(fileURLWithPath: path)
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
    }
}
