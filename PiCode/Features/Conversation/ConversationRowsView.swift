import SwiftUI

/// The row collection does not observe pointer movement. Only the individual
/// response footers read hover state, so crossing rows cannot rebuild the list.
struct ConversationRowsView: View {
    var controller: PiSessionController
    @State private var hover = TranscriptHoverState()

    var body: some View {
        ForEach(controller.rows) { row in
            ConversationMessageRow(row: row, response: controller.responseMetadata[row.id],
                                   controller: controller, hover: hover)
                .equatable()
        }
    }
}
