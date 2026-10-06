//
//  SidebarHeader.swift
//  PiCode
//
//  The sidebar's title line: the harness new chats run on, as a menu, then
//  notifications and search on the trailing edge.
//

import SwiftUI

struct SidebarHeader: View {
    @Bindable var state: AppState
    var onOpenPalette: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            harnessMenu
            Spacer(minLength: 0)
            notificationsButton
            headerButton("magnifyingglass", help: "Search sessions and commands (⇧⌘P)", action: onOpenPalette)
        }
        .padding(.leading, SidebarStyle.trafficLightColumn - 2)
        .padding(.trailing, SidebarStyle.sidebarMargin)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    /// The default harness's name as the sidebar's title. Choosing another one
    /// changes what *new* chats run on; open chats keep their own runtime.
    private var harnessMenu: some View {
        Menu {
            ForEach(state.harnesses.usableHarnesses, id: \.id) { harness in
                Button {
                    state.preferences.defaultHarnessID = harness.id
                    state.preferences.persist()
                } label: {
                    if harness.id == currentHarness.id {
                        Label(harness.displayName, systemImage: "checkmark")
                    } else {
                        Text(harness.displayName)
                    }
                }
            }
            Divider()
            Button("Manage Harnesses…") {
                state.openSettings(tab: .harnesses)
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
        } label: {
            // One `Text`, because a borderless menu snapshots its label and lays
            // an `HStack`'s parts out in its own order.
            (Text(currentHarness.displayName)
                .font(.system(size: 17, weight: .semibold))
                + Text("  ")
                + Text(Image(systemName: "chevron.down"))
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary))
            .lineLimit(1)
            .truncationMode(.tail)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        // Not `fixedSize()`: a long harness name ends in an ellipsis inside the
        // room the buttons leave, instead of pushing them (and the list's
        // geometry) around. Capped so it never crowds the trailing buttons.
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: 160, alignment: .leading)
        .help(currentHarness.displayName + " — the harness new chats run on")
    }

    private var currentHarness: HarnessDescriptor {
        state.harnesses.usableHarnesses.first { $0.id == state.preferences.defaultHarnessID }
            ?? state.activeHarness
    }

    private var notificationsButton: some View {
        Button {
            state.toggleNotifications()
        } label: {
            Image(systemName: "bell")
                .font(.system(size: 14, weight: .regular))
                .frame(width: 28, height: 28)
                .overlay(alignment: .topTrailing) {
                    if state.unreadNotificationCount > 0 {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 7, height: 7)
                            .offset(x: -6, y: 6)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(state.isShowingNotifications ? Color.primary : Color.secondary)
        .help(state.isShowingNotifications ? "Hide notifications" : "Show notifications")
        .accessibilityLabel(state.unreadNotificationCount > 0
            ? "Notifications, \(state.unreadNotificationCount) unread"
            : "Notifications")
    }

    private func headerButton(_ systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .regular))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
        .accessibilityLabel(help)
    }
}
