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
        // Wait for the session to be open with its history read.
        var controller: PiSessionController?
        for _ in 0..<120 {
            let wanted = ProcessInfo.processInfo.environment["PICODE_OPEN_SESSION"]
            if let active = state.activeController, !active.items.isEmpty, !active.isLoadingTranscriptHistory,
               wanted == nil || active.sessionFile?.hasSuffix(wanted!) == true {
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
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        var samples: [Double] = []
        var last = CACurrentMediaTime()
        let words = ["The ", "transcript ", "keeps ", "growing ", "while ", "**Pi** ", "writes ", "`code` ", "and ", "prose.\n\n"]
        for step in 0..<240 {
            controller.debugGrowLastAssistant(by: words[step % words.count])
            try? await Task.sleep(nanoseconds: 16_000_000)
            let now = CACurrentMediaTime()
            samples.append((now - last) * 1000 - 16)
            last = now
        }
        let sorted = samples.dropFirst().sorted()
        let mean = sorted.reduce(0, +) / Double(sorted.count)
        func percentile(_ p: Double) -> Double { sorted[min(sorted.count - 1, Int(Double(sorted.count) * p))] }
        let report = String(format: "rows %d  stream ticks %d  extra per tick: mean %.2fms  p50 %.2fms  p90 %.2fms  p99 %.2fms  max %.2fms\n",
                            controller.rows.count, sorted.count, mean, percentile(0.5), percentile(0.9), percentile(0.99), sorted.last ?? 0)
        try? report.write(toFile: output, atomically: true, encoding: .utf8)
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
        case .group(let items, _):
            return "group of \(items.count)"
        case .item(let item):
            let blocks = item.kind == .assistant ? MarkdownParser.parse(item.text).count : 0
            let preview = item.text.prefix(50).replacingOccurrences(of: "\n", with: " ")
            return "\(item.kind) \(item.text.count) chars, \(blocks) blocks: \(preview)"
        }
    }
}
#endif
