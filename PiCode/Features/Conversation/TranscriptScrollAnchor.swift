//
//  TranscriptScrollAnchor.swift
//  PiCode
//
//  Keeps the text under the reader still while earlier history is prepended.
//
//  History is loaded a page at a time above the viewport (`prefetchEarlierTranscript`
//  and `startIdleHistoryFill`). Every page makes the document taller *above* what
//  the user is reading, and an `NSScrollView` keeps its origin measured from the
//  top — so without help the rows under the reader slide down by the height of the
//  page, and the user loses their place. SwiftUI's `scrollPosition(id:)` did not
//  hold it either: it needs the rows to be scroll targets it can track, and the
//  transcript's custom stack layout is not one.
//
//  So while a prepend is settling, the anchor holds the distance from the
//  viewport's top to the document's *bottom*. Content added above changes the
//  document's height and nothing below the viewport, so restoring that distance
//  puts every visible row back exactly where it was. The hold is a short window
//  per prepend, not a standing rule: outside it the bottom of the document is
//  where a streaming answer grows, and anchoring to it would push the text the
//  user is reading upward instead.
//

import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class TranscriptScrollAnchor {
    private weak var scrollView: NSScrollView?
    private var observers: [NSObjectProtocol] = []
    /// Document height minus the clip's top, while a hold is active.
    private var distanceFromBottom: CGFloat?
    private var holdUntil: CFTimeInterval = 0
    /// Set while the anchor moves the clip itself, so its own scroll is not
    /// mistaken for the user's.
    private var isCorrecting = false

    /// How long after a prepend the anchor keeps holding. Long enough for the
    /// page's rows to lay out and their Markdown to finish sizing.
    private static let holdDuration: CFTimeInterval = 0.8

    func attach(_ scrollView: NSScrollView?) {
        guard let scrollView, scrollView !== self.scrollView else { return }
        detach()
        self.scrollView = scrollView
        let center = NotificationCenter.default
        scrollView.contentView.postsBoundsChangedNotifications = true
        observers.append(center.addObserver(forName: NSView.boundsDidChangeNotification,
                                            object: scrollView.contentView, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated { self?.clipDidScroll() }
        })
        if let document = scrollView.documentView {
            document.postsFrameChangedNotifications = true
            observers.append(center.addObserver(forName: NSView.frameDidChangeNotification,
                                                object: document, queue: nil) { [weak self] _ in
                MainActor.assumeIsolated { self?.documentDidResize() }
            })
        }
    }

    func detach() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        scrollView = nil
        distanceFromBottom = nil
    }

    /// Call right before prepending earlier rows.
    func holdReadingPosition() {
        guard let scrollView, let document = scrollView.documentView, document.isFlipped else { return }
        if distanceFromBottom == nil || CACurrentMediaTime() > holdUntil {
            distanceFromBottom = document.frame.height - scrollView.contentView.bounds.origin.y
        }
        holdUntil = CACurrentMediaTime() + Self.holdDuration
    }

    /// Scrolls by a height change that happened above the viewport, so the
    /// visible rows stay where they are. A prepend's hold already restores the
    /// position from the document's height, so this stands aside during one.
    func compensate(heightChangeAbove delta: CGFloat) {
        guard !isHolding, let scrollView, let document = scrollView.documentView,
              document.isFlipped else { return }
        let clip = scrollView.contentView
        let maxY = max(0, document.frame.height - clip.bounds.height)
        let target = min(max(0, clip.bounds.origin.y + delta), maxY)
        guard abs(target - clip.bounds.origin.y) > 0.5 else { return }
        isCorrecting = true
        clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: target))
        scrollView.reflectScrolledClipView(clip)
        isCorrecting = false
    }

    private var isHolding: Bool {
        distanceFromBottom != nil && CACurrentMediaTime() <= holdUntil
    }

    /// The user scrolled during the hold: what they now see is what to keep.
    private func clipDidScroll() {
        guard !isCorrecting, isHolding,
              let scrollView, let document = scrollView.documentView else { return }
        distanceFromBottom = document.frame.height - scrollView.contentView.bounds.origin.y
    }

    private func documentDidResize() {
        guard isHolding, let distanceFromBottom,
              let scrollView, let document = scrollView.documentView else {
            self.distanceFromBottom = nil
            return
        }
        let clip = scrollView.contentView
        let maxY = max(0, document.frame.height - clip.bounds.height)
        let target = min(max(0, document.frame.height - distanceFromBottom), maxY)
        guard abs(target - clip.bounds.origin.y) > 0.5 else { return }
        isCorrecting = true
        clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: target))
        scrollView.reflectScrolledClipView(clip)
        isCorrecting = false
    }
}

/// Hands the transcript's backing `NSScrollView` to the anchor once it exists.
struct TranscriptScrollViewFinder: NSViewRepresentable {
    var onFind: (NSScrollView?) -> Void

    func makeNSView(context: Context) -> FinderView {
        let view = FinderView()
        view.onFind = onFind
        return view
    }

    func updateNSView(_ nsView: FinderView, context: Context) {
        nsView.onFind = onFind
    }

    final class FinderView: NSView {
        var onFind: ((NSScrollView?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
            // The scroll view finishes assembling after this view joins it.
            DispatchQueue.main.async { [weak self] in
                self?.onFind?(self?.enclosingScrollView)
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
