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
            Button { onCommand(.renameSession) } label: { Label("Rename", iconsax: "edit-2") }
            Button(action: onTogglePin) {
                Label(isPinned ? "Unpin" : "Pin", iconsax: isPinned ? "bookmark" : "bookmark")
            }

            Divider()

            Button { onCommand(.newSession) } label: { Label("New chat", iconsax: "message-add") }
            Menu {
                Button("Fork from last message…") { onCommand(.forkLatest) }
                Button("Clone this chat") { onCommand(.cloneSession) }
            } label: { Label("Fork", iconsax: "hierarchy-2") }

            Divider()

            Button { onCommand(.exportSession) } label: { Label("Export as HTML…", iconsax: "export") }
            Menu {
                Button("Copy transcript") { onCommand(.copyTranscript) }
                Button("Copy last response") { onCommand(.copyLastResponse) }
            } label: { Label("Copy", iconsax: "copy") }

            Divider()

            Button { onCommand(.openInTerminal) } label: { Label("Open in Terminal", iconsax: "command-square") }
            Button { onCommand(.revealInFinder) } label: { Label("Open in Finder", iconsax: "folder-2") }
            Button { onCommand(.openInVSCode) } label: { Label("Open in VS Code", iconsax: "code") }

            Divider()

            Button(role: .destructive) { onCommand(.deleteSession) } label: {
                Label("Delete", iconsax: "trash")
            }
        } label: {
            IconsaxIcon(name: "more")
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
