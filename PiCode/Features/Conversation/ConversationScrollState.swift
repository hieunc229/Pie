import SwiftUI

/// Geometry is bookkeeping, not view state. Updating these values while the
/// wheel moves must not invalidate the transcript or its environment closures.
final class ConversationScrollState {
    var viewportHeight: CGFloat = 0
    var bottomY: CGFloat?
    var topGap: CGFloat = .infinity
    var openingTask: Task<Void, Never>?
    var pageTask: Task<Void, Never>?
    var generation = UUID()
    var isPrepending = false
}
