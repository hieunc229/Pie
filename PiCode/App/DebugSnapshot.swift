//
//  DebugSnapshot.swift
//  PiCode
//
//  Debug builds only: `PICODE_SNAPSHOT=/path/out.png` makes the app capture its
//  own main window after a short delay. An app may always read its own window's
//  pixels, so this needs no screen-recording permission — which is what lets a
//  layout change be checked against a reference without a person at the screen.
//

#if DEBUG
import AppKit

enum DebugSnapshot {
    static func scheduleIfRequested() {
        let environment = ProcessInfo.processInfo.environment
        guard let output = environment["PICODE_SNAPSHOT"], !output.isEmpty else { return }
        let delay = Double(environment["PICODE_SNAPSHOT_DELAY"] ?? "") ?? 4
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            capture(to: output)
        }
    }

    @MainActor
    private static func capture(to output: String) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil && $0.frame.width > 400 }),
              let frameView = window.contentView?.superview else { return }
        let bounds = frameView.bounds
        guard let rep = frameView.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        frameView.cacheDisplay(in: bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: URL(fileURLWithPath: output))
    }
}
#endif
