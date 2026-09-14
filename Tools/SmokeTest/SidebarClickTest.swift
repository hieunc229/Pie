//
//  SidebarClickTest.swift
//  PiCode smoke test — not part of the app target.
//
//  Two claims about the sidebar that only pixels and a real mouse event can
//  settle:
//
//    1. clicking a project row folds its chats away, and clicking again brings
//       them back — in a `NavigationSplitView` sidebar, with the row wrapped in a
//       `Button`, which is where a click can quietly get eaten;
//    2. the row highlight (the hover/selection pill) starts and ends on the same
//       horizontal margin as the search field, instead of running to the edges.
//
//  It renders a mock of the real row structure (metrics extracted from
//  `SidebarView.swift` by run-sidebar-click.sh), paints the project row's
//  background red so its rectangle can be measured without confusing it with
//  text, clicks that row through the window's own event path, and counts the
//  text lines that survive.
//

import SwiftUI
import AppKit

struct SidebarClickDemo: View {
    /// Reported to the harness so it knows how wide the column really is.
    var onWidth: (CGFloat) -> Void = { _ in }

    @State private var isFolded = false

    /// Not a real colour: a detector-friendly one. Text is neutral, so "red" is
    /// unambiguous when counting ink.
    private static let highlight = Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1)

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
                    Text("proj").font(SidebarStyle.rowFont)
                    Spacer(minLength: 0)
                }
                        .foregroundStyle(.primary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, SidebarStyle.projectTopMargin)
            .padding(.bottom, SidebarStyle.projectBottomMargin)
            .listRowBackground(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Self.highlight)
                    .padding(.horizontal, SidebarStyle.rowHighlightInset)
            )

            if !isFolded {
                ForEach(["proj-aaa", "proj-bbb"], id: \.self) { chat in
                    // `.primary` is not decoration: the real `SessionRow` sets it,
                    // and without it an *inactive* window draws these rows in the
                    // dimmed sidebar colour, which this harness reads as no text
                    // and reports as "the chats did not come back". It did fail
                    // that way, once, whenever another app held focus.
                    Text(chat).font(SidebarStyle.rowFont)
                        .foregroundStyle(.primary)
                        .padding(.leading, SidebarStyle.titleIndent)
                }
            }
        }
        .listStyle(.sidebar)
        // The sidebar material is invisible to `cacheDisplay` — it draws as
        // transparent, which the capture resolves to black, which makes *every*
        // pixel "darker than the backdrop" and every row one giant ink band. The
        // mock therefore paints its own flat backdrop; the real sidebar's material
        // is not what this harness is about.
        .scrollContentBackground(.hidden)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { onWidth(proxy.size.width) }
                    .onChange(of: proxy.size.width) { _, width in onWidth(width) }
            }
        )
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
        // One opaque canvas for both columns: a capture measures ink against the
        // most common brightness, and a half-transparent window leaves half the
        // picture black.
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

    /// The red pill's rectangle, in pixels.
    private func highlightRect(_ pixels: WindowPixels) -> (x: ClosedRange<Int>, y: ClosedRange<Int>)? {
        var xs: [Int] = [], ys: [Int] = []
        for y in 0..<pixels.height {
            for x in 0..<pixels.width {
                let (r, g, b) = pixels.rgb(x, y)
                if r > 120, g < 90, b < 90 { xs.append(x); ys.append(y) }
            }
        }
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return nil }
        return (minX...maxX, minY...maxY)
    }

    // MARK: - Steps

    private func measureGeometry() {
        guard let pixels = capture() else {
            check(false, "the harness could render a window")
            return finish()
        }
        guard let rect = highlightRect(pixels) else {
            check(false, "the project row's highlight was painted")
            return finish()
        }
        print(String(format: "  note  column %.1fpt wide, capture %.1fpt tall (frame %.1fpt); highlight x %.1f-%.1fpt",
                     Double(columnWidth), Double(pixels.height) / Double(pixels.scale),
                     Double(window.frame.height),
                     Double(CGFloat(rect.x.lowerBound) / pixels.scale),
                     Double(CGFloat(rect.x.upperBound) / pixels.scale)))

        // Rows, not the toolbar toggle above them and not the other column. The
        // backdrop is measured *inside the column*: the detail column has its own
        // colour, and the whole-image modal brightness is whichever of the two
        // covers more pixels.
        let columnPixels = Int((columnWidth + 1) * pixels.scale)
        let backdrop = pixels.background(in: 0..<columnPixels, yRange: rect.y.lowerBound..<pixels.height)
        let rows = pixels.textLines(gap: 4,
                                    xRange: 0..<columnPixels,
                                    yRange: rect.y.lowerBound..<pixels.height,
                                    backdrop: backdrop)
        check(rows.count == 3, "three rows are on screen before the click",
              "found \(rows.count); ink bands " + rows.map { band in "\(band.first ?? -1)-\(band.last ?? -1)" }.joined(separator: ", "))

        let left = CGFloat(rect.x.lowerBound) / pixels.scale
        let right = CGFloat(rect.x.upperBound) / pixels.scale
        check(abs(left - SidebarStyle.sidebarMargin) <= 1.5,
              "the row highlight starts on the search field's margin",
              String(format: "%.1fpt against %.1fpt", Double(left), Double(SidebarStyle.sidebarMargin)))
        let trailing = columnWidth - right
        check(abs(trailing - SidebarStyle.sidebarMargin) <= 1.5,
              "the row highlight ends on the search field's margin",
              String(format: "%.1fpt from the trailing edge", Double(trailing)))

        click(at: clickPoint(in: rect, pixels))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.checkFolded() }
    }

    private func checkFolded() {
        guard let pixels = capture(), let rect = highlightRect(pixels) else { return finish() }
        let lines = rowCount(pixels, pill: rect)
        check(lines == 1, "clicking the project folds its chats away", "\(lines) row(s) left")
        click(at: clickPoint(in: rect, pixels))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.checkUnfolded() }
    }

    private func checkUnfolded() {
        guard let pixels = capture(), let rect = highlightRect(pixels) else { return finish() }
        let lines = rowCount(pixels, pill: rect)
        check(lines == 3, "clicking it again brings the chats back", "\(lines) row(s) on screen")
        if let data = pixels.pngData() {
            try? data.write(to: URL(fileURLWithPath: "/tmp/picode-sidebar-click.png"))
            print("  note  wrote /tmp/picode-sidebar-click.png — look at it")
        }
        finish()
    }

    private func rowCount(_ pixels: WindowPixels, pill: (x: ClosedRange<Int>, y: ClosedRange<Int>)) -> Int {
        pixels.textLines(gap: 4,
                         xRange: 0..<Int((columnWidth + 1) * pixels.scale),
                         yRange: pill.y.lowerBound..<pixels.height).count
    }

    /// The capture's y counts down from the top of the *content view*, window
    /// coordinates count up from the bottom of it, and the title bar is in
    /// neither, so the two meet at the content height.
    private func clickPoint(in pill: (x: ClosedRange<Int>, y: ClosedRange<Int>), _ pixels: WindowPixels) -> NSPoint {
        let centre = CGFloat(pill.y.lowerBound + pill.y.upperBound) / 2
        return NSPoint(x: CGFloat(pill.x.lowerBound) / pixels.scale + 40,
                       y: CGFloat(pixels.height) / pixels.scale - centre / pixels.scale)
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
