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

    /// How far a step's *content* sits inside the line that owns it: a call's
    /// output under its own summary, reasoning under its `Thinking` line. One
    /// number, so the transcript never spends two steps' worth of width on
    /// indentation.
    ///
    /// It is not applied to the list of steps inside a run: a step's glyph belongs
    /// in the same column as the run's own glyph, so the labels of a run and the
    /// steps under it line up down the page. Indentation here means "this belongs to
    /// the line above", not "this is one level deeper".
    static let nestedIndent: CGFloat = 15
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

/// The transcript's row stack: what `VStack(alignment: .leading, spacing:)`
/// draws, without the parts of `VStack` that scale with the row count.
///
/// The transcript lays out every loaded row, and a long agent turn is hundreds
/// of them. On every streaming flush `VStack` re-ranked all of its children by
/// flexibility (an insertion sort) and asked each one for its leading
/// alignment guide, which recurses through the row's own stacks — so one token
/// cost a walk of the whole loaded history, well over a frame. Rows here are
/// all full-width and leading, so neither is needed: each row is measured at
/// the column's width (SwiftUI caches that per row, so an unchanged row is a
/// lookup) and placed below the previous one.
struct TranscriptStackLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rowProposal = ProposedViewSize(width: proposal.width, height: nil)
        var width: CGFloat = 0
        var height: CGFloat = 0
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(rowProposal)
            width = max(width, size.width)
            height += size.height
            if index > subviews.startIndex { height += spacing }
        }
        return CGSize(width: width, height: height)
    }

    /// No guides of its own, and none read from the rows: the transcript is
    /// top-aligned in its container, and asking hundreds of rows for a guide
    /// recurses through every one of them.
    func explicitAlignment(of guide: HorizontalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
                           subviews: Subviews, cache: inout ()) -> CGFloat? { nil }

    func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
                           subviews: Subviews, cache: inout ()) -> CGFloat? { nil }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rowProposal = ProposedViewSize(width: bounds.width, height: nil)
        var y = bounds.minY
        for subview in subviews {
            let size = subview.sizeThatFits(rowProposal)
            subview.place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading, proposal: rowProposal)
            y += size.height + spacing
        }
    }
}

/// The transcript's viewport: exactly as big as it is offered, with no
/// alignment guides of its own.
///
/// A scroll view asked for its size — by a stack ranking its children, by an
/// alignment guide forwarded through a frame, or by the window recomputing its
/// minimum size, all of which happen on every update — measures its whole
/// content at that proposal. With hundreds of rows loaded that measuring was
/// most of a streaming flush. Answering here keeps every such question from
/// reaching the rows; they are laid out once, at the viewport's real width.
struct TranscriptViewportLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
    }

    func explicitAlignment(of guide: HorizontalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
                           subviews: Subviews, cache: inout ()) -> CGFloat? { nil }

    func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
                           subviews: Subviews, cache: inout ()) -> CGFloat? { nil }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            subview.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
        }
    }
}
