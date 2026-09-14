//
//  SetupViews.swift
//  PiCode
//
//  Launching, empty, and "Pi is not installed" states.
//
//  PiCode never installs, updates, or reconfigures Pi. When Pi is missing, this
//  screen explains how to install it and how PiCode looks for it, then re-runs
//  discovery on request.
//

import SwiftUI

struct LaunchingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("Looking for your Pi installation…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct WelcomeView: View {
    @Bindable var state: AppState

    var body: some View {
        EmptyStateView(
            systemImage: "sparkles.rectangle.stack",
            title: "No session selected",
            message: "Pick a session in the sidebar, or start a new one in the selected project. PiCode runs your own `pi` binary and shows the real transcript.",
            actionTitle: state.selectedProject == nil ? "Open a project folder" : "New session",
            action: {
                if let project = state.selectedProject?.path {
                    Task { await state.startNewSession(projectPath: project) }
                } else {
                    Task { await state.addProject() }
                }
            }
        )
    }
}

struct PiSetupView: View {
    @Bindable var state: AppState

    @State private var isChecking = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Pi was not found", systemImage: "exclamationmark.triangle.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.orange)
                    Text("PiCode is a client for Pi Coding Agent. It does not bundle Pi, and it never installs or updates it for you.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let detail = state.discoveryDetail, !detail.isEmpty {
                    Text(detail)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                }

                InspectorSection(
                    title: "Install Pi",
                    subtitle: "Any of these put `pi` on your PATH.",
                    systemImage: "arrow.down.circle"
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        CommandLineRow(command: "npm install -g --ignore-scripts @earendil-works/pi-coding-agent")
                        CommandLineRow(command: "curl -fsSL https://pi.dev/install.sh | sh")
                    }
                }

                InspectorSection(
                    title: "How PiCode looks for Pi",
                    subtitle: "It asks your login shell first, then falls back to common install locations.",
                    systemImage: "magnifyingglass"
                ) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Login shell: `command -v pi` in your shell, with your shell's PATH.")
                            .font(.callout)
                        if !state.searchedPaths.isEmpty {
                            Text("Searched:")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ForEach(state.searchedPaths, id: \.self) { path in
                                Text(path.abbreviatingHomeDirectory)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Button {
                        isChecking = true
                        Task {
                            await state.launch()
                            isChecking = false
                        }
                    } label: {
                        if isChecking {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Checking…")
                            }
                        } else {
                            Text("Check again")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isChecking)

                    Button("Open Terminal in Home") {
                        state.openTerminal(at: NSHomeDirectory())
                    }
                }

                Text("Nothing on this screen changes your Pi configuration. Pi settings, sessions, and trust decisions stay in `~/.pi/agent`.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(28)
            .frame(maxWidth: 640, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// A copyable shell command with a monospaced presentation.
struct CommandLineRow: View {
    var command: String

    var body: some View {
        HStack(spacing: 8) {
            Text(command)
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 6)
            CopyButton(text: command, help: "Copy command")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 7))
    }
}
