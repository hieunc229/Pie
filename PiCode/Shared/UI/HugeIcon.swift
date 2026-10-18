//
//  HugeIcon.swift
//  PiCode
//
//  Icons from Hugeicons (free "Stroke Rounded" set, MIT licensed):
//  https://hugeicons.com
//
//  Only the glyphs this app uses are vendored, as template SVGs under
//  Assets.xcassets/Hugeicons, so they tint with the surrounding foreground style.
//

import AppKit
import SwiftUI

/// A Hugeicons glyph drawn at a consistent, Dynamic Type-aware size.
struct HugeIcon: View {
    var name: String
    /// Overrides the default size for large decorative glyphs (empty states).
    var size: CGFloat?

    @ScaledMetric(relativeTo: .body) private var scaledSize: CGFloat = 14

    var body: some View {
        hugeIconImage(name)
            .resizable()
            .scaledToFit()
            .frame(width: size ?? scaledSize, height: size ?? scaledSize)
    }
}

/// The Hugeicons glyph as an `Image`. The vendored assets carry an intrinsic
/// size, so this also works inline in `Text` and as a `Label` icon AppKit draws
/// into a menu.
func hugeIconImage(_ name: String) -> Image {
    Image("Hugeicons/\(name)")
}

extension Label where Title == Text, Icon == Image {
    init(_ titleKey: LocalizedStringKey, huge name: String) {
        self.init { Text(titleKey) } icon: { hugeIconImage(name) }
    }

    init<S: StringProtocol>(_ title: S, huge name: String) {
        self.init { Text(title) } icon: { hugeIconImage(name) }
    }
}

extension NSImage {
    /// The Hugeicons glyph as an `NSImage`, for AppKit surfaces such as menus.
    static func huge(_ name: String) -> NSImage {
        let image = NSImage(named: "Hugeicons/\(name)") ?? NSImage()
        image.isTemplate = true
        return image
    }
}
