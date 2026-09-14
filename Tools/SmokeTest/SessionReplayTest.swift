//
//  SessionReplayTest.swift
//  PiCode (smoke test)
//
//  Replays every real session file in ~/.pi/agent/sessions through the same
//  parsers the app uses (JSONLDecoder -> PiSessionEntry -> TranscriptBuilder)
//  and reports what would be rendered.
//
//  Why this exists: the RPC smoke test only proves the live protocol works. This
//  one proves the *reading* path works against megabytes of real Pi output —
//  including shapes nobody thought about — for free, without calling a model.
//
//  Sessions are opened read-only. The test never writes to ~/.pi/agent.
//
//      ./Tools/SmokeTest/run-replay.sh
//

import Foundation

@main
enum SessionReplayTest {
    static func main() {
        let sessions = SessionIndex().loadAllSessions()

        print("== indexing ==")
        print("  \(sessions.count) session(s) in \(PiPaths.sessionsDirectory.path.abbreviatingHomeDirectory)")
        var failures = 0
        func check(_ name: String, _ condition: Bool, _ detail: String = "") {
            if condition {
                print("  ok   \(name)\(detail.isEmpty ? "" : " — \(detail)")")
            } else {
                failures += 1
                print("  FAIL \(name)\(detail.isEmpty ? "" : " — \(detail)")")
            }
        }

        check("every session has a path", sessions.allSatisfy { $0.filePath != nil })
        check("every session has a working directory", sessions.allSatisfy { !$0.cwd.isEmpty })
        check("every session has an id", sessions.allSatisfy { !$0.id.isEmpty })
        let noMessages = sessions.filter { $0.messageCount == 0 }
        check("message counts were read from the file", noMessages.count < sessions.count,
              "\(sessions.count - noMessages.count) with content, \(noMessages.count) empty")

        // Aggregate findings across every session so one unusual file cannot hide
        // behind a summary.
        var itemKinds: [String: Int] = [:]
        var roles: [String: Int] = [:]
        var entryTypes: [String: Int] = [:]
        var unknownRoles: [String: Int] = [:]
        var unknownEntryTypes: [String: Int] = [:]
        var unknownEvents: [String: Int] = [:]
        var duplicateIDFiles: [String] = []
        var emptyIDFiles: [String] = []
        var truncatedFiles: [String] = []
        var undecodableLines = 0
        var totalLines = 0
        var totalItems = 0
        var toolCalls = 0
        var toolResults = 0
        var fileChanges = 0
        var orphanToolResults = 0
        var toolResultMessages = 0
        var toolResultsWithoutID = 0
        var toolResultIds = Set<String>()
        var toolCallIds = Set<String>()
        var summaries = 0
        var thinkingBlocks = 0

        print("== replaying sessions ==")
        for session in sessions {
            guard let path = session.filePath else { continue }

            let content = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
            var decoder = LineAccumulator()
            var records: [JSONValue] = []
            for line in decoder.append(content.data(using: .utf8) ?? Data()) {
                totalLines += 1
                if let value = try? JSONCoding.decode(Data(line.utf8)) {
                    records.append(value)
                } else {
                    undecodableLines += 1
                }
            }
            guard !records.isEmpty else { continue }

            // A session file's last entry is the leaf of the active branch.
            let entries = records.map(PiSessionEntry.init(json:))
            let leafId = entries.last?.id
            for entry in entries {
                entryTypes[entry.type, default: 0] += 1
                if !["message", "compaction", "branch", "label", "session", "model_change",
                     "thinking_level_change", "custom", "summary", "snapshot"].contains(entry.type) {
                    unknownEntryTypes[entry.type, default: 0] += 1
                }
            }

            let branch = TranscriptBuilder.activeBranchEntries(entries: entries, leafId: leafId)
            let messages = branch.compactMap(\.message)
            let userEntryIds = TranscriptBuilder.userEntryIds(entries: entries, leafId: leafId)
            let items = TranscriptBuilder.items(messages: messages, userEntryIds: userEntryIds)
            totalItems += items.count

            for message in messages {
                roles[message.role, default: 0] += 1
                if !["user", "assistant", "toolResult", "tool_result", "bashExecution",
                     "branchSummary", "compactionSummary", "custom", "custom_message"].contains(message.role) {
                    unknownRoles[message.role, default: 0] += 1
                }
                thinkingBlocks += message.content.filter { $0.kind == .thinking }.count
                if message.role == "toolResult" {
                    toolResultMessages += 1
                    if let id = message.toolCallId { toolResultIds.insert(id) }
                    else { toolResultsWithoutID += 1 }
                }
                for block in message.content where block.kind == .toolCall {
                    if let id = block.toolCallId { toolCallIds.insert(id) }
                }
            }

            // Deterministic ids are what make live rows replace durable rows. A
            // collision inside one transcript would silently drop a row.
            var seen = Set<String>()
            var duplicates = 0
            var empties = 0
            for item in items {
                itemKinds[String(describing: item.kind), default: 0] += 1
                if item.id.isEmpty { empties += 1 }
                if !seen.insert(item.id).inserted { duplicates += 1 }
                switch item.kind {
                case .toolCall:
                    toolCalls += 1
                case .toolResult:
                    toolResults += 1
                default:
                    break
                }
                if item.fullOutputPath != nil { truncatedFiles.append(path) }
            }
            if duplicates > 0 { duplicateIDFiles.append("\(path) (\(duplicates) duplicates)") }
            if empties > 0 { emptyIDFiles.append("\(path) (\(empties) empty)") }

            // Tool rows need a matching pair: a result with no call would render
            // as an orphan card. Results are checked at the message level, because
            // `TranscriptBuilder` folds them into their call's row.
            fileChanges += items.reduce(0) { $0 + $1.fileChanges.count }
        }

        // Every tool result on the active branch must belong to a tool call on
        // the same branch, otherwise the row has nothing to attach to.
        orphanToolResults = toolResultIds.subtracting(toolCallIds).count

        check("every line decoded", undecodableLines == 0,
              "\(totalLines) lines, \(undecodableLines) undecodable")
        check("no duplicate transcript row ids", duplicateIDFiles.isEmpty,
              duplicateIDFiles.joined(separator: "; "))
        check("no empty transcript row ids", emptyIDFiles.isEmpty)
        check("tool results carry a toolCallId", toolResultsWithoutID == 0,
              "\(toolResultsWithoutID) of \(toolResultMessages) missing an id")
        check("tool results have a matching call", orphanToolResults == 0,
              "\(orphanToolResults) orphan(s) out of \(toolResultIds.count) distinct result id(s),"
              + " \(toolCallIds.count) call id(s)")
        check("no unknown message roles", unknownRoles.isEmpty,
              unknownRoles.map { "\($0.key)×\($0.value)" }.sorted().joined(separator: ", "))
        check("no unknown entry types", unknownEntryTypes.isEmpty,
              unknownEntryTypes.map { "\($0.key)×\($0.value)" }.sorted().joined(separator: ", "))

        print("  entries:   \(entryTypes.sorted { $0.value > $1.value }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))")
        print("  roles:     \(roles.sorted { $0.value > $1.value }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))")
        print("  rows:      \(itemKinds.sorted { $0.value > $1.value }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))")
        print("  totals:    \(totalItems) rows from \(totalLines) lines, \(toolCalls) tool calls,"
              + " \(toolResults) standalone tool-result rows, \(toolResultMessages) tool-result messages,"
              + " \(thinkingBlocks) thinking blocks,"
              + " \(fileChanges) file changes, \(summaries) summaries,"
              + " \(truncatedFiles.count) rows with saved full output")

        print(failures == 0 ? "\nRESULT: all checks passed" : "\nRESULT: \(failures) check(s) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
