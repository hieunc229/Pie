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
            Button { onCommand(.renameSession) } label: { Label("Rename", systemImage: "pencil") }
            Button(action: onTogglePin) {
                Label(isPinned ? "Unpin" : "Pin", systemImage: isPinned ? "pin.slash" : "pin")
            }

            Divider()

            Button { onCommand(.newSession) } label: { Label("New chat", systemImage: "plus.bubble") }
            Menu {
                Button("Fork from last message…") { onCommand(.forkLatest) }
                Button("Clone this chat") { onCommand(.cloneSession) }
            } label: { Label("Fork", systemImage: "arrow.triangle.branch") }

            Divider()

            Button { onCommand(.exportSession) } label: { Label("Export as HTML…", systemImage: "square.and.arrow.up") }
            Menu {
                Button("Copy transcript") { onCommand(.copyTranscript) }
                Button("Copy last response") { onCommand(.copyLastResponse) }
            } label: { Label("Copy", systemImage: "square.on.square") }

            Divider()

            Menu {
                Button("Terminal") { onCommand(.openInTerminal) }
                Button("Finder") { onCommand(.revealInFinder) }
                Button("VS Code") { onCommand(.openInVSCode) }
            } label: { Label("Open in", systemImage: "arrow.up.right") }

            Divider()

            Button(role: .destructive) { onCommand(.deleteSession) } label: {
                Label("Delete", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .regular))
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
