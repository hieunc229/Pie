import Foundation

enum TranscriptHistory {
    /// Session entries retain the full branch even when get_messages contains
    /// only the compacted model context. Merge the not-yet-persisted tail into it.
    static func messages(entries: [PiSessionEntry], leafId: String?, context: [PiMessage]) -> [PiMessage] {
        let branch = TranscriptBuilder.activeBranchEntries(entries: entries, leafId: leafId)
        guard !branch.isEmpty else { return context }
        var history = branch.compactMap { entry -> PiMessage? in
            if let message = entry.message { return message }
            switch entry.type {
            case "compaction", "branch_summary":
                return PiMessage(raw: .object([
                    "role": .string(entry.type == "compaction" ? "compactionSummary" : "branchSummary"),
                    "summary": .string(entry.summary ?? ""),
                    "fromId": .string(entry.id),
                    "timestamp": entry.raw["timestamp"] ?? .null
                ]))
            case "custom_message":
                return PiMessage(raw: .object([
                    "role": .string("custom"),
                    "content": entry.raw["content"] ?? .null,
                    "customType": entry.raw["customType"] ?? .null,
                    "display": entry.raw["display"] ?? .bool(true),
                    "timestamp": entry.raw["timestamp"] ?? .null
                ]))
            default: return nil
            }
        }
        // Reverse the buckets so popLast consumes repeated messages in their
        // original order without scanning the history or shifting arrays.
        var byIdentity: [TranscriptMessageIdentity: [Int]] = [:]
        var withoutTimestamp: [JSONValue: [Int]] = [:]
        for index in history.indices.reversed() {
            let message = history[index]
            if message.timestamp != nil {
                let key = TranscriptMessageIdentity(role: message.role, timestamp: message.timestamp, text: message.textContent)
                byIdentity[key, default: []].append(index)
            } else {
                withoutTimestamp[message.raw, default: []].append(index)
            }
        }
        let hasCompaction = branch.contains { $0.type == "compaction" }
        let hasBranchSummary = branch.contains { $0.type == "branch_summary" }
        for message in context {
            // Model context moves the compaction summary before kept messages;
            // the transcript shows the marker at its actual point in history.
            if message.role == "compactionSummary", hasCompaction { continue }
            if message.role == "branchSummary", hasBranchSummary { continue }
            let index: Int?
            if message.timestamp != nil {
                let key = TranscriptMessageIdentity(role: message.role, timestamp: message.timestamp, text: message.textContent)
                index = byIdentity[key]?.popLast()
            } else {
                index = withoutTimestamp[message.raw]?.popLast()
            }
            if let index {
                history[index] = message
            } else {
                history.append(message)
            }
        }
        return history
    }
}
