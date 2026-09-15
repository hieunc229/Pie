//
//  ComposerView.swift
//  PiCode
//
//  The prompt composer: text, attachments, model/thinking controls, and the
//  send/queue decision.
//
//  PiCode sends exactly what the user typed. Slash commands and `@path`
//  references are Pi's own prompt syntax, so the composer only autocompletes
//  them; it never rewrites the prompt on the way out.
//

import AppKit
import SwiftUI

/// Shape, padding and height constants shared by the composer and its harness.
///
/// They are here, and not inline in the view, so the harness can *predict* the
/// box's height and width instead of hard-coding a number that then drifts: it
/// asserts the measured box against `boxHeight(forEditor:)` and against
/// `ConversationLayout.maxContentWidth`.
enum ComposerMetrics {
    /// Rounded enough that the box reads as one soft object next to the sidebar's
    /// pills, small enough that a single line does not look like a capsule.
    static let cornerRadius: CGFloat = 18

    /// The box's own padding. Roomy on the sides and underneath: the prompt should
    /// sit in the box rather than press against its edge, and the controls need air
    /// below the text they act on. There is deliberately *none* on top — the editor
    /// already carries its own text inset, and the box must shrink to exactly the
    /// editor's height plus this chrome, so a two-line prompt is a two-line box and
    /// not a box with a blank band above it.
    static let boxHorizontalPadding: CGFloat = 12
    static let boxTopPadding: CGFloat = 0
    static let boxBottomPadding: CGFloat = 8

    /// Between the editor and the control row, and a little more before an
    /// attachment chip row when one is showing.
    static let editorControlGap: CGFloat = 7
    static let attachmentGap: CGFloat = 8

    /// What one control row takes. Not a guess: the harness measures the drawn
    /// box against `boxHeight(forEditor:)`, so a control that grows taller than
    /// this is caught rather than silently absorbed.
    static let controlRowHeight: CGFloat = 20

    /// The editor's own height: two lines always visible, six before it starts
    /// scrolling instead of growing further.
    static var editorMinHeight: CGFloat { ComposerTextView.height(forLines: ComposerTextView.minimumLines) + 8 }
    static var editorMaxHeight: CGFloat { ComposerTextView.height(forLines: ComposerTextView.maximumLines) + 8 }

    /// The box's height for an editor of `editorHeight` — the number the harness
    /// checks the rendered box against. Attachments add a row on top.
    static func boxHeight(forEditor editorHeight: CGFloat) -> CGFloat {
        editorHeight + boxTopPadding + editorControlGap + controlRowHeight + boxBottomPadding
    }
}

struct ComposerView: View {
    @Bindable var state: AppState
    var controller: PiSessionController
    var focusTick: Int

    @State private var text = ""
    @State private var attachments: [Attachment] = []
    @State private var suggestionIndex = 0
    @State private var fileMatches: [FileNode] = []
    @State private var fileSearchTask: Task<Void, Never>?
    @State private var isSending = false
    @State private var attachmentError: String?
    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !suggestions.isEmpty {
                ComposerSuggestionList(
                    suggestions: suggestions,
                    selectedIndex: suggestionIndex,
                    onSelect: accept(suggestion:),
                    onHover: { index in suggestionIndex = index }
                )
            }

            if let attachmentError {
                BannerView(level: .warning, title: "Attachment not added", message: attachmentError, onDismiss: { self.attachmentError = nil })
            }

            composerBox
        }
        .onAppear { loadDraft() }
        .onChange(of: controller.draftKey) { _, _ in loadDraft() }
        .onChange(of: controller.composerPrefill) { _, newValue in
            guard let newValue, !newValue.isEmpty else { return }
            text = newValue
            controller.composerPrefill = nil
        }
        .onChange(of: state.composerInsertion) { _, newValue in
            guard let newValue, !newValue.isEmpty else { return }
            text = text.isEmpty ? newValue : text + " " + newValue
            state.composerInsertion = nil
        }
        .onChange(of: text) { _, newValue in
            controller.drafts.setText(newValue, for: controller.draftKey, attachments: attachments)
            suggestionIndex = 0
            refreshFileMatchesIfNeeded()
        }
    }

    // MARK: - Editor

    /// One rounded box: the editor on top, every control on one row beneath it.
    /// The box is the only filled shape in the composer — there is no second
    /// container behind it, so the whole thing reads as one object instead of a
    /// card sitting inside a bar. It is also deliberately short: two lines of
    /// text, then the controls (§6).
    private var composerBox: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The placeholder is drawn inside the text view, at the same origin
            // as real text, so the two cannot sit on different lines.
            ComposerTextView(
                text: $text,
                placeholder: placeholder,
                focusTick: focusTick,
                sendKey: state.preferences.sendKey,
                suggestionsActive: !suggestions.isEmpty,
                isEnabled: controller.connection.isConnected,
                onSend: { send() },
                onFollowUp: { send(delivery: .followUp) },
                onEscape: handleEscape,
                onMoveSuggestion: moveSuggestion,
                onAcceptSuggestion: acceptCurrentSuggestion
            )
            .frame(minHeight: ComposerMetrics.editorMinHeight, maxHeight: ComposerMetrics.editorMaxHeight)
            .padding(.top, 8)
            
            // `.frame(minHeight:maxHeight:)` is flexible: the composer floats in
            // an overlay, so the stack that holds the box is proposed the whole
            // pane height and hands the surplus to the only child that will take
            // it — the editor — which then sits at `editorMaxHeight` even when it
            // is empty (a blank band above the placeholder). `fixedSize` proposes
            // no height, so the frame resolves to the height `sizeThatFits`
            // measured for the text, and the box is two lines when the prompt is.
            .fixedSize(horizontal: false, vertical: true)

            if !attachments.isEmpty {
                attachmentRow.padding(.top, ComposerMetrics.attachmentGap)
            }

            controlRow.padding(.top, ComposerMetrics.editorControlGap)
        }
        .padding(.horizontal, ComposerMetrics.boxHorizontalPadding)
        .padding(.top, ComposerMetrics.boxTopPadding)
        .padding(.bottom, ComposerMetrics.boxBottomPadding)
        .background(AppTheme.composerFill, in: RoundedRectangle(cornerRadius: ComposerMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ComposerMetrics.cornerRadius, style: .continuous)
                .stroke(isDropTargeted ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: isDropTargeted ? 2 : 1)
        )
        .dropDestination(for: URL.self) { urls, _ in
            addAttachments(urls)
            return true
        } isTargeted: { isDropTargeted = $0 }
    }

    private var placeholder: String {
        if !controller.connection.isConnected { return "Pi is not running…" }
        if controller.runtime.isBusy { return "Steer Pi, or queue a follow-up…" }
        return "Ask Pi to do something"
    }

    private var attachmentRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(attachments) { attachment in
                    HStack(spacing: 6) {
                        Image(systemName: attachment.systemImage)
                            .imageScale(.small)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(attachment.fileName)
                                .font(.caption)
                                .lineLimit(1)
                            Text(attachment.displaySize)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Button {
                            attachments.removeAll { $0.id == attachment.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .imageScale(.small)
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove \(attachment.fileName)")
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 7))
                }
            }
            .padding(.horizontal, 2)
        }
    }

    // MARK: - Controls

    /// Left: what goes into the prompt. Right: how Pi will run it. One row, and
    /// no more: everything that used to sit here (a queue counter, a separate
    /// interrupt, a steering/follow-up dropdown) is either redundant with Return
    /// or lives on the stop button's own shortcut.
    private var controlRow: some View {
        HStack(spacing: 2) {
            iconButton("paperclip", help: "Attach images or text files — drag and drop works too") {
                chooseAttachments()
            }

            ComposerAccessControl(controller: controller)

            Spacer(minLength: 8)

            // The model/reasoning control and the send button are the two ends of
            // one action — choose how, then do it — so they sit apart from the
            // attachment controls and with a clear gap between them.
            HStack(spacing: 10) {
                modelThinkingMenu
                primaryActionButton
            }
        }
        .font(.system(size: 12))
    }

    private func iconButton(_ systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    /// Idle it sends; working it stops. Both are one button, in the place the
    /// hand already is.
    @ViewBuilder
    private var primaryActionButton: some View {
        if isStreamingRun {
            Button {
                Task {
                    // The documented Stop: clear the queue, put what was queued
                    // back in the box, then abort. `⌘.` in the menu is the
                    // hard stop that leaves the queue to Pi.
                    await controller.interrupt()
                    text = controller.drafts.text(for: controller.draftKey)
                }
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.accentColor))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Stop Pi and put anything queued back in the box (esc; ⌘. aborts without restoring)")
        } else {
            Button {
                send(delivery: .automatic)
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(canSend ? Color.accentColor : Color(nsColor: .tertiaryLabelColor)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .help("Send (⏎)")
        }
    }

    /// Model and reasoning effort, as one control: the model's name, the effort
    /// beside it when the model is reasoning, and a chevron that opens both
    /// pickers. They are one choice — how Pi will answer — so they are one menu.
    private var modelThinkingMenu: some View {
        Menu {
            ForEach(providers, id: \.self) { provider in
                Section(provider) {
                    ForEach(controller.availableModels.filter { $0.provider == provider }) { model in
                        Button {
                            Task { await controller.setModel(model) }
                        } label: {
                            if model.id == controller.model?.id {
                                Label(model.displayName, systemImage: "checkmark")
                            } else {
                                Text(model.displayName)
                            }
                        }
                    }
                }
            }

            Divider()

            Section("Reasoning effort") {
                ForEach(controller.thinkingLevels, id: \.self) { level in
                    Button {
                        Task { await controller.setThinkingLevel(level) }
                    } label: {
                        if level == controller.thinkingLevel {
                            Label(level, systemImage: "checkmark")
                        } else {
                            Text(level)
                        }
                    }
                }
                if controller.thinkingLevels.isEmpty {
                    Text("This model has no reasoning levels")
                }
            }

            Divider()
            Button("Cycle Model") { Task { await controller.cycleModel() } }
            if !controller.thinkingLevels.isEmpty {
                Button("Cycle Reasoning Effort") { Task { await controller.cycleThinkingLevel() } }
            }
        } label: {
            // No hand-drawn chevron: `Menu` already draws its own indicator, and a
            // second one in front of the model name read as two separate controls.
            HStack(spacing: 4) {
                Text(controller.model?.displayName ?? "Model")
                    .lineLimit(1)
                if let effort {
                    Text(effort)
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.callout)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .foregroundStyle(.secondary)
        .help("Model and reasoning effort used for new prompts")
    }

    /// The reasoning effort to draw beside the model, or `nil` when the model is
    /// not reasoning: an "off" level is not a second word to read, it is silence.
    private var effort: String? {
        guard let level = controller.thinkingLevel?.trimmingCharacters(in: .whitespaces),
              !level.isEmpty,
              level.lowercased() != "off"
        else { return nil }
        return level
    }

    // MARK: - Send

    private var isStreamingRun: Bool { controller.runtime.isBusy }

    private var canSend: Bool {
        let hasContent = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || attachments.contains { $0.imagePayload != nil }
        return hasContent && controller.connection.isConnected && !isSending
    }

    private func send(delivery: PiSessionController.PromptDelivery = .automatic) {
        guard canSend else { return }
        let outgoing = text
        let outgoingAttachments = attachments
        isSending = true
        Task {
            let delivered = await controller.send(text: outgoing, attachments: outgoingAttachments, delivery: delivery)
            isSending = false
            if delivered {
                text = ""
                attachments = []
                fileMatches = []
            }
        }
    }

    private func handleEscape() {
        if !suggestions.isEmpty {
            text = suggestionContextCleared()
            fileMatches = []
            return
        }
        if controller.hasPendingWork {
            Task {
                await controller.interrupt()
                text = controller.drafts.text(for: controller.draftKey)
            }
        }
    }

    private func loadDraft() {
        text = controller.drafts.text(for: controller.draftKey)
    }

    // MARK: - Attachments

    private func chooseAttachments() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.message = "Images are sent to Pi as image content. Text files are inlined as @path references."
        guard panel.runModal() == .OK else { return }
        addAttachments(panel.urls)
    }

    private func addAttachments(_ urls: [URL]) {
        attachmentError = nil
        var failures: [String] = []
        for url in urls {
            switch AttachmentLoader.load(url: url) {
            case .success(let attachment):
                guard !attachments.contains(where: { $0.path == attachment.path && $0.fileName == attachment.fileName }) else { continue }
                attachments.append(attachment)
            case .failure(let failure):
                failures.append(failure.message)
            }
        }
        if !failures.isEmpty {
            attachmentError = failures.joined(separator: "\n") + " (AppleScript-based and binary formats are not attached.)"
        }
    }

    // MARK: - Suggestions

    private var suggestions: [ComposerSuggestion] {
        if let query = commandQuery {
            let matches = controller.commands.filter { command in
                query.isEmpty
                    || command.name.lowercased().contains(query.lowercased())
                    || command.description.lowercased().contains(query.lowercased())
            }
            return matches.prefix(8).map(ComposerSuggestion.init(command:))
        }
        if fileQuery != nil {
            return fileMatches.prefix(8).compactMap { node in
                ComposerSuggestion(node: node, root: controller.projectPath)
            }
        }
        return []
    }

    /// Everything after the first character, when the composer holds only a
    /// slash command being typed.
    private var commandQuery: String? {
        guard text.hasPrefix("/"), !text.contains("\n") else { return nil }
        let body = String(text.dropFirst())
        guard !body.contains(" ") else { return nil }
        return body
    }

    /// The `@path` token being typed at the end of the composer.
    private var fileQuery: String? {
        guard let atIndex = text.lastIndex(of: "@") else { return nil }
        let prefix = text[text.startIndex..<atIndex]
        if let last = prefix.last, !last.isWhitespace, !last.isNewline { return nil }
        let token = text[text.index(after: atIndex)...]
        guard !token.contains(where: { $0.isWhitespace || $0.isNewline }) else { return nil }
        return String(token)
    }

    private func refreshFileMatchesIfNeeded() {
        guard let query = fileQuery else {
            fileSearchTask?.cancel()
            fileMatches = []
            return
        }
        let root = controller.projectPath
        fileSearchTask?.cancel()
        fileSearchTask = Task {
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            let matches = await Task.detached(priority: .userInitiated) {
                ProjectFileTree.search(root: root, query: query, limit: 60)
            }.value
            guard !Task.isCancelled else { return }
            fileMatches = matches
        }
    }

    private func accept(suggestion: ComposerSuggestion) {
        switch suggestion.kind {
        case .command:
            text = suggestion.insertion
        case .file:
            guard let atIndex = text.lastIndex(of: "@") else { return }
            text = String(text[text.startIndex..<atIndex]) + suggestion.insertion
        }
        fileMatches = []
        suggestionIndex = 0
    }

    private func acceptCurrentSuggestion() {
        let list = suggestions
        guard !list.isEmpty else { return }
        accept(suggestion: list[min(suggestionIndex, list.count - 1)])
    }

    private func moveSuggestion(_ delta: Int) {
        let count = suggestions.count
        guard count > 0 else { return }
        suggestionIndex = (suggestionIndex + delta + count) % count
    }

    private func suggestionContextCleared() -> String {
        if commandQuery != nil { return "" }
        if let atIndex = text.lastIndex(of: "@") {
            return String(text[text.startIndex..<atIndex])
        }
        return text
    }

    private var providers: [String] {
        Array(Set(controller.availableModels.map(\.provider))).sorted()
    }
}

// MARK: - Suggestions list

struct ComposerSuggestion: Identifiable, Equatable {
    enum Kind: Equatable { case command, file }

    var id: String
    var kind: Kind
    var title: String
    var subtitle: String?
    var insertion: String
    var systemImage: String

    init(command: PiCommand) {
        id = "command-\(command.name)"
        kind = .command
        title = command.invocation
        subtitle = command.description.isEmpty ? command.sourceLabel : command.description
        insertion = command.invocation + " "
        systemImage = command.source == .skill ? "sparkles" : "slash.circle"
    }

    init?(node: FileNode, root: String) {
        guard !node.isDirectory else { return nil }
        let relative = ProjectFileTree.relativePath(of: node.path, from: root)
        id = "file-\(node.path)"
        kind = .file
        title = relative
        subtitle = node.byteSize > 0 ? ByteCountFormatter.string(fromByteCount: Int64(node.byteSize), countStyle: .file) : nil
        insertion = "@" + relative + " "
        systemImage = "doc.text"
    }
}

struct ComposerSuggestionList: View {
    var suggestions: [ComposerSuggestion]
    var selectedIndex: Int
    var onSelect: (ComposerSuggestion) -> Void
    var onHover: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                Button {
                    onSelect(suggestion)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: suggestion.systemImage)
                            .imageScale(.small)
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        Text(suggestion.title)
                            .font(.callout.monospaced())
                            .lineLimit(1)
                        if let subtitle = suggestion.subtitle {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(index == selectedIndex ? Color.accentColor.opacity(0.14) : .clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering { onHover(index) }
                }
            }
        }
        .padding(.vertical, 4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(.separator))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
    }
}

// MARK: - Attachment loading

enum AttachmentLoader {
    struct Failure: Error {
        var message: String
    }

    static let maxImageBytes = 12 * 1024 * 1024
    static let maxTextBytes = 400 * 1024

    static func load(url: URL) -> Result<Attachment, Failure> {
        let path = url.path
        let name = url.lastPathComponent
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        let size = (attributes?[.size] as? NSNumber)?.intValue ?? 0
        let mime = FileClassification.mimeType(for: path)

        if FileClassification.isImage(path: path) {
            guard size <= maxImageBytes else {
                return .failure(Failure(message: "\(name) is larger than \(ByteCountFormatter.string(fromByteCount: Int64(maxImageBytes), countStyle: .file))."))
            }
            guard let data = try? Data(contentsOf: url) else {
                return .failure(Failure(message: "Could not read \(name)."))
            }
            return .success(Attachment(
                kind: .image,
                fileName: name,
                mimeType: mime,
                byteSize: size,
                path: path,
                imageData: data.base64EncodedString(),
                textContent: nil,
                error: nil
            ))
        }

        if FileClassification.isTextLike(path: path) {
            guard size <= maxTextBytes else {
                return .failure(Failure(message: "\(name) is larger than \(ByteCountFormatter.string(fromByteCount: Int64(maxTextBytes), countStyle: .file)). Use an @path reference instead."))
            }
            let preview = FilePreviewLoader.load(path: path)
            if let error = preview.error {
                return .failure(Failure(message: "Could not read \(name): \(error)"))
            }
            return .success(Attachment(
                kind: .text,
                fileName: name,
                mimeType: mime,
                byteSize: preview.byteSize,
                path: path,
                imageData: nil,
                textContent: preview.text,
                error: nil
            ))
        }

        return .failure(Failure(message: "\(name) is not an image or a text file."))
    }
}
