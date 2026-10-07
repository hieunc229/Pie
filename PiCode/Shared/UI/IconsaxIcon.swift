//
//  IconsaxIcon.swift
//  PiCode
//
//  Iconsax (Linear) icon rendering. The used glyphs are vendored as template
//  SVGs under Assets.xcassets/Iconsax, so they tint with the surrounding
//  foreground style.
//

import AppKit
import SwiftUI

/// An Iconsax glyph drawn at a consistent, Dynamic Type-aware size.
struct IconsaxIcon: View {
    var name: String
    /// Overrides the default size for large decorative glyphs (empty states).
    var size: CGFloat?

    @ScaledMetric(relativeTo: .body) private var scaledSize: CGFloat = 14

    var body: some View {
        iconsaxImage(name)
            .resizable()
            .scaledToFit()
            .frame(width: size ?? scaledSize, height: size ?? scaledSize)
    }
}

/// The Iconsax glyph as an `Image`. The vendored assets carry an intrinsic size,
/// so this also works inline in `Text` and as a `Label` icon AppKit draws into a
/// menu.
func iconsaxImage(_ name: String) -> Image {
    Image("Iconsax/\(name)")
}

extension Label where Title == Text, Icon == Image {
    init(_ titleKey: LocalizedStringKey, iconsax name: String) {
        self.init { Text(titleKey) } icon: { iconsaxImage(name) }
    }

    init<S: StringProtocol>(_ title: S, iconsax name: String) {
        self.init { Text(title) } icon: { iconsaxImage(name) }
    }
}

extension NSImage {
    /// The Iconsax glyph as an `NSImage`, for AppKit surfaces such as menus.
    static func iconsax(_ name: String) -> NSImage {
        let image = NSImage(named: "Iconsax/\(name)") ?? NSImage()
        image.isTemplate = true
        return image
    }
}
