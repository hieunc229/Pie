//
//  JSONLDecoder.swift
//  PiCode
//
//  Strict JSONL framing for Pi RPC.
//
//  Pi's RPC mode uses LF as the only record delimiter. This decoder therefore:
//   - splits on byte 0x0A only,
//   - accepts CRLF by stripping a single trailing 0x0D,
//   - never treats U+2028/U+2029 as line breaks (unlike generic line readers),
//   - decodes as UTF-8 only after a complete record is available, so multi-byte
//     scalars split across reads are handled correctly.
//

import Foundation

struct JSONLDecoder {
    /// Guards against an unbounded buffer if a peer never emits a delimiter.
    static let maxRecordBytes = 32 * 1024 * 1024

    private var bytes: [UInt8] = []
    private var cursor = 0
    private var overflowed = false

    /// Appends raw bytes and returns every complete record.
    mutating func append(_ data: Data) -> [Data] {
        bytes.append(contentsOf: data)

        var records: [Data] = []
        while true {
            guard let newline = nextNewlineIndex(from: cursor) else { break }
            records.append(makeRecord(from: cursor, to: newline))
            cursor = newline + 1
        }

        if cursor > 0 {
            if cursor == bytes.count {
                bytes.removeAll(keepingCapacity: true)
                cursor = 0
            } else if cursor > 64 * 1024 {
                bytes.removeFirst(cursor)
                cursor = 0
            }
        }

        if bytes.count - cursor > Self.maxRecordBytes {
            // Drop the oversized record rather than growing without bound.
            bytes.removeAll(keepingCapacity: false)
            cursor = 0
            overflowed = true
        }

        return records
    }

    /// Returns any trailing record without a delimiter. Used when a stream ends.
    mutating func flush() -> Data? {
        guard cursor < bytes.count else {
            bytes.removeAll(keepingCapacity: false)
            cursor = 0
            return nil
        }
        let record = makeRecord(from: cursor, to: bytes.count)
        bytes.removeAll(keepingCapacity: false)
        cursor = 0
        return record.isEmpty ? nil : record
    }

    /// True when at least one oversized record was discarded.
    mutating func consumeOverflowFlag() -> Bool {
        defer { overflowed = false }
        return overflowed
    }

    private func nextNewlineIndex(from start: Int) -> Int? {
        var index = start
        while index < bytes.count {
            if bytes[index] == 0x0A { return index }
            index += 1
        }
        return nil
    }

    private func makeRecord(from start: Int, to end: Int) -> Data {
        var end = end
        if end > start, bytes[end - 1] == 0x0D { end -= 1 }
        return Data(bytes[start..<end])
    }
}

/// Splits a byte stream into UTF-8 lines for stderr diagnostics. stderr is not
/// protocol data, so it only needs to be human readable.
struct LineAccumulator {
    private var decoder = JSONLDecoder()

    mutating func append(_ data: Data) -> [String] {
        decoder.append(data).compactMap { String(data: $0, encoding: .utf8) }
    }

    mutating func flush() -> [String] {
        decoder.flush().flatMap { String(data: $0, encoding: .utf8) }.map { [$0] } ?? []
    }
}
