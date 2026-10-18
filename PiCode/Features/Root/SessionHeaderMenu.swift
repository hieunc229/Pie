//
//  SessionHeaderMenu.swift
//  PiCode
//
//  The "…" dropdown in the titlebar: actions for the chat on screen.
//

import SwiftUI

struct SessionHeaderMenu: View {
    var isPinned: Bool
    var onCommand: (PaletteCommand) -> Void
    var onTogglePin: () -> Void

    var body: some View {
        Menu {
            Button { onCommand(.renameSession) } label: { Label("Rename", huge: "edit-02") }
            Button(action: onTogglePin) {
                Label(isPinned ? "Unpin" : "Pin", huge: isPinned ? "bookmark-01" : "bookmark-01")
            }

            Divider()

            Button { onCommand(.newSession) } label: { Label("New chat", huge: "add-01") }
            Menu {
                Button("Fork from last message…") { onCommand(.forkLatest) }
                Button("Clone this chat") { onCommand(.cloneSession) }
            } label: { Label("Fork", huge: "git-branch") }

            Divider()

            Button { onCommand(.exportSession) } label: { Label("Export as HTML…", huge: "arrow-up-right-01") }
            Menu {
                Button("Copy transcript") { onCommand(.copyTranscript) }
                Button("Copy last response") { onCommand(.copyLastResponse) }
            } label: { Label("Copy", huge: "copy-01") }

            Divider()

            Button { onCommand(.openInTerminal) } label: { Label("Open in Terminal", huge: "terminal") }
            Button { onCommand(.revealInFinder) } label: { Label("Open in Finder", huge: "folder-02") }
            Button { onCommand(.openInVSCode) } label: { Label("Open in VS Code", huge: "code") }

            Divider()

            Button(role: .destructive) { onCommand(.deleteSession) } label: {
                Label("Delete", huge: "delete-01")
            }
        } label: {
            HugeIcon(name: "more-horizontal", size: AppRailMetrics.iconSize)
                .frame(width: TitlebarIconButton.size, height: TitlebarIconButton.size)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Chat actions")
        .accessibilityLabel("Chat actions")
    }
}
