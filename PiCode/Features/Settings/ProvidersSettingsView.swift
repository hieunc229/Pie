//
//  ProvidersSettingsView.swift
//  PiCode
//
//  Third-party provider definitions managed by PiCode.
//

import SwiftUI

@Observable
@MainActor
final class ProvidersModel {
    private(set) var customProviders: [ProviderConfiguration] = []
    private(set) var customProblems: [PiProviderService.Problem] = []

    var lastError: String?
    var statusMessage: String?

    var onProvidersChanged: (([ProviderConfiguration]) throws -> Void)?

    func reload() {
        customProviders = ProviderRegistry.providers()
        customProblems = PiProviderService.customProviderProblems(at: ProviderRegistry.fileURL)
    }

    // MARK: Mutations

    func saveCustomProviders(_ providers: [ProviderConfiguration]) {
        do {
            try ProviderRegistry.save(providers)
            try onProvidersChanged?(providers)
            reload()
            statusMessage = "Saved \(providers.count) provider(s)."
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
    @State private var editingProvider: ProviderConfiguration?
    @State private var isAddingProvider = false
    @State private var pendingRemoval: String?

    var body: some View {
        SettingsPage {
            customProvidersSection
            footer
        }
        .onAppear {
            model.reload()
            // A saved or removed provider is mirrored to every installed harness
            // and applied to running sessions at once, so the composer's model
            // menu reflects the change without a manual reload.
            model.onProvidersChanged = { _ in
                state.providersDidChange()
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
            if let id = pendingRemoval {
                Button("Remove", role: .destructive) {
                    model.removeCustomProvider(id: id)
                    pendingRemoval = nil
                }
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: {
            if let id = pendingRemoval {
                Text("PiCode will remove the provider configuration “\(id)”.")
            }
        }
    }

    // MARK: Sections

    private var customProvidersSection: some View {
        SettingsSection(
            "Custom providers",
            caption: "Configure the provider endpoint, protocol, credentials, and available models."
        ) {
            if model.customProviders.isEmpty {
                SettingsRow(
                    "No custom providers",
                    detail: "Add one for an OpenAI- or Anthropic-compatible server, a gateway, or a local runtime."
                )
            }
            ForEach(model.customProviders) { provider in
                customProviderRow(provider)
            }
            SettingsRow("Add a provider") {
                Button("Add Provider…") { isAddingProvider = true }
                    .buttonStyle(.settingsPill)
            }
        }
    }

    @ViewBuilder
    private func customProviderRow(_ provider: ProviderConfiguration) -> some View {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(provider.id).font(.system(size: 14, weight: .medium))
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
                        .buttonStyle(.settingsPill)
                    Button("Remove") { pendingRemoval = provider.id }
                        .buttonStyle(.settingsPill)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
    }
    @ViewBuilder
    private var footer: some View {
        if model.statusMessage != nil || model.lastError != nil {
          VStack(alignment: .leading, spacing: 6) {
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
          }
        }
    }
}

struct CustomProviderSheet: View {
    var provider: ProviderConfiguration?
    var onSave: (ProviderConfiguration) -> Void

    @State private var id = ""
    @State private var baseURL = ""
    @State private var api = PiProviderService.supportedAPIs[0]
    @State private var apiKey = ""
    @State private var modelIDs = ""
    @State private var contextWindow = ""
    @State private var reasoning = false
    @State private var acceptsImages = false
    @State private var presetID = "custom"
    @State private var isLoadingModels = false
    @State private var loadMessage: String?
    @State private var loadError: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(provider == nil ? "Add a provider" : "Edit \(provider?.id ?? "")")
                .font(.headline)
            Form {
                if provider == nil {
                    Picker("Preset", selection: $presetID) {
                        ForEach(ProviderPresets.all) { preset in
                            Text(preset.name).tag(preset.id)
                        }
                    }
                    .onChange(of: presetID) { _, newValue in
                        applyPreset(ProviderPresets.preset(id: newValue))
                    }
                    if let note = ProviderPresets.preset(id: presetID).note {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                TextField("Provider id", text: $id, prompt: Text("deepseek"))
                TextField("Base URL", text: $baseURL, prompt: Text("https://api.deepseek.com/v1"))
                Picker("API", selection: $api) {
                    ForEach(PiProviderService.supportedAPIs, id: \.self) { Text($0).tag($0) }
                }
                TextField("API key", text: $apiKey, prompt: Text(keyPlaceholder))
                HStack(spacing: 8) {
                    TextField("Model ids", text: $modelIDs, prompt: Text("deepseek-chat, deepseek-reasoner"))
                    Button {
                        Task { await loadModels() }
                    } label: {
                        if isLoadingModels {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Load Models")
                        }
                    }
                    .disabled(isLoadingModels || baseURL.trimmingCharacters(in: .whitespaces).isEmpty)
                    .help("Query the endpoint for its model list")
                }
                if let loadMessage {
                    Text(loadMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let loadError {
                    Text(loadError)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                TextField("Context window", text: $contextWindow, prompt: Text("128000"))
                Toggle("Supports reasoning", isOn: $reasoning)
                Toggle("Accepts images", isOn: $acceptsImages)
            }
            .formStyle(.columns)
            Text("A literal key is stored with this provider. `$ENV_VAR` or `!command` keeps the secret elsewhere.")
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

    private var keyPlaceholder: String {
        if let provider, let match = ProviderPresets.matching(baseURL: provider.baseURL, providerID: provider.id) {
            return match.keyPlaceholder
        }
        return ProviderPresets.preset(id: presetID).keyPlaceholder
    }

    /// Fills the form from a preset. "Custom" clears the endpoint fields so the
    /// user starts from a blank form.
    private func applyPreset(_ preset: ProviderPreset) {
        loadMessage = nil
        loadError = nil
        guard !preset.isCustom else {
            id = ""
            baseURL = ""
            api = PiProviderService.supportedAPIs[0]
            modelIDs = ""
            return
        }
        id = preset.providerID
        baseURL = preset.baseURL
        api = preset.api
        modelIDs = preset.modelIDs.joined(separator: ", ")
    }

    private func loadModels() async {
        isLoadingModels = true
        loadMessage = nil
        loadError = nil
        defer { isLoadingModels = false }
        do {
            let result = try await PiProviderDiscovery.discover(
                baseURL: baseURL,
                api: api,
                apiKey: apiKey
            )
            modelIDs = result.models.map(\.id).joined(separator: ", ")
            if let first = result.models.first {
                if let window = first.contextWindow { contextWindow = String(window) }
                reasoning = first.reasoning
                acceptsImages = first.acceptsImages
            }
            loadMessage = "Loaded \(result.models.count) model(s) through \(result.endpoint.host() ?? "the endpoint")."
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func save() {
        let models = modelIDs
            .split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { name in
                ProviderModelConfiguration(
                    id: name,
                    name: nil,
                    reasoning: reasoning,
                    acceptsImages: acceptsImages,
                    contextWindow: Int(contextWindow),
                    maxTokens: nil
                )
            }
        onSave(ProviderConfiguration(
            id: id.trimmingCharacters(in: .whitespaces),
            baseURL: baseURL.trimmingCharacters(in: .whitespaces),
            api: api,
            apiKey: apiKey.isEmpty ? (models.isEmpty ? nil : "no-key-required") : apiKey,
            models: models,
            // Editing keeps fields PiCode does not expose, such as compat,
            // headers, samplingParams, and thinkingLevelMap.
            extra: provider?.extra ?? [:]
        ))
        dismiss()
    }
}
