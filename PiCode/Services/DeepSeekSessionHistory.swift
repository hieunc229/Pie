//
//  DeepSeekSessionHistory.swift
//  PiCode
//
//  Reads a saved DeepSeek Harness session back into transcript messages. `dsh`
//  keeps each session as a zstd-compressed JSONL event log under
//  `$DSH_HOME/sessions/<project>/<session id>/session.v4.jsonl.zstd`; the SDK's
//  `session/resume` restores the agent but does not replay history, so the
//  transcript is rebuilt here. Needs the `zstd` tool; without it the chat still
//  resumes, just with an empty transcript.
//

import Foundation

enum DeepSeekSessionHistory {
    static func logURL(sessionId: String) -> URL? {
        let home = ProcessInfo.processInfo.environment["DSH_HOME"].map { URL(fileURLWithPath: $0) }
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".dsh")
        let root = home.appendingPathComponent("sessions")
        let projects = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil)) ?? []
        for project in projects {
            let url = project.appendingPathComponent(sessionId).appendingPathComponent("session.v4.jsonl.zstd")
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    static func load(sessionId: String) -> [PiMessage] {
        guard let log = logURL(sessionId: sessionId), let zstd = zstdExecutable() else { return [] }
        let process = Process()
        process.executableURL = zstd
        process.arguments = ["-dc", "-q", log.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        var messages: [PiMessage] = []
        for line in data.split(separator: 0x0A) {
            // Cheap prefilter: most of the log is step bookkeeping and job events.
            guard let head = String(data: line.prefix(40), encoding: .utf8),
                  head.contains("user/message") || head.contains("assistant/message")
                    || head.contains("tool/result"),
                  let json = try? JSONCoding.decode(Data(line)),
                  let data = json.object("data") else { continue }
            switch json.string("type") {
            case "user/message":
                guard data.object("source")?.string("kind") == "user" else { continue }
                let text = textOf(data.array("content"))
                if !text.isEmpty { messages.append(PiMessage(raw: AgentWire.userMessage(text))) }
            case "assistant/message":
                guard let message = data.object("message") else { continue }
                messages.append(PiMessage(raw: assistant(message, time: json.double("time"))))
            case "tool/result":
                guard let message = data.object("message") else { continue }
                let id = message.object("source")?.string("callId") ?? message.string("toolCallId") ?? ""
                messages.append(PiMessage(raw: AgentWire.toolResultMessage(
                    id: id, name: "tool", output: textOf(message.array("content")),
                    isError: message.bool("isError") == true)))
            default:
                break
            }
        }
        return messages
    }

    private static func textOf(_ blocks: [JSONValue]?) -> String {
        (blocks ?? []).compactMap { $0.string("text") }.joined(separator: "\n")
    }

    private static func assistant(_ message: JSONValue, time: Double?) -> JSONValue {
        let blocks: [JSONValue] = (message.array("content") ?? []).compactMap { block in
            switch block.string("type") {
            case "text":
                return .object(["type": .string("text"), "text": .string(block.string("text") ?? "")])
            case "reasoning":
                return .object(["type": .string("thinking"), "thinking": .string(block.string("text") ?? "")])
            case "tool-call":
                let arguments = (block.string("arguments")?.data(using: .utf8))
                    .flatMap { try? JSONCoding.decode($0) } ?? .object([:])
                return .object([
                    "type": .string("toolCall"),
                    "id": .string(block.string("id") ?? UUID().uuidString),
                    "name": .string(block.string("name") ?? "tool"),
                    "arguments": arguments
                ])
            default:
                return nil
            }
        }
        var object: [String: JSONValue] = ["role": .string("assistant"), "content": .array(blocks)]
        if let time { object["timestamp"] = .number(time) }
        if let source = message.object("source") {
            if let model = source.string("model") { object["model"] = .string(model) }
            if let provider = source.string("provider") { object["provider"] = .string(provider) }
        }
        return .object(object)
    }

    private static func zstdExecutable() -> URL? {
        ["/opt/homebrew/bin/zstd", "/usr/local/bin/zstd", "/usr/bin/zstd"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }
}
