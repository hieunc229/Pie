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
}

struct AppRail: View {
    @Bindable var state: AppState
    var onOpenPalette: () -> Void
    var onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            RailButton(systemImage: "home", help: "Home", isSelected: !state.isPackagesVisible && !state.isSettingsPresented) {
                state.hidePackages()
            }
            RailButton(systemImage: "clock", help: "Search history (⇧⌘P)", isSelected: false, action: onOpenPalette)
            RailButton(systemImage: "box", help: "Packages", isSelected: state.isPackagesVisible && !state.isSettingsPresented) {
                state.showPackages()
            }
            moreMenu

            Rectangle()
                .fill(AppTheme.cardStroke)
                .frame(width: 22, height: 1)
                .padding(.vertical, 6)

            RailButton(
                systemImage: "hierarchy-2",
                help: "Changes and context (⌥⌘I)",
                isSelected: state.isInspectorVisible && !state.isNotificationsVisible
            ) {
                state.toggleInspector()
            }
            .disabled(state.activeController == nil)

            Spacer(minLength: 0)

            UpdateButton(updater: state.updater)

            RailButton(
                systemImage: "setting-2",
                help: "Settings",
                isSelected: state.isSettingsPresented,
                action: onOpenSettings
            )
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
            Text(iconsaxImage("more"))
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

/// Shown above Settings when a newer release exists: a white download glyph on a
/// blue square. Click downloads, installs and relaunches.
struct UpdateButton: View {
    var updater: AppUpdater

    var body: some View {
        if let release = updater.release {
            Button(action: updater.install) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.blue)
                    switch updater.state {
                    case .downloading(_, let progress):
                        Circle()
                            .trim(from: 0, to: max(progress, 0.03))
                            .stroke(Color.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 18, height: 18)
                    case .installing:
                        ProgressView().controlSize(.small).colorScheme(.dark)
                    default:
                        IconsaxIcon(name: "arrow-down", size: AppRailMetrics.iconSize)
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: AppRailMetrics.buttonSize, height: AppRailMetrics.buttonSize)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(updater.isBusy)
            .padding(.bottom, 8)
            .help(helpText(release))
            .accessibilityLabel("Update to \(release.version)")
        }
    }

    private func helpText(_ release: AppUpdater.Release) -> String {
        switch updater.state {
        case .downloading(_, let p): "Downloading \(release.version)… \(Int(p * 100))%"
        case .installing: "Installing \(release.version)…"
        case .failed(_, let message): "Update failed: \(message). Click to retry."
        default: "Update to \(release.version) — click to install and restart"
        }
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
            IconsaxIcon(name: systemImage, size: AppRailMetrics.iconSize)
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
