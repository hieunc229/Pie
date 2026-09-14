//
//  PiDiagnosticsLog.swift
//  PiCode
//
//  Optional, user-enabled record of raw RPC payloads.
//
//  This exists so protocol problems can be diagnosed without a terminal. It is
//  off unless the user turns on "Record RPC payloads" in Settings, it lives only
//  in memory, and it is capped so a long session cannot grow without bound.
//

import Foundation

final class PiDiagnosticsLog: @unchecked Sendable {
    static let shared = PiDiagnosticsLog()

    private let lock = NSLock()
    private var entries: [String] = []
    let limit: Int

    init(limit: Int = 2_000) {
        self.limit = limit
    }

    func append(_ line: String) {
        lock.lock()
        entries.append(line)
        if entries.count > limit {
            entries.removeFirst(entries.count - limit)
        }
        lock.unlock()
    }

    func snapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }

    func text() -> String {
        snapshot().joined(separator: "\n\n")
    }

    func clear() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.count
    }
}
