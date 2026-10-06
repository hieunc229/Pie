//
//  HarnessInstallEnvironment.swift
//  PiCode
//
//  Prepares package-manager installs for a GUI app. Global npm/pnpm installs
//  use directories owned by the current user, and JavaScript installers prefer
//  the newest Node version manager runtime already present on the Mac.
//

import Foundation

enum HarnessInstallEnvironment {
    static func plan(for method: HarnessInstallMethod) -> HarnessInstallPlan {
        switch method.kind {
        case .npm:
            return npmPlan(command: method.shellScript)
        case .bun:
            return bunPlan(command: method.shellScript)
        case .pnpm:
            return pnpmPlan(command: method.shellScript)
        case .pip, .brew, .script:
            return HarnessInstallPlan(script: method.shellScript, notes: [])
        }
    }

    private static func npmPlan(command: String) -> HarnessInstallPlan {
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let prefix = home.appendingPathComponent(".local", isDirectory: true).path
        let cache = home.appendingPathComponent("Library/Caches/PiCode/npm", isDirectory: true).path
        var exports = [
            "export npm_config_prefix=\(shellQuote(prefix))",
            "export npm_config_cache=\(shellQuote(cache))"
        ]
        var notes = ["Using user-owned npm prefix \(prefix.abbreviatingHomeDirectory)."]

        if let nodeBin = preferredNodeBinDirectory() {
            exports.insert("export PATH=\(shellQuote(nodeBin)):\"$PATH\"", at: 0)
            notes.append("Using Node runtime from \(nodeBin.abbreviatingHomeDirectory).")
        }

        let setup = "mkdir -p \(shellQuote(prefix + "/bin")) \(shellQuote(cache))"
        return HarnessInstallPlan(
            script: ([setup] + exports + [command]).joined(separator: "; "),
            notes: notes
        )
    }

    private static func bunPlan(command: String) -> HarnessInstallPlan {
        let bin = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent(".bun/bin", isDirectory: true).path
        return HarnessInstallPlan(
            script: "export PATH=\(shellQuote(bin)):\"$PATH\"; \(command)",
            notes: ["Using Bun from \(bin.abbreviatingHomeDirectory)."]
        )
    }

    private static func pnpmPlan(command: String) -> HarnessInstallPlan {
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let pnpmHome = home.appendingPathComponent("Library/pnpm", isDirectory: true).path
        let setup = "mkdir -p \(shellQuote(pnpmHome))"
        let exports = "export PNPM_HOME=\(shellQuote(pnpmHome)); export PATH=\(shellQuote(pnpmHome)):\"$PATH\""
        return HarnessInstallPlan(
            script: "\(setup); \(exports); \(command)",
            notes: ["Using user-owned pnpm home \(pnpmHome.abbreviatingHomeDirectory)."]
        )
    }

    /// The newest version-manager Node already installed by the user. Putting it
    /// before a stale system Node prevents both npm `unsupported engine` errors
    /// and failures when the installed CLI later runs its `/usr/bin/env node`
    /// shebang.
    static func preferredNodeBinDirectory() -> String? {
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let nvmRoot = home.appendingPathComponent(".nvm/versions/node", isDirectory: true)
        let nvmBins = ((try? FileManager.default.contentsOfDirectory(
            at: nvmRoot,
            includingPropertiesForKeys: nil
        )) ?? [])
            .compactMap { versionDirectory -> (version: [Int], path: String)? in
                let components = versionDirectory.lastPathComponent
                    .trimmingCharacters(in: CharacterSet(charactersIn: "v"))
                    .split(separator: ".")
                    .compactMap { Int($0) }
                let bin = versionDirectory.appendingPathComponent("bin", isDirectory: true)
                let node = bin.appendingPathComponent("node").path
                guard components.count >= 2,
                      FileManager.default.isExecutableFile(atPath: node) else { return nil }
                return (components, bin.path)
            }
            .sorted { compareVersions($0.version, $1.version) }

        if let newest = nvmBins.last?.path { return newest }

        let otherBins = [
            home.appendingPathComponent(".volta/bin", isDirectory: true).path,
            "/opt/homebrew/opt/node/bin",
            "/usr/local/opt/node/bin"
        ]
        return otherBins.first {
            FileManager.default.isExecutableFile(
                atPath: URL(fileURLWithPath: $0).appendingPathComponent("node").path
            )
        }
    }

    private static func compareVersions(_ lhs: [Int], _ rhs: [Int]) -> Bool {
        for index in 0..<max(lhs.count, rhs.count) {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
