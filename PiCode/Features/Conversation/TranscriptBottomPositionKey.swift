import SwiftUI

/// The actual content bottom in viewport coordinates, including composer space.
struct TranscriptBottomPositionKey: PreferenceKey {
    static let defaultValue: CGFloat? = nil

    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        if let next = nextValue() { value = next }
    }
}
