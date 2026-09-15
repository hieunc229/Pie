//
//  WorkspaceMenuButton.swift
//  PiCode
//
//  Native workspace dropdown whose opened menu is trailing-edge aligned to its
//  trigger. SwiftUI's `Menu` does not expose the popup anchor alignment.
//

import AppKit
import SwiftUI

struct WorkspaceMenuButton: NSViewRepresentable {
    var isTerminalVisible: Bool
    var onToggleTerminal: () -> Void
    var onOpenInFinder: () -> Void
    var onOpenInVSCode: () -> Void

    func makeCoordinator() -> WorkspaceMenuCoordinator {
        WorkspaceMenuCoordinator()
    }

    func makeNSView(context: Context) -> WorkspaceMenuControl {
        let button = WorkspaceMenuControl()
        button.isBordered = false
        button.image = NSImage(
            systemSymbolName: "equal.square",
            accessibilityDescription: "Workspace actions"
        )
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = .labelColor
        button.isActive = isTerminalVisible
        button.target = context.coordinator
        button.action = #selector(WorkspaceMenuCoordinator.showMenu(_:))
        button.toolTip = "Workspace actions"
        button.setAccessibilityLabel("Workspace actions")
        context.coordinator.update(from: self)
        return button
    }

    func updateNSView(_ button: WorkspaceMenuControl, context: Context) {
        context.coordinator.update(from: self)
        button.isActive = isTerminalVisible
        button.needsDisplay = true
    }
}

final class WorkspaceMenuControl: NSButton {
    private var trackingAreaReference: NSTrackingArea?
    private var isHovered = false

    var isActive = false {
        didSet { updateAppearance() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        updateAppearance()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        updateAppearance()
    }

    override func updateTrackingAreas() {
        if let trackingAreaReference { removeTrackingArea(trackingAreaReference) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaReference = area
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateAppearance()
    }

    private func updateAppearance() {
        alphaValue = isActive || isHovered ? 1 : 0.55
    }
}

final class WorkspaceMenuCoordinator: NSObject {
    private var isTerminalVisible = false
    private var onToggleTerminal: () -> Void = {}
    private var onOpenInFinder: () -> Void = {}
    private var onOpenInVSCode: () -> Void = {}

    func update(from button: WorkspaceMenuButton) {
        isTerminalVisible = button.isTerminalVisible
        onToggleTerminal = button.onToggleTerminal
        onOpenInFinder = button.onOpenInFinder
        onOpenInVSCode = button.onOpenInVSCode
    }

    @objc func showMenu(_ sender: NSButton) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(menuItem(
            title: isTerminalVisible ? "Hide Terminal" : "Show Terminal",
            image: WorkspaceApplicationIcons.terminal,
            action: #selector(toggleTerminal)
        ))
        menu.addItem(.separator())
        menu.addItem(menuItem(
            title: "Open in Finder",
            image: WorkspaceApplicationIcons.finder,
            action: #selector(openInFinder)
        ))
        menu.addItem(menuItem(
            title: "Open in VS Code",
            image: WorkspaceApplicationIcons.visualStudioCode,
            action: #selector(openInVSCode)
        ))
        menu.update()

        let origin = NSPoint(
            x: sender.bounds.maxX - menu.size.width,
            y: sender.bounds.minY - 3
        )
        menu.popUp(positioning: nil, at: origin, in: sender)
    }

    @objc private func toggleTerminal() { onToggleTerminal() }
    @objc private func openInFinder() { onOpenInFinder() }
    @objc private func openInVSCode() { onOpenInVSCode() }

    private func menuItem(title: String, image: NSImage, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.image = image.copy() as? NSImage
        item.image?.size = NSSize(width: 16, height: 16)
        item.isEnabled = true
        return item
    }
}
