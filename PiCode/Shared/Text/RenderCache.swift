//
//  RenderCache.swift
//  PiCode
//
//  A small, bounded cache for the expensive, pure derivations the transcript asks
//  for again as it scrolls: syntax highlighting, Markdown block parsing and inline
//  attributed strings.
//
//  SwiftUI re-evaluates a row's body whenever the transcript's row list changes,
//  and the row list changes on every streaming tick. Without a cache that means
//  re-tokenizing every visible code block and re-running the Markdown parser and
//  link regex over every visible paragraph, many times a second, for text that has
//  not changed since the last time.
//
//  The derivations are deterministic functions of their input, so remembering them
//  is safe. `NSCache` is thread-safe and evicts under memory pressure. Each entry is
//  charged by character count rather than by count, so one huge file read cannot
//  evict a screenful of small blocks, and the total cap keeps the cache proportional
//  to what is on screen rather than to the length of the session.
//

import Foundation

final class RenderCache<Value> {
    /// `NSCache` stores class values only, so the cached value is boxed.
    private final class Entry: NSObject {
        let value: Value

        init(_ value: Value) {
            self.value = value
        }
    }

    private let cache = NSCache<NSString, Entry>()

    init(totalCostLimit: Int) {
        cache.totalCostLimit = totalCostLimit
    }

    /// Returns the cached value for `key`, or computes, stores and returns it.
    /// `cost` is the value's size in characters and only affects eviction.
    func value(forKey key: String, cost: Int, make: () -> Value) -> Value {
        let nsKey = key as NSString
        if let hit = cache.object(forKey: nsKey) {
            return hit.value
        }
        let value = make()
        cache.setObject(Entry(value), forKey: nsKey, cost: max(cost, 1))
        return value
    }
}
