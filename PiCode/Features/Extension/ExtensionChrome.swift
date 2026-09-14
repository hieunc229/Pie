//
//  ExtensionChrome.swift
//  PiCode
//
//  Surfaces Pi extensions can drive over RPC: footer status entries, widgets,
//  notifications, and the agent status line PiCode adds itself.
//
//  Everything here is Pi's data rendered verbatim. PiCode adds no interpretation
//  of its own, so a status entry means exactly what the extension said.
//

import SwiftUI

// MARK: - Widgets

struct ExtensionWidgetStrip: View {
    var controller: PiSessionController
    var placement: WidgetPlacement

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let widgets = controller.extensionWidgets[placement] ?? [:]
        if !widgets.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(widgets.keys.sorted(), id: \.self) { key in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(key)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                        ForEach(Array((widgets[key] ?? []).enumerated()), id: \.offset) { _, line in
                            Text(ANSIParser.attributed(line, scheme: colorScheme, baseFont: .system(.caption, design: .monospaced)))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 7))
                }
            }
        }
    }
}

// MARK: - Status line

struct ExtensionStatusBar: View {
    var controller: PiSessionController

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                runtimePill
                if let model = controller.model {
                    Text(model.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let level = controller.thinkingLevel {
                    Label(level, systemImage: "brain")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                TrustBadge(state: controller.trustState)
                if controller.git.isRepository, let branch = controller.git.branch {
                    Label(branch, systemImage: "arrow.triangle.branch")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if let stats = controller.stats, let percent = stats.contextUsage?.percent {
                    Label(Format.percent(percent / 100), systemImage: "chart.pie")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .help(contextHelp(stats))
                }
                if controller.toolCallCount > 0 {
                    Label("\(controller.toolCallCount)", systemImage: "wrench.and.screwdriver")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .help("Tool calls this session")
                }
            }

            if !controller.extensionStatuses.isEmpty {
                HStack(spacing: 8) {
                    ForEach(controller.extensionStatuses.keys.sorted(), id: \.self) { key in
                        if let text = controller.extensionStatuses[key] {
                            StatusPill(text: "\(key): \(text)", tint: .secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var runtimePill: some View {
        Group {
            switch controller.runtime {
            case .working:
                StatusPill(text: "Working", systemImage: "play.fill", tint: .accentColor, isProminent: true)
            case .compacting:
                StatusPill(text: "Compacting", systemImage: "arrow.down.right.and.arrow.up.left", tint: .accentColor, isProminent: true)
            case .retrying(let attempt, let maxAttempts, _):
                StatusPill(text: "Retrying \(attempt)/\(maxAttempts)", systemImage: "arrow.clockwise", tint: .orange, isProminent: true)
            case .stopping:
                StatusPill(text: "Stopping", systemImage: "stop.fill", tint: .orange)
            case .disconnected:
                StatusPill(text: "Disconnected", systemImage: "bolt.slash", tint: .red)
            case .starting:
                StatusPill(text: "Starting", systemImage: "bolt.horizontal", tint: .secondary)
            case .idle:
                StatusPill(text: "Idle", systemImage: "checkmark.circle", tint: .secondary)
            }
        }
    }

    private func contextHelp(_ stats: PiSessionStats) -> String {
        guard let usage = stats.contextUsage else { return "Context usage" }
        var parts: [String] = []
        if let tokens = usage.tokens { parts.append(Format.tokens(tokens) + " tokens") }
        if let window = usage.contextWindow { parts.append("of " + Format.tokens(window)) }
        if stats.cost > 0 { parts.append(stats.cost.currencyString) }
        return parts.joined(separator: " ")
    }
}

// MARK: - Notifications

struct NotificationStack: View {
    @Bindable var controller: PiSessionController

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ForEach(controller.notifications.suffix(4)) { notification in
                BannerView(
                    level: level(notification.level),
                    title: notification.sourceName ?? "Pi",
                    message: notification.message,
                    onDismiss: { controller.dismissNotification(notification.id) }
                )
                .frame(maxWidth: 420)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: controller.notifications.count)
    }

    private func level(_ level: ExtensionNotification.Level) -> BannerView.Level {
        switch level {
        case .info: return .info
        case .warning: return .warning
        case .error: return .error
        }
    }
}
