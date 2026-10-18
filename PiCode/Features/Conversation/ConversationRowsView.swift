import SwiftUI

/// The row collection does not observe pointer movement. Only the individual
/// response footers read hover state, so crossing rows cannot rebuild the list.
///
/// Rows far from the viewport are drawn as empty space of their measured height
/// (`TranscriptVirtualizer`); everything else is the row itself.
struct ConversationRowsView: View {
    var controller: PiSessionController
    var virtualizer: TranscriptVirtualizer
    @State private var hover = TranscriptHoverState()

    var body: some View {
        ForEach(controller.rows) { row in
            if virtualizer.hiddenIDs.contains(row.id), let height = virtualizer.height(of: row.id) {
                Color.clear.frame(height: height)
            } else {
                ConversationMessageRow(row: row, response: controller.responseMetadata[row.id],
                                       controller: controller, hover: hover)
                    .equatable()
                    .background(TranscriptRowHeightReporter(id: row.id, virtualizer: virtualizer))
            }
        }
        .onChange(of: controller.rows.map(\.id), initial: true) { _, ids in
            virtualizer.update(rowIDs: ids)
        }
    }
}
