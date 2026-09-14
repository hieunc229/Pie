//
//  ANSI.swift
//  PiCode
//
//  Terminal output from the bash tool arrives with ANSI escape sequences. The
//  transcript renders it as styled text instead of dumping raw escapes, while
//  keeping the log selectable and copyable as plain text.
//

import AppKit
import SwiftUI

enum ANSIParser {
    /// Strips every escape sequence and normalizes carriage-return overwrites.
    static func plainText(_ text: String) -> String {
        var output = ""
        output.reserveCapacity(text.count)
        var iterator = text.makeIterator()
        var pending: Character?

        func flushPending() {
            if let character = pending { output.append(character) }
            pending = nil
        }

        while let character = iterator.next() {
            if character == "\u{1B}" {
                consumeEscape(&iterator)
                continue
            }
            if character == "\r" {
                // Keep only the final frame of an in-place progress line.
                if let newline = output.lastIndex(of: "\n") {
                    output.removeSubrange(output.index(after: newline)...)
                } else {
                    output.removeAll()
                }
                continue
            }
            flushPending()
            pending = character
        }
        flushPending()
        return output
    }

    /// Builds a styled string, mapping SGR attributes to semantic colors.
    static func attributed(_ text: String, scheme: ColorScheme, baseFont: Font = .system(.body, design: .monospaced)) -> AttributedString {
        var result = AttributedString()
        var state = SGRState()

        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]

            if character == "\u{1B}" {
                let next = text.index(after: index)
                guard next < text.endIndex, text[next] == "[" else {
                    index = next
                    continue
                }
                var cursor = text.index(after: next)
                var parameters = ""
                var final: Character?
                while cursor < text.endIndex {
                    let value = text[cursor]
                    if value.isNumber || value == ";" || value == "?" || value == ":" || value == ">" || value == "<" {
                        parameters.append(value)
                        cursor = text.index(after: cursor)
                        continue
                    }
                    final = value
                    cursor = text.index(after: cursor)
                    break
                }
                if final == "m" {
                    state.apply(parameters)
                }
                index = cursor
                continue
            }

            if character == "\r" {
                // Emulate in-place overwrite by trimming the current line.
                let characters = result.characters
                if let newline = characters.lastIndex(of: "\n") {
                    let start = characters.index(after: newline)
                    result.removeSubrange(start..<characters.endIndex)
                } else {
                    result.removeSubrange(result.startIndex..<result.endIndex)
                }
                index = text.index(after: index)
                continue
            }

            let start = index
            while index < text.endIndex, text[index] != "\u{1B}", text[index] != "\r" {
                index = text.index(after: index)
            }
            var segment = AttributedString(String(text[start..<index]))
            segment.font = state.bold ? .system(.body, design: .monospaced).bold() : baseFont
            segment.foregroundColor = state.foreground(scheme: scheme)
            if state.underline {
                segment.underlineStyle = .single
            }
            if state.italic {
                segment.inlinePresentationIntent = .emphasized
            }
            result.append(segment)
        }

        return result
    }

    private static func consumeEscape<I: IteratorProtocol>(_ iterator: inout I) where I.Element == Character {
        // Handles OSC (`ESC ] ... BEL|ST`) and short escapes (`ESC c`, `ESC ( B`).
        guard let next = iterator.next() else { return }
        if next == "]" {
            while let character = iterator.next() {
                if character == "\u{07}" { return }
                if character == "\u{1B}" {
                    _ = iterator.next()
                    return
                }
            }
        }
    }

    struct SGRState {
        var bold = false
        var dim = false
        var italic = false
        var underline = false
        var inverse = false
        var foregroundIndex: Int?
        var backgroundIndex: Int?
        var trueColor: (r: Double, g: Double, b: Double)?
        var backgroundColor: Color?

        mutating func apply(_ parameters: String) {
            let values = parameters
                .split(separator: ";", omittingEmptySubsequences: false)
                .map { Int($0) ?? 0 }
            let codes = values.isEmpty ? [0] : values
            var index = 0
            while index < codes.count {
                let code = codes[index]
                switch code {
                case 0:
                    self = SGRState()
                case 1: bold = true
                case 2: dim = true
                case 3: italic = true
                case 4: underline = true
                case 7: inverse = true
                case 22: bold = false; dim = false
                case 23: italic = false
                case 24: underline = false
                case 27: inverse = false
                case 30...37:
                    foregroundIndex = code - 30
                    trueColor = nil
                case 39:
                    foregroundIndex = nil
                    trueColor = nil
                case 40...47:
                    backgroundIndex = code - 40
                case 49:
                    backgroundIndex = nil
                    backgroundColor = nil
                case 90...97:
                    foregroundIndex = code - 90 + 8
                    trueColor = nil
                case 100...107:
                    backgroundIndex = code - 100 + 8
                case 38, 48:
                    // Extended color: `38;5;n` or `38;2;r;g;b`.
                    guard index + 1 < codes.count else { break }
                    let mode = codes[index + 1]
                    if mode == 5, index + 2 < codes.count {
                        let value = codes[index + 2]
                        if code == 38 {
                            foregroundIndex = value
                            trueColor = nil
                        } else {
                            backgroundIndex = value
                        }
                        index += 2
                    } else if mode == 2, index + 4 < codes.count {
                        let r = Double(codes[index + 2]) / 255
                        let g = Double(codes[index + 3]) / 255
                        let b = Double(codes[index + 4]) / 255
                        if code == 38 {
                            trueColor = (r, g, b)
                        } else {
                            backgroundColor = Color(.sRGB, red: r, green: g, blue: b)
                        }
                        index += 4
                    }
                default:
                    break
                }
                index += 1
            }
        }

        func foreground(scheme: ColorScheme) -> Color {
            if let trueColor {
                return Color(.sRGB, red: trueColor.r, green: trueColor.g, blue: trueColor.b)
            }
            if let foregroundIndex {
                return ANSIPalette.color(index: foregroundIndex, scheme: scheme)
            }
            return Color(nsColor: .labelColor)
        }
    }
}

/// Standard ANSI palette, tuned per appearance so dim colors stay readable on
/// both light and dark backgrounds.
enum ANSIPalette {
    static func color(index: Int, scheme: ColorScheme) -> Color {
        let table = scheme == .dark ? dark : light
        return table[((index % 16) + 16) % 16]
    }

    private static let dark: [Color] = [
        Color(.sRGB, red: 0.35, green: 0.35, blue: 0.38),   // black -> gray
        Color(.sRGB, red: 0.94, green: 0.42, blue: 0.42),   // red
        Color(.sRGB, red: 0.48, green: 0.82, blue: 0.48),   // green
        Color(.sRGB, red: 0.94, green: 0.78, blue: 0.42),   // yellow
        Color(.sRGB, red: 0.45, green: 0.65, blue: 0.96),   // blue
        Color(.sRGB, red: 0.80, green: 0.55, blue: 0.95),   // magenta
        Color(.sRGB, red: 0.42, green: 0.82, blue: 0.86),   // cyan
        Color(.sRGB, red: 0.88, green: 0.88, blue: 0.90),   // white
        Color(.sRGB, red: 0.50, green: 0.50, blue: 0.54),   // bright black
        Color(.sRGB, red: 1.00, green: 0.55, blue: 0.55),
        Color(.sRGB, red: 0.60, green: 0.92, blue: 0.60),
        Color(.sRGB, red: 1.00, green: 0.88, blue: 0.55),
        Color(.sRGB, red: 0.58, green: 0.75, blue: 1.00),
        Color(.sRGB, red: 0.88, green: 0.65, blue: 1.00),
        Color(.sRGB, red: 0.55, green: 0.92, blue: 0.95),
        Color(.sRGB, red: 1.00, green: 1.00, blue: 1.00)
    ]

    private static let light: [Color] = [
        Color(.sRGB, red: 0.20, green: 0.20, blue: 0.22),
        Color(.sRGB, red: 0.75, green: 0.16, blue: 0.16),
        Color(.sRGB, red: 0.12, green: 0.52, blue: 0.18),
        Color(.sRGB, red: 0.62, green: 0.45, blue: 0.02),
        Color(.sRGB, red: 0.13, green: 0.33, blue: 0.78),
        Color(.sRGB, red: 0.58, green: 0.20, blue: 0.72),
        Color(.sRGB, red: 0.06, green: 0.48, blue: 0.52),
        Color(.sRGB, red: 0.35, green: 0.35, blue: 0.38),
        Color(.sRGB, red: 0.45, green: 0.45, blue: 0.48),
        Color(.sRGB, red: 0.88, green: 0.22, blue: 0.22),
        Color(.sRGB, red: 0.16, green: 0.60, blue: 0.22),
        Color(.sRGB, red: 0.72, green: 0.53, blue: 0.02),
        Color(.sRGB, red: 0.15, green: 0.40, blue: 0.88),
        Color(.sRGB, red: 0.68, green: 0.25, blue: 0.82),
        Color(.sRGB, red: 0.05, green: 0.55, blue: 0.60),
        Color(.sRGB, red: 0.15, green: 0.15, blue: 0.17)
    ]
}
