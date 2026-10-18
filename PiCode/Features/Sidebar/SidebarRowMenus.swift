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
                Label("New chat", huge: "add-01")
            }

            Divider()

            Button {
                state.openTerminal(at: project.path)
            } label: {
                Label("Open in Terminal", huge: "terminal")
            }
            Button {
                WorkspaceLauncher.reveal(project.path)
            } label: {
                Label("Reveal in Finder", huge: "folder-02")
            }
            Button {
                state.copyToPasteboard(project.path)
            } label: {
                Label("Copy Path", huge: "copy-01")
            }
            Button {
                state.togglePin(project: project)
            } label: {
                Label(
                    project.isPinned ? "Unpin Project" : "Pin Project",
                    huge: project.isPinned ? "bookmark-01" : "bookmark-01"
                )
            }

            Divider()

            Button {
                state.presentProjectSettings(project)
            } label: {
                Label("Settings…", huge: "settings-02")
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
                    Label("Keep Working", huge: "arrow-right-01")
                }
            } else {
                Button {
                    Task { await state.open(session: session) }
                } label: {
                    Label("Open", huge: "arrow-right-01")
                }
            }

            Button {
                state.presentRename(session: session)
            } label: {
                Label("Rename…", huge: "edit-02")
            }
            Button {
                state.togglePin(session: session)
            } label: {
                Label(
                    session.isPinned ? "Unpin" : "Pin",
                    huge: session.isPinned ? "bookmark-01" : "bookmark-01"
                )
            }

            Divider()

            Button {
                if let path = session.filePath { state.copyToPasteboard(path) }
            } label: {
                Label("Copy Session Path", huge: "copy-01")
            }
            .disabled(session.filePath == nil)
            Button {
                if let path = session.filePath { WorkspaceLauncher.reveal(path) }
            } label: {
                Label("Reveal Session File", huge: "file-01")
            }
            .disabled(session.filePath == nil)
            Button {
                Task { await state.hide(session: session) }
            } label: {
                Label("Hide from Sidebar", huge: "view-off")
            }

            Divider()

            Button(role: .destructive) {
                state.sessionPendingDeletion = session
                state.run(.deleteSession)
            } label: {
                Label("Delete Session…", huge: "delete-01")
            }
            .disabled(session.filePath == nil)
        }
    }
}
