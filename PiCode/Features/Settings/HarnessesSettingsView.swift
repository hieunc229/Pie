//
//  HarnessesSettingsView.swift
//  PiCode
//
//  Installed coding-agent runtimes and the supported-harness install flow.
//

import SwiftUI

struct HarnessesSettingsView: View {
    @Bindable var state: AppState
    @State private var logHarness: HarnessID?
    @State private var isAddingHarness = false

    private var installedDescriptors: [HarnessDescriptor] {
        state.harnesses.descriptors.filter { state.harnesses.installation(for: $0.id) != nil }
    }

    private var availableDescriptors: [HarnessDescriptor] {
        state.harnesses.descriptors.filter {
            $0.hasAdapter && state.harnesses.installation(for: $0.id) == nil
        }
    }

    private var updates: HarnessUpdateChecker { state.harnessUpdates }

    var body: some View {
        SettingsPage {
            Text("Installed harnesses run coding sessions and keep their own API and account configuration.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(.bottom, -14)

            ForEach(installedDescriptors) { descriptor in
                SettingsSection(descriptor.displayName) {
                    row(descriptor)
                }
            }

            SettingsSection("Add a harness") {
                SettingsRow(
                    "Add Harness",
                    detail: availableDescriptors.isEmpty
                        ? "All supported harnesses are installed."
                        : "Add another supported harness without showing uninstalled runtimes in the main list."
                ) {
                    Button("Add Harness…") { isAddingHarness = true }
                        .buttonStyle(.settingsPill)
                        .disabled(availableDescriptors.isEmpty)
                }
            }
        }
        .task { await state.checkHarnessUpdates() }
        .sheet(item: $logHarness) { id in
            InstallLogSheet(state: state, harnessID: id) { logHarness = nil }
        }
        .sheet(isPresented: $isAddingHarness) {
            AddHarnessSheet(descriptors: availableDescriptors) { descriptor, method in
                isAddingHarness = false
                install(descriptor, method: method)
            }
        }
    }

    @ViewBuilder
    private func row(_ descriptor: HarnessDescriptor) -> some View {
        let installation = state.harnesses.installation(for: descriptor.id)
        let isDefault = state.preferences.defaultHarnessID == descriptor.id
        let note = descriptor.supportNote.flatMap { descriptor.isBuiltIn ? nil : $0 }

        SettingsRow(descriptor.displayName, detail: [descriptor.tagline, note].compactMap { $0 }.joined(separator: "\n")) {
            HStack(spacing: 6) {
                if descriptor.isBuiltIn { badge("Built-in") }
                if isDefault && descriptor.hasAdapter { badge("Default") }
                if !descriptor.hasAdapter { badge("Adapter planned") }
                statusPill
            }
        }

        if let installation {
            SettingsRow("Version", detail: installation.displayPath) {
                HStack(spacing: 10) {
                    updateStatus(for: descriptor.id)
                    Text(installation.version).foregroundStyle(.secondary)
                    if case .available = updates.status(for: descriptor.id) {
                        Button(state.installs.isInstalling(descriptor.id) ? "Updating…" : "Update") {
                            Task { await state.updateHarness(descriptor) }
                        }
                        .buttonStyle(.settingsPillProminent)
                        .disabled(state.installs.isInstalling(descriptor.id))
                    }
                }
            }
        }

        SettingsRow("Actions") {
            HStack(spacing: 8) {
                if descriptor.hasAdapter {
                    Button(isDefault ? "Default Harness" : "Set as Default") {
                        state.preferences.defaultHarnessID = descriptor.id
                        state.preferences.persist()
                    }
                    .buttonStyle(.settingsPill)
                    .disabled(isDefault)
                } else {
                    Text("Session adapter not implemented")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("Check Again") {
                    Task {
                        await state.harnesses.refresh(descriptor.id)
                        state.synchronizeProviders()
                        await state.checkHarnessUpdates()
                    }
                }
                .buttonStyle(.settingsPill)

                if state.installs.run(for: descriptor.id) != nil {
                    Button("View Log") { logHarness = descriptor.id }
                        .buttonStyle(.settingsPill)
                }
            }
        }

        SettingsBlock {
            HarnessAPISettingsView(state: state, descriptor: descriptor)
        }
    }

    @ViewBuilder
    private func updateStatus(for id: HarnessID) -> some View {
        switch updates.status(for: id) {
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Checking for updates…").foregroundStyle(.secondary)
            }
            .font(.caption)
        case .available(let latest):
            Text("Update available: \(latest)")
                .font(.caption.weight(.medium))
                .foregroundStyle(.orange)
        case .upToDate:
            Text("Up to date").font(.caption).foregroundStyle(.secondary)
        case .unknown, nil:
            EmptyView()
        }
    }

    private func install(_ descriptor: HarnessDescriptor, method: HarnessInstallMethod) {
        logHarness = descriptor.id
        Task {
            _ = await state.installs.install(descriptor, using: method)
            await state.harnesses.refresh(descriptor.id)
            state.synchronizeProviders()
            // If this was the first harness, the app may now be able to run.
            if case .needsPi = state.phase, !state.harnesses.usableHarnesses.isEmpty {
                await state.launch()
            }
        }
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
    }

    private var statusPill: some View {
        Text("Installed")
            .font(.caption.weight(.medium))
            .foregroundStyle(.green)
    }
}

private struct AddHarnessSheet: View {
    var descriptors: [HarnessDescriptor]
    var onInstall: (HarnessDescriptor, HarnessInstallMethod) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Add Harness").font(.headline)
                Spacer(minLength: 0)
                Button("Close") { dismiss() }
            }

            Text("Choose a supported harness and installation method.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(descriptors) { descriptor in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(descriptor.displayName).fontWeight(.medium)
                            Text(descriptor.tagline)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                ForEach(descriptor.installMethods) { method in
                                    Button("Install with \(method.label)") {
                                        onInstall(descriptor, method)
                                    }
                                    CopyButton(text: method.command, help: "Copy \(method.label) install command")
                                }
                            }
                        }
                        .padding(12)
                        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 540, height: 420)
    }
}

private struct InstallLogSheet: View {
    @Bindable var state: AppState
    var harnessID: HarnessID
    var onClose: () -> Void

    var body: some View {
        let run = state.installs.run(for: harnessID)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Install \(state.harnesses.descriptor(for: harnessID).displayName)")
                    .font(.headline)
                Spacer(minLength: 0)
                if state.installs.isInstalling(harnessID) {
                    ProgressView().controlSize(.small)
                    Button("Cancel") { state.installs.cancel(harnessID) }
                }
                Button("Close") { onClose() }
            }
            .padding(12)
            Divider()
            ScrollView {
                Text(run?.output.isEmpty == false ? run!.output : "Waiting for output…")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
        .frame(width: 640, height: 440)
    }
}


// MARK: - Updating

extension AppState {
    /// Looks up the newest version of every installed harness.
    func checkHarnessUpdates() async {
        let entries = harnesses.descriptors.compactMap { descriptor in
            harnesses.installation(for: descriptor.id).map { (descriptor: descriptor, installed: $0.version) }
        }
        await harnessUpdates.check(entries)
    }

    /// Re-runs the harness's own install command (npm preferred), which installs
    /// the newest release, then refreshes what is installed.
    func updateHarness(_ descriptor: HarnessDescriptor) async {
        guard let method = descriptor.installMethods.first(where: { $0.kind == .npm })
                ?? descriptor.installMethods.first else { return }
        _ = await installs.install(descriptor, using: method)
        await harnesses.refresh(descriptor.id)
        synchronizeProviders()
        await checkHarnessUpdates()
    }

    var harnessesWithUpdates: [HarnessDescriptor] {
        harnesses.descriptors.filter {
            if case .available = harnessUpdates.status(for: $0.id) { return true }
            return false
        }
    }

    func updateAllHarnesses() async {
        for descriptor in harnessesWithUpdates { await updateHarness(descriptor) }
    }
}

/// Shown at the top right of the Harnesses page while any harness is behind.
struct UpdateAllHarnessesButton: View {
    @Bindable var state: AppState

    var body: some View {
        let pending = state.harnessesWithUpdates
        let isUpdating = pending.contains { state.installs.isInstalling($0.id) }
        if !pending.isEmpty {
            Button(isUpdating ? "Updating…" : "Update all (\(pending.count))") {
                Task { await state.updateAllHarnesses() }
            }
            .buttonStyle(.settingsPillProminent)
            .disabled(isUpdating)
        }
    }
}
