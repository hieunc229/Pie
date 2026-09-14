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
    @Binding var text: String
    var placeholder: String
    var focusTick: Int
    var sendKey: PreferencesStore.SendKey
    var suggestionsActive: Bool
    var isEnabled: Bool

    var onSend: () -> Void
    var onEscape: () -> Void
    var onMoveSuggestion: (Int) -> Void
    var onAcceptSuggestion: () -> Void

    final class Coordinator: NSObject, NSTextViewDelegate {
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

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                if parent.suggestionsActive {
                    parent.onAcceptSuggestion()
                    return true
                }
                if parent.sendKey == .returnKey {
                    parent.onSend()
                    return true
                }
                return false

            case #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                // Shift-Return for the Return-sends mode; Command-Return for the
                // Command-Return-sends mode.
                if parent.suggestionsActive {
                    parent.onAcceptSuggestion()
                    return true
                }
                if parent.sendKey == .commandReturn {
                    parent.onSend()
                    return true
                }
                return false

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
        textView.font = .preferredFont(forTextStyle: .body)
        textView.textContainerInset = NSSize(width: 6, height: 6)
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
