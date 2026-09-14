//
//  ComposerTextView.swift
//  PiCode
//
//  AppKit-backed plain-text editor for the composer.
//
//  AppKit is used instead of SwiftUI's TextField/TextEditor because the send key,
//  suggestion navigation, and Escape behavior must be decided before the text
//  system inserts anything — exactly what `doCommandBy` provides.
//

import AppKit
import SwiftUI

struct ComposerTextView: NSViewRepresentable {
    /// Where the text actually starts inside the view, exposed so the placeholder
    /// overlay can put itself on exactly the same spot without a magic number.
    static let textInset = NSSize(width: 2, height: 2)

    /// Same size as the transcript content and the sidebar menu — the app's one
    /// reading size (`Typography.baseSize`), so the box you type into and the words
    /// you are answering are set at the same scale.
    static let fontSize: CGFloat = Typography.baseSize

    /// The composer box has a fixed dark fill (#2a2b2b) in every appearance, so
    /// the text and caret need fixed light colors too — the dynamic defaults
    /// would render black-on-black in light mode.
    static let textColor = NSColor(red: 0.92, green: 0.92, blue: 0.93, alpha: 1)
    static let caretColor = NSColor(red: 0.92, green: 0.92, blue: 0.93, alpha: 1)

    /// How many lines the box shows before it scrolls instead of growing. Two
    /// lines is the whole budget: the composer floats over the transcript (§6),
    /// and every line it grows is a line of the conversation it covers.
    static let visibleLines = 2

    /// One line of this view's own font, as AppKit lays it out. Derived rather
    /// than hardcoded: the font is what decides it, and a metric that silently
    /// stops matching the font is how a "two line" box ends up showing one and a
    /// half lines.
    static let lineHeight = ceil(NSLayoutManager().defaultLineHeight(for: .systemFont(ofSize: fontSize)))

    /// The height this view needs to show `lines` lines, insets included.
    static func height(forLines lines: Int) -> CGFloat {
        CGFloat(lines) * lineHeight + textInset.height * 2
    }

    @Binding var text: String
    var placeholder: String
    var focusTick: Int
    var sendKey: PreferencesStore.SendKey
    var suggestionsActive: Bool
    var isEnabled: Bool

    var onSend: () -> Void
    var onFollowUp: () -> Void
    var onEscape: () -> Void
    var onMoveSuggestion: (Int) -> Void
    var onAcceptSuggestion: () -> Void

    final class Coordinator: NSObject, NSTextViewDelegate {
        /// Command-Return does not reach a text view as a newline command at all
        /// — measured, it arrives as `noop:`, a selector AppKit does not declare
        /// in its headers. It is matched by name, and if a future macOS stops
        /// sending it we simply fall through and do nothing, which is what
        /// `noop:` means anyway.
        private static let noopSelector = Selector(("noop:"))

        var parent: ComposerTextView
        weak var textView: NSTextView?
        var lastFocusTick = 0
        var isProgrammaticChange = false

        init(parent: ComposerTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isProgrammaticChange, let textView else { return }
            parent.text = textView.string
        }

        /// Which modifiers are down *now*. The selector alone cannot answer this:
        /// a plain text view reports Shift-Return as plain `insertNewline:` and
        /// Command-Return as `noop:`, so the modifiers are the only reliable
        /// signal. `Tools/SmokeTest/run-composer.sh` pins this table down.
        private var currentModifiers: NSEvent.ModifierFlags {
            (NSApp.currentEvent?.modifierFlags ?? []).intersection(.deviceIndependentFlagsMask)
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)),
                 #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)),
                 Coordinator.noopSelector:
                if parent.suggestionsActive {
                    parent.onAcceptSuggestion()
                    return true
                }

                let modifiers = currentModifiers
                if modifiers.contains(.option) {
                    parent.onFollowUp()
                    return true
                }
                // Shift always means "add a line", in both send-key modes.
                if modifiers.contains(.shift) { return false }

                switch parent.sendKey {
                case .returnKey where !modifiers.contains(.command):
                    parent.onSend()
                    return true
                case .commandReturn where modifiers.contains(.command):
                    parent.onSend()
                    return true
                default:
                    // The chord that does not send adds a line. Command-Return
                    // reaches us as `noop:`, which would otherwise do nothing.
                    if selector == Coordinator.noopSelector {
                        textView.insertNewline(nil)
                        return true
                    }
                    return false
                }

            case #selector(NSResponder.cancelOperation(_:)):
                parent.onEscape()
                return true

            case #selector(NSResponder.moveUp(_:)):
                guard parent.suggestionsActive else { return false }
                parent.onMoveSuggestion(-1)
                return true

            case #selector(NSResponder.moveDown(_:)):
                guard parent.suggestionsActive else { return false }
                parent.onMoveSuggestion(1)
                return true

            case #selector(NSResponder.deleteBackward(_:)):
                return false

            default:
                return false
            }
        }

    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    /// The height the editor actually wants: as many lines as are in it, never
    /// more than `visibleLines`.
    ///
    /// Without this the view reports no size of its own and SwiftUI hands it the
    /// largest height allowed, so the box was always as tall as `maxHeight` —
    /// measured, a one-line prompt sat in a 220pt box (see §10).
    ///
    /// The text container is deliberately left alone here. Setting its size inside
    /// this call (to "make sure" the width is current) invalidates layout while
    /// SwiftUI is asking, and the heights come back stale: measured, a three-line
    /// prompt reported its one-line height and the box collapsed as you typed.
    /// `widthTracksTextView` already keeps the container the right width.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        guard let textView = nsView.documentView as? NSTextView,
              let container = textView.textContainer,
              let layout = textView.layoutManager else { return nil }
        layout.ensureLayout(for: container)
        let used = layout.usedRect(for: container).height
        let height = min(max(used + Self.textInset.height * 2, Self.height(forLines: 1)),
                         Self.height(forLines: Self.visibleLines))
        return CGSize(width: proposal.width ?? nsView.frame.width, height: height)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.font = .systemFont(ofSize: Self.fontSize)
        textView.textColor = Self.textColor
        textView.insertionPointColor = Self.caretColor
        textView.textContainerInset = Self.textInset
        textView.drawsBackground = false
        textView.string = text
        textView.isEditable = isEnabled
        textView.isSelectable = true
        textView.usesFindBar = false

        // Pi's composer accepts plain text; newlines and paths are literal.
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]

        scrollView.documentView = textView
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }

        textView.isEditable = isEnabled

        if textView.string != text {
            context.coordinator.isProgrammaticChange = true
            let selected = textView.selectedRange()
            textView.string = text
            let limit = (text as NSString).length
            textView.setSelectedRange(NSRange(location: min(selected.location, limit), length: 0))
            context.coordinator.isProgrammaticChange = false
        }

        if context.coordinator.lastFocusTick != focusTick {
            context.coordinator.lastFocusTick = focusTick
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }
    }
}
