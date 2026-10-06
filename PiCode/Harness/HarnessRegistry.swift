//
//  HarnessRegistry.swift
//  PiCode
//
//  Detects which coding-agent harnesses are installed on this Mac and remembers
//  the user's default. Detection is read-only; installation is a separate,
//  explicitly confirmed action in `HarnessInstallService`.
//

import Foundation
import Observation

@Observable
@MainActor
final class HarnessRegistry {
    /// Harnesses found on disk, keyed by id.
    private(set) var installations: [HarnessID: HarnessInstallation] = [:]
    /// Human-readable reason when a harness is not installed.
    private(set) var missingDetail: [HarnessID: String] = [:]
    private(set) var isDiscovering = false
    private(set) var lastRefreshedAt: Date?

    /// The catalog, in menu order.
    var descriptors: [HarnessDescriptor] { HarnessDescriptor.all }

    func descriptor(for id: HarnessID) -> HarnessDescriptor {
        HarnessDescriptor.descriptor(for: id)
    }

    func installation(for id: HarnessID) -> HarnessInstallation? { installations[id] }

    func isInstalled(_ id: HarnessID) -> Bool { installations[id] != nil }

    var installedHarnessIDs: Set<HarnessID> { Set(installations.keys) }

    /// Harnesses that are both installed and have a working adapter, so a session
    /// can actually start.
    var usableHarnesses: [HarnessDescriptor] {
        descriptors.filter { $0.hasAdapter && installations[$0.id] != nil }
    }

    /// Discovers every catalog harness. A login-shell miss for one harness never
    /// blocks the others.
    func refresh() async {
        guard !isDiscovering else { return }
        isDiscovering = true
        defer {
            isDiscovering = false
            lastRefreshedAt = Date()
        }

        let descriptors = self.descriptors
        await withTaskGroup(of: (HarnessID, HarnessDiscoveryResult).self) { group in
            for descriptor in descriptors {
                group.addTask {
                    let result = await HarnessDiscoveryService(descriptor: descriptor).discover()
                    return (descriptor.id, result)
                }
            }
            for await (id, result) in group {
                switch result {
                case .found(let installation):
                    installations[id] = installation
                    missingDetail[id] = nil
                case .missing(_, let detail):
                    installations[id] = nil
                    missingDetail[id] = detail
                }
            }
        }
    }

    func refresh(_ id: HarnessID) async {
        let result = await HarnessDiscoveryService(descriptor: descriptor(for: id)).discover()
        switch result {
        case .found(let installation):
            installations[id] = installation
            missingDetail[id] = nil
        case .missing(_, let detail):
            installations[id] = nil
            missingDetail[id] = detail
        }
    }
}
