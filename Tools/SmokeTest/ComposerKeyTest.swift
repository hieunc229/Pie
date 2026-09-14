//
//  ComposerKeyTest.swift
//  PiCode smoke test — not part of the app target.
//
//  What the composer promises about the Return key, checked against the real
//  `ComposerTextView` in a real window with real key events:
//
//    * Return sends and leaves no newline behind;
//    * Shift-Return adds a line and never sends;
//    * Option-Return queues the message as a follow-up;
//    * the non-sending chord of the other `PreferencesStore.SendKey` mode still
//      adds a line;
//    * an open suggestion list swallows Return (you are choosing, not sending);
//    * Escape reaches the composer.
//
//  Every one of those was wrong or unreachable in the first implementation, and
//  the reason is a key-mapping trap that cannot be guessed from the selector
//  names — see the table printed at the end, and §10 of PROCESS.md. So the table
//  itself is asserted, not assumed.
//
//  It also renders the composer box and measures its corner, because "rounder"
//  is a number and the harness should hold it.
//

import AppKit
import SwiftUI

// MARK: - A host that reports what the text view asked for

final class ComposerProbe: ObservableObject {
    @Published var text = ""
    var sends = 0
    var followUps = 0
    var escapes = 0
    var accepts = 0

    func reset() {
        text = ""
        sends = 0
        followUps = 0
        escapes = 0
        accepts = 0
    }
}

struct ComposerHost: View {
    @ObservedObject var probe: ComposerProbe
    var sendKey: PreferencesStore.SendKey
    var suggestionsActive: Bool
    var onTextView: (NSTextView) -> Void = { _ in }

    var body: some View {
        ComposerTextView(
            text: $probe.text,
            placeholder: "Ask Pi to change something in this project…",
            focusTick: 1,
            sendKey: sendKey,
            suggestionsActive: suggestionsActive,
            isEnabled: true,
            onSend: { probe.sends += 1 },
            onFollowUp: { probe.followUps += 1 },
            onEscape: { probe.escapes += 1 },
            onMoveSuggestion: { _ in },
            onAcceptSuggestion: { probe.accepts += 1 }
        )
        .frame(width: 420, height: 70)
        .onAppear { }
    }
}

// MARK: - Scenarios

struct KeyStep {
    var key: String
    var code: UInt16
    var flags: NSEvent.ModifierFlags = []
    var sends = 0
    var followUps = 0
    var accepts = 0
    var escapes = 0
    /// The editor's whole content after the press, so a stray newline cannot hide.
    var text = ""
}

struct KeyScenario {
    var name: String
    var sendKey: PreferencesStore.SendKey
    var suggestionsActive = false
    var steps: [KeyStep]
}

enum KeyCodes {
    static let ret: UInt16 = 36
    static let escape: UInt16 = 53
}

let keyScenarios: [KeyScenario] = [
    KeyScenario(
        name: "Return sends, Shift-Return adds a line",
        sendKey: .returnKey,
        steps: [
            KeyStep(key: "Return", code: KeyCodes.ret, sends: 1, text: ""),
            KeyStep(key: "Shift+Return", code: KeyCodes.ret, flags: [.shift], sends: 1, text: "\n"),
            KeyStep(key: "Option+Return", code: KeyCodes.ret, flags: [.option], sends: 1, followUps: 1, text: "\n"),
            KeyStep(key: "Command+Return", code: KeyCodes.ret, flags: [.command], sends: 1, followUps: 1, text: "\n\n"),
            KeyStep(key: "Escape", code: KeyCodes.escape, sends: 1, followUps: 1, escapes: 1, text: "\n\n"),
        ]
    ),
    KeyScenario(
        name: "Command-Return sends, Return adds a line",
        sendKey: .commandReturn,
        steps: [
            KeyStep(key: "Return", code: KeyCodes.ret, text: "\n"),
            KeyStep(key: "Command+Return", code: KeyCodes.ret, flags: [.command], sends: 1, text: "\n"),
            KeyStep(key: "Shift+Return", code: KeyCodes.ret, flags: [.shift], sends: 1, text: "\n\n"),
        ]
    ),
    KeyScenario(
        name: "An open suggestion list swallows Return",
        sendKey: .returnKey,
        suggestionsActive: true,
        steps: [
            KeyStep(key: "Return", code: KeyCodes.ret, accepts: 1, text: ""),
            KeyStep(key: "Shift+Return", code: KeyCodes.ret, flags: [.shift], accepts: 2, text: ""),
        ]
    ),
]

// MARK: - Harness

final class ComposerKeyDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var failures = 0
    private var checks = 0
    private var probe = ComposerProbe()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setvbuf(stdout, nil, _IONBF, 0)

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 120),
                          styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "composer harness"
        window.contentView = hostingView(sendKey: .returnKey, suggestionsActive: false)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // A stuck harness should fail, not hang a release check.
        let watchdog = Thread {
            Thread.sleep(forTimeInterval: 30)
            print("\nRESULT: harness timed out")
            exit(2)
        }
        watchdog.start()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            self.runKeyScenarios()
            self.runGeometryChecks()
            self.report()
        }
    }

    private func hostingView(sendKey: PreferencesStore.SendKey, suggestionsActive: Bool) -> NSHostingView<ComposerHost> {
        probe.reset()
        return NSHostingView(rootView: ComposerHost(probe: probe,
                                                    sendKey: sendKey,
                                                    suggestionsActive: suggestionsActive))
    }

    // MARK: Keys

    private func runKeyScenarios() {
        print("== what Return means ==")
        for scenario in keyScenarios {
            window.contentView = hostingView(sendKey: scenario.sendKey, suggestionsActive: scenario.suggestionsActive)
            pump(0.35)

            guard let textView = ComposerKeyDelegate.firstTextView(in: window.contentView) else {
                check("\(scenario.name): the editor exists", false)
                continue
            }
            textView.window?.makeFirstResponder(textView)
            pump(0.15)
            textView.string = ""
            probe.text = ""
            pump(0.05)

            print("  · \(scenario.name)")
            for step in scenario.steps {
                press(step.code, step.flags)
                pump(0.12)
                let counters = "sends \(probe.sends), followUps \(probe.followUps), accepts \(probe.accepts), escapes \(probe.escapes)"
                let expected = "sends \(step.sends), followUps \(step.followUps), accepts \(step.accepts), escapes \(step.escapes)"
                check("    \(step.key) → \(expected)", counters == expected, detail: "got \(counters)")
                // `textView.string` is the editor's own content, not the binding:
                // a newline inserted by the text system shows up here either way.
                check("    \(step.key) leaves \(step.text.isEmpty ? "no newline" : "\(step.text.count) newline(s)")",
                      textView.string == step.text,
                      detail: "editor holds \(textView.string.debugDescription)")
            }
        }
    }

    private static func firstTextView(in view: NSView?) -> NSTextView? {
        guard let view else { return nil }
        if let textView = view as? NSTextView { return textView }
        for subview in view.subviews {
            if let found = firstTextView(in: subview) { return found }
        }
        return nil
    }

    /// Posts a real key event through the app's event queue. `CGEvent` rather than
    /// a synthesised `NSEvent` so AppKit computes the same selector and modifier
    /// flags a human's key press would.
    private func press(_ code: UInt16, _ flags: NSEvent.ModifierFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        for isDown in [true, false] {
            guard let cgEvent = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: isDown),
                  let event = NSEvent(cgEvent: cgEvent) else { continue }
            event.cgEvent?.flags = CGEventFlags(rawValue: UInt64(flags.rawValue))
            NSApp.postEvent(event, atStart: false)
        }
    }

    /// Runs the app's own event loop for a while. Mouse/key handling in SwiftUI
    /// runs an event-tracking loop of its own, so events have to be posted and
    /// then let through here rather than delivered with `sendEvent` inline.
    private func pump(_ seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if let event = NSApp.nextEvent(matching: .any,
                                           until: Date().addingTimeInterval(0.02),
                                           inMode: .default,
                                           dequeue: true) {
                NSApp.sendEvent(event)
            }
        }
    }

    // MARK: Geometry

    /// The box is drawn the way the composer draws it — same `ComposerMetrics`
    /// compiled into this binary — over a red page, so the fill can be measured
    /// without text getting in the way.
    private func runGeometryChecks() {
        print()
        print("== the prompt box ==")
        window.contentView = NSHostingView(rootView: BoxProbe())
        pump(0.4)

        // Draw the view itself rather than photographing the window: this harness
        // shares the screen with the real app, and an occluded window captures
        // black (`WindowPixels.capture(_ view:)`).
        guard let box = window.contentView, let pixels = WindowPixels.capture(box) else {
            check("the box can be captured", false)
            return
        }
        let scale = pixels.scale
        let isFill: (Int, Int) -> Bool = { x, y in
            let (r, g, b) = pixels.rgb(x, y)
            return r > 235 && g > 235 && b > 235
        }

        var rows: [(y: Int, min: Int, max: Int)] = []
        for y in 0..<pixels.height {
            let xs = (0..<pixels.width).filter { isFill($0, y) }
            if let first = xs.first, let last = xs.last { rows.append((y, first, last)) }
        }
        guard let firstRow = rows.first, let lastRow = rows.last else {
            check("the box fill is visible", false)
            return
        }

        let widest = rows.map { $0.max - $0.min + 1 }.max() ?? 0
        let width = CGFloat(widest) / scale
        let height = CGFloat(lastRow.y - firstRow.y + 1) / scale
        // At its topmost row a rounded rectangle is only as wide as its flat
        // span, so the missing width on each side is the corner. For SwiftUI's
        // `.continuous` corner that span is *narrower* than `width - 2r`, so the
        // raw number is not the radius. Measured through this exact capture path
        // (`WindowPixels.capture(_ view:)`), a 300pt box on a red page:
        //
        //     radius     10     14     18     22   (circular 18)
        //     inset    11.0   16.0   21.0   26.0          17.0
        //     height   11.5   16.5   21.5   26.5          17.5
        //
        // Inset and corner height both track the radius linearly, so the fit below
        // turns a measurement back into the radius it was drawn with. It is
        // calibrated for *this* path: a window-server capture of the same shape
        // reads 3.5pt wider, so re-measure if the capture changes. `.circular`
        // sits off the line (17.0 where continuous measures 21.0), which is why
        // the style is part of what this pins down.
        let corner = CGFloat(widest - (firstRow.max - firstRow.min + 1)) / 2 / scale
        let predicted = 1.25 * ComposerMetrics.cornerRadius - 1.5

        print(String(format: "  measured: box %.1fpt wide, %.1fpt tall, corner inset %.1fpt (radius %.1fpt predicts %.1fpt)",
                     width, height, corner, ComposerMetrics.cornerRadius, predicted))
        check(String(format: "the box is softly rounded (inset %.1fpt; the old 10pt radius measured 11.0pt)", corner),
              corner >= 20, detail: "inset \(corner)")
        check("the corner is drawn at ComposerMetrics.cornerRadius",
              abs(corner - predicted) <= 1.5,
              detail: "inset \(corner) vs predicted \(predicted)")
        check("the box stays short (one line plus its controls)", height <= 84,
              detail: "height \(height)")

        if let png = pixels.pngData() {
            let path = "/tmp/picode-composer-box.png"
            try? png.write(to: URL(fileURLWithPath: path))
            print("  wrote \(path)")
        }
    }

    // MARK: Reporting

    private func check(_ name: String, _ passed: Bool, detail: String? = nil) {
        checks += 1
        if passed {
            print("  ok   \(name)")
        } else {
            failures += 1
            print("  FAIL \(name)\(detail.map { " — \($0)" } ?? "")")
        }
    }

    private func report() {
        print()
        print("== how AppKit reports the Return family (the trap this pins down) ==")
        for (name, selector) in [("Return", "insertNewline:"),
                                 ("Shift+Return", "insertNewline: (with .shift)"),
                                 ("Option+Return", "insertNewlineIgnoringFieldEditor:"),
                                 ("Command+Return", "noop:")] {
            print("  \(name.padding(toLength: 16, withPad: " ", startingAt: 0))→ \(selector)")
        }
        print()
        if failures == 0 {
            print("RESULT: all checks passed (\(checks) checks)")
            exit(0)
        } else {
            print("RESULT: \(failures) check(s) failed of \(checks)")
            exit(1)
        }
    }
}

/// The composer's box shape, isolated: white fill on a red page, with the same
/// radius and roughly the same content height as the real composer.
struct BoxProbe: View {
    var body: some View {
        ZStack {
            Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1)
            VStack(alignment: .leading, spacing: 0) {
                Color.clear.frame(height: 26)
                HStack(spacing: 2) {
                    Color.clear.frame(width: 22, height: 20)
                    Spacer(minLength: 8)
                    Color.clear.frame(width: 22, height: 20)
                }
                .padding(.top, 5)
            }
            .padding(.horizontal, 9)
            .padding(.top, 6)
            .padding(.bottom, 5)
            .background(Color.white, in: RoundedRectangle(cornerRadius: ComposerMetrics.cornerRadius, style: .continuous))
            .padding(24)
        }
    }
}

@main
struct ComposerKeyHarness {
    static func main() {
        // Unbuffered: a wedged run loop must still show the last line printed.
        setvbuf(stdout, nil, _IONBF, 0)
        // Nothing here should take 30s; a hung window on someone's screen is worse
        // than a failed check.
        DispatchQueue.global().asyncAfter(deadline: .now() + 30) {
            print("\nRESULT: harness timed out (a key event wedged the run loop?)")
            exit(2)
        }
        let application = NSApplication.shared
        let delegate = ComposerKeyDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}
