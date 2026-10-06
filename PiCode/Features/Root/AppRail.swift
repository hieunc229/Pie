//
//  AppRail.swift
//  PiCode
//
//  The narrow icon rail on the window's leading edge: the app's destinations
//  (home, history, packages, terminal), then the panel the session's changes live
//  in, and the user's own badge at the bottom, which opens Settings.
//
//  It is drawn on the window chrome rather than inside the content card, so it
//  reads as the window's frame and stays put when the sidebar folds away.
//

import SwiftUI

enum AppRailMetrics {
    static let width: CGFloat = 52
    static let buttonSize: CGFloat = 36
    static let iconSize: CGFloat = 17
    static let avatarSize: CGFloat = 26
}

struct AppRail: View {
    @Bindable var state: AppState
    var onOpenPalette: () -> Void
    var onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            RailButton(systemImage: "house", help: "Home", isSelected: !state.isPackagesVisible && !state.isSettingsPresented) {
                state.hidePackages()
            }
            RailButton(systemImage: "clock", help: "Search history (⇧⌘P)", isSelected: false, action: onOpenPalette)
            RailButton(systemImage: "shippingbox", help: "Packages", isSelected: state.isPackagesVisible && !state.isSettingsPresented) {
                state.showPackages()
            }
            RailButton(systemImage: "apple.terminal", help: "Toggle terminal", isSelected: state.isTerminalVisible) {
                state.toggleTerminal()
            }
            .disabled(state.activeController == nil)
            moreMenu

            Rectangle()
                .fill(AppTheme.cardStroke)
                .frame(width: 22, height: 1)
                .padding(.vertical, 6)

            RailButton(
                systemImage: "arrow.triangle.branch",
                help: "Changes and context (⌥⌘I)",
                isSelected: state.isInspectorVisible && !state.isNotificationsVisible
            ) {
                state.toggleInspector()
            }
            .disabled(state.activeController == nil)

            Spacer(minLength: 0)

            UserBadge(action: onOpenSettings)
                .padding(.bottom, 14)
        }
        .padding(.top, 2)
        .frame(width: AppRailMetrics.width)
        .frame(maxHeight: .infinity)
    }

    /// The commands that are about the app rather than about a chat.
    private var moreMenu: some View {
        Menu {
            Button(PaletteCommand.addProject.title) { state.run(.addProject) }
            Button(PaletteCommand.refreshSessions.title) { state.run(.refreshSessions) }
            Divider()
            Button(PaletteCommand.revealPiDirectory.title) { state.run(.revealPiDirectory) }
            Button(PaletteCommand.checkForPiUpdates.title) { state.run(.checkForPiUpdates) }
            Divider()
            Button("Settings…", action: onOpenSettings)
        } label: {
            // A menu's label is snapshotted as a template image, so the glyph is
            // wrapped in `Text` to survive it (see `ProjectRow`).
            Text(Image(systemName: "ellipsis"))
                .font(.system(size: AppRailMetrics.iconSize, weight: .regular))
                .frame(width: AppRailMetrics.buttonSize, height: AppRailMetrics.buttonSize)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(.secondary)
        .help("More")
    }
}

/// One rail destination: a glyph in a rounded square that fills when selected
/// and on hover.
struct RailButton: View {
    var systemImage: String
    var help: String
    var isSelected: Bool
    var action: () -> Void

    @State private var isHovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: AppRailMetrics.iconSize, weight: .regular))
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .frame(width: AppRailMetrics.buttonSize, height: AppRailMetrics.buttonSize)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(isSelected ? AppTheme.railSelection
                              : (isHovering && isEnabled ? AppTheme.railSelection.opacity(0.6) : .clear))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.45)
        .onHover { isHovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

/// The user's initials in a filled circle — the macOS account's full name, so
/// it is the person at the keyboard and not an account PiCode invented.
struct UserBadge: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(Self.initials)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: AppRailMetrics.avatarSize, height: AppRailMetrics.avatarSize)
                .background(Circle().fill(Color(nsColor: NSColor(rgb: 0xD15602))))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Settings")
        .accessibilityLabel("Settings")
    }

    static let initials: String = {
        let words = NSFullUserName().split(separator: " ").filter { $0.first?.isLetter == true }
        let letters = words.prefix(2).compactMap(\.first).map { String($0).uppercased() }
        return letters.isEmpty ? "?" : letters.joined()
    }()
}
