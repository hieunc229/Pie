//
//  TranscriptVirtualizer.swift
//  PiCode
//
//  Unloads transcript rows that are far from the viewport.
//
//  The transcript is an eager stack on purpose (see `ConversationView`): a lazy
//  stack guesses the heights of rows it has not built and the content jumps as
//  the guesses are corrected. But eager means every row of history the user has
//  scrolled through stays built — views, text layout and all — for as long as
//  the chat is open.
//
//  This keeps the eager stack's exact geometry and drops the cost: each row's
//  height is measured once it is built, and a row more than a few screens from
//  the viewport is swapped for empty space of that same height. Nothing moves,
//  because the space is exactly as tall as the row it replaces; when the reader
//  comes back within range the row is rebuilt before it reaches the screen.
//
//  The range has hysteresis — a row is unloaded one screen further out than it
//  is rebuilt — so scrolling back and forth across the edge does not rebuild the
//  same row on every frame.
//
//  A rebuilt row can come back a different height than the space it left (the
//  window was resized while it was unloaded, or its content changed). When that
//  happens above the viewport the difference is scrolled away, so the text the
//  user is reading stays put.
//

import SwiftUI

@Observable
@MainActor
final class TranscriptVirtualizer {
    /// Rows currently drawn as empty space. The only observed state: the rows
    /// view re-renders when this changes, and not on every scroll.
    private(set) var hiddenIDs: Set<String> = []

    /// Screens kept built above and below the viewport.
    @ObservationIgnored var screens = 2
    /// Off while a session opens, so the first layout builds and measures every
    /// loaded row before any of them is unloaded.
    @ObservationIgnored var isEnabled = false {
        didSet { if isEnabled != oldValue { recompute() } }
    }
    /// Scrolls the transcript by a row's height change above the viewport.
    @ObservationIgnored var onHeightChangeAboveViewport: ((CGFloat) -> Void)?

    @ObservationIgnored private var heights: [String: CGFloat] = [:]
    @ObservationIgnored private var rowIDs: [String] = []
    @ObservationIgnored private var topGap: CGFloat = 0
    @ObservationIgnored private var viewportHeight: CGFloat = 0
    @ObservationIgnored private var recomputeScheduled = false

    /// Must match `TranscriptStackLayout`'s spacing and the stack's top padding
    /// in `ConversationView`, so a row's position here is its position on screen.
    static let rowSpacing: CGFloat = 20
    static let topPadding: CGFloat = 12

    func height(of id: String) -> CGFloat? { heights[id] }

    func reset() {
        heights = [:]
        rowIDs = []
        isEnabled = false
        if !hiddenIDs.isEmpty { hiddenIDs = [] }
    }

    /// A built row's measured height.
    func report(id: String, height: CGFloat) {
        let old = heights[id]
        if let old, abs(old - height) < 0.5 { return }
        if let old, isEnabled, let maxY = maxY(of: id), maxY <= topGap {
            onHeightChangeAboveViewport?(height - old)
        }
        heights[id] = height
        scheduleRecompute()
    }

    func update(rowIDs: [String]) {
        guard rowIDs != self.rowIDs else { return }
        self.rowIDs = rowIDs
        scheduleRecompute()
    }

    func update(topGap: CGFloat, viewportHeight: CGFloat) {
        self.topGap = topGap
        self.viewportHeight = viewportHeight
        recompute()
    }

    /// Height reports arrive one per row during a layout pass; recompute once
    /// after the pass rather than once per row.
    private func scheduleRecompute() {
        guard !recomputeScheduled else { return }
        recomputeScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.recomputeScheduled = false
            self?.recompute()
        }
    }

    private func recompute() {
        guard isEnabled, viewportHeight > 0, topGap.isFinite else {
            if !hiddenIDs.isEmpty { hiddenIDs = [] }
            return
        }
        let visibleTop = topGap
        let visibleBottom = topGap + viewportHeight
        let showWithin = CGFloat(screens) * viewportHeight
        let hideBeyond = CGFloat(screens + 1) * viewportHeight
        var y = Self.topPadding
        var hidden = Set<String>()
        for id in rowIDs {
            // A row never measured is built, so it can be; until it reports it
            // takes no room in this estimate.
            guard let height = heights[id] else {
                y += Self.rowSpacing
                continue
            }
            let distance = max(0, visibleTop - (y + height), y - visibleBottom)
            let limit = hiddenIDs.contains(id) ? showWithin : hideBeyond
            if distance > limit { hidden.insert(id) }
            y += height + Self.rowSpacing
        }
        if hidden != hiddenIDs { hiddenIDs = hidden }
    }

    private func maxY(of id: String) -> CGFloat? {
        var y = Self.topPadding
        for rowID in rowIDs {
            let height = heights[rowID] ?? 0
            if rowID == id { return y + height }
            y += height + Self.rowSpacing
        }
        return nil
    }
}

/// Reports a built row's height to the virtualizer.
struct TranscriptRowHeightReporter: View {
    var id: String
    var virtualizer: TranscriptVirtualizer

    var body: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear { virtualizer.report(id: id, height: geo.size.height) }
                .onChange(of: geo.size.height) { _, height in
                    virtualizer.report(id: id, height: height)
                }
        }
    }
}
