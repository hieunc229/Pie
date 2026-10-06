//
//  ProviderRegistry.swift
//  PiCode
//
//  PiCode-owned source of truth for third-party provider definitions. Harness
//  exporters translate this neutral catalog into each runtime's native file.
//

import Foundation

enum ProviderRegistry {
    static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("PiCode", isDirectory: true)
            .appendingPathComponent("providers.json")
    }

    /// Imports the old Pi-owned catalog once, then uses PiCode's registry.
    static func providers() -> [ProviderConfiguration] {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            return ProviderConfigurationStore.load(from: fileURL)
        }
        let migrated = PiProviderService.customProviders()
        if !migrated.isEmpty { try? save(migrated) }
        return migrated
    }

    static func save(_ providers: [ProviderConfiguration]) throws {
        try ProviderConfigurationStore.save(providers, to: fileURL)
    }

    /// Applies the complete neutral catalog. Removing a provider therefore also
    /// removes the PiCode-managed copy from every installed supported harness.
    static func synchronize(_ providers: [ProviderConfiguration],
                            with harnesses: Set<HarnessID>) throws {
        let providers = ProviderModelCapabilities.normalized(providers)
        if harnesses.contains(.pi) {
            try ProviderConfigurationStore.save(providers, to: PiPaths.modelsFile)
        }
        if harnesses.contains(.ohMyPi) {
            try OMPProviderService.saveCustomProviders(providers)
        }
        if harnesses.contains(.deepseekHarness) {
            try DSHProviderService.saveCustomProviders(providers)
        }
    }
}
