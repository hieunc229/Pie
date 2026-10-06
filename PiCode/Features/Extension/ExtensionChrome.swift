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
                    VStack(alignment: .leading, spacing: 6) {
                        Text(key)
                            .font(.system(size: Typography.baseSize - 2, weight: .semibold))
                            .foregroundStyle(.tertiary)
                        ForEach(Array((widgets[key] ?? []).enumerated()), id: \.offset) { _, line in
                            Text(ANSIParser.attributed(line, scheme: colorScheme, baseFont: Typography.noticeCode))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    // Drawn in the composer's tray, which supplies the fill.
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

// Notifications are not a floating stack over the transcript any more. The
// content header's bell opens the full list in the right panel; the view lives
// with the rest of the inspector in `InspectorView.swift`.
