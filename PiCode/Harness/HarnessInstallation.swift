//
//  HarnessInstallation.swift
//  PiCode
//
//  A harness executable PiCode found on this Mac and verified with
//  `--version`. Nothing here is harness-specific beyond the id.
//

import Foundation

struct HarnessInstallation: Equatable, Sendable {
    var harnessID: HarnessID = .pi
    var executableURL: URL
    var version: String
    /// PATH from the login shell, forwarded to the child process so the harness
    /// can resolve its own runtime (Node, Bun) and dependencies.
    var shellPath: String?
    var shell: String?
    /// How the executable was located, for diagnostics.
    var origin: String

    var displayPath: String { executableURL.path.abbreviatingHomeDirectory }
}

/// Pi is the original harness, so the existing `PiInstallation` name keeps
/// working while the rest of the app migrates to `HarnessInstallation`.
typealias PiInstallation = HarnessInstallation
