//
//  SettingsView.swift
//  PiCode
//
//  PiCode preferences, installed harness configuration, and third-party
//  provider definitions. Harness-owned accounts stay with their harness.
//

import SwiftUI

struct SettingsView: View {
    @Bindable var state: AppState

    @State private var query = ""

    var body: some View {
        HStack(spacing: 0) {
            menu
            Rectangle().fill(AppTheme.cardStroke).frame(width: 1)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(AppTheme.background)
        }
        .onExitCommand { state.isSettingsPresented = false }
    }

    // MARK: - Left menu

    private var visibleTabs: [SettingsTab] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return SettingsTab.allCases }
        return SettingsTab.allCases.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
    }

    private var menu: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                Button {
                    state.isSettingsPresented = false
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Back to app")
                            .font(Typography.body)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 8)

                searchField
                    .padding(.top, 10)
                    .padding(.bottom, 10)

                ForEach(SettingsTab.Group.allCases) { group in
                    let tabs = visibleTabs.filter { $0.group == group }
                    if !tabs.isEmpty {
                        Text(group.title)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.top, 14)
                            .padding(.bottom, 4)
                        ForEach(tabs) { settingsMenuRow($0) }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 16)
        }
        .frame(width: 256)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(AppTheme.sidebar)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            TextField("Search", text: $query)
                .textFieldStyle(.plain)
                .font(Typography.body)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Capsule().fill(AppTheme.railSelection.opacity(0.5)))
    }

    private func settingsMenuRow(_ tab: SettingsTab) -> some View {
        let isSelected = state.settingsTab == tab
        return Button {
            state.settingsTab = tab
        } label: {
            HStack(spacing: 10) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 13, weight: .regular))
                    .frame(width: 18)
                Text(tab.title)
                    .font(Typography.body)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? AppTheme.railSelection : .clear)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Content

    private var content: some View {
        ZStack(alignment: .top) {
            Group {
                switch state.settingsTab {
                case .general: GeneralSettings(state: state)
                case .harnesses: HarnessesSettingsView(state: state)
                case .providers: ProvidersSettingsView(state: state)
                case .composer: ComposerSettings(state: state)
                case .sessions: SessionSettings(state: state)
                case .pi: PiSettingsTab(state: state)
                }
            }
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 22)

            header
        }
        .frame(maxWidth: 860, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(AppTheme.background)
    }

    /// The page title, pinned over the scrolling content. Equal space above and
    /// below the text; the background fades out so rows slide under it softly.
    private var header: some View {
        HStack(alignment: .center) {
            Text(state.settingsTab.title)
                .font(.system(size: 30, weight: .semibold))
            Spacer(minLength: 12)
            if state.settingsTab == .harnesses { UpdateAllHarnessesButton(state: state) }
        }
        .padding(.horizontal, 40)
        .frame(height: SettingsMetrics.headerHeight)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                stops: [
                    .init(color: AppTheme.background, location: 0),
                    .init(color: AppTheme.background, location: 0.55),
                    .init(color: AppTheme.background.opacity(0), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: SettingsMetrics.headerHeight + 24)
            .frame(maxHeight: SettingsMetrics.headerHeight, alignment: .top)
            .allowsHitTesting(false),
            alignment: .top
        )
    }
}

/// Tabs of the settings window, so the command palette can open a specific one
/// instead of dropping the user on General.
enum SettingsTab: String, CaseIterable, Identifiable, Hashable {
    case general
    case harnesses
    case providers
    case composer
    case sessions
    case pi

    var id: String { rawValue }

    /// The labelled clusters in the settings menu.
    enum Group: String, CaseIterable, Identifiable {
        case personal, integrations, coding

        var id: String { rawValue }
        var title: String {
            switch self {
            case .personal: return "Personal"
            case .integrations: return "Integrations"
            case .coding: return "Coding"
            }
        }
    }

    var group: Group {
        switch self {
        case .general, .composer: return .personal
        case .harnesses, .providers: return .integrations
        case .sessions, .pi: return .coding
        }
    }

    var title: String {
        switch self {
        case .general: return "General"
        case .harnesses: return "Harnesses"
        case .providers: return "Providers"
        case .composer: return "Composer"
        case .sessions: return "Sessions"
        case .pi: return "Diagnostics"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .harnesses: return "shippingbox"
        case .providers: return "key"
        case .composer: return "text.cursor"
        case .sessions: return "bubble.left.and.text.bubble.right"
        case .pi: return "stethoscope"
        }
    }
}

// MARK: - General

struct GeneralSettings: View {
    @Bindable var state: AppState

    var body: some View {
        SettingsPage {
            SettingsSection("Appearance") {
                SettingsRow("Appearance", detail: "Match the system or force a light or dark window.") {
                    Picker("", selection: Binding(
                        get: { state.preferences.appearance },
                        set: { state.preferences.appearance = $0; state.preferences.persist() }
                    )) {
                        ForEach(PreferencesStore.Appearance.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                SettingsRow("Reduce motion", detail: "Overrides the system setting for PiCode's animations only.") {
                    Toggle("", isOn: Binding(
                        get: { state.preferences.reducedMotionOverride ?? false },
                        set: { state.preferences.reducedMotionOverride = $0; state.preferences.persist() }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
                SettingsRow("Notify when a long turn finishes") {
                    Toggle("", isOn: Binding(
                        get: { state.preferences.notificationsEnabled },
                        set: { state.preferences.notificationsEnabled = $0; state.preferences.persist() }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
            }

            SettingsSection("Workspace") {
                SettingsRow("Show inspector", detail: "The panel with the session's changes and context.") {
                    Toggle("", isOn: Binding(
                        get: { state.isInspectorVisible },
                        set: { state.isInspectorVisible = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
                SettingsRow(
                    "Project folder",
                    detail: state.selectedProjectPath?.abbreviatingHomeDirectory ?? "No project is selected."
                ) {
                    HStack(spacing: 8) {
                        if let path = state.selectedProjectPath {
                            CopyButton(text: path, help: "Copy project path")
                        }
                        Button("Open…") { Task { await state.addProject() } }
                            .buttonStyle(.settingsPill)
                    }
                }
            }
        }
    }
}

// MARK: - Composer

struct ComposerSettings: View {
    @Bindable var state: AppState

    var body: some View {
        SettingsPage {
            SettingsSection("Sending") {
                SettingsRow("Send key", detail: "The key that sends a message from the composer.") {
                    Picker("", selection: Binding(
                        get: { state.preferences.sendKey },
                        set: { state.preferences.sendKey = $0; state.preferences.persist() }
                    )) {
                        ForEach(PreferencesStore.SendKey.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }

            SettingsSection("Defaults for new sessions") {
                SettingsRow("Thinking level") {
                    Picker("", selection: Binding(
                        get: { state.preferences.defaultThinkingLevel ?? "" },
                        set: { state.preferences.defaultThinkingLevel = $0.isEmpty ? nil : $0; state.preferences.persist() }
                    )) {
                        Text("Pi's default").tag("")
                        Text("off").tag("off")
                        Text("low").tag("low")
                        Text("medium").tag("medium")
                        Text("high").tag("high")
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                if let controller = state.activeController, !controller.availableModels.isEmpty {
                    SettingsRow("\(controller.harness.displayName) model") {
                        Picker("", selection: Binding(
                            get: { state.preferences.defaultModelByHarness[controller.harness.id.rawValue] ?? "" },
                            set: {
                                state.preferences.defaultModelByHarness[controller.harness.id.rawValue] = $0.isEmpty ? nil : $0
                                if controller.harness.id == .pi {
                                    state.preferences.defaultModelQualifiedID = $0.isEmpty ? nil : $0
                                }
                                state.preferences.persist()
                            }
                        )) {
                            Text("\(controller.harness.displayName)'s default").tag("")
                            ForEach(controller.availableModels) { model in
                                Text("\(model.provider)/\(model.id)").tag(model.qualifiedID)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                } else {
                    SettingsRow(
                        "Default model",
                        detail: "Open a session to choose a default model. The selected harness's own default is used until then."
                    )
                }
            }
        }
    }
}

// MARK: - Sessions

struct SessionSettings: View {
    @Bindable var state: AppState

    var body: some View {
        SettingsPage {
            SettingsSection("Sessions") {
                SettingsRow("Ask before deleting a session") {
                    Toggle("", isOn: Binding(
                        get: { state.preferences.confirmBeforeDeletingSessions },
                        set: { state.preferences.confirmBeforeDeletingSessions = $0; state.preferences.persist() }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
                SettingsRow(
                    "Record RPC payloads",
                    detail: "Keeps the last \(PiDiagnosticsLog.shared.limit) RPC payloads in memory for troubleshooting. Nothing is written to disk."
                ) {
                    Toggle("", isOn: Binding(
                        get: { state.preferences.recordRPCPayloads },
                        set: { state.preferences.recordRPCPayloads = $0; state.preferences.persist() }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
            }

            SettingsSection("Pi's session storage") {
                SettingsRow(
                    "Sessions folder",
                    detail: "\(PiPaths.sessionsDirectory.path.abbreviatingHomeDirectory)\nPiCode indexes these files read-only and never rewrites them."
                ) {
                    Button("Reveal") { WorkspaceLauncher.reveal(PiPaths.sessionsDirectory.path) }
                        .buttonStyle(.settingsPill)
                }
            }

            SettingsSection("Hidden and pinned") {
                SettingsRow(
                    "Hidden sessions",
                    detail: "\(state.preferences.pinnedSessions.count) pinned sessions, \(state.preferences.hiddenSessions.count) hidden sessions."
                ) {
                    Button("Forget Hidden Sessions") {
                        state.preferences.hiddenSessions = []
                        state.preferences.persist()
                    }
                    .buttonStyle(.settingsPill)
                }
            }
        }
    }
}

// MARK: - Pi

struct PiSettingsTab: View {
    @Bindable var state: AppState

    @State private var showsPayloadLog = false

    var body: some View {
        SettingsPage {
            SettingsSection("\(state.activeHarness.displayName) installation") {
                if let installation = state.installation {
                    SettingsRow("Version") {
                        Text(installation.version).foregroundStyle(.secondary)
                    }
                    SettingsRow("Path", detail: installation.displayPath)
                } else {
                    SettingsRow("Not found", detail: state.discoveryDetail ?? "No harness was found yet.") {
                        Button("Search Again") { Task { await state.retryDiscovery() } }
                            .buttonStyle(.settingsPill)
                    }
                }
                SettingsRow("Version check") {
                    Button("Check \(state.activeHarness.displayName) Version") { state.run(.checkForPiUpdates) }
                        .buttonStyle(.settingsPill)
                }
                SettingsRow("Setup instructions") {
                    Button("Show") { state.run(.showPiSetup) }
                        .buttonStyle(.settingsPill)
                }
            }

            SettingsSection("Launch arguments") {
                SettingsBlock {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Extra arguments", text: Binding(
                            get: { state.preferences.extraLaunchArguments },
                            set: { state.preferences.extraLaunchArguments = $0; state.preferences.persist() }
                        ), prompt: Text("--verbose"))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.callout, design: .monospaced))
                        Text("Appended to every `pi --mode rpc` launch. PiCode never writes to Pi's settings files.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            SettingsSection("Pi configuration") {
                ForEach(configFiles, id: \.path) { file in
                    SettingsRow(file.lastPathComponent, detail: file.path.abbreviatingHomeDirectory) {
                        if FileManager.default.fileExists(atPath: file.path) {
                            Button("Reveal") { WorkspaceLauncher.reveal(file.path) }
                                .buttonStyle(.settingsPill)
                        } else {
                            Text("missing").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                }
                SettingsRow("Pi's folder") {
                    Button("Open") { state.run(.revealPiDirectory) }
                        .buttonStyle(.settingsPill)
                }
            }

            SettingsSection("Diagnostics") {
                SettingsRow("Recorded payloads", detail: "\(PiDiagnosticsLog.shared.count) recorded") {
                    HStack(spacing: 8) {
                        Button("View Payload Log") { showsPayloadLog = true }
                            .buttonStyle(.settingsPill)
                        Button("Clear") { PiDiagnosticsLog.shared.clear() }
                            .buttonStyle(.settingsPill)
                    }
                }
            }
        }
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
