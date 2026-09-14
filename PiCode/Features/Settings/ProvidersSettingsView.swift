//
//  ProvidersSettingsView.swift
//  PiCode
//
//  Settings for the two files that decide which models a session can use:
//  Pi's `auth.json` (credentials) and Pi's `models.json` (custom providers).
//
//  PiCode does not keep its own copy of either. It reads them, reports what Pi
//  says about them, and writes only when the user asks — because a provider
//  configured here has to work in the terminal too, and a second source of truth
//  would eventually disagree with Pi.
//

import SwiftUI

@Observable
@MainActor
final class ProvidersModel {
    private(set) var credentials: [PiProviderService.Credential] = []
    private(set) var problems: [PiProviderService.Problem] = []
    private(set) var customProviders: [PiProviderService.CustomProvider] = []
    private(set) var customProblems: [PiProviderService.Problem] = []
    private(set) var readiness: [String: PiProviderService.Readiness] = [:]
    private(set) var hasWizard = false
    private(set) var isChecking = false

    var lastError: String?
    var statusMessage: String?

    /// Set by the app so a configuration change can reach live sessions.
    var onConfigurationChanged: (() -> Void)?

    func reload() {
        credentials = PiProviderService.credentials()
        problems = PiProviderService.problems()
        customProviders = PiProviderService.customProviders()
        customProblems = PiProviderService.customProviderProblems()
        hasWizard = PiProviderService.hasCustomProviderWizard()
    }

    /// Providers worth asking Pi about: everything already configured, plus the
    /// catalog the running session sees.
    func providersToCheck(catalog: [PiModel]) -> [String] {
        var names = Set(credentials.map(\.provider))
        names.formUnion(customProviders.map(\.id))
        names.formUnion(catalog.map(\.provider))
        return names.sorted()
    }

    /// Drops cached answers about files that just changed.
    func forgetReadiness() {
        readiness = [:]
    }

    func checkReadiness(providers: [String], installation: PiInstallation?) async {
        guard let installation else {
            lastError = "Pi was not found, so readiness cannot be checked."
            return
        }
        isChecking = true
        defer { isChecking = false }
        readiness = await PiProviderService.readiness(
            for: providers,
            executable: installation.executableURL,
            shellPath: installation.shellPath
        )
    }

    // MARK: Mutations

    func setAPIKey(_ key: String, provider: String) {
        do {
            try PiProviderService.setAPIKey(key, for: provider)
            reload()
            statusMessage = "Saved a credential for “\(provider)” in Pi's auth.json."
            onConfigurationChanged?()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func removeCredential(provider: String) {
        do {
            try PiProviderService.removeCredential(for: provider)
            reload()
            statusMessage = "Removed the credential for “\(provider)”."
            onConfigurationChanged?()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// One bad entry makes Pi's whole credential store unreadable, so this is
    /// offered as a repair rather than applied silently.
    func removeUnreadableEntries() {
        do {
            let removed = try PiProviderService.removeUnreadableEntries()
            reload()
            statusMessage = removed.isEmpty
                ? "Nothing to repair."
                : "Removed unreadable entries: \(removed.joined(separator: ", "))."
            onConfigurationChanged?()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func saveCustomProviders(_ providers: [PiProviderService.CustomProvider]) {
        do {
            try PiProviderService.saveCustomProviders(providers)
            reload()
            statusMessage = "Saved \(providers.count) custom provider(s) to Pi's models.json."
            onConfigurationChanged?()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func removeCustomProvider(id: String) {
        saveCustomProviders(customProviders.filter { $0.id != id })
        statusMessage = "Removed the custom provider “\(id)”."
    }
}

struct ProvidersSettingsView: View {
    @Bindable var state: AppState
    @State private var model = ProvidersModel()
    @State private var isAddingCredential = false
    @State private var editingProvider: PiProviderService.CustomProvider?
    @State private var isAddingProvider = false
    @State private var pendingRemoval: PendingRemoval?

    private enum PendingRemoval: Identifiable {
        case credential(String)
        case provider(String)

        var id: String {
            switch self {
            case .credential(let name): return "credential:\(name)"
            case .provider(let name): return "provider:\(name)"
            }
        }
    }

    var body: some View {
        Form {
            if !model.problems.isEmpty { problemSection }
            credentialsSection
            customProvidersSection
            readinessSection
            footer
        }
        .formStyle(.grouped)
        .padding(.top, 8)
        .onAppear {
            model.reload()
            // Readiness is Pi's answer about a specific set of files: once those
            // files change, the previous answer is stale and should not linger.
            model.onConfigurationChanged = { model.forgetReadiness() }
        }
        .sheet(isPresented: $isAddingCredential) {
            CredentialSheet(existing: model.credentials.map(\.provider)) { provider, key in
                model.setAPIKey(key, provider: provider)
            }
        }
        .sheet(isPresented: $isAddingProvider) {
            CustomProviderSheet(provider: nil) { model.saveCustomProviders(model.customProviders + [$0]) }
        }
        .sheet(item: $editingProvider) { provider in
            CustomProviderSheet(provider: provider) { updated in
                var providers = model.customProviders
                if let index = providers.firstIndex(where: { $0.id == provider.id }) { providers[index] = updated }
                else { providers.append(updated) }
                model.saveCustomProviders(providers)
            }
        }
        .confirmationDialog("Remove this configuration?", isPresented: Binding(
            get: { pendingRemoval != nil },
            set: { if !$0 { pendingRemoval = nil } }
        ), titleVisibility: .visible) {
            if let pending = pendingRemoval {
                Button("Remove", role: .destructive) {
                    switch pending {
                    case .credential(let provider): model.removeCredential(provider: provider)
                    case .provider(let id): model.removeCustomProvider(id: id)
                    }
                    pendingRemoval = nil
                }
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: {
            if let pending = pendingRemoval {
                switch pending {
                case .credential(let provider):
                    Text("PiCode will delete the “\(provider)” entry from Pi's auth.json. Pi and the terminal lose it too.")
                case .provider(let id):
                    Text("PiCode will delete the “\(id)” provider from Pi's models.json.")
                }
            }
        }
    }

    // MARK: Sections

    private var problemSection: some View {
        Section {
            ForEach(model.problems) { problem in
                VStack(alignment: .leading, spacing: 2) {
                    Text(problem.provider)
                        .font(.callout.weight(.semibold))
                    Text(problem.reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text("Pi's credential file is read as a whole: while one entry cannot be parsed, **every** provider reports “invalid state”. PiCode verified this against Pi.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Remove Unreadable Entries") { model.removeUnreadableEntries() }
                Button("Reveal auth.json") { WorkspaceLauncher.reveal(PiPaths.authFile.path) }
            }
        } header: {
            Text("Pi cannot read \(model.problems.count) entr\(model.problems.count == 1 ? "y" : "ies")")
        }
    }

    private var credentialsSection: some View {
        Section {
            if model.credentials.isEmpty {
                Text("No credentials yet. Pi reads API keys from its auth.json or from environment variables.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(model.credentials) { credential in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(credential.provider)
                            .font(.callout.weight(.medium))
                        Text(credential.kindLabel + (credential.fingerprint.map { " · \($0)" } ?? ""))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Button("Remove") { pendingRemoval = .credential(credential.provider) }
                        .controlSize(.small)
                }
            }
            Button("Set API Key…") { isAddingCredential = true }
            Text("Written to Pi's auth.json with `0600` permissions, the same way `/login` writes it, and picked up by running sessions within a second. PiCode never reads a key back into the UI and never logs one. Remove a key here and Pi loses it in the terminal too.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Credentials")
        }
    }

    private var customProvidersSection: some View {
        Section {
            if model.customProviders.isEmpty {
                Text("No custom providers. Add one for an OpenAI- or Anthropic-compatible server, a gateway, or a local runtime.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(model.customProviders) { provider in
                customProviderRow(provider)
            }
            HStack {
                Button("Add Provider…") { isAddingProvider = true }
                if model.hasWizard {
                    Button("Pi's Provider Wizard") {
                        _ = WorkspaceLauncher.openTerminal(at: NSHomeDirectory())
                        state.showToast("Run `/setup-custom-providers` in the terminal Pi just opened.")
                    }
                    .help("Opens a terminal with Pi; the installed pi-setup-custom-providers extension handles discovery, health checks, and presets.")
                }
            }
            Text("Written to Pi's models.json, the file Pi documents for third-party providers. Pi reads it when a session starts, so restart a session to see a new provider in its model picker.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Custom providers")
        }
    }

    @ViewBuilder
    private func customProviderRow(_ provider: PiProviderService.CustomProvider) -> some View {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(provider.id).font(.callout.weight(.medium))
                            if provider.isLocalServer {
                                Text("local")
                                    .font(.caption2)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(.quaternary, in: Capsule())
                            }
                        }
                        Text([provider.api, provider.baseURL, "\(provider.models.count) model(s)"]
                            .compactMap { $0 }
                            .joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if let problem = model.customProblems.first(where: { $0.provider == provider.id }) {
                            Text(problem.reason)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    Spacer(minLength: 0)
                    Button("Edit") { editingProvider = provider }
                        .controlSize(.small)
                    Button("Remove") { pendingRemoval = .provider(provider.id) }
                        .controlSize(.small)
                }
    }


    private var readinessSection: some View {
        Section {
            if model.readiness.isEmpty {
                Text("Ask Pi which providers it can actually use. PiCode runs `pi auth check`, which never calls a model.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(model.readiness.keys.sorted(), id: \.self) { provider in
                let readiness = model.readiness[provider] ?? .unknown("unchecked")
                HStack(spacing: 8) {
                    Circle()
                        .fill(readiness.isReady ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(provider).font(.callout)
                    Spacer(minLength: 0)
                    Text(readiness.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            HStack {
                Button(model.isChecking ? "Checking…" : "Check with Pi") {
                    Task {
                        await model.checkReadiness(
                            providers: model.providersToCheck(catalog: state.activeController?.availableModels ?? []),
                            installation: state.installation
                        )
                    }
                }
                .disabled(model.isChecking)
            }
        } header: {
            Text("Provider readiness")
        }
    }

    private var footer: some View {
        Section {
            if let status = model.statusMessage {
                Label(status, systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let error = model.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Button("Restart Sessions to Apply Changes") {
                state.restartSessionsForConfigurationChange()
            }
            .help("Pi reads models.json and builds its model catalog when a process starts, so a running session keeps the old provider list until it restarts. Credential changes do not need this.")
            Text("PiCode writes nothing unless you use the buttons above, and it never stores credentials of its own.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Sheets

struct CredentialSheet: View {
    /// Providers PiCode already knows about, offered as suggestions.
    var existing: [String]
    var onSave: (String, String) -> Void

    @State private var provider = ""
    @State private var key = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Set an API key")
                .font(.headline)
            Text("Stored in Pi's auth.json. Pi's built-in provider names are listed; you can also type a custom provider id from models.json.")
                .font(.caption)
                .foregroundStyle(.secondary)
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

struct CustomProviderSheet: View {
    var provider: PiProviderService.CustomProvider?
    var onSave: (PiProviderService.CustomProvider) -> Void

    @State private var id = ""
    @State private var baseURL = ""
    @State private var api = PiProviderService.supportedAPIs[0]
    @State private var apiKey = ""
    @State private var modelIDs = ""
    @State private var contextWindow = ""
    @State private var reasoning = false
    @State private var acceptsImages = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(provider == nil ? "Add a custom provider" : "Edit \(provider?.id ?? "")")
                .font(.headline)
            Form {
                TextField("Provider id", text: $id, prompt: Text("deepseek"))
                TextField("Base URL", text: $baseURL, prompt: Text("https://api.deepseek.com/v1"))
                Picker("API", selection: $api) {
                    ForEach(PiProviderService.supportedAPIs, id: \.self) { Text($0).tag($0) }
                }
                TextField("API key", text: $apiKey, prompt: Text("$MY_API_KEY or sk-…"))
                TextField("Model ids", text: $modelIDs, prompt: Text("deepseek-chat, deepseek-reasoner"))
                TextField("Context window", text: $contextWindow, prompt: Text("128000"))
                Toggle("Supports reasoning", isOn: $reasoning)
                Toggle("Accepts images", isOn: $acceptsImages)
            }
            .formStyle(.columns)
            Text("A literal key is stored in Pi's models.json in clear text, exactly as Pi documents. `$ENV_VAR` or `!command` keeps the secret elsewhere.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer(minLength: 0)
                Button("Cancel") { dismiss() }
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(id.trimmingCharacters(in: .whitespaces).isEmpty || baseURL.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear {
            guard let provider else { return }
            id = provider.id
            baseURL = provider.baseURL ?? ""
            api = provider.api ?? PiProviderService.supportedAPIs[0]
            apiKey = provider.apiKey ?? ""
            modelIDs = provider.models.map(\.id).joined(separator: ", ")
            contextWindow = provider.models.first?.contextWindow.map(String.init) ?? ""
            reasoning = provider.models.first?.reasoning ?? false
            acceptsImages = provider.models.first?.acceptsImages ?? false
        }
    }

    private func save() {
        let models = modelIDs
            .split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { name in
                PiProviderService.CustomModel(
                    id: name,
                    name: nil,
                    reasoning: reasoning,
                    acceptsImages: acceptsImages,
                    contextWindow: Int(contextWindow),
                    maxTokens: nil
                )
            }
        onSave(PiProviderService.CustomProvider(
            id: id.trimmingCharacters(in: .whitespaces),
            baseURL: baseURL.trimmingCharacters(in: .whitespaces),
            api: api,
            apiKey: apiKey.isEmpty ? nil : apiKey,
            models: models,
            // Editing keeps fields PiCode does not expose, such as compat,
            // headers, samplingParams, and thinkingLevelMap.
            extra: provider?.extra ?? [:]
        ))
        dismiss()
    }
}
