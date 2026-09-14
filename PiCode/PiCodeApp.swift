//
//  PiCodeApp.swift
//  PiCode
//
//  A native macOS client for Pi Coding Agent.
//
//  PiCode is not a fork of Pi and does not reimplement its agent loop. It hosts
//  the user's own `pi` binary over Pi's documented RPC mode and renders the
//  result with native AppKit/SwiftUI surfaces.
//

import SwiftUI

@main
struct PiCodeApp: App {
    @State private var state = AppState()

    var body: some Scene {
        WindowGroup {
            RootView(state: state)
                .frame(minWidth: 900, minHeight: 560)
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands { PiCodeCommands(state: state) }

        Settings {
            SettingsView(state: state)
        }
    }
}

/// Menu bar commands. Every entry routes through the same `PaletteCommand` list
/// the command palette uses, so the two can never drift apart.
struct PiCodeCommands: Commands {
    let state: AppState

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(PaletteCommand.newSession.title) { state.run(.newSession) }
                .keyboardShortcut("n", modifiers: .command)
            Button(PaletteCommand.addProject.title) { state.run(.addProject) }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            Divider()
            Button(PaletteCommand.openInTerminal.title) { state.run(.openInTerminal) }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .disabled(state.activeController == nil)
        }

        CommandMenu("Session") {
            Button(PaletteCommand.renameSession.title) { state.run(.renameSession) }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(state.activeController == nil)
            Button(PaletteCommand.cloneSession.title) { state.run(.cloneSession) }
                .disabled(state.activeController == nil)
            Button(PaletteCommand.forkLatest.title) { state.run(.forkLatest) }
                .disabled(state.activeController == nil)
            Divider()
            Button(PaletteCommand.compactContext.title) { state.run(.compactContext) }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(state.activeController == nil)
            Button(PaletteCommand.compactWithInstructions.title) { state.run(.compactWithInstructions) }
                .disabled(state.activeController == nil)
            Divider()
            Button(PaletteCommand.exportSession.title) { state.run(.exportSession) }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(state.activeController == nil)
            Button(PaletteCommand.copyTranscript.title) { state.run(.copyTranscript) }
                .disabled(state.activeController == nil)
            Button(PaletteCommand.copyLastResponse.title) { state.run(.copyLastResponse) }
                .disabled(state.activeController == nil)
            Divider()
            Button(PaletteCommand.deleteSession.title) { state.run(.deleteSession) }
                .disabled(state.activeController == nil)
        }

        CommandMenu("Agent") {
            Button(PaletteCommand.focusComposer.title) { state.run(.focusComposer) }
                .keyboardShortcut("l", modifiers: .command)
                .disabled(state.activeController == nil)
            Button(PaletteCommand.interrupt.title) { state.run(.interrupt) }
                .disabled(state.activeController == nil)
            Button(PaletteCommand.abortRun.title) { state.run(.abortRun) }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(state.activeController == nil)
            Divider()
            Button(PaletteCommand.cycleModel.title) { state.run(.cycleModel) }
                .disabled(state.activeController == nil)
            Button(PaletteCommand.cycleThinkingLevel.title) { state.run(.cycleThinkingLevel) }
                .disabled(state.activeController == nil)
            Divider()
            Button(PaletteCommand.refreshSessions.title) { state.run(.refreshSessions) }
                .keyboardShortcut("r", modifiers: .command)
        }

        CommandGroup(after: .sidebar) {
            Button(PaletteCommand.toggleInspector.title) { state.run(.toggleInspector) }
                .keyboardShortcut("i", modifiers: [.command, .option])
            Button(PaletteCommand.toggleSidebar.title) { state.run(.toggleSidebar) }
                .keyboardShortcut("s", modifiers: [.control, .command])
        }
    }
}
