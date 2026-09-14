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
///
/// `Codable` conformance exists for small, shallow stores. **Do not** use
/// `JSONDecoder`/`JSONEncoder` with `JSONValue` for RPC or session payloads:
/// Pi's payloads nest deeply (a session tree nests once per entry) and the
/// recursive `Decodable` path overflows the stack. Use `JSONCoding.decode` and
/// `JSONScanner.serialize`, which keep an explicit stack.
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
    ///
    /// Recursive, but depth-limited: `prettyDescription` (iterative) is the safe
    /// way to render arbitrary payloads, and this guard keeps a hostile or
    /// unexpectedly deep value from overflowing the stack while it is being
    /// summarised inside a view.
    var compactDescription: String {
        compactDescription(depth: 0)
    }

    private func compactDescription(depth: Int) -> String {
        guard depth < 64 else { return "…" }
        switch self {
        case .null: return "null"
        case .bool(let value): return value ? "true" : "false"
        case .number(let value):
            if value.rounded() == value { return String(Int(value)) }
            return String(value)
        case .string(let value): return value
        case .array(let value):
            return "[" + value.map { $0.compactDescription(depth: depth + 1) }.joined(separator: ", ") + "]"
        case .object(let value):
            let keys = value.keys.sorted()
            let body = keys.map { "\($0): \(value[$0]!.compactDescription(depth: depth + 1))" }
            return "{" + body.joined(separator: ", ") + "}"
        }
    }

    /// Multi-line indented rendering, used for raw tool payloads.
    var prettyDescription: String {
        JSONScanner.serialize(self, pretty: true)
    }
}

// MARK: - Encoding helpers

enum JSONCoding {
    static let decoder = JSONDecoder()

    /// Parses one RPC message or JSONL record.
    ///
    /// Uses the iterative scanner rather than `JSONDecoder`: Pi's payloads can be
    /// deeply nested (a session tree nests once per entry) and the recursive
    /// decoder overflows the stack on those.
    static func decode(_ data: Data) throws -> JSONValue {
        try JSONScanner.parse(data)
    }

    /// Encodes one JSONL record. Records are always terminated by a single LF
    /// and never contain raw newlines inside strings.
    static func line(_ value: JSONValue) throws -> Data {
        var data = Data(JSONScanner.serialize(value).utf8)
        data.append(0x0A)
        return data
    }
}
