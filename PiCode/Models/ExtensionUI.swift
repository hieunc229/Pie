//
//  ExtensionUI.swift
//  PiCode
//
//  Model types for the extension UI sub-protocol: blocking dialogs, footer
//  status entries, widgets, notifications, and the explicit compatibility notes
//  for surfaces that only exist in Pi's TUI.
//

import Foundation

/// A blocking dialog requested by an extension. Exactly one is presented at a
/// time; the rest queue so extensions cannot steal focus from each other.
struct ExtensionDialog: Identifiable, Equatable {
    var id: String
    var request: ExtensionUIRequest
    /// Editable text for `.input` and `.editor` methods.
    var draftText: String = ""
    /// Choice for `.select`.
    var selection: String?
    /// Set when another queued dialog is shown while this one waits.
    var queuedBehind: String?

    var title: String {
        request.title ?? defaultTitle
    }

    var defaultTitle: String {
        switch request.method {
        case .select: return "Choose an option"
        case .confirm: return "Confirm"
        case .input: return "Enter a value"
        case .editor: return "Edit text"
        default: return "Extension request"
        }
    }

    var message: String? {
        guard let message = request.message, !message.isEmpty else { return nil }
        return message
    }
}

struct ExtensionNotification: Identifiable, Equatable {
    enum Level: String {
        case info
        case warning
        case error

        var systemImage: String {
            switch self {
            case .info: return "info-circle"
            case .warning: return "warning-2"
            case .error: return "danger"
            }
        }
    }

    var id = UUID()
    var message: String
    var level: Level = .info
    var timestamp = Date()
    var extensionPath: String?

    var sourceName: String? {
        guard let extensionPath else { return nil }
        return (extensionPath as NSString).lastPathComponent
    }
}

/// One line in the session activity timeline. This is PiCode's own record of
/// runtime events (retries, compaction, errors) so the UI can explain *why*
/// something is happening without inventing information.
struct ActivityEntry: Identifiable, Equatable {
    enum Kind: String {
        case connection
        case agentStart
        case agentEnd
        case settled
        case turn
        case tool
        case compaction
        case retry
        case summarizationRetry
        case queue
        case error
        case extensionError
        case extensionRequest
        case notify
        case sessionChange

        var systemImage: String {
            switch self {
            case .connection: return "flash"
            case .agentStart: return "play-circle"
            case .agentEnd: return "stop-circle"
            case .settled: return "tick-circle"
            case .turn: return "refresh"
            case .tool: return "setting-4"
            case .compaction: return "convert"
            case .retry: return "refresh"
            case .summarizationRetry: return "clock"
            case .queue: return "task-square"
            case .error: return "warning-2"
            case .extensionError: return "category-2"
            case .extensionRequest: return "message-question"
            case .notify: return "notification"
            case .sessionChange: return "arrow-swap-horizontal"
            }
        }
    }

    var id = UUID()
    var kind: Kind
    var title: String
    var detail: String?
    var timestamp = Date()
    var isError = false
}

/// Placements Pi's RPC widget protocol supports.
enum WidgetPlacement: String, CaseIterable {
    case aboveEditor
    case belowEditor

    var label: String {
        self == .aboveEditor ? "Above composer" : "Below composer"
    }
}
