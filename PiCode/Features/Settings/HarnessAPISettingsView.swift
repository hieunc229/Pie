//
//  HarnessAPISettingsView.swift
//  PiCode
//
//  Harness-owned account and API configuration shown with that harness.
//

import SwiftUI

@Observable
@MainActor
final class PiHarnessAPIModel {
    private(set) var credentials: [PiProviderService.Credential] = []
    private(set) var problems: [PiProviderService.Problem] = []
    var lastError: String?
    var statusMessage: String?

    func reload() {
        credentials = PiProviderService.credentials()
        problems = PiProviderService.problems()
    }

    func setAPIKey(_ key: String, provider: String) {
        do {
            try PiProviderService.setAPIKey(key, for: provider)
            reload()
            statusMessage = "Saved \(provider) for Pi."
        } catch {
            lastError = error.localizedDescription
        }
    }

    func removeCredential(_ provider: String) {
        do {
            try PiProviderService.removeCredential(for: provider)
            reload()
            statusMessage = "Removed \(provider) from Pi."
        } catch {
            lastError = error.localizedDescription
        }
    }

    func repair() {
        do {
            let removed = try PiProviderService.removeUnreadableEntries()
            reload()
            statusMessage = removed.isEmpty ? "Nothing to repair." : "Removed: \(removed.joined(separator: ", "))."
        } catch {
            lastError = error.localizedDescription
        }
    }
}

struct HarnessAPISettingsView: View {
    @Bindable var state: AppState
    var descriptor: HarnessDescriptor

    @ViewBuilder
    var body: some View {
        switch descriptor.id {
        case .pi:
            PiHarnessAPISettingsView()
        case .ohMyPi:
            VStack(alignment: .leading, spacing: 7) {
                Divider()
                Text("API & accounts")
                    .font(.caption.weight(.semibold))
                Text("Oh My Pi owns account credentials in its agent database. Open OMP and use `/login`; shared third-party providers are synchronized separately.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button("Open Terminal") {
                        _ = WorkspaceLauncher.openTerminal(at: NSHomeDirectory())
                        state.showToast("Run `omp`, then `/login` to configure Oh My Pi accounts.")
                    }
                    .controlSize(.small)
                    CopyButton(text: "omp", help: "Copy the Oh My Pi command")
                }
            }
        case .claudeCode, .codex, .opencode:
            LocalHarnessAccountSettingsView(state: state, descriptor: descriptor)
        case .deepseekHarness:
            EmptyView()
        }
    }
}

private struct PiHarnessAPISettingsView: View {
    @State private var model = PiHarnessAPIModel()
    @State private var isAddingCredential = false
    @State private var pendingRemoval: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Divider()
            HStack {
                Text("API & accounts")
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 0)
                Button("Set API Key…") { isAddingCredential = true }
                    .controlSize(.small)
            }
            if model.credentials.isEmpty {
                Text("No Pi account credentials configured.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.credentials) { credential in
                    HStack(spacing: 8) {
                        Text(credential.provider)
                            .font(.caption.weight(.medium))
                        Text(credential.kindLabel + (credential.fingerprint.map { " · \($0)" } ?? ""))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Button("Remove") { pendingRemoval = credential.provider }
                            .controlSize(.mini)
                    }
                }
            }
            if !model.problems.isEmpty {
                Label("Pi cannot read \(model.problems.count) credential entr\(model.problems.count == 1 ? "y" : "ies").", iconsax: "warning-2")
                    .font(.caption)
                    .foregroundStyle(.orange)
                HStack {
                    Button("Repair") { model.repair() }
                    Button("Reveal auth.json") { WorkspaceLauncher.reveal(PiPaths.authFile.path) }
                }
                .controlSize(.small)
            }
            if let message = model.statusMessage {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            if let error = model.lastError {
                Text(error).font(.caption).foregroundStyle(.orange)
            }
        }
        .onAppear { model.reload() }
        .sheet(isPresented: $isAddingCredential) {
            HarnessCredentialSheet(existing: model.credentials.map(\.provider)) { provider, key in
                model.setAPIKey(key, provider: provider)
            }
        }
        .confirmationDialog("Remove this Pi credential?", isPresented: Binding(
            get: { pendingRemoval != nil },
            set: { if !$0 { pendingRemoval = nil } }
        ), titleVisibility: .visible) {
            if let provider = pendingRemoval {
                Button("Remove", role: .destructive) {
                    model.removeCredential(provider)
                    pendingRemoval = nil
                }
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        }
    }
}

private struct HarnessCredentialSheet: View {
    var existing: [String]
    var onSave: (String, String) -> Void

    @State private var provider = ""
    @State private var key = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Set a Pi API key").font(.headline)
            TextField("Provider", text: $provider, prompt: Text("anthropic"))
                .textFieldStyle(.roundedBorder)
            if !existing.isEmpty {
                HStack(spacing: 4) {
                    ForEach(existing.prefix(6), id: \.self) { name in
                        Button(name) { provider = name }
                            .buttonStyle(.link)
                            .font(.caption)
                    }
                }
            }
            SecureField("API key", text: $key, prompt: Text("sk-…"))
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer(minLength: 0)
                Button("Cancel") { dismiss() }
                Button("Save") {
                    onSave(provider.trimmingCharacters(in: .whitespaces), key)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(provider.trimmingCharacters(in: .whitespaces).isEmpty || key.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
