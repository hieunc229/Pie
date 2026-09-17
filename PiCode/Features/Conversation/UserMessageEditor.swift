import SwiftUI

struct UserMessageEditor: View {
    @State var text: String
    var entryId: String
    var controller: PiSessionController
    var onCancel: () -> Void
    @State private var isSending = false
    @State private var error: String?
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextEditor(text: $text)
                .font(TranscriptStyle.text)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 100, maxHeight: 260)
                .focused($isFocused)
                .disabled(isSending)
                .accessibilityLabel("Edit message")

            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .disabled(isSending)
                Button(isSending ? "Sending…" : "Send") {
                    isSending = true
                    error = nil
                    Task {
                        let sent = await controller.fork(fromEntryId: entryId, prefill: false, editedText: text)
                        isSending = false
                        if sent {
                            onCancel()
                        } else {
                            error = controller.lastError ?? "The edit was not sent. Your text has been kept."
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSending || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || controller.runtime.isBusy || controller.isChangingBranch)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color.gray.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
        .onAppear { isFocused = true }
    }
}
