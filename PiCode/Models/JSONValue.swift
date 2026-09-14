//
//  JSONValue.swift
//  PiCode
//
//  A permissive, lossless JSON representation used for the Pi RPC boundary.
//
//  Pi's RPC payloads evolve over time and contain fields PiCode does not know
//  about yet. Decoding into `JSONValue` instead of strict `Codable` structs keeps
//  unknown fields from breaking the client while still allowing typed access to
//  the fields PiCode does understand.
//

import Foundation

/// Any JSON value. Unknown/extra fields in RPC payloads survive round trips.
enum JSONValue: Codable, Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value):
            // Keep integral values integral so request payloads stay clean.
            if value.rounded() == value, abs(value) < 9_007_199_254_740_992 {
                try container.encode(Int(value))
            } else {
                try container.encode(value)
            }
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

// MARK: - Typed access

extension JSONValue {
    var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var doubleValue: Double? {
        switch self {
        case .number(let value): return value
        case .string(let value): return Double(value)
        default: return nil
        }
    }

    var intValue: Int? {
        guard let double = doubleValue else { return nil }
        return Int(double)
    }

    var boolValue: Bool? {
        switch self {
        case .bool(let value): return value
        case .number(let value): return value != 0
        default: return nil
        }
    }

    var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    /// `nil` when the key is absent or explicitly null, which is the common
    /// pattern for optional RPC fields.
    subscript(key: String) -> JSONValue? {
        guard case .object(let dictionary) = self else { return nil }
        guard let value = dictionary[key], !value.isNull else { return nil }
        return value
    }

    func string(_ key: String) -> String? { self[key]?.stringValue }
    func int(_ key: String) -> Int? { self[key]?.intValue }
    func double(_ key: String) -> Double? { self[key]?.doubleValue }
    func bool(_ key: String) -> Bool? { self[key]?.boolValue }
    func array(_ key: String) -> [JSONValue]? { self[key]?.arrayValue }
    func object(_ key: String) -> JSONValue? { self[key] }

    /// Compact single-line rendering, used for tool input summaries.
    var compactDescription: String {
        switch self {
        case .null: return "null"
        case .bool(let value): return value ? "true" : "false"
        case .number(let value):
            if value.rounded() == value { return String(Int(value)) }
            return String(value)
        case .string(let value): return value
        case .array(let value): return "[" + value.map(\.compactDescription).joined(separator: ", ") + "]"
        case .object(let value):
            let keys = value.keys.sorted()
            return "{" + keys.map { "\($0): \(value[$0]!.compactDescription)" }.joined(separator: ", ") + "}"
        }
    }

    /// Multi-line indented rendering, used for raw tool payloads.
    var prettyDescription: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(self),
              let string = String(data: data, encoding: .utf8) else {
            return compactDescription
        }
        return string
    }
}

// MARK: - Encoding helpers

enum JSONCoding {
    static let decoder = JSONDecoder()

    static func decode(_ data: Data) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: data)
    }

    /// Encodes one JSONL record. Records are always terminated by a single LF
    /// and never contain raw newlines inside strings.
    static func line(_ value: JSONValue) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        var data = try encoder.encode(value)
        data.append(0x0A)
        return data
    }
}
