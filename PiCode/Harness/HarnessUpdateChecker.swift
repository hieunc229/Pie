//
//  HarnessUpdateChecker.swift
//  PiCode
//
//  Looks up the newest published version of each installed harness from the
//  npm registry, so Settings can say when an update exists.
//

import Foundation
import Observation

@MainActor
@Observable
final class HarnessUpdateChecker {
    enum Status: Equatable {
        case checking
        case upToDate
        case available(String)
        case unknown
    }

    private(set) var statuses: [HarnessID: Status] = [:]

    func status(for id: HarnessID) -> Status? { statuses[id] }

    /// Checks every descriptor in `entries` (id, descriptor, installed version).
    func check(_ entries: [(descriptor: HarnessDescriptor, installed: String)]) async {
        for entry in entries { statuses[entry.descriptor.id] = .checking }
        await withTaskGroup(of: (HarnessID, Status, String?).self) { group in
            for entry in entries {
                group.addTask {
                    let status = await Self.lookup(entry.descriptor, installed: entry.installed)
                    return (entry.descriptor.id, status.0, status.1)
                }
            }
            for await (id, status, tag) in group { statuses[id] = status; tags[id] = tag }
        }
    }

    /// npm dist-tag that carries the available version, so the update installs
    /// `pkg@tag` rather than whatever `latest` points at.
    private(set) var tags: [HarnessID: String] = [:]

    private nonisolated static func lookup(_ descriptor: HarnessDescriptor,
                                           installed: String) async -> (Status, String?) {
        guard let package = npmPackage(of: descriptor),
              let encoded = package.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://registry.npmjs.org/-/package/\(encoded)/dist-tags")
        else { return (.unknown, nil) }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let tags = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let current = SemVer(installed)
        else { return (.unknown, nil) }
        // A stable install follows `latest`. A pre-release install (0.2.0-rc.2)
        // also follows tags on the same pre-release line, since `latest` may lag.
        let line = current.preLabel
        var best: (tag: String, version: SemVer, text: String)?
        for (tag, text) in tags {
            guard let version = SemVer(text) else { continue }
            let eligible = tag == "latest"
                || (line != nil && version.preLabel == line)
            guard eligible, best == nil || version > best!.version else { continue }
            best = (tag, version, text)
        }
        guard let best else { return (.unknown, nil) }
        return best.version > current ? (.available(best.text), best.tag) : (.upToDate, nil)
    }

    /// Semantic version with pre-release ordering (1.0.0-rc.2 < 1.0.0).
    private nonisolated struct SemVer: Comparable {
        var core: [Int]
        var pre: [String]
        var preLabel: String? { pre.first }

        init?(_ text: String) {
            guard let range = text.range(of: #"\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?"#, options: .regularExpression)
            else { return nil }
            let parts = text[range].split(separator: "-", maxSplits: 1)
            core = parts[0].split(separator: ".").compactMap { Int($0) }
            pre = parts.count > 1 ? parts[1].split(separator: ".").map(String.init) : []
        }

        static func < (l: SemVer, r: SemVer) -> Bool {
            if l.core != r.core { return l.core.lexicographicallyPrecedes(r.core) }
            if l.pre.isEmpty != r.pre.isEmpty { return !l.pre.isEmpty }
            for (a, b) in zip(l.pre, r.pre) where a != b {
                if let x = Int(a), let y = Int(b) { return x < y }
                return a < b
            }
            return l.pre.count < r.pre.count
        }
    }

    /// The command that updates the copy PiCode actually launches, in the package
    /// manager that installed it. Falls back to the descriptor's npm install.
    static func updateMethod(for descriptor: HarnessDescriptor,
                             installation: HarnessInstallation?,
                             tag: String?) -> HarnessInstallMethod? {
        let real = installation.map { $0.executableURL.resolvingSymlinksInPath().path } ?? ""
        let linked = installation?.executableURL.path ?? ""
        // Claude Code's native installer keeps versions outside node_modules.
        if descriptor.id == .claudeCode, !real.contains("/node_modules/"),
           let exe = installation?.executableURL.path {
            let quoted = "'" + exe.replacingOccurrences(of: "'", with: "'\\''") + "'"
            return HarnessInstallMethod(kind: .script, label: "claude update", command: "claude update",
                                        shellScript: "\(quoted) update")
        }
        guard let npm = descriptor.installMethods.first(where: { $0.kind == .npm }),
              let package = npmPackage(of: descriptor) else {
            return descriptor.installMethods.first
        }
        let target = tag.map { "\(package)@\($0)" } ?? "\(package)@latest"
        if real.contains("/.bun/") || linked.contains("/.bun/") {
            return HarnessInstallMethod(kind: .bun, label: "bun", command: "bun install -g \(target)")
        }
        let flags = npm.command.contains("--ignore-scripts") ? " --ignore-scripts" : ""
        return HarnessInstallMethod(kind: .npm, label: "npm", command: "npm install -g\(flags) \(target)")
    }

    nonisolated static func npmPackage(of descriptor: HarnessDescriptor) -> String? {
        descriptor.installMethods.first { $0.kind == .npm }?
            .command.split(separator: " ").last.map(String.init)
    }

    /// The first dotted number in a version banner, e.g. "pi 0.4.2 (abc)" → [0, 4, 2].
    private nonisolated static func components(_ text: String) -> [Int]? {
        guard let range = text.range(of: #"\d+(\.\d+)+"#, options: .regularExpression) else { return nil }
        return text[range].split(separator: ".").compactMap { Int($0) }
    }
}
