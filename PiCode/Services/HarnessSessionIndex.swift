import Foundation

/// Read-only adapters over native session stores. No credentials or transcript
/// copies are written to a second database.
enum HarnessSessionIndex {
    static func directory(_ variable: String, fallback: String) -> URL {
        let path = ProcessInfo.processInfo.environment[variable] ?? fallback
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    static func files(in root: URL, extension suffix: String = "jsonl") -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
        ) else { return [] }
        return enumerator.compactMap { $0 as? URL }.filter {
            $0.pathExtension == suffix && !$0.pathComponents.contains("subagents")
        }
    }

    static func load() -> [SessionRef] {
        let omp = directory("PI_CODING_AGENT_DIR", fallback: "~/.omp/agent")
            .appendingPathComponent("sessions")
        var result = files(in: omp).compactMap { url -> SessionRef? in
            guard var ref = SessionIndex().parse(fileURL: url) else { return nil }
            ref.harnessID = .ohMyPi
            ref.id = "oh-my-pi:\(ref.id)"
            return ref
        }
        for harness in [HarnessID.claudeCode, .codex] {
            result += nativeFiles(for: harness).compactMap { parse($0, harness: harness) }
        }
        return result + deepSeekSessions()
    }

    static func deepSeekSessions() -> [SessionRef] {
        let root = directory("DSH_HOME", fallback: "~/.dsh")
            .appendingPathComponent("storages/session_projcache/sessions")
        return files(in: root, extension: "json").compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let record = try? JSONCoding.decode(data).object("record"),
                  let identity = record.object("identity"),
                  let cwd = identity.string("cwd") else { return nil }
            let id = url.deletingPathExtension().lastPathComponent
            let created = Date(timeIntervalSince1970: (identity.double("createdAt") ?? 0) / 1000)
            let rows = record.object("rows")
            let activity = rows?.object("sessionListMetadata")?.object("val")?.double("lastPromptAt")
            return SessionRef(
                id: "deepseek-harness:\(id)", sessionId: id, filePath: nil,
                name: rows?.object("title")?.string("val"), cwd: cwd,
                createdAt: created,
                updatedAt: activity.map { Date(timeIntervalSince1970: $0 / 1000) } ?? created,
                messageCount: 0, firstUserMessage: nil, parentSession: nil,
                harnessID: .deepseekHarness
            )
        }
    }

    static func nativeFiles(for harness: HarnessID) -> [URL] {
        switch harness {
        case .claudeCode:
            return files(in: directory("CLAUDE_CONFIG_DIR", fallback: "~/.claude").appendingPathComponent("projects"))
        case .codex:
            return files(in: directory("CODEX_HOME", fallback: "~/.codex").appendingPathComponent("sessions"))
        default: return []
        }
    }

    static func records(at url: URL, metadataOnly: Bool = false) -> [JSONValue] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        // Metadata reads are bounded; history is read only when a chat is opened.
        var data: Data
        if metadataOnly {
            data = (try? handle.read(upToCount: 512 * 1024)) ?? Data()
            if let size = try? handle.seekToEnd(), size > UInt64(data.count) {
                let offset = max(UInt64(data.count), size > 128 * 1024 ? size - 128 * 1024 : 0)
                try? handle.seek(toOffset: offset)
                if let tail = try? handle.readToEnd() {
                    // Discard the first fragment when starting mid-record.
                    let complete = offset == UInt64(data.count) ? tail : Data(tail.drop { $0 != 10 }.dropFirst())
                    data.append(10)
                    data.append(complete)
                }
            }
        } else {
            data = (try? handle.readToEnd()) ?? Data()
        }
        return data.split(separator: 10).compactMap { try? JSONCoding.decode(Data($0)) }
    }

    static func parse(_ url: URL, harness: HarnessID) -> SessionRef? {
        let records = records(at: url, metadataOnly: true)
        let header = harness == .codex
            ? records.first(where: { $0.string("type") == "session_meta" })?.object("payload")
            : records.first(where: { $0.string("sessionId") != nil && $0.string("cwd") != nil })
        guard let header, let cwd = header.string("cwd"),
              let id = header.string(harness == .codex ? "id" : "sessionId") else { return nil }
        if header.bool("isSidechain") == true { return nil }
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
        let messages = messages(from: records, harness: harness)
        return SessionRef(
            id: "\(harness.rawValue):\(id)", sessionId: id, filePath: url.path,
            name: records.last(where: { $0.string("type") == "custom-title" })?.string("customTitle"),
            cwd: cwd,
            createdAt: header.string("timestamp").flatMap { ISO8601DateFormatter.piCode.date(from: $0) } ?? modified,
            updatedAt: modified, messageCount: messages.count,
            firstUserMessage: messages.first(where: \.isUser)?.textContent,
            parentSession: nil, harnessID: harness
        )
    }

    static func history(id: String, harness: HarnessID) -> [PiMessage] {
        guard let file = nativeFiles(for: harness).first(where: {
            $0.lastPathComponent.contains(id)
        }) else { return [] }
        return messages(from: records(at: file), harness: harness)
    }

    static func messages(from records: [JSONValue], harness: HarnessID) -> [PiMessage] {
        records.compactMap { record in
            if harness == .claudeCode {
                guard ["user", "assistant"].contains(record.string("type") ?? ""),
                      let message = record.object("message") else { return nil }
                return PiMessage(raw: message)
            }
            guard record.string("type") == "response_item",
                  let payload = record.object("payload"), payload.string("type") == "message",
                  let role = payload.string("role"), ["user", "assistant"].contains(role) else { return nil }
            let text = (payload.array("content") ?? []).compactMap { $0.string("text") }.joined(separator: "\n")
            return PiMessage(raw: .object([
                "role": .string(role),
                "content": .array([.object(["type": .string("text"), "text": .string(text)])
                ])
            ]))
        }
    }
}
