//
//  ExtensionDialogHost.swift
//  PiCode
//
//  Hosts blocking dialogs requested by Pi extensions.
//
//  Pi's RPC extension UI methods `select`, `confirm`, `input`, and `editor` block
//  the extension until the client answers, so exactly one dialog is presented at
//  a time and the rest queue. PiCode never auto-answers: if an extension needs a
//  decision, the user makes it.
//

import SwiftUI

struct ExtensionDialogHost: View {
    @Bindable var state: AppState

    var body: some View {
        if let controller = state.activeController, let dialog = controller.activeDialog {
            ZStack {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                    .onTapGesture { /* Dialogs are explicit decisions; a stray click must not dismiss them. */ }

                ExtensionDialogView(dialog: dialog, controller: controller)
                    .frame(maxWidth: 520)
                    .padding(24)
                    .transition(.scale(scale: 0.97).combined(with: .opacity))
            }
            .animation(.easeInOut(duration: 0.16), value: controller.activeDialog?.id)
        }
    }
}

struct ExtensionDialogView: View {
    var dialog: ExtensionDialog
    @Bindable var controller: PiSessionController

    @State private var text: String = ""
    @State private var selection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(.tint)
                Text(dialog.title)
                    .font(.headline)
                Spacer(minLength: 0)
                if controller.dialogs.count > 1 {
                    StatusPill(text: "\(controller.dialogs.count - 1) more waiting", tint: .secondary)
                }
            }

            if let message = dialog.message {
                Text(message)
                    .font(.callout)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            switch dialog.request.method {
            case .select:
                selectBody
            case .confirm:
                EmptyView()
            case .input:
                TextField(dialog.request.placeholder ?? "Value", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { confirm() }
            case .editor:
                TextEditor(text: $text)
                    .font(.system(.callout, design: .monospaced))
                    .frame(minHeight: 160)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
            default:
                Text("PiCode cannot render this request type (\(dialog.request.methodName)).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if let timeout = dialog.request.timeoutSeconds {
                Text("Nobody has answered, so Pi will resolve this itself after \(Format.duration(timeout)); this card will close.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Cancel") { controller.cancel(dialog) }
                    .keyboardShortcut(.cancelAction)
                Spacer(minLength: 0)
                Button(confirmTitle) { confirm() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canConfirm)
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.separator))
        .shadow(color: .black.opacity(0.25), radius: 22, y: 8)
        .onAppear {
            text = dialog.draftText
            selection = dialog.selection ?? dialog.request.options.first
        }
        .onChange(of: dialog.id) { _, _ in
            text = dialog.draftText
            selection = dialog.selection ?? dialog.request.options.first
        }
    }

    // MARK: - Select

    private var selectBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(dialog.request.options, id: \.self) { option in
                Button {
                    selection = option
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: selection == option ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(selection == option ? Color.accentColor : Color.secondary)
                        Text(option)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(selection == option ? Color.accentColor.opacity(0.1) : .clear)
                )
            }
        }
    }

    // MARK: - Actions

    private var icon: String {
        switch dialog.request.method {
        case .select: return "list.bullet.circle"
        case .confirm: return "questionmark.circle"
        case .input: return "text.cursor"
        case .editor: return "square.and.pencil"
        default: return "puzzlepiece.extension"
        }
    }

    private var confirmTitle: String {
        switch dialog.request.method {
        case .confirm: return "Confirm"
        case .select: return "Choose"
        default: return "Send"
        }
    }

    private var canConfirm: Bool {
        switch dialog.request.method {
        case .select: return selection != nil
        case .input, .editor: return true
        default: return true
        }
    }

    private func confirm() {
        switch dialog.request.method {
        case .select:
            guard let selection else { return }
            controller.respond(to: dialog, value: selection)
        case .confirm:
            controller.confirm(dialog, confirmed: true)
        case .input, .editor:
            controller.respond(to: dialog, value: text)
        default:
            controller.cancel(dialog)
        }
    }
}
