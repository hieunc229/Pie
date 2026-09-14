//
//  ProjectTrustService.swift
//  PiCode
//
//  Mirrors Pi's project trust semantics instead of inventing a new promise.
//
//  Pi considers a directory to have trust-requiring resources when it finds:
//    - .pi/settings.json
//    - .pi/extensions, .pi/skills, .pi/prompts, .pi/themes
//    - .pi/SYSTEM.md, .pi/APPEND_SYSTEM.md
//    - a project .agents/skills directory in this or an ancestor directory
//      (the user-global ~/.agents/skills is always trusted)
//
//  Saved decisions live in `~/.pi/agent/trust.json` as `{ "<canonical path>": true|false }`
//  with nearest-ancestor lookup. That file is Pi's supported store (`/trust`
//  writes it), so PiCode writes the same format and does not maintain a rival
//  source of truth. Trust is an input-loading guard, not a sandbox.
//

import Foundation

struct ProjectTrustService {
    private let fileManager = FileManager.default

    /// Resource names under `.pi` that Pi gates behind trust.
    static let trustRequiringResources = [
        "settings.json",
        "extensions",
        "skills",
        "prompts",
        "themes",
        "SYSTEM.md",
        "APPEND_SYSTEM.md"
    ]

    // MARK: - Resource detection

    func hasTrustRequiringResources(cwd: String) -> Bool {
        let home = CanonicalPath.of(NSHomeDirectory())
        let userAgentsSkills = URL(fileURLWithPath: home)
            .appendingPathComponent(".agents/skills").path

        var current = CanonicalPath.of(cwd)
        let configDirectory = URL(fileURLWithPath: current).appendingPathComponent(".pi")
        for resource in Self.trustRequiringResources where fileManager.fileExists(
            atPath: configDirectory.appendingPathComponent(resource).path
        ) {
            return true
        }

        while true {
            let agentsSkills = URL(fileURLWithPath: current)
                .appendingPathComponent(".agents/skills").path
            if agentsSkills != userAgentsSkills, fileManager.fileExists(atPath: agentsSkills) {
                return true
            }
            let parent = (current as NSString).deletingLastPathComponent
            if parent == current || parent.isEmpty { return false }
            current = parent
        }
    }

    // MARK: - Saved decisions

    /// Contents of the trust store, or an empty dictionary when absent.
    func trustStore() -> [String: Bool] {
        guard let data = try? Data(contentsOf: PiPaths.trustFile),
              let json = try? JSONCoding.decode(data),
              let object = json.objectValue else { return [:] }
        var result: [String: Bool] = [:]
        for (key, value) in object {
            if let decision = value.boolValue { result[key] = decision }
        }
        return result
    }

    /// Nearest saved decision for `cwd` or one of its ancestors.
    func savedDecision(cwd: String) -> (path: String, decision: Bool)? {
        let store = trustStore()
        var current = CanonicalPath.of(cwd)
        while true {
            if let decision = store[current] { return (current, decision) }
            let parent = (current as NSString).deletingLastPathComponent
            if parent == current || parent.isEmpty { return nil }
            current = parent
        }
    }

    /// Global `defaultProjectTrust` setting from Pi's settings file.
    func defaultProjectTrust() -> String {
        guard let data = try? Data(contentsOf: PiPaths.settingsFile),
              let json = try? JSONCoding.decode(data) else { return "ask" }
        return json.string("defaultProjectTrust") ?? "ask"
    }

    // MARK: - State

    func state(for cwd: String) -> ProjectTrustState {
        guard hasTrustRequiringResources(cwd: cwd) else { return .notRequired }
        guard let saved = savedDecision(cwd: cwd) else { return .asked }
        return saved.decision ? .trusted : .untrusted
    }

    /// Effective decision for a run, matching `resolveProjectTrusted` in RPC mode:
    /// non-interactive modes never prompt, so an unresolved project falls back to
    /// `defaultProjectTrust` (`ask`/`never` ignore resources, `always` trusts).
    func effectiveTrust(cwd: String) -> Bool {
        guard hasTrustRequiringResources(cwd: cwd) else { return true }
        if let saved = savedDecision(cwd: cwd) { return saved.decision }
        switch defaultProjectTrust() {
        case "always": return true
        default: return false
        }
    }

    /// Arguments that pin Pi's trust behavior for one RPC run so the session
    /// always matches the trust state shown in the UI.
    func launchArguments(cwd: String) -> [String] {
        effectiveTrust(cwd: cwd) ? ["--approve"] : ["--no-approve"]
    }

    // MARK: - Writing

    /// Persists a decision using Pi's store. `nil` clears the entry so the
    /// ancestor/default rules apply again.
    @discardableResult
    func setDecision(cwd: String, decision: Bool?) throws -> Bool {
        let path = CanonicalPath.of(cwd)
        return try withTrustLock {
            var store = trustStore()
            if let decision {
                store[path] = decision
            } else {
                store.removeValue(forKey: path)
            }
            try write(store: store)
            return true
        }
    }

    /// Trusts the immediate parent folder, matching Pi's "Trust parent folder"
    /// option: the parent is trusted and the child's own entry is cleared.
    @discardableResult
    func trustParentFolder(of cwd: String) throws -> Bool {
        let child = CanonicalPath.of(cwd)
        let parent = (child as NSString).deletingLastPathComponent
        guard parent != child, !parent.isEmpty else { return false }
        return try withTrustLock {
            var store = trustStore()
            store[parent] = true
            store.removeValue(forKey: child)
            try write(store: store)
            return true
        }
    }

    private func write(store: [String: Bool]) throws {
        var object: [String: JSONValue] = [:]
        for (key, value) in store { object[key] = .bool(value) }
        // Written through the shared scanner so trust.json matches the rest of
        // PiCode's output (sorted keys, one trailing newline) without relying on
        // the recursive `Codable` conformance.
        var data = Data(JSONScanner.serialize(.object(object), pretty: true).utf8)
        data.append(0x0A)
        try FileManager.default.createDirectory(
            at: PiPaths.agentDirectory,
            withIntermediateDirectories: true
        )
        try data.write(to: PiPaths.trustFile, options: .atomic)
    }

    // MARK: - Locking

    /// `proper-lockfile` (used by Pi) creates `<file>.lock` as a directory.
    /// PiCode uses the same lock path and mkdir strategy so concurrent writers
    /// do not interleave, with stale-lock recovery for crashed writers.
    private func withTrustLock<T>(_ body: () throws -> T) throws -> T {
        let lockURL = URL(fileURLWithPath: PiPaths.trustFile.path + ".lock")
        try FileManager.default.createDirectory(
            at: lockURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var acquired = false
        for _ in 0..<40 {
            if (try? FileManager.default.createDirectory(
                at: lockURL,
                withIntermediateDirectories: false
            )) != nil {
                acquired = true
                break
            }
            // Recover from a stale lock left by a crashed process.
            if let attributes = try? FileManager.default.attributesOfItem(atPath: lockURL.path),
               let modified = attributes[.modificationDate] as? Date,
               Date().timeIntervalSince(modified) > 15 {
                try? FileManager.default.removeItem(at: lockURL)
                continue
            }
            Thread.sleep(forTimeInterval: 0.02)
        }

        defer { if acquired { try? FileManager.default.removeItem(at: lockURL) } }
        guard acquired else {
            throw NSError(
                domain: "PiCode.Trust",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not lock Pi's trust store. Try again."]
            )
        }
        return try body()
    }
}
