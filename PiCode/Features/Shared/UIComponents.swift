//
//  UIComponents.swift
//  PiCode
//
//  Small shared building blocks. They use semantic system colors, materials,
//  SF Symbols, and Dynamic Type-friendly fonts only, per the design constraints:
//  no hard-coded screenshot colors, no bespoke chrome that fights macOS.
//

import SwiftUI

// MARK: - Composer tray

/// Whether a view is drawn inside the composer's tray — the light, borderless
/// band tucked behind the top of the composer box. Notices drawn there drop
/// their own card chrome (the tray is the card) and use the reading size.
private struct ComposerTrayKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isInComposerTray: Bool {
        get { self[ComposerTrayKey.self] }
        set { self[ComposerTrayKey.self] = newValue }
    }
}

// MARK: - Notice surface

/// The one surface for what the agent says outside the conversation — notices,
/// errors, stray tool results, banners: the same light, borderless band as the
/// strip behind the composer, so every agent message reads as one family.
struct NoticeSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(AppTheme.composerContextFill,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

extension View {
    func noticeSurface() -> some View { modifier(NoticeSurface()) }
}

// MARK: - Banner

struct BannerView: View {
    enum Level {
        case info
        case warning
        case error
        case success

        var systemImage: String {
            switch self {
            case .info: return "info-circle"
            case .warning: return "warning-2"
            case .error: return "danger"
            case .success: return "tick-circle"
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

    @Environment(\.isInComposerTray) private var isInComposerTray

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            IconsaxIcon(name: level.systemImage)
                .foregroundStyle(level.tint)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(Typography.noticeSemibold)
                if let message, !message.isEmpty {
                    Text(message)
                        .font(Typography.notice)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }

            Spacer(minLength: 8)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderless)
                    .font(Typography.notice)
            }

            if let onDismiss {
                Button {
                    onDismiss()
                } label: {
                    IconsaxIcon(name: "close-circle")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .help("Dismiss")
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, isInComposerTray ? 10 : 12)
        // In the composer's tray the tray is the surface; anywhere else the
        // banner brings its own.
        .background {
            if !isInComposerTray {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppTheme.composerContextFill)
            }
        }
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
                IconsaxIcon(name: systemImage)
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
            IconsaxIcon(name: entry.kind.systemImage)
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
                    IconsaxIcon(name: systemImage)
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
            IconsaxIcon(name: systemImage, size: 34)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 16, weight: .regular))
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

// MARK: - Light button style

/// A button drawn entirely by SwiftUI: its label, dimmed while pressed.
///
/// On macOS `.borderless` is backed by a real `NSButton`, which is cheap once
/// but not hundreds of times — and the transcript builds a few per row. Rows
/// use this instead, so building a page of history creates no AppKit views.
struct LightButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.5 : 1)
            .contentShape(Rectangle())
    }
}

extension ButtonStyle where Self == LightButtonStyle {
    static var light: LightButtonStyle { LightButtonStyle() }
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
            IconsaxIcon(name: didCopy ? "tick-circle" : "document-copy")
                .imageScale(.small)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.light)
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
        // Split once per evaluation, not twice: both the count and the truncated
        // prefix come from the same array, and the split is the only O(text) work
        // this view does outside `SyntaxText`.
        let lines = text.isEmpty ? [] : text.split(separator: "\n", omittingEmptySubsequences: false)
        let needsDisclosure = lines.count > lineLimit

        VStack(alignment: .leading, spacing: 6) {
            Group {
                if isExpanded || !needsDisclosure {
                    SyntaxText(text: text, language: language)
                } else {
                    SyntaxText(text: lines.prefix(lineLimit).joined(separator: "\n"), language: language)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if needsDisclosure {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
                } label: {
                    Label(
                        isExpanded ? "Show less" : "Show \(lines.count - lineLimit) more lines",
                        iconsax: isExpanded ? "arrow-up-2" : "arrow-down-2"
                    )
                    .font(Typography.body)
                    .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.light)
            }
        }
        .onAppear {
            if isInitiallyExpanded { isExpanded = true }
        }
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
    /// Defaults to the transcript's reading size; a block container passes a
    /// smaller one instead — `Typography.codeBlock`, or `codeBlockCompact` in the
    /// inspector.
    var font: Font = Typography.code

    private static let highlightLimit = 60_000

    var body: some View {
        Text(attributed)
            .font(font)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: !wraps)
    }

    private var attributed: AttributedString {
        guard text.count <= Self.highlightLimit else { return AttributedString(text) }
        return SyntaxHighlighter.highlight(text, language: language)
    }
}
