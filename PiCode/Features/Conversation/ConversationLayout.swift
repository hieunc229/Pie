//
//  ConversationLayout.swift
//  PiCode
//
//  The transcript's content column, in one place.
//
//  It lives apart from `ConversationView` because the floating composer has to
//  ask for the same column explicitly: an overlay inherits nothing from what it
//  floats over, so without this the box ended up as wide as the *pane* while the
//  rows under it stopped at the cap — visibly wider than the conversation it
//  belongs to.
//
//  The one number a person would name is the width of the *content* — what the
//  rows and the box measure — so that is what `maxContentWidth` holds and the
//  column's cap is derived from it. Do not put the gutters into
//  `maxContentWidth`: the frame below would then hand the text 44pt less than it
//  says, which is exactly the off-by-a-gutter this file exists to prevent.
//

import SwiftUI

enum ConversationLayout {
    /// The widest the rows themselves get — what the eye reads as "the content
    /// width", and the width of the composer box. 736pt: wide enough for a code
    /// block and a table to breathe, narrow enough that a long line of prose stays
    /// readable on a 27-inch display, where the pane can be 1600pt.
    static let maxContentWidth: CGFloat = 736
    /// Gutter on each side, so rows never touch the pane's edge.
    static let horizontalPadding: CGFloat = 22

    /// What `.frame(maxWidth:)` gets: the content plus its gutters, because the
    /// padding goes *inside* the cap (see `ConversationColumn`).
    static var maxColumnWidth: CGFloat { maxContentWidth + horizontalPadding * 2 }
}

/// The content column: apply this to anything that must line up with the
/// transcript's rows. `ConversationView` wraps the transcript in it, and the
/// composer box's container uses it too, so one number decides both.
///
/// The padding goes *inside* the cap — `padding` then `frame(maxWidth:)` — so a
/// narrow window still gets its gutter and a wide one still stops at
/// `maxColumnWidth` with `maxContentWidth` of text; reversing the two would make
/// the box 44pt wider than the text at every size.
struct ConversationColumn<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, ConversationLayout.horizontalPadding)
            .frame(maxWidth: ConversationLayout.maxColumnWidth)
    }
}
