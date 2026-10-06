import QuartzCore
import SwiftUI

/// Geometry is bookkeeping, not view state. Updating these values while the
/// wheel moves must not invalidate the transcript or its environment closures.
final class ConversationScrollState {
    var viewportHeight: CGFloat = 0
    var bottomY: CGFloat?
    var topGap: CGFloat = .infinity
    var openingTask: Task<Void, Never>?
    var pageTask: Task<Void, Never>?
    /// Fills in earlier history while the transcript is at rest. See
    /// `ConversationView.startIdleHistoryFill`.
    var idleFillTask: Task<Void, Never>?
    /// When the transcript last moved, so history is only prepended while it is
    /// still — a prepend lays out a whole turn at once and would stall a scroll.
    var lastScrollActivity: CFTimeInterval = 0
    var generation = UUID()
    var isPrepending = false
}
