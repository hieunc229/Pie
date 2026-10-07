//
//  SidebarRowMenus.swift
//  PiCode
//
//  Shared menu content for sidebar rows. The same actions are presented by the
//  trailing ellipsis button and by a native right-click context menu.
//

import SwiftUI

struct ProjectRowMenu: View {
    @Bindable var state: AppState
    var project: ProjectGroup

    var body: some View {
        Group {
            Button {
                Task { await state.startNewSession(projectPath: project.path) }
            } label: {
                Label("New chat", iconsax: "edit-2")
            }

            Divider()

            Button {
                state.openTerminal(at: project.path)
            } label: {
                Label("Open in Terminal", iconsax: "command-square")
            }
            Button {
                WorkspaceLauncher.reveal(project.path)
            } label: {
                Label("Reveal in Finder", iconsax: "folder-2")
            }
            Button {
                state.copyToPasteboard(project.path)
            } label: {
                Label("Copy Path", iconsax: "document-copy")
            }
            Button {
                state.togglePin(project: project)
            } label: {
                Label(
                    project.isPinned ? "Unpin Project" : "Pin Project",
                    iconsax: project.isPinned ? "bookmark" : "bookmark"
                )
            }

            Divider()

            Button {
                state.presentProjectSettings(project)
            } label: {
                Label("Settings…", iconsax: "setting-2")
            }
        }
    }
}

struct SessionRowMenu: View {
    @Bindable var state: AppState
    var session: SessionRef
    var isEphemeral: Bool

    var body: some View {
        Group {
            if isEphemeral {
                Button {
                    Task { await state.open(session: session) }
                } label: {
                    Label("Keep Working", iconsax: "arrow-circle-right")
                }
            } else {
                Button {
                    Task { await state.open(session: session) }
                } label: {
                    Label("Open", iconsax: "arrow-circle-right")
                }
            }

            Button {
                state.presentRename(session: session)
            } label: {
                Label("Rename…", iconsax: "edit-2")
            }
            Button {
                state.togglePin(session: session)
            } label: {
                Label(
                    session.isPinned ? "Unpin" : "Pin",
                    iconsax: session.isPinned ? "bookmark" : "bookmark"
                )
            }

            Divider()

            Button {
                if let path = session.filePath { state.copyToPasteboard(path) }
            } label: {
                Label("Copy Session Path", iconsax: "document-copy")
            }
            .disabled(session.filePath == nil)
            Button {
                if let path = session.filePath { WorkspaceLauncher.reveal(path) }
            } label: {
                Label("Reveal Session File", iconsax: "document")
            }
            .disabled(session.filePath == nil)
            Button {
                Task { await state.hide(session: session) }
            } label: {
                Label("Hide from Sidebar", iconsax: "eye-slash")
            }

            Divider()

            Button(role: .destructive) {
                state.sessionPendingDeletion = session
                state.run(.deleteSession)
            } label: {
                Label("Delete Session…", iconsax: "trash")
            }
            .disabled(session.filePath == nil)
        }
    }
}
