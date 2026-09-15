//
//  ProviderSettingsModal.swift
//  PiCode
//
//  Provider-focused settings: navigation on the left, one provider's credentials,
//  connection, configuration, and model catalog on the right.
//

import Foundation
import SwiftUI

struct ProviderSettingsModal: View {
    @Bindable var state: AppState
    var onClose: () -> Void

    @State private var model = ProvidersModel()
    @State private var selectedProviderID: String?
    @State private var isAddingProvider = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings").font(.headline)
                Spacer(minLength: 0)
                Button("Done", action: onClose).keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            HSplitView {
                providerNavigation
                    .frame(width: 210)
                    .frame(maxHeight: .infinity, alignment: .topLeading)
                providerDetail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 840, height: 620)
        .background(AppTheme.background)
        .onAppear {
            model.reload()
            model.onConfigurationChanged = { [weak model] in
                model?.forgetReadiness()
            }
            if selectedProviderID == nil { selectedProviderID = providerIDs.first }
        }
        .onChange(of: providerIDs) { _, providers in
            if let selectedProviderID, providers.contains(selectedProviderID) { return }
            selectedProviderID = providers.first
        }
        .sheet(isPresented: $isAddingProvider) {
            CustomProviderSheet(provider: nil) { provider in
                model.saveCustomProviders(model.customProviders + [provider])
                selectedProviderID = provider.id
            }
        }
    }

    private var providerNavigation: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Providers", systemImage: "key")
                .font(Typography.bodySemibold)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(providerIDs, id: \.self) { providerID in
                        Button { selectedProviderID = providerID } label: {
                            HStack(spacing: 7) {
                                Circle()
                                    .fill(providerTint(providerID))
                                    .frame(width: 7, height: 7)
                                Text(providerID).font(Typography.body).lineLimit(1)
                                Spacer(minLength: 0)
                                if customProvider(providerID) != nil {
                                    Text("Custom").font(.caption2).foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(selectedProviderID == providerID ? SidebarStyle.rowHighlightFill : .clear)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Divider().padding(.vertical, 4)

            Button { isAddingProvider = true } label: {
                Label("Add third-party provider", systemImage: "plus")
                    .font(Typography.body)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .padding(8)
        .background(AppTheme.elevated)
    }

    @ViewBuilder
    private var providerDetail: some View {
        if let providerID = selectedProviderID {
            if let provider = customProvider(providerID) {
                CustomProviderDetailView(
                    provider: provider,
                    model: model,
                    onDelete: { selectedProviderID = nil }
                )
                .id(provider.id)
            } else {
                BuiltInProviderDetailView(
                    providerID: providerID,
                    models: catalog.filter { $0.provider == providerID },
                    model: model,
                    installation: state.installation
                )
                .id(providerID)
            }
        } else {
            EmptyStateView(
                systemImage: "key",
                title: "No providers",
                message: "Add a third-party provider or start a session to load Pi's provider catalog."
            )
        }
    }

    private var catalog: [PiModel] { state.activeController?.availableModels ?? [] }

    private var providerIDs: [String] {
        var ids = Set(catalog.map(\.provider))
        ids.formUnion(model.credentials.map(\.provider))
        ids.formUnion(model.customProviders.map(\.id))
        return ids.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func customProvider(_ id: String) -> PiProviderService.CustomProvider? {
        model.customProviders.first { $0.id == id }
    }

    private func providerTint(_ id: String) -> Color {
        if model.readiness[id]?.isReady == true { return .green }
        if model.credentials.contains(where: { $0.provider == id }) { return .green.opacity(0.75) }
        if customProvider(id)?.isLocalServer == true { return .blue }
        return .secondary.opacity(0.55)
    }
}

private struct BuiltInProviderDetailView: View {
    var providerID: String
    var models: [PiModel]
    var model: ProvidersModel
    var installation: PiInstallation?

    @State private var apiKey = ""

    var body: some View {
        Form {
            Section("Provider") {
                LabeledContent("Name", value: providerID)
                if let credential = model.credentials.first(where: { $0.provider == providerID }) {
                    LabeledContent("Credential", value: credential.kindLabel)
                    if let fingerprint = credential.fingerprint { LabeledContent("Key", value: fingerprint) }
                    Button("Remove credential", role: .destructive) {
                        model.removeCredential(provider: providerID)
                    }
                }
            }

            Section("Authentication") {
                SecureField("API key", text: $apiKey, prompt: Text("Paste a new key"))
                Button("Save API Key") {
                    model.setAPIKey(apiKey, provider: providerID)
                    apiKey = ""
                }
                .disabled(apiKey.isEmpty)
            }

            Section("Connection") {
                if let readiness = model.readiness[providerID] {
                    Label(
                        readiness.summary,
                        systemImage: readiness.isReady ? "checkmark.circle.fill" : "exclamationmark.circle"
                    )
                    .foregroundStyle(readiness.isReady ? Color.green : Color.orange)
                }
                Button(model.isChecking ? "Connecting…" : "Connect") {
                    Task { await model.checkReadiness(providers: [providerID], installation: installation) }
                }
                .disabled(model.isChecking)
            }

            Section("Models") {
                if models.isEmpty {
                    Text("No models are available from the current Pi session.")
                        .foregroundStyle(.secondary)
                }
                ForEach(models) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.displayName)
                        Text(item.id).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct CustomProviderDetailView: View {
    var provider: PiProviderService.CustomProvider
    var model: ProvidersModel
    var onDelete: () -> Void

    @State private var baseURL: String
    @State private var api: String
    @State private var apiKey: String
    @State private var advancedJSON: String
    @State private var models: [PiProviderService.CustomModel]
    @State private var selectedModelIDs: Set<String>
    @State private var manualModelIDs = ""
    @State private var isConnecting = false
    @State private var connectionMessage: String?
    @State private var configurationError: String?

    init(provider: PiProviderService.CustomProvider, model: ProvidersModel, onDelete: @escaping () -> Void) {
        self.provider = provider
        self.model = model
        self.onDelete = onDelete
        _baseURL = State(initialValue: provider.baseURL ?? "")
        _api = State(initialValue: provider.api ?? PiProviderService.supportedAPIs[0])
        _apiKey = State(initialValue: provider.apiKey ?? "")
        _advancedJSON = State(initialValue: JSONScanner.serialize(.object(provider.extra), pretty: true))
        _models = State(initialValue: provider.models)
        _selectedModelIDs = State(initialValue: Set(provider.models.map(\.id)))
    }

    var body: some View {
        Form {
            Section("\(provider.id) configuration") {
                TextField("Endpoint", text: $baseURL, prompt: Text("https://api.example.com/v1"))
                Picker("API", selection: $api) {
                    ForEach(PiProviderService.supportedAPIs, id: \.self) { Text($0).tag($0) }
                }
                SecureField("API key or reference", text: $apiKey, prompt: Text("sk-…, $ENV_VAR, or !command"))
                Text("The provider package supports literal keys, environment references, and command references. PiCode never executes command references during discovery.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Connection") {
                Button(isConnecting ? "Connecting…" : "Connect and List Models") {
                    Task { await connect() }
                }
                .disabled(isConnecting || baseURL.isEmpty)
                if let connectionMessage {
                    Text(connectionMessage)
                        .font(.caption)
                        .foregroundStyle(configurationError == nil ? Color.secondary : Color.orange)
                }
            }

            Section("Models") {
                TextField("Add model IDs manually", text: $manualModelIDs, prompt: Text("model-a, model-b"))
                if models.isEmpty {
                    Text("Connect to discover models, or enter model IDs manually.")
                        .foregroundStyle(.secondary)
                }
                ForEach(models) { item in
                    Toggle(isOn: selectionBinding(item.id)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.displayName)
                            HStack(spacing: 8) {
                                Text(item.id)
                                if let contextWindow = item.contextWindow { Text("ctx \(contextWindow)") }
                                if item.reasoning { Text("reasoning") }
                                if item.acceptsImages { Text("images") }
                            }
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Advanced package configuration") {
                TextEditor(text: $advancedJSON)
                    .font(Typography.codeBlockCompact)
                    .frame(minHeight: 100)
                Text("JSON fields such as `compat` are preserved in models.json and passed through to the provider package.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                if let configurationError { Text(configurationError).foregroundStyle(.orange) }
                HStack {
                    Button("Delete Provider", role: .destructive) {
                        model.removeCustomProvider(id: provider.id)
                        onDelete()
                    }
                    Spacer(minLength: 0)
                    Button("Save") { save() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(baseURL.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func connect() async {
        isConnecting = true
        configurationError = nil
        connectionMessage = nil
        defer { isConnecting = false }
        do {
            let result = try await PiProviderDiscovery.discover(baseURL: baseURL, api: api, apiKey: apiKey)
            models = result.models
            selectedModelIDs = Set(result.models.map(\.id))
            connectionMessage = "Connected through \(result.endpoint.absoluteString) · \(result.models.count) model(s)"
        } catch {
            configurationError = error.localizedDescription
            connectionMessage = error.localizedDescription
        }
    }

    private func selectionBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { selectedModelIDs.contains(id) },
            set: { selected in
                if selected { selectedModelIDs.insert(id) }
                else { selectedModelIDs.remove(id) }
            }
        )
    }

    private func save() {
        guard let data = advancedJSON.data(using: .utf8),
              let extra = try? JSONCoding.decode(data).objectValue else {
            configurationError = "Advanced configuration must be a JSON object."
            return
        }
        let manualModels = manualModelIDs
            .split(whereSeparator: { $0 == "," || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { candidate in !candidate.isEmpty && !models.contains(where: { $0.id == candidate }) }
            .map {
                PiProviderService.CustomModel(
                    id: $0,
                    name: nil,
                    reasoning: false,
                    acceptsImages: false,
                    contextWindow: 128_000,
                    maxTokens: 16_384
                )
            }
        let savedModels = models.filter { selectedModelIDs.contains($0.id) } + manualModels
        let updated = PiProviderService.CustomProvider(
            id: provider.id,
            baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            api: api,
            apiKey: apiKey.isEmpty ? (savedModels.isEmpty ? nil : "no-key-required") : apiKey,
            models: savedModels,
            extra: extra
        )
        var providers = model.customProviders
        if let index = providers.firstIndex(where: { $0.id == provider.id }) { providers[index] = updated }
        model.saveCustomProviders(providers)
        configurationError = nil
    }
}
