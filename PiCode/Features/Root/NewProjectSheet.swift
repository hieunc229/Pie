//
//  NewProjectSheet.swift
//  PiCode
//
//  The harness / provider / model chooser shown when a project is opened for the
//  first time. The choice is stored per project, so a repo can run on Pi while
//  another runs on a different harness.
//

import SwiftUI

struct NewProjectSheet: View {
    @Bindable var state: AppState
    var path: String
    var onDone: () -> Void

    @State private var harnessID: HarnessID
    @State private var provider: String
    @State private var model: String
    @State private var modelText: String

    init(state: AppState, path: String, onDone: @escaping () -> Void) {
        self.state = state
        self.path = path
        self.onDone = onDone
        let settings = state.preferences.projectSettings(for: CanonicalPath.of(path))
        _harnessID = State(initialValue: settings.harness ?? state.preferences.defaultHarnessID)
        _provider = State(initialValue: settings.providerID ?? "")
        _model = State(initialValue: settings.modelID ?? "")
        _modelText = State(initialValue: settings.modelID ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            Form {
                Section("Project") {
                    LabeledContent("Folder") {
                        Text(path.abbreviatingHomeDirectory)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                }

                Section("Harness") {
                    if state.harnesses.usableHarnesses.isEmpty {
                        Text("No harness with a PiCode adapter is installed yet. Install one in Settings → Harnesses.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        LabeledContent("Agent runtime") {
                            Dropdown(
                                selection: $harnessID,
                                options: state.harnesses.usableHarnesses.map { .init(label: $0.displayName, value: $0.id) }
                            )
                        }
                        Text(selectedDescriptor?.tagline ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if supportsPrelaunchProviderConfiguration {
                    Section("Provider") {
                        LabeledContent("Provider") {
                            Dropdown(
                                selection: $provider,
                                options: [.init(label: "Automatic", value: "")]
                                    + providerOptions.map { .init(label: $0, value: $0) }
                            )
                        }
                    }

                    Section("Model") {
                        if !modelOptions.isEmpty {
                            LabeledContent("Model") {
                                Dropdown(
                                    selection: $model,
                                    options: [.init(label: "Automatic", value: "")]
                                        + modelOptions.map { .init(label: $0, value: $0) }
                                )
                            }
                        } else {
                            TextField("Model", text: $modelText, prompt: Text("provider/model"))
                                .font(.system(.caption, design: .monospaced))
                            Text("Type a qualified model id, or leave blank to use the harness default and pick one in the composer.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if selectedDescriptor?.capabilities.contains(.modelCatalog) == true {
                    Section("Provider and model") {
                        Text("\(selectedDescriptor?.displayName ?? "This harness") owns its provider configuration and model catalog. Start the chat, then choose one of the models it reports in the composer.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onDone() }
                    .buttonStyle(.settingsPill)
                Button("Create Chat") { create() }
                    .buttonStyle(.settingsPillProminent)
                    .disabled(selectedDescriptor == nil)
            }
            .padding(12)
        }
        .frame(width: 520, height: 560)
        .onChange(of: harnessID) { _, _ in
            provider = ""
            model = ""
            modelText = ""
        }
        .onChange(of: provider) { _, _ in
            model = ""
            modelText = ""
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("New project")
                .font(.headline)
            Text("Choose how the agent runs in this folder.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
    }

    private var selectedDescriptor: HarnessDescriptor? {
        state.harnesses.usableHarnesses.first { $0.id == harnessID }
            ?? state.harnesses.usableHarnesses.first
    }

    private var supportsPrelaunchProviderConfiguration: Bool {
        !providerOptions.isEmpty
    }

    /// Only providers whose wire protocol the selected harness can actually use.
    private var providerOptions: [String] {
        guard let descriptor = selectedDescriptor else { return [] }
        var ids = Set(HarnessProviderCatalog.providers(for: descriptor.id).map(\.id))
        if descriptor.id == .pi {
            ids.formUnion(PiProviderService.credentials().map(\.provider))
        }
        if let controller = state.activeController, controller.harness.id == descriptor.id {
            for model in controller.availableModels { ids.insert(model.provider) }
        }
        return ids.sorted()
    }

    /// Models for the selected provider, translated through that harness's
    /// compatibility catalog and augmented by its live catalog when available.
    private var modelOptions: [String] {
        guard !provider.isEmpty, let descriptor = selectedDescriptor else { return [] }
        var ids = HarnessProviderCatalog.providers(for: descriptor.id)
            .first(where: { $0.id == provider })?.models.map(\.id) ?? []
        if let controller = state.activeController, controller.harness.id == descriptor.id {
            ids.append(contentsOf: controller.availableModels
                .filter { $0.provider == provider }
                .map(\.id))
        }
        return Array(Set(ids)).sorted()
    }

    private func create() {
        guard let descriptor = selectedDescriptor else { return }
        let chosenModel: String?
        if !model.isEmpty {
            chosenModel = model
        } else if !modelText.trimmingCharacters(in: .whitespaces).isEmpty {
            chosenModel = modelText.trimmingCharacters(in: .whitespaces)
        } else {
            chosenModel = nil
        }
        let chosenProvider = provider.isEmpty ? nil : provider
        Task {
            await state.createProject(
                path: path,
                harness: descriptor,
                provider: chosenProvider,
                model: chosenModel
            )
            onDone()
        }
    }
}
