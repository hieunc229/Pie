//
//  SidebarClickTest.swift
//  PiCode smoke test — not part of the app target.
//
//  Three claims about the sidebar that only pixels and a real mouse event can
//  settle:
//
//    1. clicking a project row folds its chats away, and clicking again brings
//       them back — in a `NavigationSplitView` sidebar, with the row wrapped in a
//       `Button`, which is where a click can quietly get eaten;
//    2. the row highlight (the hover/selection pill) starts and ends on the same
//       horizontal margin as the search field, instead of running to the edges;
//    3. the space above a project is a *margin*: the project's pill is the same
//       height as a chat's, the 12pt of air above it is unpainted, and there is
//       none of it below.
//
//  Every row in the mock paints its own distinctly-coloured background, so a row
//  can be found, measured and counted by *colour* alone — no measurement here
//  depends on reading text. That matters: text drawn over a saturated fill picks
//  up that fill's tint, and over pure blue its edge pixels land 26 off neutral,
//  past the threshold `WindowPixels.isText` uses to keep coloured fills out of a
//  count of text lines. Counting rows by ink made this harness fail for a reason
//  that had nothing to do with the sidebar.
//
//  The mock calls the app's own `sidebarRow(fill:topMargin:bottomMargin:)` rather
//  than a copy of it: run-sidebar-click.sh extracts everything between
//  `enum SidebarStyle` and `struct SidebarView`, which includes it. So what is
//  measured below is the shipped rule, not a re-implementation of it.
//

import SwiftUI
import AppKit

struct SidebarClickDemo: View {
    /// Reported to the harness so it knows how wide the column really is.
    var onWidth: (CGFloat) -> Void = { _ in }

    @State private var isFolded = false

    /// Detector colours, not design ones. Each is a pair of bright channels with
    /// one dark, so the four predicates below can never overlap:
    ///
    ///     red      projA         magenta  projA-aaa
    ///     cyan     projA-bbb     green    projB        yellow  projB-ccc
    static let projectA = Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1)
    static let chatA1 = Color(.sRGB, red: 1, green: 0, blue: 1, opacity: 1)
    static let chatA2 = Color(.sRGB, red: 0, green: 1, blue: 1, opacity: 1)
    static let projectB = Color(.sRGB, red: 0, green: 1, blue: 0, opacity: 1)
    static let chatB1 = Color(.sRGB, red: 1, green: 1, blue: 0, opacity: 1)

    var body: some View {
        List {
            Button {
                isFolded.toggle()
            } label: {
                HStack(spacing: SidebarStyle.iconTextSpacing) {
                    Image(systemName: "folder")
                        .font(.system(size: SidebarStyle.projectIconSize, weight: .regular))
                        .frame(width: SidebarStyle.projectIconSize,
                               height: SidebarStyle.projectIconSize,
                               alignment: .leading)
                        .offset(x: -SidebarStyle.projectIconShift)
                    Text("projA").font(SidebarStyle.rowFont)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.primary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .sidebarRow(fill: Self.projectA,
                        topMargin: SidebarStyle.projectTopMargin,
                        bottomMargin: SidebarStyle.projectBottomMargin)

            if !isFolded {
                // `.primary` on the text is not decoration: the real `SessionRow`
                // sets it, and without it an *inactive* window draws these rows in
                // the dimmed sidebar colour. Nothing here measures the text, but the
                // mock should still look like the thing it stands in for.
                chat("projA-aaa", Self.chatA1)
                chat("projA-bbb", Self.chatA2)
            }

            // A second group, so the space above a project can be measured against
            // the chat that precedes it rather than against the list's own top.
            Text("projB").font(SidebarStyle.rowFont)
                .foregroundStyle(.primary)
                .sidebarRow(fill: Self.projectB,
                            topMargin: SidebarStyle.projectTopMargin,
                            bottomMargin: SidebarStyle.projectBottomMargin)
            chat("projB-ccc", Self.chatB1)
        }
        .listStyle(.sidebar)
        // The sidebar material is invisible to `cacheDisplay` — it draws as
        // transparent, which the capture resolves to black. The mock therefore
        // paints its own flat backdrop; the real sidebar's material is not what
        // this harness is about.
        .scrollContentBackground(.hidden)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { onWidth(proxy.size.width) }
                    .onChange(of: proxy.size.width) { _, width in onWidth(width) }
            }
        )
    }

    private func chat(_ title: String, _ colour: Color) -> some View {
        Text(title).font(SidebarStyle.rowFont)
            .foregroundStyle(.primary)
            .padding(.leading, SidebarStyle.titleIndent)
            .sidebarRow(fill: colour)
    }
}

final class SidebarClickDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var failures = 0
    private var columnWidth: CGFloat = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 400),
                          styleMask: [.titled], backing: .buffered, defer: false)
        // The app's sidebar lives in a NavigationSplitView; if anything is going to
        // swallow a click on a row, it is that.
        window.contentView = NSHostingView(rootView: NavigationSplitView {
            SidebarClickDemo { width in self.columnWidth = width }
                .navigationSplitViewColumnWidth(min: 232, ideal: 268, max: 360)
        } detail: {
            Text("detail").frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // One opaque canvas for both columns: the capture is one image and a
        // half-transparent window leaves half of it black.
        .background(Color(nsColor: .textBackgroundColor)))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { self.measureGeometry() }
    }

    func check(_ passed: Bool, _ what: String, _ detail: String = "") {
        print("  \(passed ? "ok  " : "FAIL") \(what)\(detail.isEmpty ? "" : " — \(detail)")")
        if !passed { failures += 1 }
    }

    // MARK: - Capture

    /// The view, not the window: a window capture asks the window server what it
    /// last composited, and this window sits behind the real app whenever the app
    /// is running — then the pill is never found and the harness blames the view.
    private func capture() -> WindowPixels? {
        guard let content = window.contentView else { return nil }
        return WindowPixels.capture(content)
    }

    // MARK: - Pills, by colour

    private struct Pill {
        var name: String
        var x: ClosedRange<Int>
        var y: ClosedRange<Int>

        func height(in pixels: WindowPixels) -> CGFloat {
            CGFloat(Double(y.count)) / pixels.scale
        }
        func points(_ value: Int, _ pixels: WindowPixels) -> CGFloat {
            CGFloat(Double(value)) / pixels.scale
        }
    }

    private typealias Colour = (Int, Int, Int) -> Bool

    private static let rows: [(String, Colour)] = [
        ("projA", { r, g, b in r > 120 && g < 90 && b < 90 }),
        ("projA-aaa", { r, g, b in r > 120 && g < 90 && b > 120 }),
        ("projA-bbb", { r, g, b in r < 90 && g > 120 && b > 120 }),
        ("projB", { r, g, b in r < 90 && g > 120 && b < 90 }),
        ("projB-ccc", { r, g, b in r > 120 && g > 120 && b < 90 }),
    ]

    /// One row's painted rectangle, found by colour: the extents of every pixel the
    /// row's own fill matched. Rounded corners and antialiased edges cost at most a
    /// pixel at each edge, which is why every comparison allows 1.5pt.
    private func rect(_ pixels: WindowPixels, _ match: Colour) -> (x: ClosedRange<Int>, y: ClosedRange<Int>)? {
        var xs: [Int] = [], ys: [Int] = []
        for y in 0..<pixels.height {
            for x in 0..<pixels.width {
                let (r, g, b) = pixels.rgb(x, y)
                if match(r, g, b) { xs.append(x); ys.append(y) }
            }
        }
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return nil }
        return (minX...maxX, minY...maxY)
    }

    /// Every row that is on screen, in the order the list draws them.
    private func pills(_ pixels: WindowPixels) -> [Pill] {
        Self.rows.compactMap { name, match -> Pill? in
            guard let found = rect(pixels, match) else { return nil }
            return Pill(name: name, x: found.x, y: found.y)
        }
    }

    // MARK: - Steps

    private func measureGeometry() {
        guard let pixels = capture() else {
            check(false, "the harness could render a window")
            return finish()
        }
        let found = pills(pixels)
        let byName = Dictionary(uniqueKeysWithValues: found.map { ($0.name, $0) })
        guard let projectA = byName["projA"], let chatA1 = byName["projA-aaa"],
              let chatA2 = byName["projA-bbb"], let projectB = byName["projB"] else {
            check(false, "every mock row painted its own highlight",
                  "found " + (found.isEmpty ? "none" : found.map(\.name).joined(separator: ", ")))
            return finish()
        }
        print(String(format: "  note  column %.1fpt wide; projA y %.1f-%.1f, projA-aaa y %.1f-%.1f, projA-bbb y %.1f-%.1f, projB y %.1f-%.1f",
                     Double(columnWidth),
                     projectA.points(projectA.y.lowerBound, pixels), projectA.points(projectA.y.upperBound, pixels),
                     chatA1.points(chatA1.y.lowerBound, pixels), chatA1.points(chatA1.y.upperBound, pixels),
                     chatA2.points(chatA2.y.lowerBound, pixels), chatA2.points(chatA2.y.upperBound, pixels),
                     projectB.points(projectB.y.lowerBound, pixels), projectB.points(projectB.y.upperBound, pixels)))

        // Rows, counted by colour, not by ink: every row here paints one.
        check(found.count == 5, "five rows are on screen before the click",
              "found \(found.count): " + found.map(\.name).joined(separator: ", "))

        highlightInsets(pixels, projectA, "the first")
        highlightInsets(pixels, projectB, "the second")

        measureMargin(pixels, projectA, chatA1, chatA2, projectB)

        click(at: clickPoint(in: projectA, pixels))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.checkFolded() }
    }

    private func highlightInsets(_ pixels: WindowPixels, _ pill: Pill, _ which: String) {
        let left = pill.points(pill.x.lowerBound, pixels)
        let right = columnWidth - pill.points(pill.x.upperBound, pixels)
        check(abs(left - SidebarStyle.sidebarMargin) <= 1.5 && abs(right - SidebarStyle.sidebarMargin) <= 1.5,
              "\(which) row's highlight sits on the search field's margin",
              String(format: "%.1fpt from the leading edge, %.1fpt from the trailing one (margin %.1fpt)",
                     Double(left), Double(right), Double(SidebarStyle.sidebarMargin)))
    }

    /// The space above a project is a *margin*.
    ///
    /// Three measurements settle it, and none of them needs the text:
    ///
    ///   * the project's pill is exactly as tall as a chat's — it used to be 37pt
    ///     against 28pt, because `listRowBackground` fills the row's whole cell and
    ///     the project row was padding itself *inside* it;
    ///   * the air above it, measured from the pill of the chat that precedes the
    ///     next project, is the top margin and nothing else;
    ///   * there is none below it: the project's pill ends where its first chat's
    ///     begins. A margin on the wrong side would show up here as a gap.
    private func measureMargin(_ pixels: WindowPixels,
                               _ projectA: Pill, _ chatA1: Pill, _ chatA2: Pill, _ projectB: Pill) {
        let projectHeight = projectA.height(in: pixels)
        let chatHeight = chatA1.height(in: pixels)
        check(abs(projectHeight - chatHeight) <= 1.5,
              "a project's highlight is the height of a chat's",
              String(format: "%.1fpt against %.1fpt (it was 37.0 against 28.0 while the margin was inside the pill)",
                     Double(projectHeight), Double(chatHeight)))

        let gapAbove = Double(projectB.y.lowerBound - chatA2.y.upperBound - 1) / Double(pixels.scale)
        check(abs(gapAbove - SidebarStyle.projectTopMargin) <= 1.5,
              "the gap above a project is the top margin, outside the pill",
              String(format: "%.1fpt against %.1fpt", gapAbove, Double(SidebarStyle.projectTopMargin)))

        let gapBelow = Double(chatA1.y.lowerBound - projectA.y.upperBound - 1) / Double(pixels.scale)
        check(abs(gapBelow) <= 1.5,
              "a project's highlight ends where its first chat's begins",
              String(format: "%.1fpt below it", gapBelow))
    }

    private func checkFolded() {
        guard let pixels = capture() else { return finish() }
        let found = pills(pixels)
        check(found.count == 3, "clicking the project folds its chats away",
              "\(found.count) row(s) left: " + found.map(\.name).joined(separator: ", "))
        if let projectA = found.first(where: { $0.name == "projA" }) {
            click(at: clickPoint(in: projectA, pixels))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.checkUnfolded() }
    }

    private func checkUnfolded() {
        guard let pixels = capture() else { return finish() }
        let found = pills(pixels)
        check(found.count == 5, "clicking it again brings the chats back",
              "\(found.count) row(s) on screen: " + found.map(\.name).joined(separator: ", "))
        if let data = pixels.pngData() {
            try? data.write(to: URL(fileURLWithPath: "/tmp/picode-sidebar-click.png"))
            print("  note  wrote /tmp/picode-sidebar-click.png — look at it")
        }
        finish()
    }

    /// The capture's y counts down from the top of the *content view*, window
    /// coordinates count up from the bottom of it, and the title bar is in
    /// neither, so the two meet at the content height.
    private func clickPoint(in pill: Pill, _ pixels: WindowPixels) -> NSPoint {
        let centre = CGFloat(Double(pill.y.lowerBound + pill.y.upperBound) / 2)
        return NSPoint(x: CGFloat(Double(pill.x.lowerBound) / Double(pixels.scale)) + 40,
                       y: CGFloat(Double(pixels.height) / Double(pixels.scale)) - centre / pixels.scale)
    }

    /// Through the window's own event path, so hit testing, the List row and the
    /// Button all have their say — an action called directly would prove nothing.
    /// The events are *posted*, not delivered: SwiftUI runs an event-tracking loop
    /// on mouse-down that waits for the matching mouse-up, so `sendEvent`ing the
    /// two directly deadlocks the harness on the first one.
    private func click(at point: NSPoint) {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let event = NSEvent.mouseEvent(with: type,
                                                 location: point,
                                                 modifierFlags: [],
                                                 timestamp: ProcessInfo.processInfo.systemUptime,
                                                 windowNumber: window.windowNumber,
                                                 context: nil,
                                                 eventNumber: 0,
                                                 clickCount: 1,
                                                 pressure: 1) else { continue }
            NSApp.postEvent(event, atStart: false)
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
struct SidebarClickHarness {
    static func main() {
        // Unbuffered: if a click ever wedges the run loop, the last line printed is
        // the only clue left, and a killed process never flushes a pipe.
        setvbuf(stdout, nil, _IONBF, 0)
        // Nothing here should take 25s; if it does, say so and die rather than
        // leaving a hung window on someone's screen. A background thread, because
        // the main one may be sitting in an event-tracking loop.
        DispatchQueue.global().asyncAfter(deadline: .now() + 25) {
            print("  FAIL the harness did not finish within 25s (a click blocked the run loop?)")
            print("\nRESULT: 1 check(s) failed")
            exit(1)
        }
        let application = NSApplication.shared
        let delegate = SidebarClickDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}
