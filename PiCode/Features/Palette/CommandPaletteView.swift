//
//  CommandPaletteView.swift
//  PiCode
//
//  One palette for commands and sessions.
//
//  Every entry routes through the same `PaletteCommand` enum the menu bar uses,
//  so a shortcut, a menu item, and a palette row can never drift apart.
//

import SwiftUI

struct CommandPaletteView: View {
    @Bindable var state: AppState
    var onRun: (PaletteCommand) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFieldFocused: Bool
    @State private var selectedIndex = 0

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            results
        }
        .frame(width: 560, height: 420)
        .onAppear {
            state.openPalette()
            isFieldFocused = true
        }
        .onDisappear { state.closePalette() }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "command")
                .foregroundStyle(.secondary)
            TextField("Run a command or search sessions", text: $state.paletteQuery)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($isFieldFocused)
                .onSubmit(runSelected)
                .onChange(of: state.paletteQuery) { _, _ in
                    selectedIndex = 0
                    state.updatePaletteQuery()
                }
                .onMoveCommand { direction in
                    switch direction {
                    case .up: move(-1)
                    case .down: move(1)
                    default: break
                    }
                }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var results: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !commands.isEmpty {
                        sectionHeader("Commands")
                        ForEach(Array(commands.enumerated()), id: \.element) { offset, command in
                            row(
                                index: offset,
                                systemImage: command.systemImage,
                                title: command.title,
                                subtitle: command.group.label,
                                shortcut: command.shortcutHint,
                                isEnabled: isEnabled(command)
                            ) {
                                state.closePalette()
                                dismiss()
                                onRun(command)
                            }
                            .id(offset)
                        }
                    }

                    if !state.paletteResults.isEmpty {
                        sectionHeader("Sessions")
                        ForEach(Array(state.paletteResults.enumerated()), id: \.offset) { offset, result in
                            let index = commands.count + offset
                            row(
                                index: index,
                                systemImage: "bubble.left",
                                title: result.session.displayName,
                                subtitle: result.project.name + " · " + Format.relativeTime(result.session.updatedAt),
                                shortcut: nil,
                                isEnabled: true
                            ) {
                                state.closePalette()
                                dismiss()
                                Task { await state.open(session: result.session) }
                            }
                            .id(index)
                        }
                    }

                    if commands.isEmpty && state.paletteResults.isEmpty {
                        Text(state.paletteQuery.isEmpty ? "Type to filter." : "No matches.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(14)
                    }
                }
            }
            .onChange(of: selectedIndex) { _, newValue in
                withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo(newValue, anchor: .center) }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }

    private func row(
        index: Int,
        systemImage: String,
        title: String,
        subtitle: String?,
        shortcut: String?,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .frame(width: 18)
                    .foregroundStyle(.secondary)
                Text(title)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if let shortcut {
                    Text(shortcut)
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(index == selectedIndex ? Color.accentColor.opacity(0.16) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
    }

    // MARK: - Data

    /// Commands filtered by the query. An empty query shows the useful subset
    /// rather than every command, so the palette is never a wall of text.
    private var commands: [PaletteCommand] {
        let query = state.paletteQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return PaletteCommand.allCases }
        return PaletteCommand.allCases.filter { command in
            command.title.lowercased().contains(query)
                || command.group.label.lowercased().contains(query)
        }
    }

    private func isEnabled(_ command: PaletteCommand) -> Bool {
        if command.requiresSession && state.activeController == nil { return false }
        if command.requiresIdleAgent && state.isActiveSessionBusy { return false }
        return true
    }

    private var totalCount: Int { commands.count + state.paletteResults.count }

    private func move(_ delta: Int) {
        guard totalCount > 0 else { return }
        selectedIndex = (selectedIndex + delta + totalCount) % totalCount
    }

    private func runSelected() {
        guard totalCount > 0 else { return }
        let index = min(selectedIndex, totalCount - 1)
        if index < commands.count {
            let command = commands[index]
            guard isEnabled(command) else { return }
            state.closePalette()
            dismiss()
            onRun(command)
        } else {
            let session = state.paletteResults[index - commands.count].session
            state.closePalette()
            dismiss()
            Task { await state.open(session: session) }
        }
    }
}
