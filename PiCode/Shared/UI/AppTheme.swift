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
//      cards laid on top of it: the sidebar, the inspector, the composer box.
//
//  Both resolve per appearance through `NSColor(name:)`, so a single view has no
//  `colorScheme` checks and the two values live in exactly one place.
//

import AppKit
import SwiftUI

enum AppTheme {
    /// The base background: #181818 in the dark appearance, the system's text
    /// background in the light one.
    static let background = adaptive(dark: 0x181818, light: NSColor(white: 1, alpha: 1))

    /// A surface one step above the base: #212121 in the dark appearance, the
    /// system's text background in the light one.
    static let elevated = adaptive(dark: 0x212121, light: NSColor(white: 0.98, alpha: 1))

    /// The composer box: #212121 in the dark appearance. In the light one it
    /// keeps the fixed dark grey the box has always had, because the box is
    /// deliberately dark in every appearance.
    static let composerFill = adaptive(
        dark: 0x343434,
        light: NSColor(white: 1, alpha: 1)
    )

    /// The composer's outline: a faint light edge on the dark box, a grey
    /// hairline on the white one.
    static let composerStroke = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 1, alpha: 0.04)
            : NSColor(white: 0, alpha: 0.10)
    })

    /// The composer's drop shadow: deep on dark, soft on light.
    static let composerShadow = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 0, alpha: 0.25)
            : NSColor(white: 0, alpha: 0.07)
    })

    /// The emphasised pill button: white on dark, near-black on light.
    static let prominentPillFill = adaptive(dark: 0xFFFFFF, light: NSColor(white: 0.1, alpha: 1))
    static let prominentPillText = adaptive(dark: 0x111111, light: NSColor(white: 1, alpha: 1))

    /// The cards on a settings page: a step above the page in the dark
    /// appearance, white with a hairline in the light one.
    static let settingsCard = adaptive(dark: 0x212121, light: NSColor(white: 1, alpha: 1))

    /// The window's own chrome: the band behind the traffic lights, the icon
    /// rail, and the thin frame around the content card. One step lighter than
    /// the sidebar so the card reads as set into it.
    /// Translucent, so the window's vibrancy (`WindowVibrancy`) shows through
    /// the way it does through a Finder sidebar.
    static let chrome = translucent(dark: 0x333333, light: NSColor(white: 0.945, alpha: 1), alpha: 0.55)

    /// The sessions sidebar and the settings menu column: the elevated surface's
    /// tint, translucent so the window's vibrancy shows through.
    static let sidebar = translucent(dark: 0x212121, light: NSColor(white: 0.98, alpha: 1), alpha: 0.6)

    /// The selected icon in the rail, and the selected row in the sidebar.
    static let railSelection = adaptive(dark: 0x444444, light: NSColor(white: 0.898, alpha: 1))

    /// The context strip the composer sits on (project, runtime, branch).
    static let composerContextFill = adaptive(dark: 0x272727, light: NSColor(white: 0.96, alpha: 1))

    /// The hairline around the content card and between its panes.
    static let cardStroke = adaptive(dark: 0x3c3c3c, light: NSColor(white: 0.90, alpha: 1))

    /// The pill behind an inline code span: a flat step up from the transcript,
    /// with no outline.
    static let inlineCodeFill = adaptive(dark: 0x303030, light: NSColor(white: 0.94, alpha: 1))

    /// A hovered or active row in the sidebar: a faint lift of the primary
    /// colour, a touch lighter in the light appearance so it reads as a tint of
    /// the column rather than a grey block.
    static let sidebarRowHighlight = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 1, alpha: 0.08)
            : NSColor(white: 0, alpha: 0.055)
    })

    /// The icon on an error notice: red in the dark appearance, the label colour
    /// in the light one.
    static let errorCardIcon = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor.systemRed
            : NSColor.labelColor
    })

    /// `adaptive`, at `alpha` opacity in both appearances.
    static func translucent(dark: UInt32, light: NSColor, alpha: CGFloat) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(rgb: dark).withAlphaComponent(alpha)
                : light.withAlphaComponent(alpha)
        })
    }

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

/// The sidebar column's fill: a translucent tint over the window's vibrancy,
/// so the desktop behind the window shows through as it does in Finder.
struct SidebarColumnBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(AppTheme.sidebar)
    }
}

/// The window's own backdrop: the system's behind-window blur, the standard
/// macOS translucency. It dims with the window when the window is inactive.
/// The chrome and the sidebar are tinted over it; the conversation pane stays
/// opaque so the transcript keeps its contrast.
struct WindowVibrancy: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
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
