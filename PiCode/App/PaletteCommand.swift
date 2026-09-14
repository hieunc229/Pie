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
    case showChanges
    case showFiles
    case showTerminal
    case showTree
    case showContext

    case copyTranscript
    case copyLastResponse
    case openInTerminal
    case revealInFinder
    case revealPiDirectory

    case openSettings
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
        case .showChanges: return "Show Changes"
        case .showFiles: return "Show Files"
        case .showTerminal: return "Show Terminal"
        case .showTree: return "Show Tree"
        case .showContext: return "Show Context"
        case .copyTranscript: return "Copy Transcript"
        case .copyLastResponse: return "Copy Last Response"
        case .openInTerminal: return "Open Project in Terminal"
        case .revealInFinder: return "Reveal Project in Finder"
        case .revealPiDirectory: return "Reveal Pi's Config Folder"
        case .openSettings: return "Settings…"
        case .showPiSetup: return "Pi Setup Help"
        case .checkForPiUpdates: return "Check Pi Version"
        }
    }

    var systemImage: String {
        switch self {
        case .newSession: return "plus.bubble"
        case .addProject: return "folder.badge.plus"
        case .refreshSessions: return "arrow.clockwise"
        case .renameSession: return "pencil"
        case .cloneSession: return "doc.on.doc"
        case .forkLatest: return "arrow.triangle.branch"
        case .compactContext, .compactWithInstructions: return "arrow.down.right.and.arrow.up.left"
        case .exportSession: return "square.and.arrow.up"
        case .deleteSession: return "trash"
        case .focusComposer: return "text.cursor"
        case .interrupt: return "escape"
        case .abortRun: return "stop.circle"
        case .cycleModel: return "cpu"
        case .cycleThinkingLevel: return "brain"
        case .toggleInspector: return "sidebar.right"
        case .toggleSidebar: return "sidebar.left"
        case .showChanges: return "plusminus.circle"
        case .showFiles: return "folder"
        case .showTerminal: return "terminal"
        case .showTree: return "point.topleft.down.to.point.bottomright.curvepath"
        case .showContext: return "chart.pie"
        case .copyTranscript: return "doc.on.clipboard"
        case .copyLastResponse: return "text.badge.checkmark"
        case .openInTerminal: return "terminal"
        case .revealInFinder: return "folder.circle"
        case .revealPiDirectory: return "gearshape.2"
        case .openSettings: return "gearshape"
        case .showPiSetup: return "questionmark.circle"
        case .checkForPiUpdates: return "arrow.triangle.2.circlepath.circle"
        }
    }

    /// Actions that only make sense with a live session.
    var requiresSession: Bool {
        switch self {
        case .newSession, .addProject, .refreshSessions, .toggleInspector, .toggleSidebar,
             .openSettings, .showPiSetup, .checkForPiUpdates, .revealPiDirectory,
             .showChanges, .showFiles, .showTerminal, .showTree, .showContext:
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
        case .toggleInspector, .toggleSidebar, .showChanges, .showFiles, .showTerminal,
             .showTree, .showContext:
            return .view
        case .copyTranscript, .copyLastResponse, .openInTerminal, .revealInFinder, .revealPiDirectory:
            return .share
        case .openSettings, .showPiSetup, .checkForPiUpdates:
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
