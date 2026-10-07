//
//  PaletteCommand.swift
//  PiCode
//
//  The single list of actions that menus, keyboard shortcuts, and the command
//  palette all share. Views own the dispatch (they have the focused controls);
//  this file only names the actions and their presentation.
//

import Foundation

enum PaletteCommand: String, CaseIterable, Identifiable, Hashable {
    case newSession
    case addProject
    case refreshSessions
    case renameSession
    case cloneSession
    case forkLatest
    case compactContext
    case compactWithInstructions
    case exportSession
    case deleteSession

    case focusComposer
    case interrupt
    case abortRun
    case cycleModel
    case cycleThinkingLevel

    case toggleInspector
    case toggleSidebar
    case toggleTerminal

    case copyTranscript
    case copyLastResponse
    case openInTerminal
    case openInVSCode
    case revealInFinder
    case revealPiDirectory

    case openSettings
    case providersSettings
    case packages
    case showPiSetup
    case checkForPiUpdates

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newSession: return "New Session"
        case .addProject: return "Open Project Folder…"
        case .refreshSessions: return "Reload Sessions"
        case .renameSession: return "Rename Session…"
        case .cloneSession: return "Clone Current Branch"
        case .forkLatest: return "Fork…"
        case .compactContext: return "Compact Context"
        case .compactWithInstructions: return "Compact with Instructions…"
        case .exportSession: return "Export Session as HTML…"
        case .deleteSession: return "Delete Session…"
        case .focusComposer: return "Focus Composer"
        case .interrupt: return "Interrupt and Restore Queue"
        case .abortRun: return "Stop the Agent"
        case .cycleModel: return "Cycle Model"
        case .cycleThinkingLevel: return "Cycle Thinking Level"
        case .toggleInspector: return "Toggle Inspector"
        case .toggleSidebar: return "Toggle Sidebar"
        case .toggleTerminal: return "Toggle Terminal"
        case .copyTranscript: return "Copy Transcript"
        case .copyLastResponse: return "Copy Last Response"
        case .openInTerminal: return "Open Project in Terminal"
        case .openInVSCode: return "Open Project in VS Code"
        case .revealInFinder: return "Reveal Project in Finder"
        case .revealPiDirectory: return "Reveal Pi's Config Folder"
        case .openSettings: return "Settings…"
        case .providersSettings: return "Providers and Credentials…"
        case .packages: return "Packages"
        case .showPiSetup: return "Pi Setup Help"
        case .checkForPiUpdates: return "Check Pi Version"
        }
    }

    var systemImage: String {
        switch self {
        case .newSession: return "message-add"
        case .addProject: return "folder-add"
        case .refreshSessions: return "refresh"
        case .renameSession: return "edit-2"
        case .cloneSession: return "document-copy"
        case .forkLatest: return "hierarchy-2"
        case .compactContext, .compactWithInstructions: return "convert"
        case .exportSession: return "export"
        case .deleteSession: return "trash"
        case .focusComposer: return "edit-2"
        case .interrupt: return "stop"
        case .abortRun: return "stop-circle"
        case .cycleModel: return "cpu"
        case .cycleThinkingLevel: return "lamp-on"
        case .toggleInspector: return "sidebar-right"
        case .toggleSidebar: return "sidebar-left"
        case .toggleTerminal: return "command-square"
        case .copyTranscript: return "clipboard-text"
        case .copyLastResponse: return "tick-circle"
        case .openInTerminal: return "command-square"
        case .openInVSCode: return "code"
        case .revealInFinder: return "folder"
        case .revealPiDirectory: return "setting-3"
        case .openSettings: return "setting-2"
        case .providersSettings: return "key"
        case .packages: return "box"
        case .showPiSetup: return "message-question"
        case .checkForPiUpdates: return "refresh-circle"
        }
    }

    /// Actions that only make sense with a live session.
    var requiresSession: Bool {
        switch self {
        case .newSession, .addProject, .refreshSessions, .toggleInspector, .toggleSidebar,
             .toggleTerminal, .openSettings, .providersSettings, .packages, .showPiSetup,
             .checkForPiUpdates, .revealPiDirectory:
            return false
        default:
            return true
        }
    }

    /// Actions that require Pi to be idle.
    var requiresIdleAgent: Bool {
        switch self {
        case .compactContext, .compactWithInstructions, .deleteSession, .renameSession,
             .cloneSession, .forkLatest, .exportSession, .newSession:
            return true
        default:
            return false
        }
    }

    var shortcutHint: String? {
        switch self {
        case .newSession: return "⌘N"
        case .addProject: return "⇧⌘O"
        case .refreshSessions: return "⌘R"
        case .renameSession: return "⇧⌘R"
        case .compactContext: return "⌘K"
        case .exportSession: return "⇧⌘E"
        case .focusComposer: return "⌘L"
        case .interrupt: return "esc"
        case .abortRun: return "⌘."
        case .toggleInspector: return "⌥⌘I"
        case .toggleSidebar: return "⌃⌘S"
        case .toggleTerminal: return "⌃`"
        case .openSettings: return "⌘,"
        case .openInTerminal: return "⇧⌘T"
        default: return nil
        }
    }

    var group: Group {
        switch self {
        case .newSession, .addProject, .refreshSessions, .renameSession, .cloneSession,
             .forkLatest, .compactContext, .compactWithInstructions, .exportSession, .deleteSession:
            return .session
        case .focusComposer, .interrupt, .abortRun, .cycleModel, .cycleThinkingLevel:
            return .run
        case .toggleInspector, .toggleSidebar, .toggleTerminal, .packages:
            return .view
        case .copyTranscript, .copyLastResponse, .openInTerminal, .openInVSCode, .revealInFinder,
             .revealPiDirectory:
            return .share
        case .openSettings, .providersSettings, .showPiSetup, .checkForPiUpdates:
            return .app
        }
    }

    enum Group: String, CaseIterable, Identifiable {
        case session
        case run
        case view
        case share
        case app

        var id: String { rawValue }

        var label: String {
            switch self {
            case .session: return "Session"
            case .run: return "Agent"
            case .view: return "View"
            case .share: return "Share"
            case .app: return "PiCode"
            }
        }
    }
}
