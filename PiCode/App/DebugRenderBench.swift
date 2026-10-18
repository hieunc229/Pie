//
//  DebugRenderBench.swift
//  PiCode
//
//  Debug builds only: `PICODE_RENDER_BENCH=/path/report.txt` loads the open
//  session's whole transcript, then hosts every row off-screen at the
//  transcript's width and times how long SwiftUI takes to build and measure it.
//  It is the cost a row adds the first time it scrolls into view (or the first
//  time a page of earlier history is prepended), isolated from scrolling.
//

#if DEBUG
import AppKit
import SwiftUI

@MainActor
enum DebugRenderBench {
    static func runIfRequested(state: AppState) async {
        guard let output = ProcessInfo.processInfo.environment["PICODE_RENDER_BENCH"], !output.isEmpty else { return }
        func note(_ text: String) { FileHandle.standardError.write("RENDERBENCH \(text)\n".data(using: .utf8)!) }
        note("waiting")
        // A bench window is rarely frontmost; without this App Nap stretches
        // every timer and the numbers measure throttling instead of work.
        let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical],
                                                             reason: "render bench")
        defer { ProcessInfo.processInfo.endActivity(activity) }
        // Wait for the session to be open with its history read.
        var controller: PiSessionController?
        for _ in 0..<120 {
            let wanted = ProcessInfo.processInfo.environment["PICODE_OPEN_SESSION"]
            if let active = state.activeController, !active.items.isEmpty, !active.isLoadingTranscriptHistory,
               wanted == nil || active.sessionFile?.hasSuffix(wanted!) == true || active.sessionId == wanted {
                controller = active
                break
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        note("controller \(controller != nil), active \(state.activeController?.items.count ?? -1) loading \(state.activeController?.isLoadingTranscriptHistory ?? false)")
        guard let controller else {
            try? "no session\n".write(toFile: output, atomically: true, encoding: .utf8)
            return
        }
        let wantedRows = Int(ProcessInfo.processInfo.environment["PICODE_RENDER_BENCH_ROWS"] ?? "") ?? 60
        while controller.hasEarlierTranscript, controller.rows.count < wantedRows {
            controller.loadEarlierTranscript()
        }

        if let shotPrefix = ProcessInfo.processInfo.environment["PICODE_SCREENSHOT"] {
            await screenshots(controller: controller, prefix: shotPrefix)
            return
        }
        if let scrollOutput = ProcessInfo.processInfo.environment["PICODE_SCROLL_BENCH"] {
            await scrollBench(controller: controller, output: scrollOutput)
            return
        }
        if let streamOutput = ProcessInfo.processInfo.environment["PICODE_STREAM_BENCH"] {
            await streamBench(controller: controller, output: streamOutput)
            return
        }
        let rows = controller.rows
        note("measuring \(rows.count) rows")
        let width = ConversationLayout.maxContentWidth
        let hover = TranscriptHoverState()
        var lines: [String] = []
        var total = 0.0
        var totalHeight = 0.0
        var byKind: [String: (count: Int, ms: Double)] = [:]
        let repeats = Int(ProcessInfo.processInfo.environment["PICODE_RENDER_BENCH_REPEATS"] ?? "") ?? 2

        for row in rows {
            var best = Double.infinity
            var height: CGFloat = 0
            for _ in 0..<repeats {
                let view = ConversationMessageRow(row: row, response: controller.responseMetadata[row.id],
                                                  controller: controller, hover: hover)
                    .frame(width: width)
                    .environment(\.colorScheme, .dark)
                let start = CACurrentMediaTime()
                let host = NSHostingView(rootView: view)
                let size = host.fittingSize
                host.frame = NSRect(origin: .zero, size: size)
                host.layoutSubtreeIfNeeded()
                best = min(best, (CACurrentMediaTime() - start) * 1000)
                height = size.height
            }
            note(String(format: "row %.1fms", best))
            let kind = Self.kind(of: row)
            total += best
            totalHeight += height
            byKind[kind, default: (0, 0)].count += 1
            byKind[kind, default: (0, 0)].ms += best
            lines.append(String(format: "%7.2fms %6.0fpt  %@", best, height, Self.describe(row)))
        }

        var report = [String(format: "rows %d  total %.1fms  height %.0fpt  => %.2fms per 1000pt",
                             rows.count, total, totalHeight, totalHeight > 0 ? total / totalHeight * 1000 : 0)]
        for (kind, value) in byKind.sorted(by: { $0.value.ms > $1.value.ms }) {
            report.append(String(format: "  %-12@ %4d rows  %8.1fms", kind as NSString, value.count, value.ms))
        }
        report.append("slowest rows:")
        report += lines.sorted(by: >).prefix(15)
        try? report.joined(separator: "\n").appending("\n").write(toFile: output, atomically: true, encoding: .utf8)
        NSApp.terminate(nil)
    }

    /// Appends a few words to the last reply every frame, the way a streaming
    /// turn does, and records how long each run-loop turn takes — with every
    /// loaded row on screen or off, so the cost of the rows that did *not*
    /// change shows up.
    private static func streamBench(controller: PiSessionController, output: String) async {
        let delay = Double(ProcessInfo.processInfo.environment["PICODE_STREAM_BENCH_DELAY"] ?? "") ?? 1.5
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        FileHandle.standardError.write("RENDERBENCH stream start\n".data(using: .utf8)!)
        let pipeline = controller.debugTimeModelPipeline(
            repeats: Int(ProcessInfo.processInfo.environment["PICODE_PIPELINE_REPEATS"] ?? "") ?? 10)
        var samples: [Double] = []
        var workMs = 0.0
        var last = CACurrentMediaTime()
        let words = ["The ", "transcript ", "keeps ", "growing ", "while ", "**Pi** ", "writes ", "`code` ", "and ", "prose.\n\n"]
        for step in 0..<240 {
            let work = CACurrentMediaTime()
            if ProcessInfo.processInfo.environment["PICODE_STREAM_BENCH_NOOP"] == nil {
                controller.debugGrowLastAssistant(by: words[step % words.count])
            }
            workMs += (CACurrentMediaTime() - work) * 1000
            try? await Task.sleep(nanoseconds: 16_000_000)
            let now = CACurrentMediaTime()
            samples.append((now - last) * 1000 - 16)
            last = now
        }
        let sorted = samples.dropFirst().sorted()
        let mean = sorted.reduce(0, +) / Double(sorted.count)
        func percentile(_ p: Double) -> Double { sorted[min(sorted.count - 1, Int(Double(sorted.count) * p))] }
        let report = String(format: "rows %d  stream ticks %d  model work/tick %.2fms  extra per tick: mean %.2fms  p50 %.2fms  p90 %.2fms  p99 %.2fms  max %.2fms\n",
                            controller.rows.count, sorted.count, workMs / Double(samples.count), mean, percentile(0.5), percentile(0.9), percentile(0.99), sorted.last ?? 0)
        try? (pipeline + "\n" + report).write(toFile: output, atomically: true, encoding: .utf8)
        NSApp.terminate(nil)
    }

    /// Scrolls the on-screen transcript up and back down a few points per frame,
    /// the way a trackpad does, and records how long each frame takes — the cost
    /// the user actually feels, including history the idle fill prepends.
    private static func scrollBench(controller: PiSessionController, output: String) async {
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        func scrollViews(in view: NSView) -> [NSScrollView] {
            ((view as? NSScrollView).map { [$0] } ?? []) + view.subviews.flatMap(scrollViews(in:))
        }
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
              let scroll = scrollViews(in: window.contentView!)
                .filter({ $0.documentView != nil })
                .max(by: { ($0.documentView?.frame.height ?? 0) < ($1.documentView?.frame.height ?? 0) })
        else {
            try? "no scroll view\n".write(toFile: output, atomically: true, encoding: .utf8)
            NSApp.terminate(nil)
            return
        }
        let step = CGFloat(Double(ProcessInfo.processInfo.environment["PICODE_SCROLL_STEP"] ?? "") ?? 24)
        let frames = Int(ProcessInfo.processInfo.environment["PICODE_SCROLL_FRAMES"] ?? "") ?? 600
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        var samples: [Double] = []
        var phases = [Double](repeating: 0, count: 4)
        var direction: CGFloat = -1
        for _ in 0..<frames {
            let start = CACurrentMediaTime()
            let clip = scroll.contentView
            var origin = clip.bounds.origin
            let maxY = max(0, (scroll.documentView?.frame.height ?? 0) - clip.bounds.height)
            origin.y += direction * step * (scroll.documentView?.isFlipped == true ? 1 : -1)
            if origin.y <= 0 || origin.y >= maxY { direction = -direction }
            origin.y = min(max(0, origin.y), maxY)
            clip.scroll(to: origin)
            scroll.reflectScrolledClipView(clip)
            // One display cycle's worth of work, done synchronously so the
            // sample is the main thread's cost rather than timer slack:
            // pending SwiftUI transactions (state set by geometry callbacks),
            // layout, and display.
            let t1 = CACurrentMediaTime()
            RunLoop.main.run(mode: .default, before: Date())
            let t2 = CACurrentMediaTime()
            window.layoutIfNeeded()
            let t3 = CACurrentMediaTime()
            window.displayIfNeeded()
            CATransaction.flush()
            let t4 = CACurrentMediaTime()
            phases[0] += t1 - start; phases[1] += t2 - t1; phases[2] += t3 - t2; phases[3] += t4 - t3
            samples.append((t4 - start) * 1000)
            try? await Task.sleep(nanoseconds: 4_000_000)
        }
        let sorted = samples.dropFirst().sorted()
        let mean = sorted.reduce(0, +) / Double(sorted.count)
        func percentile(_ p: Double) -> Double { sorted[min(sorted.count - 1, Int(Double(sorted.count) * p))] }
        let over16 = sorted.filter { $0 > 16.7 }.count
        let report = String(format: "rows %d items %d docHeight %.0f  frame ms: mean %.2f  p50 %.2f  p90 %.2f  p99 %.2f  max %.2f  >16.7ms %d/%d  phases(ms total) scroll %.0f runloop %.0f layout %.0f display %.0f\n",
                            controller.rows.count, controller.items.count, scroll.documentView?.frame.height ?? 0,
                            mean, percentile(0.5), percentile(0.9), percentile(0.99), sorted.last ?? 0, over16, sorted.count,
                            phases[0] * 1000, phases[1] * 1000, phases[2] * 1000, phases[3] * 1000)
        try? report.write(toFile: output, atomically: true, encoding: .utf8)
        NSApp.terminate(nil)
    }

    /// Saves the window at the bottom of the transcript, then after scrolling
    /// up through a few prepended pages, so layout and scroll anchoring can be
    /// checked by eye.
    private static func screenshots(controller: PiSessionController, prefix: String) async {
        try? await Task.sleep(nanoseconds: 4_000_000_000)
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
              let content = window.contentView else { NSApp.terminate(nil); return }
        func save(_ name: String) {
            guard let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { return }
            content.cacheDisplay(in: content.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(prefix)-\(name).png"))
        }
        func scrollViews(in view: NSView) -> [NSScrollView] {
            ((view as? NSScrollView).map { [$0] } ?? []) + view.subviews.flatMap(scrollViews(in:))
        }
        var log: [String] = []
        save("bottom")
        log.append("bottom rows \(controller.rows.count)")
        if let scroll = scrollViews(in: content).filter({ $0.documentView != nil })
            .max(by: { ($0.documentView?.frame.height ?? 0) < ($1.documentView?.frame.height ?? 0) }) {
            let steps = Int(ProcessInfo.processInfo.environment["PICODE_SCREENSHOT_STEPS"] ?? "") ?? 120
            for step in 0..<steps {
                let clip = scroll.contentView
                var origin = clip.bounds.origin
                origin.y -= 40 * (scroll.documentView?.isFlipped == true ? 1 : -1)
                origin.y = max(0, origin.y)
                clip.scroll(to: origin)
                scroll.reflectScrolledClipView(clip)
                try? await Task.sleep(nanoseconds: 16_000_000)
                if step % 30 == 29 {
                    log.append(String(format: "step %d rows %d docHeight %.0f originY %.0f",
                                      step, controller.rows.count, scroll.documentView?.frame.height ?? 0,
                                      scroll.contentView.bounds.origin.y))
                }
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            save("scrolled")
        }
        try? log.joined(separator: "\n").write(toFile: "\(prefix).txt", atomically: true, encoding: .utf8)
        NSApp.terminate(nil)
    }

    private static func kind(of row: TranscriptRow) -> String {
        switch row {
        case .group: return "group"
        case .item(let item): return "\(item.kind)"
        }
    }

    private static func describe(_ row: TranscriptRow) -> String {
        switch row {
        case .group(let items, _, _):
            return "group of \(items.count)"
        case .item(let item):
            let blocks = item.kind == .assistant ? MarkdownParser.parse(item.text).count : 0
            let preview = item.text.prefix(50).replacingOccurrences(of: "\n", with: " ")
            return "\(item.kind) \(item.text.count) chars, \(blocks) blocks: \(preview)"
        }
    }
}
#endif
