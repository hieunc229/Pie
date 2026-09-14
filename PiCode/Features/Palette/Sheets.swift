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
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        Task {
            guard let controller = state.activeController else { return }
            isSaving = true
            await controller.setSessionName(name.trimmingCharacters(in: .whitespaces))
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

    @State private var isDeleting = false
    @State private var error: String?

    var body: some View {
        SheetScaffold(
            title: "Delete Session?",
            message: message,
            primaryTitle: isDeleting ? "Deleting…" : "Delete",
            primaryRole: .destructive,
            isPrimaryDisabled: isDeleting || session.filePath == nil,
            onCancel: onFinish
        ) {
            Task {
                isDeleting = true
                do {
                    try await state.delete(session: session)
                    isDeleting = false
                    onFinish()
                } catch {
                    self.error = error.localizedDescription
                    isDeleting = false
                }
            }
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                if let path = session.filePath {
                    Text(path.abbreviatingHomeDirectory)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(3)
                        .truncationMode(.middle)
                }
                if let error {
                    BannerView(level: .error, title: "Could not delete", message: error, onDismiss: { self.error = nil })
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
