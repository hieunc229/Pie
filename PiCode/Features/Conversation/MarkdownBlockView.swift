import SwiftUI

/// Unchanged blocks retain their rendered subtree while the response streams.
struct MarkdownBlockView: View, Equatable {
    var block: MarkdownBlock

    var body: some View {
        renderBlock(block)
    }
}

