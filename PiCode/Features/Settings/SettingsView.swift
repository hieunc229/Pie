//
//  SettingsView.swift
//  PiCode
//
//  PiCode's own preferences, plus the one place PiCode edits configuration Pi
//  owns: the Providers tab, which writes Pi's `auth.json` and `models.json` on
//  explicit request. Everything else here is PiCode state, and the Pi tab only
//  shows where Pi keeps its files.
//
//  The rule for that one exception: PiCode writes the *documented* shape of a
//  file Pi already reads, never a private format, and never without a click.
//

import SwiftUI

struct SettingsView: View {
    @Bindable var state: AppState

    var body: some View {
        TabView(selection: $state.settingsTab) {
            GeneralSettings(state: state)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            ComposerSettings(state: state)
                .tabItem { Label("Composer", systemImage: "text.cursor") }
                .tag(SettingsTab.composer)
            SessionSettings(state: state)
                .tabItem { Label("Sessions", systemImage: "bubble.left.and.text.bubble.right") }
                .tag(SettingsTab.sessions)
            ProvidersSettingsView(state: state)
                .tabItem { Label("Providers", systemImage: "key") }
                .tag(SettingsTab.providers)
            PiSettingsTab(state: state)
                .tabItem { Label("Pi", systemImage: "terminal") }
                .tag(SettingsTab.pi)
        }
        .frame(width: 560, height: 520)
    }
}

/// Tabs of the settings window, so the command palette can open a specific one
/// instead of dropping the user on General.
enum SettingsTab: String, CaseIterable, Identifiable, Hashable {
    case general
    case composer
    case sessions
    case providers
    case pi

    var id: String { rawValue }
}

// MARK: - General

struct GeneralSettings: View {
    @Bindable var state: AppState

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: Binding(
                    get: { state.preferences.appearance },
                    set: { state.preferences.appearance = $0; state.preferences.persist() }
                )) {
                    ForEach(PreferencesStore.Appearance.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }

                Toggle("Reduce motion", isOn: Binding(
                    get: { state.preferences.reducedMotionOverride ?? false },
                    set: { state.preferences.reducedMotionOverride = $0; state.preferences.persist() }
                ))
                .help("Overrides the system setting for PiCode's animations only")

                Toggle("Notify when a long turn finishes", isOn: Binding(
                    get: { state.preferences.notificationsEnabled },
                    set: { state.preferences.notificationsEnabled = $0; state.preferences.persist() }
                ))
            }

            Section("Workspace") {
                Toggle("Show inspector", isOn: Binding(
                    get: { state.preferences.showInspector },
                    set: { state.preferences.showInspector = $0; state.preferences.persist() }
                ))
                Button("Open Project Folder…") { Task { await state.addProject() } }
                if let path = state.selectedProjectPath {
                    HStack {
                        Text(path.abbreviatingHomeDirectory)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                        CopyButton(text: path, help: "Copy project path")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(.top, 8)
    }
}

// MARK: - Composer

struct ComposerSettings: View {
    @Bindable var state: AppState

    var body: some View {
        Form {
            Section {
                Picker("Send key", selection: Binding(
                    get: { state.preferences.sendKey },
                    set: { state.preferences.sendKey = $0; state.preferences.persist() }
                )) {
                    ForEach(PreferencesStore.SendKey.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.radioGroup)
            }

            Section("Defaults for new sessions") {
                Picker("Thinking level", selection: Binding(
                    get: { state.preferences.defaultThinkingLevel ?? "" },
                    set: { state.preferences.defaultThinkingLevel = $0.isEmpty ? nil : $0; state.preferences.persist() }
                )) {
                    Text("Pi's default").tag("")
                    Text("off").tag("off")
                    Text("low").tag("low")
                    Text("medium").tag("medium")
                    Text("high").tag("high")
                }
                if let controller = state.activeController, !controller.availableModels.isEmpty {
                    Picker("Model", selection: Binding(
                        get: { state.preferences.defaultModelQualifiedID ?? "" },
                        set: { state.preferences.defaultModelQualifiedID = $0.isEmpty ? nil : $0; state.preferences.persist() }
                    )) {
                        Text("Pi's default").tag("")
                        ForEach(controller.availableModels) { model in
                            Text("\(model.provider)/\(model.id)").tag(model.qualifiedID)
                        }
                    }
                } else {
                    Text("Open a session to choose a default model. Pi's own default is used until then.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding(.top, 8)
    }
}

// MARK: - Sessions

struct SessionSettings: View {
    @Bindable var state: AppState

    var body: some View {
        Form {
            Section {
                Toggle("Ask before deleting a session", isOn: Binding(
                    get: { state.preferences.confirmBeforeDeletingSessions },
                    set: { state.preferences.confirmBeforeDeletingSessions = $0; state.preferences.persist() }
                ))
                Toggle("Record RPC payloads", isOn: Binding(
                    get: { state.preferences.recordRPCPayloads },
                    set: { state.preferences.recordRPCPayloads = $0; state.preferences.persist() }
                ))
                .help("Keeps the last \(PiDiagnosticsLog.shared.limit) RPC payloads in memory for troubleshooting. Nothing is written to disk.")
            }

            Section("Pi's session storage") {
                HStack {
                    Text(PiPaths.sessionsDirectory.path.abbreviatingHomeDirectory)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                    Button("Reveal") { WorkspaceLauncher.reveal(PiPaths.sessionsDirectory.path) }
                        .controlSize(.small)
                }
                Text("PiCode indexes these files read-only and never rewrites them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Hidden and pinned") {
                Text("\(state.preferences.pinnedSessions.count) pinned sessions, \(state.preferences.hiddenSessions.count) hidden sessions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Forget Hidden Sessions") {
                    state.preferences.hiddenSessions = []
                    state.preferences.persist()
                }
                .controlSize(.small)
            }
        }
        .formStyle(.grouped)
        .padding(.top, 8)
    }
}

// MARK: - Pi

struct PiSettingsTab: View {
    @Bindable var state: AppState

    @State private var showsPayloadLog = false

    var body: some View {
        Form {
            Section("Pi installation") {
                if let installation = state.installation {
                    LabeledContent("Version", value: installation.version)
                    LabeledContent("Path") {
                        Text(installation.displayPath)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                } else {
                    Text(state.discoveryDetail ?? "Pi was not found yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Search Again") { Task { await state.retryDiscovery() } }
                }
                Button("Check Pi Version") { state.run(.checkForPiUpdates) }
                Button("Show Setup Instructions") { state.run(.showPiSetup) }
            }

            Section("Launch arguments") {
                TextField("Extra arguments", text: Binding(
                    get: { state.preferences.extraLaunchArguments },
                    set: { state.preferences.extraLaunchArguments = $0; state.preferences.persist() }
                ), prompt: Text("--verbose"))
                .font(.system(.caption, design: .monospaced))
                Text("Appended to every `pi --mode rpc` launch. PiCode never writes to Pi's settings files.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Pi configuration") {
                ForEach(configFiles, id: \.path) { file in
                    HStack {
                        Text(file.path.abbreviatingHomeDirectory)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                        if FileManager.default.fileExists(atPath: file.path) {
                            Button("Reveal") { WorkspaceLauncher.reveal(file.path) }
                                .controlSize(.small)
                        } else {
                            Text("missing")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                Button("Open Pi's Folder") { state.run(.revealPiDirectory) }
            }

            Section("Diagnostics") {
                LabeledContent("Recorded payloads", value: "\(PiDiagnosticsLog.shared.count)")
                Button("View Payload Log") { showsPayloadLog = true }
                Button("Clear") { PiDiagnosticsLog.shared.clear() }
            }
        }
        .formStyle(.grouped)
        .padding(.top, 8)
        .sheet(isPresented: $showsPayloadLog) {
            PayloadLogView()
        }
    }

    private var configFiles: [URL] {
        [PiPaths.settingsFile, PiPaths.trustFile, PiPaths.authFile,
         PiPaths.modelsFile, PiPaths.modelsStoreFile]
    }
}

struct PayloadLogView: View {
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("RPC payload log")
                    .font(.headline)
                Spacer(minLength: 0)
                CopyButton(text: text, help: "Copy log")
                Button("Refresh") { text = PiDiagnosticsLog.shared.text() }
                Button("Close") { dismiss() }
            }
            .padding(12)
            Divider()
            ScrollView {
                Text(text.isEmpty ? "Nothing recorded. Enable “Record RPC payloads” first." : text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
        }
        .frame(width: 640, height: 460)
        .onAppear { text = PiDiagnosticsLog.shared.text() }
    }

    @Environment(\.dismiss) private var dismiss
}
