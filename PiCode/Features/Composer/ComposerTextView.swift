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

    /// The composer box is dark in every appearance (#212121 in the dark one,
    /// #2a2b2b in the light one), so the text and caret need fixed light colors
    /// too — the dynamic defaults would render black-on-black in light mode.
    static let textColor = NSColor(red: 0.92, green: 0.92, blue: 0.93, alpha: 1)
    static let caretColor = NSColor(red: 0.92, green: 0.92, blue: 0.93, alpha: 1)
    static let placeholderColor = NSColor(red: 0.92, green: 0.92, blue: 0.93, alpha: 0.45)

    /// How many lines the box always shows, and how many it shows before it
    /// scrolls instead of growing any further. The composer floats over the
    /// transcript (§6), so its ceiling is deliberately low: two lines is the
    /// floor that keeps the box from collapsing to a sliver, six is the most of
    /// the conversation it may cover as a prompt grows.
    static let minimumLines = 2
    static let maximumLines = 6

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

    /// The height the editor actually wants: as many lines as are in it, held
    /// between `minimumLines` and `maximumLines`.
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
        let height = min(max(used + Self.textInset.height * 2, Self.height(forLines: Self.minimumLines)),
                         Self.height(forLines: Self.maximumLines))
        return CGSize(width: proposal.width ?? nsView.frame.width, height: height)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textView = PlaceholderTextView()
        textView.placeholder = placeholder
        textView.placeholderColor = Self.placeholderColor
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

        (textView as? PlaceholderTextView)?.placeholder = placeholder
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

/// The composer's text view, with the placeholder drawn in the text system's own
/// coordinates. A SwiftUI `Text` overlaid on the editor lays its first line out
/// separately from the text view, so the two never quite shared a baseline; this
/// draws from the same container origin the real text uses, which makes them the
/// same line by construction.
private final class PlaceholderTextView: NSTextView {
    var placeholder: String = ""
    var placeholderColor: NSColor = ComposerTextView.placeholderColor

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: ComposerTextView.fontSize),
            .foregroundColor: placeholderColor
        ]
        let origin = textContainerOrigin
        // Real glyphs start one `lineFragmentPadding` inside the container, so the
        // placeholder has to as well or it hangs left of the text it stands in for.
        let x = origin.x + (textContainer?.lineFragmentPadding ?? 0)
        (placeholder as NSString).draw(at: NSPoint(x: x, y: origin.y), withAttributes: attributes)
    }
}
