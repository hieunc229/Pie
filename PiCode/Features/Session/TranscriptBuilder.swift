//
//  TranscriptBuilder.swift
//  PiCode
//
//  Converts Pi's authoritative message list into transcript rows.
//
//  Rules that keep the transcript honest:
//   - `get_messages` / `message_end` are the source of truth for content,
//     tool results, and errors.
//   - Tool rows are keyed by Pi's `toolCallId`, so live `tool_execution_*`
//     events can update the exact row the message list later confirms.
//   - Nothing is invented: when Pi reports an unknown role or stop reason, the
//     raw role string is shown rather than a guess.
//

import Foundation

enum TranscriptBuilder {
    /// Walks the tree from `leafId` to the root to find the entries that form the
    /// currently active branch, oldest first.
    static func activeBranchEntries(entries: [PiSessionEntry], leafId: String?) -> [PiSessionEntry] {
        guard let leafId else { return [] }
        var byId: [String: PiSessionEntry] = [:]
        for entry in entries { byId[entry.id] = entry }

        var branch: [PiSessionEntry] = []
        var visited = Set<String>()
        var cursor: String? = leafId
        while let id = cursor, let entry = byId[id], !visited.contains(id) {
            visited.insert(id)
            branch.append(entry)
            cursor = entry.parentId
        }
        return branch.reversed()
    }

    /// User message entry ids on the active branch, in message order. Used so the
    /// transcript can offer fork-from-here for exactly the messages Pi allows.
    static func userEntryIds(entries: [PiSessionEntry], leafId: String?) -> [String] {
        activeBranchEntries(entries: entries, leafId: leafId)
            .filter { $0.type == "message" && ($0.message?.isUser ?? false) }
            .map(\.id)
    }

    static func items(messages: [PiMessage], userEntryIds: [String] = []) -> [TranscriptItem] {
        Builder(userEntryIds: userEntryIds).build(messages: messages)
    }

    // MARK: - Builder

    private final class Builder {
        private var items: [TranscriptItem] = []
        private var indexByItemID: [String: Int] = [:]
        private var userEntryCursor = 0
        private let userEntryIds: [String]
        /// The user entry that produced the assistant blocks we are walking.
        /// Pi only allows forking at user messages (`get_fork_messages`), so an
        /// assistant row's branch point is the message that asked for it.
        private var lastUserEntryId: String?

        init(userEntryIds: [String]) {
            self.userEntryIds = userEntryIds
        }

        func build(messages: [PiMessage]) -> [TranscriptItem] {
            for (index, message) in messages.enumerated() {
                switch message.role {
                case "user": appendUser(message, index: index)
                case "assistant": appendAssistant(message, index: index)
                case "toolResult": appendToolResult(message, index: index)
                case "bashExecution": appendBash(message, index: index)
                case "branchSummary", "compactionSummary": appendSummary(message, index: index)
                case "custom", "custom_message": appendCustom(message, index: index)
                default: appendUnknown(message, index: index)
                }
            }
            return items
        }

        private func append(_ item: TranscriptItem) {
            indexByItemID[item.id] = items.count
            items.append(item)
        }

        private func appendUser(_ message: PiMessage, index: Int) {
            var entryId: String?
            if userEntryCursor < userEntryIds.count {
                entryId = userEntryIds[userEntryCursor]
                userEntryCursor += 1
            }
            lastUserEntryId = entryId
            append(TranscriptItem(
                id: "msg-\(index)-user",
                kind: .user,
                text: message.textContent,
                timestamp: message.timestamp,
                entryId: entryId,
                forkEntryId: entryId
            ))
        }

        private func appendAssistant(_ message: PiMessage, index: Int) {
            var wroteAnyBlock = false

            for (blockIndex, block) in message.content.enumerated() {
                switch block.kind {
                case .text:
                    guard !block.text.isEmpty else { continue }
                    wroteAnyBlock = true
                    append(TranscriptItem(
                        id: "msg-\(index)-assistant-\(blockIndex)",
                        kind: .assistant,
                        text: block.text,
                        timestamp: message.timestamp,
                        modelName: message.model,
                        provider: message.provider,
                        usage: message.usage,
                        stopReason: message.stopReason,
                        forkEntryId: lastUserEntryId
                    ))

                case .thinking:
                    guard !block.thinking.isEmpty else { continue }
                    wroteAnyBlock = true
                    append(TranscriptItem(
                        id: "msg-\(index)-thinking-\(blockIndex)",
                        kind: .thinking,
                        text: block.thinking,
                        timestamp: message.timestamp,
                        modelName: message.model,
                        provider: message.provider,
                        forkEntryId: lastUserEntryId
                    ))

                case .toolCall:
                    guard let toolCallId = block.toolCallId else { continue }
                    wroteAnyBlock = true
                    mergeToolCall(block: block, toolCallId: toolCallId, timestamp: message.timestamp)

                case .image:
                    continue

                case .unknown(let type):
                    guard !type.isEmpty else { continue }
                    append(TranscriptItem(
                        id: "msg-\(index)-unknown-\(blockIndex)",
                        kind: .system,
                        text: "[Unsupported content block: \(type)]",
                        timestamp: message.timestamp,
                        badge: "Unsupported"
                    ))
                }
            }

            let failed = message.stopReason == "error" || (message.errorMessage?.isEmpty == false)
            guard failed else { return }
            let text = message.errorMessage ?? "The response ended with stop reason `\(message.stopReason ?? "error")`."
            append(TranscriptItem(
                id: wroteAnyBlock ? "msg-\(index)-error-note" : "msg-\(index)-error",
                kind: .error,
                text: text,
                timestamp: message.timestamp,
                modelName: message.model,
                provider: message.provider,
                stopReason: message.stopReason,
                errorMessage: message.errorMessage
            ))
        }

        private func mergeToolCall(block: PiContentBlock, toolCallId: String, timestamp: Date?) {
            let item = TranscriptItem(
                id: "tool-\(toolCallId)",
                kind: .toolCall,
                text: block.toolName ?? "",
                timestamp: timestamp,
                toolCallId: toolCallId,
                toolName: block.toolName,
                toolArguments: block.toolArguments,
                toolStatus: .pending
            )
            guard let existing = indexByItemID[item.id] else {
                append(item)
                return
            }
            // A live execution row already exists; keep its runtime state.
            var merged = item
            merged.toolStatus = items[existing].toolStatus
            merged.toolOutput = items[existing].toolOutput
            merged.toolStartedAt = items[existing].toolStartedAt
            merged.toolEndedAt = items[existing].toolEndedAt
            merged.toolDetails = items[existing].toolDetails
            merged.fullOutputPath = items[existing].fullOutputPath
            merged.isStreaming = false
            items[existing] = merged
        }

        private func appendToolResult(_ message: PiMessage, index: Int) {
            let resultContent = message.content
            let output = Self.text(of: resultContent)
            let status: ToolStatus = message.isError ? .failure : .success

            if let toolCallId = message.toolCallId, let existing = indexByItemID["tool-\(toolCallId)"] {
                items[existing].toolOutput = output
                items[existing].toolResultContent = resultContent
                items[existing].toolStatus = status
                items[existing].toolEndedAt = items[existing].toolEndedAt ?? message.timestamp
                if items[existing].toolName == nil { items[existing].toolName = message.toolName }
                return
            }

            // Tool results whose call is no longer in the active message list (for
            // example after compaction) still deserve a row.
            append(TranscriptItem(
                id: "toolresult-\(index)",
                kind: .toolResult,
                text: output,
                timestamp: message.timestamp,
                toolCallId: message.toolCallId,
                toolName: message.toolName,
                toolOutput: output,
                toolResultContent: resultContent,
                toolStatus: status,
                toolEndedAt: message.timestamp
            ))
        }

        private func appendBash(_ message: PiMessage, index: Int) {
            let id = "bash-\(index)"
            append(TranscriptItem(
                id: id,
                kind: .toolCall,
                text: message.command ?? "",
                timestamp: message.timestamp,
                toolCallId: id,
                toolName: "bash",
                toolArguments: message.command.map { .object(["command": .string($0)]) },
                toolOutput: message.output ?? "",
                toolStatus: message.cancelled
                    ? .cancelled
                    : ((message.exitCode ?? 0) == 0 ? .success : .failure),
                toolEndedAt: message.timestamp,
                fullOutputPath: message.fullOutputPath
            ))
        }

        private func appendSummary(_ message: PiMessage, index: Int) {
            append(TranscriptItem(
                id: "summary-\(index)",
                kind: .compaction,
                text: message.summary.isEmpty ? message.text : message.summary,
                timestamp: message.timestamp,
                entryId: message.fromId,
                // The role is what carries the distinction; the transcript row
                // names it and picks its glyph from `SummaryKind`.
                summaryKind: message.role == "branchSummary" ? .branch : .compaction
            ))
        }

        private func appendCustom(_ message: PiMessage, index: Int) {
            guard message.display else { return }
            let text = message.textContent.isEmpty ? (message.customType ?? "") : message.textContent
            guard !text.isEmpty else { return }
            append(TranscriptItem(
                id: "custom-\(index)",
                kind: .system,
                text: text,
                timestamp: message.timestamp,
                badge: message.customType ?? "Extension"
            ))
        }

        private func appendUnknown(_ message: PiMessage, index: Int) {
            let text = message.textContent
            guard !text.isEmpty else { return }
            append(TranscriptItem(
                id: "msg-\(index)-\(message.role)",
                kind: .system,
                text: text,
                timestamp: message.timestamp,
                badge: message.role
            ))
        }

        static func text(of blocks: [PiContentBlock]) -> String {
            blocks.map { block -> String in
                switch block.kind {
                case .text: return block.text
                case .image: return "[image]"
                default: return ""
                }
            }.joined()
        }
    }
}
