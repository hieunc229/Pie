//
//  InspectorArtifactRendering.swift
//  PiCode
//
//  Full-bleed renderers for selected tool artifacts. The panel itself is the
//  surface: these views deliberately do not add cards, wells, or outer margins.
//

import SwiftUI

struct InspectorToolArtifactView: View {
    var item: TranscriptItem
    var wrapsText: Bool

    var body: some View {
        switch InspectorArtifactRendering.content(for: item) {
        case .terminal(let command, let output):
            InspectorTerminalView(
                command: command,
                output: output,
                isRunning: item.isStreaming,
                wrapsText: wrapsText
            )
        case .code(let text, let language):
            CodeViewer(text: text, language: language, highlightLine: nil, wrapsText: wrapsText)
        case .diff(let diff):
            DiffView(diff: diff, wrapsText: wrapsText)
        case .generic(let arguments, let output, let details):
            InspectorGenericToolView(
                arguments: arguments,
                output: output,
                details: details,
                wrapsText: wrapsText
            )
        case .running:
            ToolRunningLine()
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .empty(let message, let isFailure):
            Text(message)
                .font(Typography.body)
                .foregroundStyle(isFailure ? Color.red : Color.secondary)
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

struct InspectorTerminalView: View {
    var command: String?
    var output: String?
    var isRunning: Bool
    var wrapsText: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            ScrollView(wrapsText ? .vertical : [.vertical, .horizontal]) {
                VStack(alignment: .leading, spacing: 0) {
                    if let command {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("$")
                                .foregroundStyle(Color.green)
                            Text(command)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: !wrapsText, vertical: false)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.bottom, output == nil && !isRunning ? 0 : 8)
                    }

                    if let output {
                        Text(ANSIParser.attributed(
                            output,
                            scheme: colorScheme,
                            baseFont: Typography.codeBlockCompact,
                            defaultForeground: Color.primary.opacity(0.82)
                        ))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: !wrapsText, vertical: false)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if isRunning {
                        HStack(spacing: 7) {
                            ProgressView().controlSize(.small)
                            Text("Running…").foregroundStyle(.secondary)
                        }
                        .padding(.top, 8)
                    }
                }
                .font(Typography.codeBlockCompact)
                .padding(12)
                .frame(minWidth: geometry.size.width, alignment: .topLeading)
            }
        }
        .background(AppTheme.background)
    }
}

struct InspectorGenericToolView: View {
    var arguments: String?
    var output: String?
    var details: String?
    var wrapsText: Bool

    var body: some View {
        GeometryReader { geometry in
            ScrollView(wrapsText ? .vertical : [.vertical, .horizontal]) {
                VStack(alignment: .leading, spacing: 0) {
                    InspectorGenericSection(title: "Arguments", text: arguments, language: SyntaxLanguage(identifier: "json"), wrapsText: wrapsText)
                    InspectorGenericSection(title: "Output", text: output, language: .plain, wrapsText: wrapsText)
                    InspectorGenericSection(title: "Structured result", text: details, language: SyntaxLanguage(identifier: "json"), wrapsText: wrapsText)
                }
                .frame(minWidth: geometry.size.width, alignment: .leading)
            }
        }
        .background(AppTheme.background)
    }
}

private struct InspectorGenericSection: View {
    var title: String
    var text: String?
    var language: SyntaxLanguage
    var wrapsText: Bool

    var body: some View {
        if let text {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 5)
            Text(InspectorArtifactRendering.highlightedText(text, language: language))
                .font(Typography.codeBlockCompact)
                .textSelection(.enabled)
                .fixedSize(horizontal: !wrapsText, vertical: false)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
        }
    }
}
