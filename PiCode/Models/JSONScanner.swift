//
//  JSONScanner.swift
//  PiCode
//
//  A hand-written, iterative JSON reader/writer for the Pi boundary.
//
//  Why not `JSONDecoder`? Pi's `get_tree` response nests one level per session
//  entry, and `JSONDecoder` plus a recursive `JSONValue` decoder overflows the
//  stack on deep payloads (measured: a 145-entry session tree crashed a smoke
//  test with SIGBUS inside `_CodingPathNode.path`). The scanner below keeps its
//  own explicit stack, so depth costs heap instead of stack, and it is also much
//  faster than the `try?`-chain decoder because each byte is inspected once.
//
//  The writer is iterative for the same reason and gives PiCode deterministic,
//  sorted keys in outgoing payloads.
//

import Foundation

enum JSONScanner {
    struct ParseError: LocalizedError, Equatable {
        var message: String
        var offset: Int

        var errorDescription: String? { "\(message) at byte \(offset)" }
    }

    // MARK: - Reading

    static func parse(_ data: Data) throws -> JSONValue {
        var reader = Reader(bytes: [UInt8](data))
        return try reader.parseDocument()
    }

    static func parse(_ string: String) throws -> JSONValue {
        var reader = Reader(bytes: Array(string.utf8))
        return try reader.parseDocument()
    }

    struct Reader {
        private let bytes: [UInt8]
        private var index = 0

        init(bytes: [UInt8]) {
            self.bytes = bytes
        }

        /// One open array or object. Values accumulate here until the matching
        /// closer arrives; `keys` stays empty for arrays.
        private struct Frame {
            var isObject: Bool
            var keys: [String] = []
            var values: [JSONValue] = []
            var pendingKey: String?
        }

        mutating func parseDocument() throws -> JSONValue {
            var stack: [Frame] = []
            var result: JSONValue?
            // Tracked so a missing comma between two values is rejected.
            var needsSeparator = false

            while result == nil {
                skipWhitespace()
                if needsSeparator, let frame = stack.last {
                    let byte = peek()
                    if byte == Self.comma {
                        index += 1
                        skipWhitespace()
                        needsSeparator = false
                    } else if (frame.isObject && byte == Self.closeBrace)
                        || (!frame.isObject && byte == Self.closeBracket) {
                        // Let the closer branch below run.
                        needsSeparator = false
                    } else {
                        throw error("Expected ',' or a closing bracket")
                    }
                }

                let byte = peek()
                switch byte {
                case Self.openBrace:
                    index += 1
                    stack.append(Frame(isObject: true))
                case Self.openBracket:
                    index += 1
                    stack.append(Frame(isObject: false))
                case Self.closeBrace, Self.closeBracket:
                    guard let frame = stack.popLast() else {
                        throw error("Unexpected closing bracket")
                    }
                    let expected: UInt8 = frame.isObject ? Self.closeBrace : Self.closeBracket
                    guard byte == expected else {
                        throw error(frame.isObject
                                    ? "Expected '}' to close an object"
                                    : "Expected ']' to close an array")
                    }
                    if frame.isObject, frame.keys.count != frame.values.count {
                        throw error("Object value is missing its key")
                    }
                    index += 1
                    let container: JSONValue = frame.isObject
                        ? .object(Self.makeObject(keys: frame.keys, values: frame.values))
                        : .array(frame.values)
                    needsSeparator = true
                    if stack.isEmpty {
                        result = container
                    } else {
                        attach(container, to: &stack)
                    }
                default:
                    if var frame = stack.last, frame.isObject, frame.pendingKey == nil {
                        frame.pendingKey = try parseString()
                        stack[stack.count - 1] = frame
                        skipWhitespace()
                        guard peek() == Self.colon else { throw error("Expected ':' after a key") }
                        index += 1
                    } else {
                        let value = try parseScalar()
                        needsSeparator = true
                        if stack.isEmpty {
                            result = value
                        } else {
                            attach(value, to: &stack)
                        }
                    }
                }
            }

            skipWhitespace()
            guard index == bytes.count else { throw error("Unexpected trailing content") }
            return result ?? .null
        }

        private func attach(_ value: JSONValue, to stack: inout [Frame]) {
            var frame = stack[stack.count - 1]
            if frame.isObject {
                // Duplicate keys: last one wins, matching `JSONDecoder`.
                frame.keys.append(frame.pendingKey ?? "")
                frame.pendingKey = nil
            }
            frame.values.append(value)
            stack[stack.count - 1] = frame
        }

        private static func makeObject(keys: [String], values: [JSONValue]) -> [String: JSONValue] {
            var dictionary: [String: JSONValue] = [:]
            dictionary.reserveCapacity(keys.count)
            for (key, value) in zip(keys, values) {
                dictionary[key] = value
            }
            return dictionary
        }

        // MARK: Scalars

        private mutating func parseScalar() throws -> JSONValue {
            guard let byte = peek() else { throw error("Unexpected end of input") }
            switch byte {
            case Self.quote:
                return .string(try parseString())
            case Self.minus, 0x30...0x39:
                return try parseNumber()
            default:
                return try parseLiteral()
            }
        }

        private mutating func parseLiteral() throws -> JSONValue {
            if match("true") { return .bool(true) }
            if match("false") { return .bool(false) }
            if match("null") { return .null }
            throw error("Unrecognized value")
        }

        private mutating func parseNumber() throws -> JSONValue {
            let start = index
            if peek() == Self.minus { index += 1 }
            var sawDigit = false
            while let byte = peek() {
                switch byte {
                case 0x30...0x39:
                    sawDigit = true
                    index += 1
                case Self.plus, Self.minus, 0x2E, 0x65, 0x45:  // + - . e E
                    index += 1
                default:
                    guard sawDigit, let value = Double(String(decoding: bytes[start..<index], as: UTF8.self)) else {
                        throw error("Malformed number", at: start)
                    }
                    return .number(value)
                }
            }
            guard sawDigit, let value = Double(String(decoding: bytes[start..<index], as: UTF8.self)) else {
                throw error("Malformed number", at: start)
            }
            return .number(value)
        }

        private mutating func parseString() throws -> String {
            guard peek() == Self.quote else { throw error("Expected a string") }
            index += 1
            // Fast path: no escapes, so the whole value is one contiguous slice.
            let start = index
            while let byte = peek(), byte != Self.quote {
                if byte == Self.backslash {
                    return try parseStringWithEscapes(prefix: bytes[start..<index])
                }
                index += 1
            }
            guard peek() == Self.quote else { throw error("Unterminated string", at: start) }
            let text = String(decoding: bytes[start..<index], as: UTF8.self)
            index += 1
            return text
        }

        private mutating func parseStringWithEscapes(prefix: ArraySlice<UInt8>) throws -> String {
            var output = Array(prefix)
            while true {
                guard let byte = peek() else { throw error("Unterminated string") }
                index += 1
                if byte == Self.quote { return String(decoding: output, as: UTF8.self) }
                guard byte == Self.backslash else {
                    output.append(byte)
                    continue
                }
                guard let escape = peek() else { throw error("Unterminated escape sequence") }
                index += 1
                switch escape {
                case 0x22: output.append(0x22)          // "
                case 0x5C: output.append(0x5C)          // \
                case 0x2F: output.append(0x2F)          // /
                case 0x62: output.append(0x08)          // b
                case 0x66: output.append(0x0C)          // f
                case 0x6E: output.append(0x0A)          // n
                case 0x72: output.append(0x0D)          // r
                case 0x74: output.append(0x09)          // t
                case 0x75:                              // u
                    var scalar = try parseHex4()
                    // Combine UTF-16 surrogate pairs into one scalar.
                    if scalar >= 0xD800, scalar <= 0xDBFF, peek() == Self.backslash {
                        let saved = index
                        index += 1
                        if peek() == 0x75 {
                            index += 1
                            let low = try parseHex4()
                            if low >= 0xDC00, low <= 0xDFFF {
                                scalar = 0x10000 + ((scalar - 0xD800) << 10) + (low - 0xDC00)
                            } else {
                                output.append(contentsOf: replacementBytes(for: scalar))
                                scalar = low
                            }
                        } else {
                            index = saved
                        }
                    }
                    output.append(contentsOf: replacementBytes(for: scalar))
                default:
                    throw error("Unknown escape sequence")
                }
            }
        }

        /// Lone surrogates cannot be represented in Swift strings, so they become
        /// U+FFFD — same as Foundation.
        private func replacementBytes(for scalar: UInt32) -> [UInt8] {
            let value = (scalar >= 0xD800 && scalar <= 0xDFFF) ? 0xFFFD : scalar
            guard let unicode = UnicodeScalar(value) else { return Array("\u{FFFD}".utf8) }
            return Array(String(Character(unicode)).utf8)
        }

        private mutating func parseHex4() throws -> UInt32 {
            var value: UInt32 = 0
            for _ in 0..<4 {
                guard let byte = peek(), let digit = Self.hexDigit(byte) else {
                    throw error("Malformed \\u escape")
                }
                value = value << 4 | UInt32(digit)
                index += 1
            }
            return value
        }

        private static func hexDigit(_ byte: UInt8) -> UInt8? {
            switch byte {
            case 0x30...0x39: return byte - 0x30
            case 0x41...0x46: return byte - 0x41 + 10
            case 0x61...0x66: return byte - 0x61 + 10
            default: return nil
            }
        }

        // MARK: Byte helpers

        private func peek() -> UInt8? {
            index < bytes.count ? bytes[index] : nil
        }

        private mutating func skipWhitespace() {
            while let byte = peek(), byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D {
                index += 1
            }
        }

        private mutating func match(_ literal: String) -> Bool {
            let expected = Array(literal.utf8)
            guard index + expected.count <= bytes.count else { return false }
            for (offset, byte) in expected.enumerated() where bytes[index + offset] != byte {
                return false
            }
            index += expected.count
            return true
        }

        private func error(_ message: String, at offset: Int? = nil) -> ParseError {
            ParseError(message: message, offset: offset ?? index)
        }

        private static let quote: UInt8 = 0x22
        private static let backslash: UInt8 = 0x5C
        private static let comma: UInt8 = 0x2C
        private static let colon: UInt8 = 0x3A
        private static let plus: UInt8 = 0x2B
        private static let minus: UInt8 = 0x2D
        private static let openBrace: UInt8 = 0x7B
        private static let closeBrace: UInt8 = 0x7D
        private static let openBracket: UInt8 = 0x5B
        private static let closeBracket: UInt8 = 0x5D
    }

    // MARK: - Writing

    /// Deterministic serialization. Keys are sorted so outgoing RPC payloads and
    /// diagnostics are stable; Pi does not depend on key order.
    static func serialize(_ value: JSONValue, pretty: Bool = false) -> String {
        enum Step {
            case value(JSONValue, Int)
            case raw(String)
        }

        var output = ""
        var steps: [Step] = [.value(value, 0)]
        while let step = steps.popLast() {
            switch step {
            case .raw(let text):
                output += text
            case .value(let value, let depth):
                switch value {
                case .null:
                    output += "null"
                case .bool(let flag):
                    output += flag ? "true" : "false"
                case .number(let number):
                    output += numberText(number)
                case .string(let text):
                    output += quoted(text)
                case .array(let items):
                    guard !items.isEmpty else {
                        output += "[]"
                        continue
                    }
                    let inner = depth + 1
                    steps.append(.raw(pretty ? "\n\(indent(depth))]" : "]"))
                    // Steps pop in reverse, so the separator is pushed after the
                    // item it follows.
                    for (offset, item) in items.enumerated().reversed() {
                        steps.append(.value(item, inner))
                        if offset > 0 {
                            steps.append(.raw(pretty ? ",\n\(indent(inner))" : ","))
                        } else if pretty {
                            steps.append(.raw("\n\(indent(inner))"))
                        }
                    }
                    output += "["
                case .object(let dictionary):
                    guard !dictionary.isEmpty else {
                        output += "{}"
                        continue
                    }
                    let inner = depth + 1
                    let keys = dictionary.keys.sorted()
                    steps.append(.raw(pretty ? "\n\(indent(depth))}" : "}"))
                    for (offset, key) in keys.enumerated().reversed() {
                        steps.append(.value(dictionary[key] ?? .null, inner))
                        steps.append(.raw(pretty ? ": " : ":"))
                        steps.append(.raw(quoted(key)))
                        if offset > 0 {
                            steps.append(.raw(pretty ? ",\n\(indent(inner))" : ","))
                        } else if pretty {
                            steps.append(.raw("\n\(indent(inner))"))
                        }
                    }
                    output += "{"
                }
            }
        }
        return output
    }

    private static func indent(_ depth: Int) -> String {
        String(repeating: "  ", count: depth)
    }

    private static func numberText(_ number: Double) -> String {
        // JSON has no NaN/Infinity; emit null rather than invalid JSON.
        guard number.isFinite else { return "null" }
        if number.rounded() == number, abs(number) < 9_007_199_254_740_992 {
            return String(Int(number))
        }
        return String(number)
    }

    private static func quoted(_ text: String) -> String {
        var output = "\""
        output.reserveCapacity(text.utf8.count + 2)
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": output += "\\\""
            case "\\": output += "\\\\"
            case "\n": output += "\\n"
            case "\r": output += "\\r"
            case "\t": output += "\\t"
            case "\u{08}": output += "\\b"
            case "\u{0C}": output += "\\f"
            default:
                if scalar.value < 0x20 {
                    output += String(format: "\\u%04x", scalar.value)
                } else {
                    output.unicodeScalars.append(scalar)
                }
            }
        }
        output += "\""
        return output
    }
}
