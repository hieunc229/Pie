//
//  ConversationLayout.swift
//  PiCode
//
//  The transcript's content column, in one place.
//
//  It lives apart from `ConversationView` because the floating composer has to
//  ask for the same column explicitly: an overlay inherits nothing from what it
//  floats over, so without this the box ended up as wide as the *pane* while the
//  rows under it stopped at 860pt — visibly wider than the conversation it
//  belongs to.
//

import SwiftUI

enum ConversationLayout {
    /// The widest the content column ever gets, its own gutter included.
    static let maxContentWidth: CGFloat = 860
    /// Gutter on each side, so rows never touch the pane's edge.
    static let horizontalPadding: CGFloat = 22

    /// The width of the rows themselves — what the eye reads as "the content
    /// width", and what the composer box is measured against.
    static var textColumnWidth: CGFloat { maxContentWidth - horizontalPadding * 2 }
}

/// The content column: apply this to anything that must line up with the
/// transcript's rows. `ConversationView` wraps the transcript in it, and the
/// composer box's container uses it too, so one number decides both.
///
/// The padding goes *inside* the cap — `padding` then `frame(maxWidth:)` — so a
/// narrow window still gets its gutter and a wide one still stops at
/// `maxContentWidth`; reversing the two would make the box 44pt wider than the
/// text at every size.
struct ConversationColumn<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, ConversationLayout.horizontalPadding)
            .frame(maxWidth: ConversationLayout.maxContentWidth)
    }
}
