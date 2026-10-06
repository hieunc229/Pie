//
//  InlineCodeText.swift
//  PiCode
//
//  Rounded inline-code backing without breaking native Text wrapping, selection,
//  Markdown emphasis, or links.
//

import SwiftUI

struct MarkdownInlineText: View {
    var source: String

    @ViewBuilder
    var body: some View {
        // Selectable text is drawn by AppKit's text system, which ignores a
        // custom `TextRenderer` — so the pills cannot be drawn by the text that
        // is selected. They come from an identical copy underneath instead: the
        // same `Text`, laid out in the same frame with the same font and spacing,
        // whose renderer paints only the code backgrounds. Plain prose (no code
        // span) skips the copy.
        if #available(macOS 15.0, *), source.contains("`") {
            let text = MarkdownInline.roundedCodeText(source)
            text.background {
                text
                    .textRenderer(InlineCodePillRenderer())
                    .textSelection(.disabled)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        } else {
            Text(MarkdownInline.attributed(source))
        }
    }
}

@available(macOS 15.0, *)
private struct InlineCodeTextAttribute: TextAttribute {}

@available(macOS 15.0, *)
private struct InlineCodePillRenderer: TextRenderer {
    var displayPadding: EdgeInsets {
        EdgeInsets(top: 2, leading: 3, bottom: 2, trailing: 3)
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            // A code span can be several runs (its padding is set in the body
            // font), so touching code runs are joined into one pill per line.
            // Only the pills are drawn: the glyphs are the selectable text's.
            var pill: CGRect?
            for run in line {
                if run[InlineCodeTextAttribute.self] != nil {
                    let rect = run.typographicBounds.rect
                    pill = pill.map { $0.union(rect) } ?? rect
                } else if let rect = pill {
                    fill(rect, in: &context)
                    pill = nil
                }
            }
            if let rect = pill { fill(rect, in: &context) }
        }
    }

    private func fill(_ rect: CGRect, in context: inout GraphicsContext) {
        let background = Path(roundedRect: rect.insetBy(dx: 0, dy: -1.5), cornerRadius: 5, style: .continuous)
        context.fill(background, with: .color(AppTheme.inlineCodeFill))
    }
}

@available(macOS 15.0, *)
private extension MarkdownInline {
    static let roundedCodeCache = RenderCache<Text>(totalCostLimit: 2_000_000)

    /// The concatenated `Text` is rebuilt run by run, so it is remembered by its
    /// source the way the attributed string under it already is.
    static func roundedCodeText(_ source: String) -> Text {
        roundedCodeCache.value(forKey: source, cost: source.count) { buildRoundedCodeText(source) }
    }

    static func buildRoundedCodeText(_ source: String) -> Text {
        let attributed = attributed(source)
        // Only a code span needs to be its own segment (it carries the attribute
        // the renderer looks for). Everything between two spans — plain, bold,
        // links — stays one attributed segment, so a paragraph is a handful of
        // concatenated texts rather than one per styling run.
        var result = Text("")
        var pending = AttributedString()
        for run in attributed.runs {
            let isCode = run.inlinePresentationIntent?.contains(.code) == true
            var content = AttributedString(attributed[run.range])
            if isCode {
                if !pending.characters.isEmpty {
                    result = result + Text(pending)
                    pending = AttributedString()
                }
                content.backgroundColor = nil
                // A three-per-em space in the body font at each end pads the pill
                // from the inside (in the monospaced font it would be a full cell).
                var pad = AttributedString("\u{2004}")
                pad.font = Typography.body
                content = pad + content + pad
                result = result + Text(content).customAttribute(InlineCodeTextAttribute())
            } else {
                pending.append(content)
            }
        }
        if !pending.characters.isEmpty {
            result = result + Text(pending)
        }
        return result
    }
}
