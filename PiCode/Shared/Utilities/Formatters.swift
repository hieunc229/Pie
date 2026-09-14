//
//  Formatters.swift
//  PiCode
//
//  Display formatting shared by every surface so numbers read consistently.
//

import Foundation

extension JSONEncoder {
    /// Encoder used for PiCode's own stores (drafts, pins, diagnostics).
    static var piCode: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var piCode: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

enum Format {
    static func relativeTime(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "" }
        let seconds = now.timeIntervalSince(date)
        if seconds < 5 { return "now" }
        if seconds < 60 { return "\(Int(seconds))s ago" }
        if seconds < 3600 { return "\(Int(seconds / 60))m ago" }
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        if seconds < 60 * 60 * 24 * 7 {
            return date.formatted(.dateTime.weekday(.abbreviated))
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    static func timestamp(_ date: Date?) -> String {
        guard let date else { return "" }
        return date.formatted(date: .omitted, time: .shortened)
    }

    /// Time-only label for the activity timeline.
    static func clockTime(_ date: Date?) -> String {
        guard let date else { return "" }
        return clockTimeFormatter.string(from: date)
    }

    private static let clockTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()

    static func dayHeading(_ date: Date?) -> String {
        guard let date else { return "Unknown" }
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "—" }
        if seconds < 1 { return "\(Int((seconds * 1000).rounded()))ms" }
        if seconds < 60 { return String(format: "%.1fs", seconds) }
        let minutes = Int(seconds) / 60
        let remainder = Int(seconds) % 60
        return "\(minutes)m \(remainder)s"
    }

    static func byteSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: Int64(bytes))
    }

    static func lineCount(_ count: Int) -> String {
        count == 1 ? "1 line" : "\(count.formatted()) lines"
    }

    /// Compact token counts: 1.2k, 34.5k, 1.1M.
    static func tokens(_ count: Int) -> String {
        let value = Double(count)
        if count < 1000 { return "\(count)" }
        if count < 1_000_000 { return String(format: "%.1fk", value / 1000).replacingOccurrences(of: ".0k", with: "k") }
        return String(format: "%.2fM", value / 1_000_000)
    }

    /// Cost shown with enough precision to be useful for cheap models.
    static func cost(_ value: Double) -> String {
        if value == 0 { return "$0.00" }
        if value < 0.01 { return String(format: "$%.4f", value) }
        if value < 1 { return String(format: "$%.3f", value) }
        return String(format: "$%.2f", value)
    }

    static func signed(_ value: Int) -> String {
        value > 0 ? "+\(value)" : "\(value)"
    }

    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }
}

extension Double {
    var currencyString: String { Format.cost(self) }
}
