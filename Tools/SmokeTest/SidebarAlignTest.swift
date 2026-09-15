//
//  SidebarAlignTest.swift
//  PiCode smoke test — not part of the app target.
//
//  The sidebar promises that a chat's title starts where its project's *name*
//  starts. That is a claim about pixels, and the pixel answer depends on how
//  macOS insets list rows versus section headers — which is not documented and
//  can move between releases. So this harness renders the real row and header
//  layout in a window, captures its own window (no screen-recording permission
//  needed), and measures the two text origins.
//
//  It compiles against `SidebarStyle` *extracted from the real
//  `SidebarView.swift`* by run-sidebar-align.sh, so the numbers under test are
//  the shipped ones. The layout below mirrors `ProjectRow` and `SessionRow`;
//  if you change their structure, change it here too — `run-sidebar-align.sh`
//  also greps the real source for the wiring this depends on.
//

import SwiftUI
import AppKit

/// The shape of one group, mirroring `ProjectGroup` + its sessions.
private struct DemoProject: Identifiable {
    let id: Int
    let name: String
    let chats: [String]
}

struct SidebarAlignDemo: View {
    private let projects = [DemoProject(id: 0, name: "proj", chats: ["proj-aaa", "proj-bbb"])]

    var body: some View {
        // The real structure: one `ForEach` over projects, each emitting its
        // project row and then a `@ViewBuilder` of chat rows. If SwiftUI ever
        // stopped flattening that builder into rows, the chats would collapse
        // into a single row and the vertical rhythm measured here would change.
        List {
            ForEach(projects) { project in
                projectRow(project)
                chats(of: project)
            }
        }
        .listStyle(.sidebar)
    }

    private func projectRow(_ project: DemoProject) -> some View {
        // Geometry only: the real row wraps this in a Button that folds the chats,
        // which does not change any of the numbers below.
        HStack(spacing: SidebarStyle.iconTextSpacing) {
            Image(systemName: "folder")
                .font(.system(size: SidebarStyle.projectIconSize, weight: .regular))
                .frame(width: SidebarStyle.projectIconSize,
                       height: SidebarStyle.projectIconSize,
                       alignment: .leading)
                .offset(x: -SidebarStyle.projectIconOffset)
            Text(project.name).font(SidebarStyle.rowFont)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func chats(of project: DemoProject) -> some View {
        ForEach(project.chats, id: \.self) { chat in
            // Same structure as `SessionRow`: the leading slot is the folder
            // glyph's own 11pt mark (empty for a quiet chat), so the title starts
            // where the project name does and a running chat's spinner would sit
            // under the folder.
            HStack(spacing: SidebarStyle.iconTextSpacing) {
                Color.clear
                    .frame(width: SidebarStyle.projectIconSize,
                           height: SidebarStyle.projectIconSize,
                           alignment: .leading)
                    .offset(x: -SidebarStyle.projectIconOffset)
                Text(chat).font(SidebarStyle.rowFont)
                Spacer(minLength: 0)
            }
        }
    }
}

/// A faithful-enough mock of the whole sidebar column so the harness can dump a
/// PNG for a human to look at. It is not measured — `SidebarAlignDemo` is — but it
/// is what answers "is that fill actually darker than the sidebar?".
///
/// It mirrors the real column: New chat is the *first list row*, drawn with the
/// same glyph, spacing and highlight as a project, and the column has no rule and
/// no bar above it. The search icon is still the overlay in the titlebar row.
struct SidebarLookDemo: View {
    private let projects = [DemoProject(id: 0, name: "proj", chats: ["proj-aaa", "proj-bbb"])]

    var body: some View {
        List {
            HStack(spacing: SidebarStyle.iconTextSpacing) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: SidebarStyle.projectIconSize, weight: .regular))
                    .frame(width: SidebarStyle.projectIconSize,
                           height: SidebarStyle.projectIconSize,
                           alignment: .leading)
                    .offset(x: -SidebarStyle.projectIconOffset)
                Text("New chat").font(SidebarStyle.rowFont)
                Spacer(minLength: 0)
            }
            .sidebarRow(fill: SidebarStyle.rowHighlightFill)
            ForEach(projects) { project in
                HStack(spacing: SidebarStyle.iconTextSpacing) {
                    Image(systemName: "folder")
                        .font(.system(size: SidebarStyle.projectIconSize, weight: .regular))
                        .frame(width: SidebarStyle.projectIconSize,
                               height: SidebarStyle.projectIconSize,
                               alignment: .leading)
                        .offset(x: -SidebarStyle.projectIconOffset)
                    Text(project.name).font(SidebarStyle.rowFont)
                    Spacer(minLength: 0)
                }
                .sidebarRow(fill: .clear)
                ForEach(project.chats, id: \.self) { chat in
                    HStack(spacing: SidebarStyle.iconTextSpacing) {
                        Color.clear
                            .frame(width: SidebarStyle.projectIconSize,
                                   height: SidebarStyle.projectIconSize,
                                   alignment: .leading)
                            .offset(x: -SidebarStyle.projectIconOffset)
                        Text(chat).font(SidebarStyle.rowFont)
                        Spacer(minLength: 0)
                    }
                    .sidebarRow(fill: .clear)
                }
            }
        }
        .listStyle(.sidebar)
        .frame(width: 268, height: 340)
        .background(Color(nsColor: .windowBackgroundColor))
        // The real sidebar draws this over its own content, ignoring the top safe
        // area; here there is no toolbar, so it is the same relative mark.
        .overlay(alignment: .topTrailing) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .frame(width: SidebarStyle.topBarButtonSize, height: SidebarStyle.topBarButtonSize)
                .padding(.top, SidebarStyle.topBarTopInset)
                .padding(.trailing, SidebarStyle.topBarTrailingInset)
        }
    }
}

/// The search icon, exactly as `SidebarView.searchButton` draws it: an overlay on
/// the sidebar's trailing edge that ignores the top safe area. The icon is backed
/// by a flat marker fill so the pixel reader can find the *button's* frame in the
/// capture instead of trying to read a grey glyph over a material.
struct SidebarSearchDemo: View {
    var body: some View {
        Color(nsColor: .windowBackgroundColor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topTrailing) {
                ZStack {
                    Color.yellow
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                }
                .frame(width: SidebarStyle.topBarButtonSize, height: SidebarStyle.topBarButtonSize)
                .padding(.top, SidebarStyle.topBarTopInset)
                .padding(.trailing, SidebarStyle.topBarTrailingInset)
                .ignoresSafeArea(.container, edges: .top)
            }
    }
}

final class SidebarAlignDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var failures = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 240),
                          styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: SidebarAlignDemo())
        window.orderFrontRegardless()
        // The list lays out asynchronously; rendering it too early measures nothing.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { self.measure() }
    }

    func check(_ passed: Bool, _ what: String, _ detail: String = "") {
        print("  \(passed ? "ok  " : "FAIL") \(what)\(detail.isEmpty ? "" : " — \(detail)")")
        if !passed { failures += 1 }
    }

    private func measure() {
        // The view, not the window: a window capture asks the window server what
        // it last composited, and this window is behind the real app whenever the
        // app is running — then every measurement below reads solid black and
        // reports "nothing there" instead of "the capture failed".
        guard let content = window.contentView, let pixels = WindowPixels.capture(content) else {
            check(false, "the harness could render a window")
            return finish()
        }
        let scale = pixels.scale
        let width = pixels.width, height = pixels.height
        // Ink, from the shared reader: neutral and far from the backdrop, so a
        // coloured pill or a material change never counts as text.
        func isText(_ x: Int, _ y: Int) -> Bool { pixels.isText(x, y) }

        // A dot over a "j" or an accent sits a couple of pixels above the rest of
        // its glyph and would otherwise read as a line of its own.
        let lines = pixels.textLines()

        /// The ink runs on a line: each run is a glyph cluster.
        func runs(on line: [Int]) -> [ClosedRange<Int>] {
            var xs = Set<Int>()
            for y in line { for x in 0..<width where isText(x, y) { xs.insert(x) } }
            let sorted = xs.sorted()
            guard let first = sorted.first else { return [] }
            var result: [ClosedRange<Int>] = []
            var start = first, previous = first
            for x in sorted.dropFirst() {
                if x - previous > 3 { result.append(start...previous); start = x }
                previous = x
            }
            result.append(start...previous)
            return result
        }

        guard lines.count >= 3 else {
            check(false, "a project header and two session rows were rendered",
                  "found \(lines.count) text lines")
            return finish()
        }

        /// Vertical ink bands inside one x window. Grouping with a 4px gap merges a
        /// glyph with its own dot but still separates lines, and measuring every
        /// line inside the project *name's* window keeps them comparable — they all
        /// start at the same x. Measuring whole lines instead would let the folder
        /// glyph (taller than the text) into the project's span and skew its centre.
        func bands(in range: ClosedRange<Int>) -> [ClosedRange<Int>] {
            var result: [ClosedRange<Int>] = []
            var start: Int?
            var previous = 0
            for y in 0..<height where range.contains(where: { isText($0, y) }) {
                if start == nil || y - previous > 4 {
                    if let beginning = start { result.append(beginning...previous) }
                    start = y
                }
                previous = y
            }
            if let beginning = start { result.append(beginning...previous) }
            return result
        }

        let headerRuns = runs(on: lines[0])
        let rowRuns = runs(on: lines[1])
        // Printed always: when the alignment drifts, this is what tells you which
        // line the harness thinks is which.
        for (index, line) in lines.prefix(4).enumerated() {
            let origins = runs(on: line).map { String(format: "%.1f-%.1f", Double($0.lowerBound) / Double(scale), Double($0.upperBound) / Double(scale)) }
            print("  note  line \(index) y=\(line.first ?? 0)-\(line.last ?? 0) runs=[\(origins.joined(separator: " "))]")
        }
        check(headerRuns.count >= 2 && !rowRuns.isEmpty, "both rows have measurable text")
        guard headerRuns.count >= 2, let rowStart = rowRuns.first?.lowerBound else { return finish() }

        let iconPoints = CGFloat(headerRuns[0].count) / scale
        let projectName = headerRuns[1].lowerBound        // ink of the project's name
        let sessionTitle = rowStart                       // ink of the session's title
        let delta = CGFloat(sessionTitle - projectName) / scale

        print(String(format: "  note  project name ink at %.1fpt, session title ink at %.1fpt",
                     Double(projectName) / Double(scale), Double(sessionTitle) / Double(scale)))
        check(abs(delta) <= 0.5,
              "a session title starts where its project's name starts",
              String(format: "delta %.1fpt", Double(delta)))
        check(iconPoints > 10, "the project glyph is drawn at full size",
              String(format: "%.1fpt wide", Double(iconPoints)))
        let glyphInk = CGFloat(headerRuns[0].lowerBound) / scale
        // The glyph is drawn `projectIconRightShift` in from the search field's edge
        // (it used to sit exactly on it, which read as drifting from its name).
        let glyphMark = SidebarStyle.sidebarMargin + SidebarStyle.projectIconRightShift
        check(abs(glyphInk - glyphMark) <= 1.5,
              "the project glyph sits in from the search field's edge",
              String(format: "glyph ink %.1fpt against %.1fpt", Double(glyphInk), Double(glyphMark)))

        // The rhythm: a chat must sit as far below its project's *name* as it sits
        // below another chat.
        if lines.count >= 3 {
            let labelWindow = headerRuns[1].lowerBound...headerRuns[headerRuns.count - 1].upperBound
            let textBands = bands(in: labelWindow).filter { $0.upperBound - $0.lowerBound >= 8 }
            if textBands.count >= 3 {
                func centre(_ span: ClosedRange<Int>) -> Double { Double(span.lowerBound + span.upperBound) / 2 }
                let projectToChat = (centre(textBands[1]) - centre(textBands[0])) / Double(scale)
                let chatToChat = (centre(textBands[2]) - centre(textBands[1])) / Double(scale)
                // Now exact, and it has to be: there is no vertical margin left in
                // the sidebar at all, so both rows are one cell of the list and one
                // pitch. It used to be 26.5 against 28.0 — a project row carried
                // `projectTopMargin` as padding, and in a sidebar List row padding
                // shows up as slightly less separation than asked for while stealing
                // 1.5pt from the gap *below* the padded row (measured, and measured
                // again with a spacer row and with `.listRowInsets`: both worse).
                // The 1.5pt band stays only because ink centres are integers.
                check(abs(projectToChat - chatToChat) <= 1.5,
                      "a chat sits the same distance below a project's name as below another chat",
                      String(format: "%.1fpt then %.1fpt", projectToChat, chatToChat))
            } else {
                check(false, "the project name and both chats have measurable ink",
                      "found \(textBands.count) text band(s)")
            }
        }
        captureLook()
    }

    /// Write a picture of the column so a human can judge colour and rhythm, which
    /// no assertion here can. Dumped next to nothing important: /tmp.
    private func captureLook() {
        let look = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 268, height: 340),
                            styleMask: [.titled], backing: .buffered, defer: false)
        look.contentView = NSHostingView(rootView: SidebarLookDemo())
        look.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if let content = look.contentView, let pixels = WindowPixels.capture(content), let data = pixels.pngData() {
                try? data.write(to: URL(fileURLWithPath: "/tmp/picode-sidebar-look.png"))
                print("  note  wrote /tmp/picode-sidebar-look.png — look at it")
            } else {
                print("  note  could not write the look dump")
            }
            self.measureSearchRow()
        }
    }

    /// The search icon is the one control in the sidebar that leaves the content's
    /// safe area, so "it sits on the titlebar row" is invisible to the capture
    /// above (which deliberately has no toolbar). It gets its own window here, with
    /// a real toolbar in the *same compact style the app's hidden-titlebar window
    /// resolves to*, so the safe area it ignores is the toolbar's own and the
    /// traffic lights sit where the app's do; its centre is compared to those
    /// lights read from that live window — not to a constant copied into the test.
    /// The trailing margin is checked against the column edge for the same reason.
    private func measureSearchRow() {
        let search = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 268, height: 160),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        search.toolbarStyle = .unifiedCompact
        search.toolbar = NSToolbar(identifier: "sidebar-search-harness")
        search.contentView = NSHostingView(rootView: SidebarSearchDemo())
        search.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            guard let content = search.contentView, let pixels = WindowPixels.capture(content) else {
                self.check(false, "the harness could render the search row")
                return self.finish()
            }
            let scale = pixels.scale
            var minX = Int.max, maxX = Int.min, minY = Int.max, maxY = Int.min
            for y in 0..<pixels.height {
                for x in 0..<pixels.width {
                    let (r, g, b) = pixels.rgb(x, y)
                    if r > 200, g > 200, b < 100 {   // the marker fill, not a material
                        minX = min(minX, x); maxX = max(maxX, x)
                        minY = min(minY, y); maxY = max(maxY, y)
                    }
                }
            }
            guard minX != Int.max else {
                self.check(false, "the search icon is drawn (its marker fill was found)")
                return self.finish()
            }
            let centerY = (Double(minY) + Double(maxY)) / 2 / Double(scale)
            let trailing = Double(maxX) / Double(scale)
            var trafficCenter = SidebarStyle.titlebarRowCenter
            if let close = search.standardWindowButton(.closeButton) {
                let frame = close.convert(close.bounds, to: nil)
                trafficCenter = content.bounds.height - frame.midY
            }
            self.check(abs(centerY - trafficCenter) <= 1.5,
                       "the search icon is centred on the traffic lights' row",
                       String(format: "icon %.1fpt against %.1fpt", centerY, trafficCenter))
            self.check(abs(content.bounds.width - trailing - SidebarStyle.topBarTrailingInset) <= 1.5,
                       "the search icon keeps the sidebar's trailing margin",
                       String(format: "%.1fpt from the edge", content.bounds.width - trailing))
            self.finish()
        }
    }

    private func finish() {
        print(failures == 0
              ? "\nRESULT: all checks passed"
              : "\nRESULT: \(failures) check(s) failed")
        NSApp.terminate(nil)
        exit(failures == 0 ? 0 : 1)
    }
}

@main
struct SidebarAlignHarness {
    static func main() {
        let application = NSApplication.shared
        let delegate = SidebarAlignDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}
