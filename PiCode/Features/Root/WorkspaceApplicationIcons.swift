//
//  WorkspaceApplicationIcons.swift
//  PiCode
//
//  Resolves installed macOS application icons for workspace actions.
//

import AppKit

enum WorkspaceApplicationIcons {
    static let terminal = applicationIcon(
        bundleIdentifiers: ["com.apple.Terminal"],
        fallbackSystemName: "terminal"
    )

    static let finder = applicationIcon(
        bundleIdentifiers: ["com.apple.finder"],
        fallbackSystemName: "folder"
    )

    static let visualStudioCode = applicationIcon(
        bundleIdentifiers: [
            "com.microsoft.VSCode",
            "com.microsoft.VSCodeInsiders",
            "com.vscodium"
        ],
        fallbackSystemName: "chevron.left.forwardslash.chevron.right"
    )

    private static func applicationIcon(
        bundleIdentifiers: [String],
        fallbackSystemName: String
    ) -> NSImage {
        for identifier in bundleIdentifiers {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
                return NSWorkspace.shared.icon(forFile: url.path)
            }
        }
        return NSImage(systemSymbolName: fallbackSystemName, accessibilityDescription: nil) ?? NSImage()
    }
}
