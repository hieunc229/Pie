//
//  AppTheme.swift
//  PiCode
//
//  PiCode's background palette.
//
//  The light appearance keeps the system's own window backgrounds. The dark
//  appearance uses two flat greys, so that stacked surfaces stay legible without
//  leaning on vibrancy:
//
//    - `background` — #181818. The base the app sits on: the transcript, the
//      content header's band, the terminal panel, the package browser.
//    - `elevated`   — #212121. One step above the base, for the columns and
//      cards laid on top of it: the sidebar, the inspector, the composer box,
//      the queue bubble.
//
//  Both resolve per appearance through `NSColor(name:)`, so a single view has no
//  `colorScheme` checks and the two values live in exactly one place.
//

import AppKit
import SwiftUI

enum AppTheme {
    /// The base background: #181818 in the dark appearance, the system's text
    /// background in the light one.
    static let background = adaptive(dark: 0x181818, light: .textBackgroundColor)

    /// A surface one step above the base: #212121 in the dark appearance, the
    /// system's text background in the light one.
    static let elevated = adaptive(dark: 0x212121, light: .textBackgroundColor)

    /// The composer box: #212121 in the dark appearance. In the light one it
    /// keeps the fixed dark grey the box has always had, because the box is
    /// deliberately dark in every appearance.
    static let composerFill = adaptive(
        dark: 0x212121,
        light: NSColor(srgbRed: 0x2a / 255, green: 0x2b / 255, blue: 0x2b / 255, alpha: 1)
    )

    /// The queued-message card, which sits directly above the composer: the same
    /// #212121 in the dark appearance, and its own light grey in the light one.
    static let queueFill = adaptive(dark: 0x212121, light: NSColor(white: 0.95, alpha: 1))

    /// `dark` in the dark appearance, `light` in the light one. The provider is
    /// consulted every time AppKit needs the colour, so a system appearance
    /// change repaints without PiCode tracking it.
    static func adaptive(dark: UInt32, light: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(rgb: dark)
                : light
        })
    }
}

/// The sidebar column's fill. In the dark appearance the system material is
/// replaced by `AppTheme.elevated`, so the column reads as one surface with the
/// composer rather than as a translucent pane over the window. The light
/// appearance is left with the material it has always used.
struct SidebarColumnBackground: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if colorScheme == .dark {
            content
                .scrollContentBackground(.hidden)
                .background(AppTheme.elevated)
        } else {
            content
        }
    }
}

extension NSColor {
    /// An opaque sRGB colour from `0xRRGGBB`.
    convenience init(rgb: UInt32) {
        self.init(
            srgbRed: CGFloat((rgb >> 16) & 0xff) / 255,
            green: CGFloat((rgb >> 8) & 0xff) / 255,
            blue: CGFloat(rgb & 0xff) / 255,
            alpha: 1
        )
    }
}
