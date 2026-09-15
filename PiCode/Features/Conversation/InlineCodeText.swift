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
        if #available(macOS 15.0, *) {
            MarkdownInline.roundedCodeText(source)
                .textRenderer(InlineCodeTextRenderer())
        } else {
            Text(MarkdownInline.attributed(source))
        }
    }
}

@available(macOS 15.0, *)
private struct InlineCodeTextAttribute: TextAttribute {}

@available(macOS 15.0, *)
private struct InlineCodeTextRenderer: TextRenderer {
    var displayPadding: EdgeInsets {
        EdgeInsets(top: 2, leading: 3, bottom: 2, trailing: 3)
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            for run in line {
                if run[InlineCodeTextAttribute.self] != nil {
                    let rect = run.typographicBounds.rect.insetBy(dx: -3, dy: -1)
                    let background = Path(roundedRect: rect, cornerRadius: 4)
                    context.fill(background, with: .color(Color.gray.opacity(0.18)))
                    context.stroke(background, with: .color(Color.gray.opacity(0.24)), lineWidth: 0.5)
                }
                context.draw(run)
            }
        }
    }
}

@available(macOS 15.0, *)
private extension MarkdownInline {
    static func roundedCodeText(_ source: String) -> Text {
        let attributed = attributed(source)
        return attributed.runs.reduce(Text("")) { text, run in
            var content = AttributedString(attributed[run.range])
            let isCode = run.inlinePresentationIntent?.contains(.code) == true
            if isCode {
                content.backgroundColor = nil
            }
            let segment = Text(content)
            return text + (isCode ? segment.customAttribute(InlineCodeTextAttribute()) : segment)
        }
    }
}
