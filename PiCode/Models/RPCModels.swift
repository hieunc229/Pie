//
//  RPCModels.swift
//  PiCode
//
//  Typed views over the raw `JSONValue` RPC payloads. Raw protocol shapes live
//  here; presentation shapes live in `TranscriptItem` so protocol changes do not
//  ripple through the views.
//

import Foundation

// MARK: - Model catalog

struct PiModelCost: Equatable, Hashable {
    var input: Double = 0
    var output: Double = 0
    var cacheRead: Double = 0
    var cacheWrite: Double = 0

    init(json: JSONValue?) {
        input = json?.double("input") ?? 0
        output = json?.double("output") ?? 0
        cacheRead = json?.double("cacheRead") ?? 0
        cacheWrite = json?.double("cacheWrite") ?? 0
    }
}

struct PiModel: Identifiable, Equatable, Hashable {
    var id: String
    var name: String
    var provider: String
    var api: String?
    var baseURL: String?
    var reasoning: Bool
    var input: [String]
    var contextWindow: Int?
    var maxTokens: Int?
    var cost: PiModelCost

    init?(json: JSONValue) {
        guard let id = json.string("id"), let provider = json.string("provider") else { return nil }
        self.id = id
        self.provider = provider
        self.name = json.string("name") ?? id
        self.api = json.string("api")
        self.baseURL = json.string("baseUrl")
        self.reasoning = json.bool("reasoning") ?? false
        self.input = json.array("input")?.compactMap(\.stringValue) ?? ["text"]
        self.contextWindow = json.int("contextWindow")
        self.maxTokens = json.int("maxTokens")
        self.cost = PiModelCost(json: json.object("cost"))
    }

    var qualifiedID: String { "\(provider)/\(id)" }

    var supportsImages: Bool { input.contains("image") }

    var displayName: String {
        name.isEmpty ? id : name
    }
}

// MARK: - Usage

struct PiUsage: Equatable {
    var input: Int = 0
    var output: Int = 0
    var cacheRead: Int = 0
    var cacheWrite: Int = 0
    var totalTokens: Int = 0
    var cost: Double = 0

    init(json: JSONValue?) {
        input = json?.int("input") ?? 0
        output = json?.int("output") ?? 0
        cacheRead = json?.int("cacheRead") ?? 0
        cacheWrite = json?.int("cacheWrite") ?? 0
        totalTokens = json?.int("totalTokens") ?? (input + output + cacheRead + cacheWrite)
        cost = json?.object("cost")?.double("total") ?? json?.double("cost") ?? 0
    }

    static let zero = PiUsage(json: nil)

    var isEmpty: Bool { totalTokens == 0 && cost == 0 }
}

// MARK: - Content

struct PiContentBlock: Equatable {
    enum Kind: Equatable {
        case text
        case thinking
        case image
        case toolCall
        case unknown(String)
    }

    var kind: Kind
    var text: String = ""
    /// Thinking/reasoning text, when the provider exposes it.
    var thinking: String = ""
    var imageMimeType: String?
    var imageData: String?
    var toolCallId: String?
    var toolName: String?
    var toolArguments: JSONValue?
    var raw: JSONValue = .null

    init(json: JSONValue) {
        raw = json
        switch json.string("type") {
        case "text":
            kind = .text
            text = json.string("text") ?? ""
        case "thinking", "reasoning":
            kind = .thinking
            thinking = json.string("thinking") ?? json.string("text") ?? ""
        case "image":
            kind = .image
            imageMimeType = json.string("mimeType")
            imageData = json.string("data")
        case "toolCall", "tool_call":
            kind = .toolCall
            toolCallId = json.string("id")
            toolName = json.string("name")
            toolArguments = json.object("arguments") ?? json["arguments"]
        default:
            kind = .unknown(json.string("type") ?? "unknown")
        }
    }

    var isText: Bool { kind == .text }
    var isThinking: Bool { kind == .thinking }
    var isToolCall: Bool { kind == .toolCall }
}

// MARK: - Messages

/// A single `AgentMessage` as delivered by `get_messages`, events, or session
/// entries. Pi's message union is open ended, so this type keeps the raw payload
/// while exposing typed accessors for the roles PiCode renders.
struct PiMessage: Equatable {
    var role: String
    var raw: JSONValue

    var content: [PiContentBlock] = []
    var text: String = ""
    var timestamp: Date?
    var provider: String?
    var model: String?
    var stopReason: String?
    var errorMessage: String?
    var usage: PiUsage?
    var toolCallId: String?
    var toolName: String?
    var isError: Bool = false
    /// `bashExecution` messages and RPC bash results.
    var command: String?
    var output: String?
    var exitCode: Int?
    var cancelled: Bool = false
    var truncated: Bool = false
    var fullOutputPath: String?
    /// `custom` / `custom_message` extension payloads.
    var customType: String?
    var display: Bool = true
    /// `compactionSummary` / `branchSummary`.
    var summary: String = ""
    var tokensBefore: Int?
    var fromId: String?

    init(raw: JSONValue) {
        self.raw = raw
        role = raw.string("role") ?? "unknown"

        switch raw["content"] {
        case .some(.string(let string)):
            text = string
            content = [PiContentBlock(json: .object(["type": .string("text"), "text": .string(string)]))]
        case .some(.array(let blocks)):
            content = blocks.map(PiContentBlock.init(json:))
            text = content.filter(\.isText).map(\.text).joined()
        default:
            break
        }

        if let millis = raw.double("timestamp") {
            timestamp = Date(timeIntervalSince1970: millis / 1000)
        } else if let iso = raw.string("timestamp") {
            timestamp = ISO8601DateFormatter.piCode.date(from: iso)
        }

        provider = raw.string("provider")
        model = raw.string("model")
        stopReason = raw.string("stopReason")
        errorMessage = raw.string("errorMessage")
        if raw.object("usage") != nil { usage = PiUsage(json: raw.object("usage")) }
        toolCallId = raw.string("toolCallId")
        toolName = raw.string("toolName")
        isError = raw.bool("isError") ?? false
        command = raw.string("command")
        output = raw.string("output")
        exitCode = raw.int("exitCode")
        cancelled = raw.bool("cancelled") ?? false
        truncated = raw.bool("truncated") ?? false
        fullOutputPath = raw.string("fullOutputPath")
        customType = raw.string("customType")
        display = raw.bool("display") ?? true
        summary = raw.string("summary") ?? ""
        tokensBefore = raw.int("tokensBefore")
        fromId = raw.string("fromId")

        // `bashExecution` uses `command`/`output` rather than `content`.
        if role == "bashExecution", text.isEmpty, let output {
            text = output
        }
    }

    var isUser: Bool { role == "user" }
    var isAssistant: Bool { role == "assistant" }
    var isToolResult: Bool { role == "toolResult" || role == "tool_result" }

    var textContent: String {
        if role == "bashExecution" || role == "branchSummary" || role == "compactionSummary" {
            return summary.isEmpty ? text : summary
        }
        return text
    }

    var images: [PiContentBlock] { content.filter { $0.kind == .image } }
}

// MARK: - Tool results

struct PiToolResult: Equatable {
    var content: [PiContentBlock] = []
    var details: JSONValue?
    var isError: Bool = false

    init(json: JSONValue?) {
        content = json?.array("content")?.map(PiContentBlock.init(json:)) ?? []
        details = json?["details"]
        isError = json?.bool("isError") ?? false
    }

    var text: String {
        content.map { block -> String in
            switch block.kind {
            case .text: return block.text
            case .image: return "[image]"
            default: return ""
            }
        }.joined()
    }

    var truncation: (truncated: Bool, fullOutputPath: String?)? {
        guard let truncation = details?["truncation"], !truncation.isNull else { return nil }
        return (truncation.bool("truncated") ?? false, truncation.string("fullOutputPath"))
    }
}

// MARK: - Commands and responses

struct RPCResponse: Equatable {
    var id: String?
    var command: String
    var success: Bool
    var error: String?
    var data: JSONValue?

    init(json: JSONValue) {
        id = json.string("id")
        command = json.string("command") ?? "unknown"
        success = json.bool("success") ?? false
        error = json.string("error")
        data = json["data"]
    }
}

/// Outgoing RPC commands. Every case maps to one documented command.
enum RPCCommand {
    case getState
    case getMessages
    case getAvailableModels
    case getAvailableThinkingLevels
    case getCommands
    case getSessionStats
    case getEntries(since: String?)
    case getTree
    case getForkMessages
    case getLastAssistantText
    case setModel(provider: String, modelId: String)
    case cycleModel
    case setThinkingLevel(level: String)
    case cycleThinkingLevel
    case setSteeringMode(mode: String)
    case setFollowUpMode(mode: String)
    case setAutoCompaction(enabled: Bool)
    case setAutoRetry(enabled: Bool)
    case setSessionName(name: String)
    case prompt(message: String, images: [PiImagePayload], behavior: StreamingBehavior?)
    case steer(message: String, images: [PiImagePayload])
    case followUp(message: String, images: [PiImagePayload])
    case abort
    case abortRetry
    case abortBash
    case clearQueue
    case newSession(parentSession: String?)
    case switchSession(path: String)
    case fork(entryId: String)
    case clone
    case compact(customInstructions: String?)
    case exportHTML(outputPath: String?)
    case bash(command: String)

    enum StreamingBehavior: String {
        case steer
        case followUp
    }

    var name: String {
        switch self {
        case .getState: return "get_state"
        case .getMessages: return "get_messages"
        case .getAvailableModels: return "get_available_models"
        case .getAvailableThinkingLevels: return "get_available_thinking_levels"
        case .getCommands: return "get_commands"
        case .getSessionStats: return "get_session_stats"
        case .getEntries: return "get_entries"
        case .getTree: return "get_tree"
        case .getForkMessages: return "get_fork_messages"
        case .getLastAssistantText: return "get_last_assistant_text"
        case .setModel: return "set_model"
        case .cycleModel: return "cycle_model"
        case .setThinkingLevel: return "set_thinking_level"
        case .cycleThinkingLevel: return "cycle_thinking_level"
        case .setSteeringMode: return "set_steering_mode"
        case .setFollowUpMode: return "set_follow_up_mode"
        case .setAutoCompaction: return "set_auto_compaction"
        case .setAutoRetry: return "set_auto_retry"
        case .setSessionName: return "set_session_name"
        case .prompt: return "prompt"
        case .steer: return "steer"
        case .followUp: return "follow_up"
        case .abort: return "abort"
        case .abortRetry: return "abort_retry"
        case .abortBash: return "abort_bash"
        case .clearQueue: return "clear_queue"
        case .newSession: return "new_session"
        case .switchSession: return "switch_session"
        case .fork: return "fork"
        case .clone: return "clone"
        case .compact: return "compact"
        case .exportHTML: return "export_html"
        case .bash: return "bash"
        }
    }

    func json(id: String) -> JSONValue {
        var object: [String: JSONValue] = ["id": .string(id), "type": .string(name)]
        switch self {
        case .prompt(let message, let images, let behavior):
            object["message"] = .string(message)
            if !images.isEmpty { object["images"] = .array(images.map(\.json)) }
            if let behavior { object["streamingBehavior"] = .string(behavior.rawValue) }
        case .steer(let message, let images), .followUp(let message, let images):
            object["message"] = .string(message)
            if !images.isEmpty { object["images"] = .array(images.map(\.json)) }
        case .setModel(let provider, let modelId):
            object["provider"] = .string(provider)
            object["modelId"] = .string(modelId)
        case .setThinkingLevel(let level):
            object["level"] = .string(level)
        case .setSteeringMode(let mode):
            object["mode"] = .string(mode)
        case .setFollowUpMode(let mode):
            object["mode"] = .string(mode)
        case .setAutoCompaction(let enabled), .setAutoRetry(let enabled):
            object["enabled"] = .bool(enabled)
        case .setSessionName(let name):
            object["name"] = .string(name)
        case .newSession(let parent):
            if let parent { object["parentSession"] = .string(parent) }
        case .switchSession(let path):
            object["sessionPath"] = .string(path)
        case .fork(let entryId):
            object["entryId"] = .string(entryId)
        case .compact(let instructions):
            if let instructions { object["customInstructions"] = .string(instructions) }
        case .exportHTML(let outputPath):
            if let outputPath { object["outputPath"] = .string(outputPath) }
        case .bash(let command):
            object["command"] = .string(command)
        case .getEntries(let since):
            if let since { object["since"] = .string(since) }
        default:
            break
        }
        return .object(object)
    }
}

struct PiImagePayload: Equatable {
    var data: String
    var mimeType: String

    var json: JSONValue {
        .object(["type": .string("image"), "data": .string(data), "mimeType": .string(mimeType)])
    }
}

// MARK: - Commands, skills, and prompt templates from `get_commands`

struct PiCommand: Identifiable, Equatable, Hashable {
    enum Source: String {
        case session
        case `extension`
        case prompt
        case skill
        case unknown
    }

    var id: String { name }
    var name: String
    var description: String
    var source: Source
    var location: String?
    var path: String?

    init(json: JSONValue) {
        name = json.string("name") ?? ""
        description = json.string("description") ?? ""
        source = Source(rawValue: json.string("source") ?? "") ?? .unknown
        location = json.string("location")
        path = json.string("path")
    }

    var invocation: String {
        name.hasPrefix("/") ? name : "/" + name
    }

    var sourceLabel: String {
        switch source {
        case .session: return "Session"
        case .`extension`: return "Extension"
        case .prompt: return "Prompt"
        case .skill: return "Skill"
        case .unknown: return "Command"
        }
    }

    var scopeLabel: String? {
        switch location {
        case "user": return "user"
        case "project": return "project"
        case "path": return "path"
        default: return nil
        }
    }
}

// MARK: - Session state, stats, and tree

struct PiSessionState: Equatable {
    var model: PiModel?
    var thinkingLevel: String?
    var isStreaming = false
    var isCompacting = false
    var steeringMode: String = "one-at-a-time"
    var followUpMode: String = "one-at-a-time"
    var sessionFile: String?
    var sessionId: String?
    var sessionName: String?
    var autoCompactionEnabled = true
    var autoRetryEnabled = true
    var messageCount = 0
    var pendingMessageCount = 0

    init(json: JSONValue?) {
        model = json?.object("model").flatMap(PiModel.init(json:))
        thinkingLevel = json?.string("thinkingLevel")
        isStreaming = json?.bool("isStreaming") ?? false
        isCompacting = json?.bool("isCompacting") ?? false
        steeringMode = json?.string("steeringMode") ?? "one-at-a-time"
        followUpMode = json?.string("followUpMode") ?? "one-at-a-time"
        sessionFile = json?.string("sessionFile")
        sessionId = json?.string("sessionId")
        sessionName = json?.string("sessionName")
        autoCompactionEnabled = json?.bool("autoCompactionEnabled") ?? true
        autoRetryEnabled = json?.bool("autoRetryEnabled") ?? true
        messageCount = json?.int("messageCount") ?? 0
        pendingMessageCount = json?.int("pendingMessageCount") ?? 0
    }
}

struct PiContextUsage: Equatable {
    var tokens: Int?
    var contextWindow: Int?
    var percent: Double?

    init(json: JSONValue?) {
        tokens = json?.int("tokens")
        contextWindow = json?.int("contextWindow")
        percent = json?.double("percent")
    }
}

struct PiSessionStats: Equatable {
    var sessionFile: String?
    var sessionId: String?
    var userMessages = 0
    var assistantMessages = 0
    var toolCalls = 0
    var toolResults = 0
    var totalMessages = 0
    var tokens = PiUsage.zero
    var cost: Double = 0
    var contextUsage: PiContextUsage?

    init(json: JSONValue?) {
        sessionFile = json?.string("sessionFile")
        sessionId = json?.string("sessionId")
        userMessages = json?.int("userMessages") ?? 0
        assistantMessages = json?.int("assistantMessages") ?? 0
        toolCalls = json?.int("toolCalls") ?? 0
        toolResults = json?.int("toolResults") ?? 0
        totalMessages = json?.int("totalMessages") ?? 0
        tokens = PiUsage(json: json?.object("tokens"))
        cost = json?.double("cost") ?? 0
        if json?["contextUsage"] != nil { contextUsage = PiContextUsage(json: json?["contextUsage"]) }
    }
}

struct PiSessionEntry: Identifiable, Equatable {
    var id: String
    var parentId: String?
    var type: String
    var timestamp: Date?
    var message: PiMessage?
    var summary: String?
    var label: String?
    var targetId: String?
    var customType: String?
    var provider: String?
    var modelId: String?
    var thinkingLevel: String?
    var name: String?
    /// Tokens in the branch before a compaction entry, when present.
    var tokensBefore: Int?
    var raw: JSONValue = .null

    init(json: JSONValue) {
        id = json.string("id") ?? UUID().uuidString
        parentId = json.string("parentId")
        type = json.string("type") ?? "unknown"
        raw = json
        if let iso = json.string("timestamp") {
            timestamp = ISO8601DateFormatter.piCode.date(from: iso)
        }
        if let messageJSON = json.object("message") { message = PiMessage(raw: messageJSON) }
        summary = json.string("summary")
        label = json.string("label")
        targetId = json.string("targetId")
        customType = json.string("customType")
        provider = json.string("provider")
        modelId = json.string("modelId")
        thinkingLevel = json.string("thinkingLevel")
        name = json.string("name")
        tokensBefore = json.int("tokensBefore")
    }

    /// Short human label used by the Tree inspector.
    var displayLabel: String {
        switch type {
        case "message":
            guard let message else { return "message" }
            switch message.role {
            case "user": return "User: " + message.textContent.oneLinePreview(limit: 80)
            case "assistant": return "Assistant: " + message.textContent.oneLinePreview(limit: 80)
            case "toolResult": return "Tool result: \(message.toolName ?? "tool")"
            case "bashExecution": return "Bash: " + (message.command ?? "").oneLinePreview(limit: 60)
            case "branchSummary": return "Branch summary"
            case "compactionSummary": return "Compaction summary"
            case "custom": return "Extension: \(message.customType ?? "custom")"
            default: return message.role
            }
        case "model_change": return "Model: \(provider ?? "?")/\(modelId ?? "?")"
        case "thinking_level_change": return "Thinking: \(thinkingLevel ?? "?")"
        case "compaction": return "Compaction (\(tokensBefore ?? 0) tokens before)"
        case "branch_summary": return "Branch summary"
        case "custom": return "Extension state: \(customType ?? "custom")"
        case "custom_message": return "Extension message: \(customType ?? "custom")"
        case "label": return "Label: \(label ?? "(cleared)")"
        case "session_info": return "Session name: \(name ?? "")"
        default: return type
        }
    }

    var systemImage: String {
        switch type {
        case "message":
            switch message?.role {
            case "user": return "person"
            case "assistant": return "sparkles"
            case "toolResult": return "wrench.and.screwdriver"
            case "bashExecution": return "terminal"
            default: return "text.bubble"
            }
        case "model_change": return "cpu"
        case "thinking_level_change": return "brain"
        case "compaction": return "arrow.down.right.and.arrow.up.left"
        case "branch_summary": return "arrow.triangle.branch"
        case "label": return "bookmark"
        case "session_info": return "tag"
        default: return "circle"
        }
    }
}

struct PiTreeNode: Identifiable, Equatable {
    var entry: PiSessionEntry
    var children: [PiTreeNode]
    var label: String?
    var labelTimestamp: Date?

    var id: String { entry.id }

    init(json: JSONValue) {
        entry = PiSessionEntry(json: json.object("entry") ?? .null)
        children = json.array("children")?.map(PiTreeNode.init(json:)) ?? []
        label = json.string("label")
        if let iso = json.string("labelTimestamp") {
            labelTimestamp = ISO8601DateFormatter.piCode.date(from: iso)
        }
    }

    /// Depth-first flattening with depth, used for the outline list.
    func flattened(depth: Int = 0) -> [(node: PiTreeNode, depth: Int)] {
        var result: [(PiTreeNode, Int)] = [(self, depth)]
        for child in children {
            result.append(contentsOf: child.flattened(depth: depth + 1))
        }
        return result
    }
}

struct PiForkPoint: Identifiable, Equatable {
    var entryId: String
    var text: String

    var id: String { entryId }

    init(json: JSONValue) {
        entryId = json.string("entryId") ?? ""
        text = json.string("text") ?? ""
    }
}

struct PiCompactionResult: Equatable {
    var summary: String
    var firstKeptEntryId: String?
    var tokensBefore: Int?
    var estimatedTokensAfter: Int?
    var usage: PiUsage?

    init(json: JSONValue?) {
        summary = json?.string("summary") ?? ""
        firstKeptEntryId = json?.string("firstKeptEntryId")
        tokensBefore = json?.int("tokensBefore")
        estimatedTokensAfter = json?.int("estimatedTokensAfter")
        if json?["usage"] != nil { usage = PiUsage(json: json?["usage"]) }
    }
}

// MARK: - Extension UI

struct ExtensionUIRequest: Identifiable, Equatable {
    enum Method: Equatable {
        case select
        case confirm
        case input
        case editor
        case notify
        case setStatus
        case setWidget
        case setTitle
        case setEditorText
        case unsupported(String)
    }

    var id: String
    var method: Method
    var title: String?
    var message: String?
    var options: [String]
    var placeholder: String?
    var prefill: String?
    var timeout: Double?
    var notifyType: String?
    var statusKey: String?
    var statusText: String?
    var widgetKey: String?
    var widgetLines: [String]?
    var widgetPlacement: String?
    var text: String?
    var raw: JSONValue

    var isDialog: Bool {
        switch method {
        case .select, .confirm, .input, .editor: return true
        default: return false
        }
    }

    init(json: JSONValue) {
        id = json.string("id") ?? UUID().uuidString
        raw = json
        let rawMethod = json.string("method") ?? "unknown"
        switch rawMethod {
        case "select": method = .select
        case "confirm": method = .confirm
        case "input": method = .input
        case "editor": method = .editor
        case "notify": method = .notify
        case "setStatus": method = .setStatus
        case "setWidget": method = .setWidget
        case "setTitle": method = .setTitle
        case "set_editor_text": method = .setEditorText
        default: method = .unsupported(rawMethod)
        }
        methodName = rawMethod
        title = json.string("title")
        message = json.string("message")
        options = json.array("options")?.compactMap(\.stringValue) ?? []
        placeholder = json.string("placeholder")
        prefill = json.string("prefill")
        timeout = json.double("timeout")
        notifyType = json.string("notifyType")
        statusKey = json.string("statusKey")
        statusText = json.string("statusText")
        widgetKey = json.string("widgetKey")
        widgetLines = json.array("widgetLines")?.compactMap(\.stringValue)
        widgetPlacement = json.string("widgetPlacement")
        text = json.string("text")
    }

    /// Raw method name, kept for diagnostics and compatibility cards.
    var methodName: String = "unknown"

    func valueResponse(_ value: String) -> JSONValue {
        .object(["type": .string("extension_ui_response"), "id": .string(id), "value": .string(value)])
    }

    func confirmResponse(_ confirmed: Bool) -> JSONValue {
        .object(["type": .string("extension_ui_response"), "id": .string(id), "confirmed": .bool(confirmed)])
    }

    func cancelResponse() -> JSONValue {
        .object(["type": .string("extension_ui_response"), "id": .string(id), "cancelled": .bool(true)])
    }
}

/// TUI-only extension surfaces that RPC cannot render. Surfaced as explicit
/// compatibility cards rather than silently ignored.
struct ExtensionCompatibilityNotice: Identifiable, Equatable {
    var id = UUID()
    var surface: String
    var detail: String
}

// MARK: - Date helpers

extension ISO8601DateFormatter {
    static let piCode: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

extension String {
    /// Collapses newlines for compact list rows.
    func oneLinePreview(limit: Int = 120) -> String {
        let collapsed = split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if collapsed.count <= limit { return collapsed }
        let index = collapsed.index(collapsed.startIndex, offsetBy: limit)
        return String(collapsed[..<index]) + "…"
    }
}
