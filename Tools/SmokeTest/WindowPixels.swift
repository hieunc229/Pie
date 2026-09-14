//
//  WindowPixels.swift
//  PiCode smoke test — not part of the app target.
//
//  Shared pixel reader for the sidebar harnesses, which measure a window's own
//  pixels (in-process capture needs no screen-recording permission; `screencapture`
//  does, and hands back a black frame without it).
//
//  It exists because the obvious shortcut is a trap: reading bytes straight out of
//  `NSBitmapImageRep(cgImage:)` gives whatever layout Core Graphics felt like for
//  that capture — on this machine, alpha *first*, so a dark grey pixel reads as
//  (255, 39, 40) and looks bright red. A brightness-only test never notices; a
//  colour test measures the wrong rectangle and confidently reports nonsense. So
//  the image is redrawn into a buffer whose layout is pinned here: 8 bits per
//  channel, RGBA, premultiplied last.
//

import AppKit

struct WindowPixels {
    let width: Int
    let height: Int
    /// Pixels per point. Captures come back at the window's backing scale, so every
    /// measurement has to be divided by this before it means anything.
    let scale: CGFloat

    private let bytes: [UInt8]
    /// The most common brightness: what "ink" is measured against. Appearances
    /// differ, and so do materials, so the backdrop is never assumed.
    let background: Int

    init?(image: CGImage, scale: CGFloat) {
        let width = image.width
        let height = image.height
        self.width = width
        self.height = height
        self.scale = scale
        guard width > 0, height > 0 else { return nil }

        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress,
                                          width: width,
                                          height: height,
                                          bitsPerComponent: 8,
                                          bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        bytes = buffer

        var histogram = [Int](repeating: 0, count: 256)
        for index in stride(from: 0, to: bytes.count, by: 8 * 4) {
            histogram[(Int(bytes[index]) + Int(bytes[index + 1]) + Int(bytes[index + 2])) / 3] += 1
        }
        background = histogram.enumerated().max { $0.element < $1.element }!.offset
    }

    /// A window's own content, at full resolution.
    ///
    /// Unused by the harnesses now, and kept with a warning: it asks the window
    /// server what it last composited, so a window that is fully behind another
    /// one — which a harness window is as soon as the real app is running — comes
    /// back **entirely black**. Use `capture(_ view:)`.
    static func capture(_ window: NSWindow) -> WindowPixels? {
        let id = CGWindowID(window.windowNumber)
        guard let image = CGWindowListCreateImage(.null, .optionIncludingWindow, id,
                                                  [.boundsIgnoreFraming, .bestResolution]) else { return nil }
        return WindowPixels(image: image, scale: window.backingScaleFactor)
    }

    /// A view's content, drawn on the spot.
    ///
    /// Preferred when only a view (or a pane of it) is under test. A window
    /// capture asks the window server for what it last composited, and a window
    /// that is fully behind another one — which a harness window is, as soon as
    /// the real app is running — can come back **entirely black**. Drawing the
    /// view here cannot be occluded, and it also leaves the title bar and toolbar
    /// out of the picture.
    static func capture(_ view: NSView) -> WindowPixels? {
        guard view.bounds.width >= 1, view.bounds.height >= 1,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let image = rep.cgImage, rep.pixelsWide > 0 else { return nil }
        return WindowPixels(image: image, scale: CGFloat(rep.pixelsWide) / view.bounds.width)
    }

    func rgb(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
        let offset = (y * width + x) * 4
        return (Int(bytes[offset]), Int(bytes[offset + 1]), Int(bytes[offset + 2]))
    }

    func brightness(_ x: Int, _ y: Int) -> Int {
        let (r, g, b) = rgb(x, y)
        return (r + g + b) / 3
    }

    /// Ink: neutral in colour and far from the backdrop. Both halves matter — the
    /// neutrality is what keeps a coloured highlight or a red pill out of a count
    /// of text lines.
    func isText(_ x: Int, _ y: Int) -> Bool {
        let (r, g, b) = rgb(x, y)
        guard abs(r - g) < 24, abs(g - b) < 24 else { return false }
        let value = (r + g + b) / 3
        return background > 128 ? value < background - 40 : value > background + 40
    }

    /// Rows of text, as bands of y. A dot over a "j" or an accent sits a couple of
    /// pixels above the rest of its glyph, so bands closer than `gap` merge, and
    /// anything shorter than `minimumHeight` is not a line of text. Ranges narrow
    /// the search to one pane: a window capture holds the toolbar, the title and
    /// whatever the other column is showing, and all of it looks like ink.
    func textLines(gap: Int = 2,
                   minimumHeight: Int = 6,
                   xRange: Range<Int>? = nil,
                   yRange: Range<Int>? = nil) -> [[Int]] {
        let xs = xRange ?? 0..<width
        let ys = yRange ?? 0..<height
        var lines: [[Int]] = []
        for y in ys where xs.contains(where: { isText($0, y) }) {
            if let last = lines.last, let previous = last.last, y - previous <= gap {
                lines[lines.count - 1].append(y)
            } else {
                lines.append([y])
            }
        }
        return lines.filter { ($0.last ?? 0) - ($0.first ?? 0) >= minimumHeight }
    }

    func pngData() -> Data? {
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(width: width,
                                  height: height,
                                  bitsPerComponent: 8,
                                  bitsPerPixel: 32,
                                  bytesPerRow: width * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider,
                                  decode: nil,
                                  shouldInterpolate: false,
                                  intent: .defaultIntent) else { return nil }
        let rep = NSBitmapImageRep(cgImage: image)
        return rep.representation(using: .png, properties: [:])
    }
}
