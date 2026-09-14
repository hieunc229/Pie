//
//  ExtensionChrome.swift
//  PiCode
//
//  Surfaces Pi extensions can drive over RPC: widgets and notifications.
//
//  There is no footer status line any more. It repeated what the inspector's
//  Context pane already shows (model, thinking, context usage, tool counts, git
//  branch, extension status entries) under a composer that is meant to be the
//  only thing at the bottom of the window (see §6).
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
