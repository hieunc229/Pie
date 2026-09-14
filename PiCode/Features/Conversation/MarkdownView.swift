//
//  MarkdownView.swift
//  PiCode
//
//  Renders assistant Markdown with native SwiftUI text, real code blocks, and
//  clickable file references.
//
//  Parsing is streaming-safe: an unterminated code fence renders as a code block
//  that grows as tokens arrive instead of flashing raw backticks.
//

import SwiftUI

// MARK: - File link handling

/// Called when the user clicks a `picode://file?path=…` link. Implementations
/// open the file in the Files inspector at the referenced line.
struct PiCodeOpenFileAction {
    var handler: (String, Int?) -> Void

    func callAsFunction(_ path: String, _ line: Int?) {
        handler(path, line)
    }

    static let disabled = PiCodeOpenFileAction { _, _ in }
}

private struct PiCodeOpenFileKey: EnvironmentKey {
    static let defaultValue = PiCodeOpenFileAction.disabled
}

/// Called when the user selects a file the agent changed (a tool card's change
/// chip). Implementations open the Changes inspector on that file's diff.
struct PiCodeOpenChangeAction {
    var handler: (String) -> Void

    func callAsFunction(_ path: String) {
        handler(path)
    }

    static let disabled = PiCodeOpenChangeAction { _ in }
}

private struct PiCodeOpenChangeKey: EnvironmentKey {
    static let defaultValue = PiCodeOpenChangeAction.disabled
}

extension EnvironmentValues {
    var piCodeOpenChange: PiCodeOpenChangeAction {
        get { self[PiCodeOpenChangeKey.self] }
        set { self[PiCodeOpenChangeKey.self] = newValue }
    }
}

extension EnvironmentValues {
    var piCodeOpenFile: PiCodeOpenFileAction {
        get { self[PiCodeOpenFileKey.self] }
        set { self[PiCodeOpenFileKey.self] = newValue }
    }
}

/// Routes `picode://` links to the file handler and everything else through the
/// normal, scheme-checked open path.
struct PiCodeLinkHandler: ViewModifier {
    @Environment(\.piCodeOpenFile) private var openFile

    func body(content: Content) -> some View {
        content.environment(\.openURL, OpenURLAction { url in
            guard url.scheme == "picode" else {
                WorkspaceLauncher.openWebURL(url.absoluteString)
                return .handled
            }
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let path = components?.queryItems?.first(where: { $0.name == "path" })?.value
            let line = components?.queryItems?.first(where: { $0.name == "line" })?.value.flatMap(Int.init)
            if let path {
                openFile(path, line)
            }
            return .handled
        })
    }
}

extension View {
    func handlesPiCodeLinks() -> some View { modifier(PiCodeLinkHandler()) }
}

// MARK: - Markdown

struct MarkdownView: View {
    var text: String
    var isStreaming: Bool = false

    var body: some View {
        let blocks = MarkdownParser.parse(text)
        VStack(alignment: .leading, spacing: 12) {
            ForEach(blocks) { block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inline(text))
                .font(headingFont(level))
                .textSelection(.enabled)
                .padding(.top, level <= 2 ? 4 : 0)

        case .paragraph(let text):
            Text(inline(text))
                .font(.body)
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
                Text(inline(lines.joined(separator: "\n")))
                    .font(.body)
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
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                SyntaxText(text: raw, language: SyntaxLanguage(family: .markup, label: "HTML"))
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func inline(_ text: String) -> AttributedString {
        MarkdownInline.attributed(text)
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title2.weight(.semibold)
        case 2: return .title3.weight(.semibold)
        case 3: return .headline
        default: return .subheadline.weight(.semibold)
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
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 16, alignment: .trailing)
                    }
                    Text(inline(item.text))
                        .font(.body)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, CGFloat(item.depth) * 16)
            }
        }
    }
}

// MARK: - Code block

struct CodeBlockView: View {
    var language: SyntaxLanguage
    var code: String
    var isComplete: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(language.label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                if !isComplete {
                    StatusPill(text: "streaming", systemImage: "ellipsis", tint: .secondary)
                }
                Spacer(minLength: 0)
                CopyButton(text: code, help: "Copy code")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            Divider()

            ScrollView(.horizontal, showsIndicators: true) {
                SyntaxText(text: code, language: language, wraps: false)
                    .padding(10)
            }
        }
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(.separator.opacity(0.6))
        )
    }
}

// MARK: - Table

struct MarkdownTableView: View {
    var headers: [String]
    var rows: [[String]]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                        Text(MarkdownInline.attributed(header))
                            .font(.callout.weight(.semibold))
                            .textSelection(.enabled)
                    }
                }
                // A non-GridRow child spans every column, which is exactly what a
                // table separator should do.
                Divider()
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(MarkdownInline.attributed(cell))
                                .font(.callout)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}
