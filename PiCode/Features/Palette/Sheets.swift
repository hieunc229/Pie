//
//  Sheets.swift
//  PiCode
//
//  Modal confirmations. Every sheet that changes state does so by asking Pi —
//  PiCode never edits a session file directly.
//

import SwiftUI

// MARK: - Rename

struct RenameSessionSheet: View {
    @Bindable var state: AppState
    /// The chat to rename. `nil` means the session on screen, which is how the
    /// palette command names the active one.
    var session: SessionRef?
    var currentName: String
    var onFinish: () -> Void

    @State private var name = ""
    @State private var isSaving = false
    @FocusState private var isFocused: Bool

    var body: some View {
        SheetScaffold(
            title: "Rename Session",
            message: "Pi stores the name in the session file, so other Pi clients see it too.",
            primaryTitle: isSaving ? "Saving…" : "Rename",
            isPrimaryDisabled: name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving,
            onCancel: onFinish
        ) {
            save()
        } content: {
            TextField("Session name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onAppear {
                    name = currentName
                    isFocused = true
                }
                .onSubmit { save() }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        Task {
            isSaving = true
            if let session {
                // A chat picked in the sidebar: rename that one, whether or not it
                // is the session on screen.
                await state.rename(session: session, to: trimmed)
            } else {
                await state.activeController?.setSessionName(trimmed)
            }
            isSaving = false
            onFinish()
        }
    }
}

// MARK: - Compact

struct CompactSessionSheet: View {
    @Bindable var state: AppState
    var onFinish: () -> Void

    @State private var instructions = ""
    @State private var isRunning = false

    var body: some View {
        SheetScaffold(
            title: "Compact with Instructions",
            message: "Pi summarizes the conversation, keeping what you describe here. Your existing messages stay in the session file.",
            primaryTitle: isRunning ? "Compacting…" : "Compact",
            isPrimaryDisabled: isRunning,
            onCancel: onFinish
        ) {
            Task {
                isRunning = true
                await state.activeController?.compact(customInstructions: instructions.trimmingCharacters(in: .whitespacesAndNewlines))
                isRunning = false
                onFinish()
            }
        } content: {
            TextEditor(text: $instructions)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 120)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
        }
    }
}

// MARK: - Fork

struct ForkSessionSheet: View {
    @Bindable var state: AppState
    var onFinish: () -> Void

    @State private var selectedId: String?
    @State private var isForking = false

    var body: some View {
        SheetScaffold(
            title: "Fork Session",
            message: "Forking starts a new session from a message in this conversation. The original session is left untouched.",
            primaryTitle: isForking ? "Forking…" : "Fork",
            isPrimaryDisabled: selectedId == nil || isForking,
            onCancel: onFinish
        ) {
            guard let selectedId else { return }
            Task {
                isForking = true
                await state.activeController?.fork(fromEntryId: selectedId)
                isForking = false
                onFinish()
            }
        } content: {
            Group {
                if forkPoints.isEmpty {
                    Text("Pi has not reported any forkable messages yet. Send a message first.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(forkPoints) { point in
                                Button {
                                    selectedId = point.entryId
                                } label: {
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: selectedId == point.entryId ? "largecircle.fill.circle" : "circle")
                                            .foregroundStyle(selectedId == point.entryId ? Color.accentColor : Color.secondary)
                                            .padding(.top, 1)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(point.text.oneLinePreview(limit: 200))
                                                .font(.callout)
                                                .multilineTextAlignment(.leading)
                                            Text(point.entryId)
                                                .font(.caption2.monospaced())
                                                .foregroundStyle(.tertiary)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .padding(6)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(selectedId == point.entryId ? Color.accentColor.opacity(0.12) : .clear)
                                    )
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(minHeight: 160, maxHeight: 280)
                }
            }
        }
        .task {
            await state.activeController?.refreshForkPoints()
        }
    }

    private var forkPoints: [PiForkPoint] {
        state.activeController?.forkPoints ?? []
    }
}

// MARK: - Delete

struct DeleteSessionSheet: View {
    @Bindable var state: AppState
    var session: SessionRef
    var onFinish: () -> Void

    var body: some View {
        SheetScaffold(
            title: "Delete Session?",
            message: message,
            primaryTitle: "Delete",
            primaryRole: .destructive,
            isPrimaryDisabled: session.filePath == nil,
            onCancel: onFinish
        ) {
            // The answer is the decision, so nothing here waits on it: the row is
            // already out of the sidebar and the file is unlinked before the sheet
            // goes, and only the rescan runs behind the window. A failure has no
            // sheet left to appear in, so it reports itself in the window's banner
            // (`AppState.delete`).
            state.delete(session: session)
            onFinish()
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                if let path = session.filePath {
                    Text(path.abbreviatingHomeDirectory)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(3)
                        .truncationMode(.middle)
                }
                Text("Deleting removes the session's `.jsonl` file from disk and cannot be undone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var message: String {
        session.filePath == nil
            ? "This session has not been written to disk yet. Close it instead of deleting it."
            : "This permanently deletes \(session.displayName) from Pi's session folder."
    }
}

// MARK: - Project settings

/// Edits PiCode's own per-project choices: the name the sidebar shows, the folder
/// new chats start in, and a system prompt appended to Pi for new sessions.
///
/// Nothing here rewrites a session or Pi's configuration. The name is a PiCode
/// label; the folder only affects chats started *after* the change (Pi keeps every
/// session in the folder it actually ran in); the system prompt is handed to Pi as
/// `--append-system-prompt` on the next launch.
struct ProjectSettingsSheet: View {
    @Bindable var state: AppState
    var project: ProjectGroup
    var onFinish: () -> Void

    @State private var name = ""
    @State private var directory = ""
    @State private var systemPrompt = ""
    @State private var harnessID: HarnessID = .pi
    @State private var provider = ""
    @State private var model = ""
    @State private var isSaving = false

    var body: some View {
        SheetScaffold(
            title: "Project Settings",
            message: "Stored on this Mac only. PiCode never writes Pi's configuration or edits session files.",
            primaryTitle: isSaving ? "Saving…" : "Save",
            isPrimaryDisabled: isSaving,
            onCancel: onFinish
        ) {
            Task {
                isSaving = true
                var settings = state.projectSettings(for: project)
                settings.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                settings.directory = directory.trimmingCharacters(in: .whitespacesAndNewlines)
                settings.systemPrompt = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                settings.harness = harnessID
                settings.providerID = provider.isEmpty ? nil : provider
                settings.modelID = model.isEmpty ? nil : model
                await state.updateProjectSettings(settings, for: project)
                isSaving = false
                onFinish()
            }
        } content: {
            VStack(alignment: .leading, spacing: 16) {
                field("Name", caption: "Shown in the sidebar and header. Blank uses the folder name.") {
                    TextField(URL(fileURLWithPath: project.path).lastPathComponent, text: $name)
                        .textFieldStyle(.roundedBorder)
                }

                field("Folder", caption: "New chats start here. Existing sessions keep the folder they ran in.") {
                    HStack(spacing: 8) {
                        TextField(project.path.abbreviatingHomeDirectory, text: $directory)
                            .textFieldStyle(.roundedBorder)
                        Button("Choose…") {
                            if let chosen = WorkspaceLauncher.chooseDirectory(prompt: "Choose a folder for new chats") {
                                directory = chosen
                            }
                        }
                    }
                }

                if !state.harnesses.usableHarnesses.isEmpty {
                    field("Harness", caption: "Agent runtime new chats in this project use.") {
                        Picker("Harness", selection: $harnessID) {
                            ForEach(state.harnesses.usableHarnesses) { descriptor in
                                Text(descriptor.displayName).tag(descriptor.id)
                            }
                        }
                        .labelsHidden()
                    }
                }

                if harnessID == .pi {
                    field("Provider and model", caption: "Optional Pi configuration. Other harnesses own separate provider catalogs.") {
                        VStack(alignment: .leading, spacing: 6) {
                            Picker("Provider", selection: $provider) {
                                Text("Automatic").tag("")
                                ForEach(providerOptions, id: \.self) { id in
                                    Text(id).tag(id)
                                }
                            }
                            if !modelOptions.isEmpty {
                                Picker("Model", selection: $model) {
                                    Text("Automatic").tag("")
                                    ForEach(modelOptions, id: \.self) { id in
                                        Text(id).tag(id)
                                    }
                                }
                            } else {
                                TextField("Model", text: $model, prompt: Text("provider/model"))
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.caption, design: .monospaced))
                            }
                        }
                    }
                } else if let descriptor = state.harnesses.usableHarnesses.first(where: { $0.id == harnessID }) {
                    field("Provider and model", caption: "Configured independently by \(descriptor.displayName).") {
                        Text("Choose from \(descriptor.displayName)'s reported model catalog after starting the chat.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                field("System prompt", caption: "Appended to the agent's system prompt for new sessions in this project.") {
                    TextEditor(text: $systemPrompt)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 110)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
                }
            }
            .onAppear {
                let settings = state.projectSettings(for: project)
                name = settings.name
                directory = settings.directory
                systemPrompt = settings.systemPrompt
                harnessID = settings.harness ?? state.preferences.defaultHarnessID
                provider = settings.providerID ?? ""
                model = settings.modelID ?? ""
            }
        }
    }

    private var providerOptions: [String] {
        var ids = Set(PiProviderService.credentials().map(\.provider))
        for provider in PiProviderService.customProviders() { ids.insert(provider.id) }
        if let controller = state.activeController {
            for entry in controller.availableModels { ids.insert(entry.provider) }
        }
        return ids.sorted()
    }

    private var modelOptions: [String] {
        guard !provider.isEmpty else { return [] }
        var ids: [String] = []
        if let custom = PiProviderService.customProviders().first(where: { $0.id == provider }) {
            ids.append(contentsOf: custom.models.map(\.id))
        }
        if let controller = state.activeController {
            ids.append(contentsOf: controller.availableModels.filter { $0.provider == provider }.map(\.id))
        }
        return Array(Set(ids)).sorted()
    }

    @ViewBuilder
    private func field<Content: View>(
        _ title: String,
        caption: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.callout.weight(.medium))
            content()
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Shared shell

/// A consistent sheet frame: title, explanation, content, cancel + confirm.
struct SheetScaffold<Content: View>: View {
    var title: String
    var message: String
    var primaryTitle: String
    var primaryRole: ButtonRole?
    var isPrimaryDisabled: Bool
    var onCancel: () -> Void
    var onPrimary: () -> Void
    @ViewBuilder var content: () -> Content

    init(
        title: String,
        message: String,
        primaryTitle: String,
        primaryRole: ButtonRole? = nil,
        isPrimaryDisabled: Bool = false,
        onCancel: @escaping () -> Void,
        onPrimary: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.message = message
        self.primaryTitle = primaryTitle
        self.primaryRole = primaryRole
        self.isPrimaryDisabled = isPrimaryDisabled
        self.onCancel = onCancel
        self.onPrimary = onPrimary
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            content()

            HStack {
                Spacer(minLength: 0)
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(primaryTitle, role: primaryRole, action: onPrimary)
                    .buttonStyle(.borderedProminent)
                    .disabled(isPrimaryDisabled)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 420, maxWidth: 520)
    }
}
