//
//  WorkspaceLauncher.swift
//  PiCode
//
//  Small, permission-free ways to hand a path to the rest of macOS.
//
//  PiCode deliberately avoids AppleScript automation prompts: "Open in Terminal"
//  writes a tiny `.command` file and lets LaunchServices open it, which needs no
//  automation entitlement and cannot be silently scripted by another app.
//

import AppKit
import Foundation
import UniformTypeIdentifiers

enum WorkspaceLauncher {
    /// Opens Terminal.app at `directory` without requesting automation access.
    @discardableResult
    static func openTerminal(at directory: String) -> URL? {
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("PiCode", isDirectory: true)
        try? FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)

        let scriptURL = sandbox.appendingPathComponent("PiCode-\(UUID().uuidString.prefix(8)).command")
        let escaped = directory.replacingOccurrences(of: "'", with: "'\\''")
        let script = """
        #!/bin/zsh
        # Written by PiCode so Terminal opens in the project directory.
        rm -f "$0"
        cd '\(escaped)' || exit 1
        exec "${SHELL:-/bin/zsh}" -l
        """
        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        } catch {
            return nil
        }
        NSWorkspace.shared.open(scriptURL)
        return scriptURL
    }

    static func reveal(_ path: String) {
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
        }
    }

    static func open(_ path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    /// Copies text to the general pasteboard.
    static func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Opens an http(s) URL, refusing anything else so a model-authored link
    /// cannot talk PiCode into launching a local scheme.
    static func openWebURL(_ string: String) {
        guard let url = URL(string: string),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return }
        NSWorkspace.shared.open(url)
    }

    static func chooseDirectory(prompt: String = "Choose a project folder") -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = prompt
        panel.message = "PiCode runs `pi` in the folder you choose."
        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    static func chooseSaveLocation(suggestedName: String, allowedType: String? = nil) -> String? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        if let allowedType, let type = UTType(filenameExtension: allowedType) {
            panel.allowedContentTypes = [type]
        }
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}
