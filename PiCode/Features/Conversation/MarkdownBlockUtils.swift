import SwiftUI

extension MarkdownBlockView {
    @ViewBuilder
    func renderBlock(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            MarkdownInlineText(source: text)
                .font(headingFont(level))
                .lineSpacing(TranscriptStyle.lineSpacing)
                .textSelection(.enabled)
                .padding(.top, level <= 2 ? 4 : 0)

        case .paragraph(let text):
            MarkdownInlineText(source: text)
                .font(Typography.body)
                .lineSpacing(TranscriptStyle.lineSpacing)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

        case .bulletList(let items):
            listView(items, ordered: false, tasks: false)

        case .orderedList(let items):
            listView(items, ordered: true, tasks: false)

        case .taskList(let items):
            listView(items, ordered: false, tasks: true)

        case .codeBlock(let language, let code, let isComplete):
            CodeBlockView(language: language, code: code, isComplete: isComplete)

        case .quote(let lines):
            HStack(alignment: .top, spacing: 10) {
                Rectangle()
                    .fill(.tertiary)
                    .frame(width: 3)
                MarkdownInlineText(source: lines.joined(separator: "\n"))
                    .font(Typography.body)
                    .lineSpacing(TranscriptStyle.lineSpacing)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .fixedSize(horizontal: false, vertical: true)

        case .table(let headers, let rows):
            MarkdownTableView(headers: headers, rows: rows)

        case .rule:
            Divider()

        case .rawHTML(let raw):
            VStack(alignment: .leading, spacing: 4) {
                Text("Raw HTML block")
                    .font(Typography.bodySemibold)
                    .foregroundStyle(.secondary)
                SyntaxText(text: raw, language: SyntaxLanguage(family: .markup, label: "HTML"))
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func headingFont(_ level: Int) -> Font {
        // Headings keep their *weight*, not a size: the transcript is one column of
        // one size (`TranscriptStyle`), and a heading that grows breaks it.
        switch level {
        case 1: return Typography.body.weight(.bold)
        default: return Typography.bodySemibold
        }
    }

    private func listView(_ items: [MarkdownListItem], ordered: Bool, tasks: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if tasks {
                        Image(systemName: item.isChecked == true ? "checkmark.square.fill" : "square")
                            .imageScale(.small)
                            .foregroundStyle(item.isChecked == true ? Color.accentColor : Color.secondary)
                    } else {
                        Text(ordered ? "\(index + 1)." : "•")
                            .font(Typography.body.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 16, alignment: .trailing)
                    }
                    MarkdownInlineText(source: item.text)
                        .font(Typography.body)
                        .lineSpacing(TranscriptStyle.lineSpacing)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, CGFloat(item.depth) * 16)
            }
        }
    }
}

