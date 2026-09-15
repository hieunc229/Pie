//
//  SidebarToggleStyler.swift
//  PiCode
//
//  Keeps SwiftUI's system-provided sidebar toggle while matching its glyph to
//  the search icon. The toolbar continues to own placement and interaction.
//

import AppKit
import SwiftUI

struct SidebarToggleStyler: NSViewRepresentable {
    var iconSize: CGFloat

    func makeNSView(context: Context) -> SidebarToggleProbeView {
        let view = SidebarToggleProbeView()
        view.iconSize = iconSize
        return view
    }

    func updateNSView(_ view: SidebarToggleProbeView, context: Context) {
        view.iconSize = iconSize
        view.applyStyle()
    }
}

final class SidebarToggleProbeView: NSView {
    var iconSize: CGFloat = 13

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyStyle()
        DispatchQueue.main.async { [weak self] in self?.applyStyle() }
    }

    func applyStyle() {
        guard let toolbar = window?.toolbar,
              let item = toolbar.items.first(where: {
                  $0.itemIdentifier == .toggleSidebar
                      || $0.itemIdentifier.rawValue.lowercased().contains("sidebar")
              }) else { return }

        let size = NSSize(width: iconSize, height: iconSize)
        item.image?.size = size
        if let button = item.view as? NSButton {
            button.image?.size = size
        }
    }
}
