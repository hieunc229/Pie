//
//  SidebarHeader.swift
//  PiCode
//
//  The sidebar's title line: the harness new chats run on, as a menu, then
//  search on the trailing edge.
//

import SwiftUI

struct SidebarHeader: View {
    @Bindable var state: AppState
    var onOpenPalette: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            harnessMenu
            Spacer(minLength: 0)
            headerButton("search-normal", help: "Search sessions and commands (⇧⌘P)", action: onOpenPalette)
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
                        Label(harness.displayName, iconsax: "tick-circle")
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
                + Text(iconsaxImage("arrow-down-2"))
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

    private func headerButton(_ systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            IconsaxIcon(name: systemImage)
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
