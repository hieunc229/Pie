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
                Label("New chat", systemImage: "square.and.pencil")
            }

            Divider()

            Button {
                state.openTerminal(at: project.path)
            } label: {
                Label("Open in Terminal", systemImage: "terminal")
            }
            Button {
                WorkspaceLauncher.reveal(project.path)
            } label: {
                Label("Reveal in Finder", systemImage: "folder")
            }
            Button {
                state.copyToPasteboard(project.path)
            } label: {
                Label("Copy Path", systemImage: "doc.on.doc")
            }
            Button {
                state.togglePin(project: project)
            } label: {
                Label(
                    project.isPinned ? "Unpin Project" : "Pin Project",
                    systemImage: project.isPinned ? "pin.slash" : "pin"
                )
            }

            Divider()

            Button {
                state.presentProjectSettings(project)
            } label: {
                Label("Settings…", systemImage: "gearshape")
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
                    Label("Keep Working", systemImage: "arrow.right.circle")
                }
            } else {
                Button {
                    Task { await state.open(session: session) }
                } label: {
                    Label("Open", systemImage: "arrow.right.circle")
                }
            }

            Button {
                state.presentRename(session: session)
            } label: {
                Label("Rename…", systemImage: "pencil")
            }
            Button {
                state.togglePin(session: session)
            } label: {
                Label(
                    session.isPinned ? "Unpin" : "Pin",
                    systemImage: session.isPinned ? "pin.slash" : "pin"
                )
            }

            Divider()

            Button {
                if let path = session.filePath { state.copyToPasteboard(path) }
            } label: {
                Label("Copy Session Path", systemImage: "doc.on.doc")
            }
            .disabled(session.filePath == nil)
            Button {
                if let path = session.filePath { WorkspaceLauncher.reveal(path) }
            } label: {
                Label("Reveal Session File", systemImage: "doc")
            }
            .disabled(session.filePath == nil)
            Button {
                Task { await state.hide(session: session) }
            } label: {
                Label("Hide from Sidebar", systemImage: "eye.slash")
            }

            Divider()

            Button(role: .destructive) {
                state.sessionPendingDeletion = session
                state.run(.deleteSession)
            } label: {
                Label("Delete Session…", systemImage: "trash")
            }
            .disabled(session.filePath == nil)
        }
    }
}
