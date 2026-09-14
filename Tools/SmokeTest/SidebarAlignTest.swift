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
        HStack(spacing: SidebarStyle.iconTextSpacing) {
            Image(systemName: "folder")
                .font(.system(size: SidebarStyle.projectIconSize, weight: .regular))
                .frame(width: SidebarStyle.projectIconSize, alignment: .leading)
            Text(project.name).font(SidebarStyle.rowFont)
            Spacer(minLength: 0)
        }
        .padding(.top, SidebarStyle.projectTopMargin)
        .padding(.bottom, SidebarStyle.projectBottomMargin)
    }

    @ViewBuilder
    private func chats(of project: DemoProject) -> some View {
        ForEach(project.chats, id: \.self) { chat in
            Text(chat).font(SidebarStyle.rowFont)
                .padding(.leading, SidebarStyle.titleIndent)
        }
    }
}

/// A faithful-enough mock of the whole sidebar column so the harness can dump a
/// PNG for a human to look at. It is not measured — `SidebarAlignDemo` is — but
/// it is what answers "is that fill actually darker than the sidebar?".
struct SidebarLookDemo: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .imageScale(.small)
                Text("Search sessions").foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(SidebarStyle.searchFieldFill,
                        in: RoundedRectangle(cornerRadius: SidebarStyle.searchFieldRadius, style: .continuous))
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 10)
            Divider()
            SidebarAlignDemo()
            Spacer(minLength: 0)
        }
        .frame(width: 268, height: 340)
        .background(Color(nsColor: .windowBackgroundColor))
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
        let id = CGWindowID(window.windowNumber)
        guard let image = CGWindowListCreateImage(.null, .optionIncludingWindow, id,
                                                  [.boundsIgnoreFraming, .bestResolution]) else {
            check(false, "the harness could render a window")
            return finish()
        }
        let rep = NSBitmapImageRep(cgImage: image)
        let scale = CGFloat(rep.pixelsWide) / window.frame.width
        guard let data = rep.bitmapData else {
            check(false, "the capture has pixels")
            return finish()
        }

        let width = rep.pixelsWide, height = rep.pixelsHigh
        let rowBytes = rep.bytesPerRow, samples = rep.samplesPerPixel
        func brightness(_ x: Int, _ y: Int) -> Int {
            let offset = y * rowBytes + x * samples
            return (Int(data[offset]) + Int(data[offset + 1]) + Int(data[offset + 2])) / 3
        }

        // Appearances differ, so find the background and treat "text" as
        // whatever is furthest from it.
        var histogram = [Int](repeating: 0, count: 256)
        for y in stride(from: 0, to: height, by: 2) {
            for x in stride(from: 0, to: width, by: 2) { histogram[brightness(x, y)] += 1 }
        }
        let background = histogram.enumerated().max { $0.element < $1.element }!.offset
        let dark = background > 128
        func isText(_ x: Int, _ y: Int) -> Bool {
            let value = brightness(x, y)
            return dark ? value < background - 40 : value > background + 40
        }

        var lines: [[Int]] = []
        for y in 0..<height where (0..<width).contains(where: { isText($0, y) }) {
            if let last = lines.last, let previous = last.last, y - previous <= 2 { lines[lines.count - 1].append(y) }
            else { lines.append([y]) }
        }
        // A dot over a "j" or an accent sits a couple of pixels above the rest of
        // its glyph and would otherwise read as a line of its own.
        lines = lines.filter { line in
            guard let first = line.first, let last = line.last else { return false }
            return last - first >= 6
        }

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
        // The chats must be rows of their own, not one row holding a stack: rows
        // keep the list's own vertical rhythm, and only rows can highlight or be
        // clicked one at a time.
        if lines.count >= 3 {
            let projectToChat = CGFloat(lines[1].first! - lines[0].first!) / scale
            let chatToChat = CGFloat(lines[2].first! - lines[1].first!) / scale
            check(projectToChat > chatToChat + 4,
                  "a project has its own margin before its chats",
                  String(format: "%.1fpt then %.1fpt between chats", Double(projectToChat), Double(chatToChat)))
            check(chatToChat > 18 && chatToChat < 34,
                  "the chats are separate rows, not one stacked row",
                  String(format: "%.1fpt apart", Double(chatToChat)))
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
            let id = CGWindowID(look.windowNumber)
            if let image = CGWindowListCreateImage(.null, .optionIncludingWindow, id,
                                                  [.boundsIgnoreFraming, .bestResolution]),
               let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
                try? data.write(to: URL(fileURLWithPath: "/tmp/picode-sidebar-look.png"))
                print("  note  wrote /tmp/picode-sidebar-look.png — look at it")
            } else {
                print("  note  could not write the look dump")
            }
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
