//
//  Project.swift
//  PiCode
//
//  PiCode-owned metadata about projects and sessions, plus attachment and git
//  presentation models. Pi remains the source of truth for sessions; these types
//  hold only what the sidebar, composer, and inspector need to render.
//

import Foundation

/// A working directory that Pi sessions were created in.
struct ProjectGroup: Identifiable, Equatable {
    var id: String
    /// Canonical (symlink-resolved) working directory. This is also the key the
    /// sidebar groups sessions by, and the key project settings are stored under.
    var path: String
    var name: String
    var sessions: [SessionRef]
    /// PiCode-only pin, stored in app preferences.
    var isPinned: Bool = false
    var trustState: ProjectTrustState = .unknown
    /// Folder new chats in this project start in, when the user has pointed the
    /// project somewhere else. `nil` means the project's own path. PiCode-only,
    /// stored in app preferences: Pi still writes each session under the folder it
    /// actually ran in, so existing sessions are never moved by this.
    var workingDirectory: String? = nil

    /// The folder a *new* chat in this project runs in.
    var launchDirectory: String { workingDirectory ?? path }

    var displayPath: String { launchDirectory.abbreviatingHomeDirectory }

    var mostRecentActivity: Date {
        sessions.map(\.updatedAt).max() ?? .distantPast
    }
}

/// PiCode-only per-project settings, keyed by the project's canonical path.
/// Nothing here is written to Pi configuration; these are presentation and launch
/// choices that live on this Mac alone.
struct ProjectSettings: Codable, Equatable {
    /// Sidebar/header name for the project. Empty means the folder's own name.
    var name: String = ""
    /// Folder new chats should start in. Empty means the project's own path.
    var directory: String = ""
    /// Text appended to Pi's system prompt for new sessions in this project,
    /// passed as `--append-system-prompt`.
    var systemPrompt: String = ""

    var isEmpty: Bool { name.isEmpty && directory.isEmpty && systemPrompt.isEmpty }
}

/// A Pi session file discovered on disk or created through the app.
struct SessionRef: Identifiable, Equatable {
    var id: String
    var sessionId: String?
    var filePath: String?
    var name: String?
    var cwd: String
    var createdAt: Date
    var updatedAt: Date
    var messageCount: Int
    var firstUserMessage: String?
    var parentSession: String?
    /// PiCode-only pin, stored in app preferences.
    var isPinned: Bool = false
    var isEphemeral: Bool = false

    var displayName: String {
        if let name, !name.trimmingCharacters(in: .whitespaces).isEmpty { return name }
        if let firstUserMessage, !firstUserMessage.isEmpty {
            return firstUserMessage.oneLinePreview(limit: 48)
        }
        return "New session"
    }

    var isNamed: Bool {
        !(name ?? "").trimmingCharacters(in: .whitespaces).isEmpty
    }

    var fileName: String {
        guard let filePath else { return "ephemeral" }
        return (filePath as NSString).lastPathComponent
    }
}

/// Attachment payload prepared in the composer. Images travel through Pi's RPC
/// `images` field; text files are inlined as a fenced reference so the model can
/// read them without extra tool calls.
struct Attachment: Identifiable, Equatable {
    enum Kind: Equatable {
        case image
        case text
        case other
    }

    var id = UUID()
    var kind: Kind
    var fileName: String
    var mimeType: String
    var byteSize: Int
    var path: String?
    /// Base64 image data, only for `.image`.
    var imageData: String?
    /// Extracted text content, only for `.text`.
    var textContent: String?
    var error: String?

    var systemImage: String {
        switch kind {
        case .image: return "photo"
        case .text: return "doc.text"
        case .other: return "paperclip"
        }
    }

    var displaySize: String {
        ByteCountFormatter.string(fromByteCount: Int64(byteSize), countStyle: .file)
    }

    var imagePayload: PiImagePayload? {
        guard kind == .image, let imageData else { return nil }
        return PiImagePayload(data: imageData, mimeType: mimeType)
    }

    /// Text attachments become part of the prompt body.
    var promptSnippet: String? {
        guard kind == .text else { return nil }
        let header = path.map { "@\($0)" } ?? fileName
        let body = textContent ?? ""
        return "\(header)\n```\n\(body)\n```"
    }
}

// MARK: - Git

struct GitFileChange: Identifiable, Equatable, Hashable {
    enum Status: String {
        case modified = "M"
        case added = "A"
        case deleted = "D"
        case renamed = "R"
        case copied = "C"
        case untracked = "??"
        case conflicted = "U"
        case typeChanged = "T"

        var label: String {
            switch self {
            case .modified: return "Modified"
            case .added: return "Added"
            case .deleted: return "Deleted"
            case .renamed: return "Renamed"
            case .copied: return "Copied"
            case .untracked: return "Untracked"
            case .conflicted: return "Conflicted"
            case .typeChanged: return "Type changed"
            }
        }

        var colorRole: String {
            switch self {
            case .added, .untracked: return "green"
            case .deleted: return "red"
            case .conflicted: return "orange"
            case .renamed, .copied: return "blue"
            default: return "secondary"
            }
        }
    }

    var id: String { path }
    var path: String
    var oldPath: String?
    var status: Status
    var isStaged: Bool
    var additions: Int?
    var deletions: Int?
}

struct GitRepositoryState: Equatable {
    var isRepository: Bool = false
    var root: String?
    var branch: String?
    var changes: [GitFileChange] = []
    var error: String?
    var lastUpdated: Date?

    var hasChanges: Bool { !changes.isEmpty }
    var totalAdditions: Int { changes.compactMap(\.additions).reduce(0, +) }
    var totalDeletions: Int { changes.compactMap(\.deletions).reduce(0, +) }
}

// MARK: - Runtime state

/// Connection state of the child `pi --mode rpc` process.
enum ConnectionState: Equatable {
    case idle
    case starting
    case connected
    case disconnected(reason: String?)
    case failed(message: String)

    var isConnected: Bool { self == .connected }

    var label: String {
        switch self {
        case .idle: return "Not started"
        case .starting: return "Starting"
        case .connected: return "Connected"
        case .disconnected: return "Disconnected"
        case .failed: return "Failed"
        }
    }

    var isProblem: Bool {
        switch self {
        case .disconnected, .failed: return true
        default: return false
        }
    }
}

/// State of the agent loop itself, mirrored from Pi events.
enum AgentRuntimeState: Equatable {
    case starting
    case idle
    case working
    case compacting
    case retrying(attempt: Int, maxAttempts: Int, until: Date?)
    case stopping
    case disconnected

    var label: String {
        switch self {
        case .starting: return "Starting"
        case .idle: return "Idle"
        case .working: return "Working"
        case .compacting: return "Compacting"
        case .retrying(let attempt, let maxAttempts, _): return "Retrying \(attempt)/\(maxAttempts)"
        case .stopping: return "Stopping"
        case .disconnected: return "Disconnected"
        }
    }

    var isBusy: Bool {
        switch self {
        case .working, .compacting, .retrying, .stopping: return true
        default: return false
        }
    }

    var canAcceptPrompt: Bool {
        switch self {
        case .idle, .disconnected, .starting: return true
        default: return false
        }
    }
}

/// Trust decision for a project directory, mirroring Pi's semantics.
enum ProjectTrustState: Equatable {
    /// Project has no trust-requiring resources; nothing to decide.
    case notRequired
    case unknown
    case trusted
    case untrusted
    /// Project has trust-requiring resources and no saved decision.
    case asked

    var label: String {
        switch self {
        case .notRequired: return "No project resources"
        case .unknown: return "Not evaluated"
        case .trusted: return "Trusted"
        case .untrusted: return "Not trusted"
        case .asked: return "Needs decision"
        }
    }

    var isTrusted: Bool { self == .trusted }

    var allowsProjectResources: Bool {
        switch self {
        case .trusted, .notRequired: return true
        default: return false
        }
    }
}
