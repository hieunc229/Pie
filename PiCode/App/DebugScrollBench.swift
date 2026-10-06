//
//  DebugScrollBench.swift
//  PiCode
//
//  Debug builds only: `PICODE_SCROLL_BENCH=/path/report.txt` scrolls the open
//  transcript from the bottom to the top and back in fixed steps, one step per
//  run-loop turn, and writes how long each turn took. A turn includes everything
//  SwiftUI does for that scroll offset — materialising lazy rows, laying out
//  text, drawing — so the numbers are what a wheel or trackpad scroll feels like,
//  and they can be compared before and after a rendering change.
//

#if DEBUG
import AppKit
import QuartzCore

@MainActor
final class DebugScrollBench {
    private static var current: DebugScrollBench?

    static func scheduleIfRequested() {
        let environment = ProcessInfo.processInfo.environment
        guard let output = environment["PICODE_SCROLL_BENCH"], !output.isEmpty else { return }
        let delay = Double(environment["PICODE_SCROLL_BENCH_DELAY"] ?? "") ?? 12
        let step = CGFloat(Double(environment["PICODE_SCROLL_BENCH_STEP"] ?? "") ?? 48)
        let passes = Int(environment["PICODE_SCROLL_BENCH_PASSES"] ?? "") ?? 2
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            let bench = DebugScrollBench(output: output, step: step, passes: passes)
            current = bench
            bench.start()
        }
    }

    private let output: String
    private let step: CGFloat
    private var passesLeft: Int
    private var scrollView: NSScrollView?
    private var timer: Timer?
    private var direction: CGFloat = -1
    private var lastTick: CFTimeInterval = 0
    private var samples: [Double] = []
    private var lastY: CGFloat = 0
    /// Where the pointer was before the bench moved it over the transcript.
    private var savedPointer: CGPoint?
    private var lastHeight: CGFloat = 0
    private var log: [String] = []

    private init(output: String, step: CGFloat, passes: Int) {
        self.output = output
        self.step = step
        self.passesLeft = passes * 2
    }

    private func start() {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.frame.width > 400 }),
              let root = window.contentView,
              let scrollView = Self.transcriptScrollView(in: root) else {
            finish(note: "no transcript scroll view found")
            return
        }
        self.scrollView = scrollView
        let documentHeight = scrollView.documentView?.frame.height ?? 0
        log.append("document height at start: \(Int(documentHeight))pt, viewport \(Int(scrollView.contentView.bounds.height))pt, step \(Int(step))pt")
        // Scrolling with a trackpad happens with the pointer over the transcript,
        // which is what makes rows' hover handlers fire as content moves under it.
        // `PICODE_SCROLL_BENCH_HOVER=1` puts the pointer there for the run.
        if ProcessInfo.processInfo.environment["PICODE_SCROLL_BENCH_HOVER"] == "1",
           let screen = window.screen ?? NSScreen.main {
            let current = NSEvent.mouseLocation
            savedPointer = CGPoint(x: current.x, y: screen.frame.maxY - current.y)
            let rect = scrollView.convert(scrollView.bounds, to: nil)
            let onScreen = window.convertToScreen(rect)
            CGWarpMouseCursorPosition(CGPoint(x: onScreen.midX, y: screen.frame.maxY - onScreen.midY))
        }
        lastTick = CACurrentMediaTime()
        timer = Timer.scheduledTimer(withTimeInterval: 0.001, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        guard let scrollView, let document = scrollView.documentView else { return }
        let now = CACurrentMediaTime()
        let elapsed = (now - lastTick) * 1000
        samples.append(elapsed)
        lastTick = now
        if elapsed > 16.7, samples.count > 1 {
            log.append(String(format: "slow %.1fms at y=%.0f (dir %@), height %.0f -> %.0f",
                              elapsed, lastY, direction < 0 ? "up" : "down",
                              lastHeight, document.frame.height))
        }
        lastHeight = document.frame.height

        let clip = scrollView.contentView
        let maxY = max(0, document.frame.height - clip.bounds.height)
        // A flipped document scrolls down as y grows; an unflipped one the other way.
        let towardTop: CGFloat = document.isFlipped ? -1 : 1
        var y = clip.bounds.origin.y + step * direction * towardTop * -1
        y = min(max(0, y), maxY)
        lastY = y
        clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: y))
        scrollView.reflectScrolledClipView(clip)

        let atTop = document.isFlipped ? y <= 0 : y >= maxY
        let atBottom = document.isFlipped ? y >= maxY : y <= 0
        if (direction < 0 && atTop) || (direction > 0 && atBottom) {
            passesLeft -= 1
            log.append("pass \(direction < 0 ? "up" : "down") done, document height \(Int(document.frame.height))pt")
            direction *= -1
            if passesLeft <= 0 { finish(note: nil) }
        }
    }

    private func finish(note: String?) {
        timer?.invalidate()
        timer = nil
        if let savedPointer { CGWarpMouseCursorPosition(savedPointer) }
        var lines = log
        if let note { lines.append(note) }
        let sorted = samples.dropFirst().sorted()
        if !sorted.isEmpty {
            func percentile(_ p: Double) -> Double { sorted[min(sorted.count - 1, Int(Double(sorted.count) * p))] }
            let mean = sorted.reduce(0, +) / Double(sorted.count)
            let over16 = sorted.filter { $0 > 16.7 }.count
            let over33 = sorted.filter { $0 > 33.4 }.count
            lines.append(String(format: "turns %d  mean %.2fms  p50 %.2fms  p90 %.2fms  p99 %.2fms  max %.2fms",
                                sorted.count, mean, percentile(0.5), percentile(0.9), percentile(0.99), sorted.last ?? 0))
            lines.append("turns over 16.7ms: \(over16)   over 33.4ms: \(over33)")
        }
        try? lines.joined(separator: "\n").appending("\n").write(toFile: output, atomically: true, encoding: .utf8)
        Self.current = nil
    }

    /// The transcript is the tallest scrolling document in the window whose
    /// scroller is vertical — the sidebar's list is the other candidate, and it is
    /// narrower.
    private static func transcriptScrollView(in root: NSView) -> NSScrollView? {
        var found: [NSScrollView] = []
        func walk(_ view: NSView) {
            if let scroll = view as? NSScrollView, scroll.hasVerticalScroller || scroll.documentView != nil {
                found.append(scroll)
            }
            view.subviews.forEach(walk)
        }
        walk(root)
        return found
            .filter { ($0.documentView?.frame.height ?? 0) > $0.contentView.bounds.height }
            .max { $0.frame.width < $1.frame.width }
    }
}
#endif
