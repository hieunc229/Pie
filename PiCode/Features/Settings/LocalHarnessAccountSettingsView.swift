//
//  LocalHarnessAccountSettingsView.swift
//  PiCode
//
//  Read-only account status for CLIs which own and refresh their credentials.
//

import SwiftUI

struct LocalHarnessAccountSettingsView: View {
    @Bindable var state: AppState
    let descriptor: HarnessDescriptor

    @State private var status: LocalHarnessAccountStatus?
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Divider()
            HStack {
                Text("Subscription & local account")
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 0)
                if isLoading { ProgressView().controlSize(.mini) }
                if let status {
                    Label(status.title, systemImage: statusIcon(status.kind))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(statusColor(status.kind))
                }
            }

            Text(status?.detail ?? "Checking the account owned by \(descriptor.displayName)…")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            HStack(spacing: 8) {
                Button(status?.kind == .signedOut ? "Sign In…" : "Manage Account…") {
                    let command = LocalHarnessAccountService.loginCommand(for: descriptor.id)
                    _ = WorkspaceLauncher.openTerminal(at: NSHomeDirectory())
                    state.showToast("Run `\(command)` in the terminal.")
                }
                .controlSize(.small)

                CopyButton(
                    text: LocalHarnessAccountService.loginCommand(for: descriptor.id),
                    help: "Copy the \(descriptor.displayName) sign-in command"
                )

                Button("Refresh") { Task { await reload() } }
                    .controlSize(.small)
                    .disabled(isLoading)
            }

            Text("PiCode asks the installed CLI for status and launches it normally. Tokens remain in the CLI's own credential store.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .task(id: installation?.version) { await reload() }
    }

    private var installation: HarnessInstallation? {
        state.harnesses.installation(for: descriptor.id)
    }

    @MainActor
    private func reload() async {
        guard let installation else {
            status = LocalHarnessAccountStatus(
                kind: .unavailable,
                title: "Not installed",
                detail: "Install \(descriptor.displayName) before connecting an account."
            )
            return
        }
        isLoading = true
        status = await LocalHarnessAccountService.status(for: descriptor, installation: installation)
        isLoading = false
    }

    private func statusIcon(_ kind: LocalHarnessAccountStatus.Kind) -> String {
        switch kind {
        case .subscription: return "checkmark.seal.fill"
        case .localCredentials: return "key.fill"
        case .apiKey: return "key"
        case .signedOut: return "person.crop.circle.badge.exclamationmark"
        case .unavailable: return "questionmark.circle"
        }
    }

    private func statusColor(_ kind: LocalHarnessAccountStatus.Kind) -> Color {
        switch kind {
        case .subscription, .localCredentials, .apiKey: return .green
        case .signedOut: return .orange
        case .unavailable: return .secondary
        }
    }
}
