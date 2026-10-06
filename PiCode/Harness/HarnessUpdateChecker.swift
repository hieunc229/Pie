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
        await withTaskGroup(of: (HarnessID, Status).self) { group in
            for entry in entries {
                group.addTask {
                    let status = await Self.lookup(entry.descriptor, installed: entry.installed)
                    return (entry.descriptor.id, status)
                }
            }
            for await (id, status) in group { statuses[id] = status }
        }
    }

    private nonisolated static func lookup(_ descriptor: HarnessDescriptor, installed: String) async -> Status {
        guard let package = npmPackage(of: descriptor),
              let encoded = package.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://registry.npmjs.org/\(encoded)/latest")
        else { return .unknown }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let latest = object["version"] as? String,
              let latestParts = components(latest),
              let installedParts = components(installed)
        else { return .unknown }
        return installedParts.lexicographicallyPrecedes(latestParts) ? .available(latest) : .upToDate
    }

    private nonisolated static func npmPackage(of descriptor: HarnessDescriptor) -> String? {
        descriptor.installMethods.first { $0.kind == .npm }?
            .command.split(separator: " ").last.map(String.init)
    }

    /// The first dotted number in a version banner, e.g. "pi 0.4.2 (abc)" → [0, 4, 2].
    private nonisolated static func components(_ text: String) -> [Int]? {
        guard let range = text.range(of: #"\d+(\.\d+)+"#, options: .regularExpression) else { return nil }
        return text[range].split(separator: ".").compactMap { Int($0) }
    }
}
