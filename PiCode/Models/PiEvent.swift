//
//  PiEvent.swift
//  PiCode
//
//  Unsolicited events streamed by `pi --mode rpc` on stdout.
//
//  Every documented event type is decoded into a typed case. Unknown types are
//  preserved as `.unknown` so the app keeps running and diagnostics can report
//  new protocol surface.
//

import Foundation

enum PiEvent: Equatable {
    case agentStart
    case agentEnd(messages: [PiMessage], willRetry: Bool)
    case agentSettled
    case turnStart
    case turnEnd(message: PiMessage?, toolResults: [PiMessage])
    case messageStart(PiMessage)
    case messageUpdate(usage: PiUsage?, delta: AssistantDelta)
    case messageEnd(PiMessage)
    case bashExecutionUpdate(id: String?, delta: String)
    case toolExecutionStart(toolCallId: String, toolName: String, args: JSONValue?)
    case toolExecutionUpdate(toolCallId: String, toolName: String, partialResult: PiToolResult)
    case toolExecutionEnd(toolCallId: String, toolName: String, result: PiToolResult?, isError: Bool)
    case queueUpdate(steering: [String], followUp: [String])
    case compactionStart(reason: String)
    case compactionEnd(reason: String, result: PiCompactionResult?, aborted: Bool, errorMessage: String?, willRetry: Bool)
    case autoRetryStart(attempt: Int, maxAttempts: Int, delayMs: Int, errorMessage: String?)
    case autoRetryEnd(success: Bool, attempt: Int, finalError: String?)
    case summarizationRetryScheduled(attempt: Int, maxAttempts: Int, delayMs: Int, errorMessage: String?)
    case summarizationRetryAttemptStart(source: String?, reason: String?)
    case summarizationRetryFinished
    case extensionError(extensionPath: String?, event: String?, error: String)
    case extensionUIRequest(ExtensionUIRequest)
    case unknown(type: String)

    init(json: JSONValue) {
        let type = json.string("type") ?? "unknown"
        switch type {
        case "agent_start":
            self = .agentStart
        case "agent_end":
            self = .agentEnd(
                messages: json.array("messages")?.map(PiMessage.init(raw:)) ?? [],
                willRetry: json.bool("willRetry") ?? false
            )
        case "agent_settled":
            self = .agentSettled
        case "turn_start":
            self = .turnStart
        case "turn_end":
            self = .turnEnd(
                message: json.object("message").map(PiMessage.init(raw:)),
                toolResults: json.array("toolResults")?.map(PiMessage.init(raw:)) ?? []
            )
        case "message_start":
            self = .messageStart(PiMessage(raw: json.object("message") ?? .null))
        case "message_update":
            self = .messageUpdate(
                usage: json.object("usage").map { PiUsage(json: $0) },
                delta: AssistantDelta(json: json.object("assistantMessageEvent") ?? .null)
            )
        case "message_end":
            self = .messageEnd(PiMessage(raw: json.object("message") ?? .null))
        case "bash_execution_update":
            self = .bashExecutionUpdate(id: json.string("id"), delta: json.string("delta") ?? "")
        case "tool_execution_start":
            self = .toolExecutionStart(
                toolCallId: json.string("toolCallId") ?? "",
                toolName: json.string("toolName") ?? "",
                args: json.object("args") ?? json["args"]
            )
        case "tool_execution_update":
            self = .toolExecutionUpdate(
                toolCallId: json.string("toolCallId") ?? "",
                toolName: json.string("toolName") ?? "",
                partialResult: PiToolResult(json: json.object("partialResult"))
            )
        case "tool_execution_end":
            self = .toolExecutionEnd(
                toolCallId: json.string("toolCallId") ?? "",
                toolName: json.string("toolName") ?? "",
                result: json.object("result").map { PiToolResult(json: $0) },
                isError: json.bool("isError") ?? false
            )
        case "queue_update":
            self = .queueUpdate(
                steering: json.array("steering")?.compactMap(\.stringValue) ?? [],
                followUp: json.array("followUp")?.compactMap(\.stringValue) ?? []
            )
        case "compaction_start":
            self = .compactionStart(reason: json.string("reason") ?? "manual")
        case "compaction_end":
            self = .compactionEnd(
                reason: json.string("reason") ?? "manual",
                result: json.object("result").map { PiCompactionResult(json: $0) },
                aborted: json.bool("aborted") ?? false,
                errorMessage: json.string("errorMessage"),
                willRetry: json.bool("willRetry") ?? false
            )
        case "auto_retry_start":
            self = .autoRetryStart(
                attempt: json.int("attempt") ?? 0,
                maxAttempts: json.int("maxAttempts") ?? 0,
                delayMs: json.int("delayMs") ?? 0,
                errorMessage: json.string("errorMessage")
            )
        case "auto_retry_end":
            self = .autoRetryEnd(
                success: json.bool("success") ?? false,
                attempt: json.int("attempt") ?? 0,
                finalError: json.string("finalError")
            )
        case "summarization_retry_scheduled":
            self = .summarizationRetryScheduled(
                attempt: json.int("attempt") ?? 0,
                maxAttempts: json.int("maxAttempts") ?? 0,
                delayMs: json.int("delayMs") ?? 0,
                errorMessage: json.string("errorMessage")
            )
        case "summarization_retry_attempt_start":
            self = .summarizationRetryAttemptStart(
                source: json.string("source"),
                reason: json.string("reason")
            )
        case "summarization_retry_finished":
            self = .summarizationRetryFinished
        case "extension_error":
            self = .extensionError(
                extensionPath: json.string("extensionPath"),
                event: json.string("event"),
                error: json.string("error") ?? "Unknown extension error"
            )
        case "extension_ui_request":
            self = .extensionUIRequest(ExtensionUIRequest(json: json))
        default:
            self = .unknown(type: type)
        }
    }

    var typeName: String {
        switch self {
        case .agentStart: return "agent_start"
        case .agentEnd: return "agent_end"
        case .agentSettled: return "agent_settled"
        case .turnStart: return "turn_start"
        case .turnEnd: return "turn_end"
        case .messageStart: return "message_start"
        case .messageUpdate: return "message_update"
        case .messageEnd: return "message_end"
        case .bashExecutionUpdate: return "bash_execution_update"
        case .toolExecutionStart: return "tool_execution_start"
        case .toolExecutionUpdate: return "tool_execution_update"
        case .toolExecutionEnd: return "tool_execution_end"
        case .queueUpdate: return "queue_update"
        case .compactionStart: return "compaction_start"
        case .compactionEnd: return "compaction_end"
        case .autoRetryStart: return "auto_retry_start"
        case .autoRetryEnd: return "auto_retry_end"
        case .summarizationRetryScheduled: return "summarization_retry_scheduled"
        case .summarizationRetryAttemptStart: return "summarization_retry_attempt_start"
        case .summarizationRetryFinished: return "summarization_retry_finished"
        case .extensionError: return "extension_error"
        case .extensionUIRequest: return "extension_ui_request"
        case .unknown(let type): return type
        }
    }
}

/// Streaming deltas inside `message_update.assistantMessageEvent`.
///
/// Clients must assemble live partial content from `message_start` plus these
/// deltas; `message_end.message` is authoritative.
enum AssistantDelta: Equatable {
    case textStart(contentIndex: Int)
    case textDelta(contentIndex: Int, delta: String)
    case textEnd(contentIndex: Int, content: String)
    case thinkingStart(contentIndex: Int)
    case thinkingDelta(contentIndex: Int, delta: String)
    case thinkingEnd(contentIndex: Int, content: String)
    case toolCallStart(contentIndex: Int, id: String, toolName: String)
    case toolCallDelta(contentIndex: Int, delta: String)
    case toolCallEnd(contentIndex: Int, toolCall: PiContentBlock)
    case other(String)

    init(json: JSONValue) {
        let type = json.string("type") ?? "other"
        let index = json.int("contentIndex") ?? 0
        switch type {
        case "text_start": self = .textStart(contentIndex: index)
        case "text_delta": self = .textDelta(contentIndex: index, delta: json.string("delta") ?? "")
        case "text_end": self = .textEnd(contentIndex: index, content: json.string("content") ?? "")
        case "thinking_start": self = .thinkingStart(contentIndex: index)
        case "thinking_delta": self = .thinkingDelta(contentIndex: index, delta: json.string("delta") ?? "")
        case "thinking_end": self = .thinkingEnd(contentIndex: index, content: json.string("content") ?? "")
        case "toolcall_start":
            self = .toolCallStart(
                contentIndex: index,
                id: json.string("id") ?? "",
                toolName: json.string("toolName") ?? ""
            )
        case "toolcall_delta": self = .toolCallDelta(contentIndex: index, delta: json.string("delta") ?? "")
        case "toolcall_end":
            self = .toolCallEnd(contentIndex: index, toolCall: PiContentBlock(json: json.object("toolCall") ?? .null))
        default: self = .other(type)
        }
    }
}
