//
//  UIComponents.swift
//  PiCode
//
//  Small shared building blocks. They use semantic system colors, materials,
//  SF Symbols, and Dynamic Type-friendly fonts only, per the design constraints:
//  no hard-coded screenshot colors, no bespoke chrome that fights macOS.
//

import SwiftUI

// MARK: - Banner

struct BannerView: View {
    enum Level {
        case info
        case warning
        case error
        case success

        var systemImage: String {
            switch self {
            case .info: return "info.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .error: return "xmark.octagon.fill"
            case .success: return "checkmark.circle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .info: return .accentColor
            case .warning: return .orange
            case .error: return .red
            case .success: return .green
            }
        }
    }

    var level: Level
    var title: String
    var message: String?
    var actionTitle: String?
    var action: (() -> Void)?
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: level.systemImage)
                .foregroundStyle(level.tint)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                if let message, !message.isEmpty {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }

            Spacer(minLength: 8)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderless)
                    .font(.callout)
            }

            if let onDismiss {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .help("Dismiss")
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(level.tint.opacity(0.35))
        )
        .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
    }
}

// MARK: - Status pill

struct StatusPill: View {
    var text: String
    var systemImage: String?
    var tint: Color = .secondary
    var isProminent: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .imageScale(.small)
            }
            Text(text)
                .font(.caption.weight(isProminent ? .semibold : .regular))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(tint.opacity(0.12), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Activity row

/// One line of the activity timeline. Shared by the Inspector's timeline pane and
/// the inline disclosure under a running turn, so the two can never drift apart.
struct ActivityRowView: View {
    var entry: ActivityEntry
    var showsTimestamp: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: entry.kind.systemImage)
                .imageScale(.small)
                .foregroundStyle(entry.isError ? Color.red : Color.secondary)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title)
                    .font(.caption)
                if let detail = entry.detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if showsTimestamp {
                Spacer(minLength: 6)
                Text(Format.clockTime(entry.timestamp))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Section

struct InspectorSection<Content: View>: View {
    var title: String
    var subtitle: String?
    var systemImage: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
            }
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            content()
        }
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    var systemImage: String
    var title: String
    var message: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 380)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Path label

/// Shows a file path with the home directory abbreviated and the last component
/// emphasized, so long paths stay readable at sidebar and inspector widths.
struct PathLabel: View {
    var path: String
    var line: Int?
    var emphasizeLastComponent: Bool = true

    var body: some View {
        let abbreviated = path.abbreviatingHomeDirectory
        let components = abbreviated.split(separator: "/").map(String.init)
        HStack(spacing: 2) {
            if components.count > 1 {
                Text(components.dropLast().joined(separator: "/") + "/")
                    .foregroundStyle(.secondary)
            }
            Text(components.last ?? abbreviated)
                .foregroundStyle(emphasizeLastComponent ? .primary : .secondary)
            if let line {
                Text(":\(line)")
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.callout.monospaced())
        .lineLimit(1)
        .truncationMode(.middle)
        .help(abbreviated)
    }
}

// MARK: - Diff statistics

struct DiffStatView: View {
    var additions: Int?
    var deletions: Int?

    var body: some View {
        HStack(spacing: 6) {
            if let additions, additions > 0 {
                Text("+\(additions)")
                    .foregroundStyle(.green)
            }
            if let deletions, deletions > 0 {
                Text("-\(deletions)")
                    .foregroundStyle(.red)
            }
        }
        .font(.caption.monospacedDigit())
    }
}

// MARK: - Copy button

struct CopyButton: View {
    var text: String
    var help: String = "Copy"

    @State private var didCopy = false

    var body: some View {
        Button {
            WorkspaceLauncher.copyToPasteboard(text)
            didCopy = true
            Task {
                try? await Task.sleep(nanoseconds: 1_400_000_000)
                didCopy = false
            }
        } label: {
            Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                .imageScale(.small)
        }
        .buttonStyle(.borderless)
        .help(help)
        .accessibilityLabel(help)
    }
}

// MARK: - Collapsible output

/// Long tool output and diffs collapse by default with an explicit control, so
/// the transcript stays scannable without hiding information.
struct CollapsibleText: View {
    var text: String
    var lineLimit: Int = 14
    var language: SyntaxLanguage = .plain
    var isInitiallyExpanded: Bool = false

    @State private var isExpanded: Bool = false

    var body: some View {
        let lines = text.isEmpty ? 0 : text.split(separator: "\n", omittingEmptySubsequences: false).count
        let needsDisclosure = lines > lineLimit

        VStack(alignment: .leading, spacing: 6) {
            Group {
                if isExpanded || !needsDisclosure {
                    SyntaxText(text: text, language: language)
                } else {
                    SyntaxText(text: truncated, language: language)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if needsDisclosure {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
                } label: {
                    Label(
                        isExpanded ? "Show less" : "Show \(lines - lineLimit) more lines",
                        systemImage: isExpanded ? "chevron.up" : "chevron.down"
                    )
                    .font(Typography.body)
                }
                .buttonStyle(.borderless)
            }
        }
        .onAppear {
            if isInitiallyExpanded { isExpanded = true }
        }
    }

    private var truncated: String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .prefix(lineLimit)
            .joined(separator: "\n")
    }
}

// MARK: - Syntax text

/// Renders highlighted code/text using `SyntaxHighlighter`, falling back to plain
/// monospaced text for very large payloads where highlighting would cost more
/// than it is worth.
struct SyntaxText: View {
    var text: String
    var language: SyntaxLanguage
    var wraps: Bool = false

    private static let highlightLimit = 60_000

    var body: some View {
        Text(attributed)
            .font(Typography.code)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: !wraps)
    }

    private var attributed: AttributedString {
        guard text.count <= Self.highlightLimit else { return AttributedString(text) }
        return SyntaxHighlighter.highlight(text, language: language)
    }
}
