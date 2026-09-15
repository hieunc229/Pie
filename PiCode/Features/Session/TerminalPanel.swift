//
//  TerminalPanel.swift
//  PiCode
//
//  The terminal panel under the conversation: Pi's bash surface, shown by the
//  content header's workspace menu.
//
//  It is a third region of the session column, not a footer under the composer
//  (§6): the composer still floats over the conversation, and the terminal is a
//  panel the user opens deliberately and can resize. Its body is `TerminalPane`,
//  which runs commands through Pi's own bash tool. PiCode does not start a login
//  shell: an unrelated shell would sit outside the session the transcript is
//  about, so its output could not appear there, and the panel's own “Open in
//  Terminal” is the escape hatch for a real interactive one.
//

import AppKit
import SwiftUI

/// The resizable terminal panel under the conversation.
struct TerminalPanel: View {
    @Bindable var state: AppState
    var controller: PiSessionController

    /// Clamped so the panel can never swallow the conversation. The floor keeps
    /// a couple of history rows and the input visible; the ceiling leaves the
    /// transcript enough room to read at the window's minimum height.
    private static let minHeight: CGFloat = 120
    private static let maxHeight: CGFloat = 420

    /// Set while a drag is in flight so the resize is measured from where the
    /// drag began, not from the height the previous `onChanged` already wrote.
    @State private var heightAtDragStart: CGFloat?
    /// Tracked so the resize cursor is pushed and popped once per entry and exit
    /// rather than on every hover event.
    @State private var isHoveringHandle = false

    var body: some View {
        VStack(spacing: 0) {
            resizeHandle
            TerminalPane(controller: controller) { state.isTerminalVisible = false }
        }
        .frame(height: state.terminalHeight)
        .background(AppTheme.background)
    }

    /// The panel's top edge doubles as its resize grip. The hairline separates
    /// the terminal from the conversation; the taller transparent band is the
    /// target, so the user does not have to hit a one-point line.
    private var resizeHandle: some View {
        ZStack(alignment: .top) {
            Color.clear
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(height: 1)
        }
        .frame(height: 7)
        .contentShape(Rectangle())
        .onHover { inside in
            guard inside != isHoveringHandle else { return }
            isHoveringHandle = inside
            if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let start = heightAtDragStart ?? state.terminalHeight
                    if heightAtDragStart == nil { heightAtDragStart = start }
                    // Dragging the edge up grows the panel, so the translation's
                    // sign is inverted.
                    state.terminalHeight = Self.clamp(start - value.translation.height)
                }
                .onEnded { _ in heightAtDragStart = nil }
        )
        .help("Drag to resize the terminal")
    }

    private static func clamp(_ height: CGFloat) -> CGFloat {
        min(max(height, minHeight), maxHeight)
    }
}
