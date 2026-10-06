//
//  ProviderConfigurationTypes.swift
//  PiCode
//
//  Harness-neutral third-party provider configuration.
//

import Foundation

struct ProviderModelConfiguration: Identifiable, Equatable {
    var id: String
    var name: String?
    var reasoning: Bool
    var acceptsImages: Bool
    var contextWindow: Int?
    var maxTokens: Int?

    var identifier: String { id }
    var displayName: String { name ?? id }
}

struct ProviderConfiguration: Identifiable, Equatable {
    var id: String
    var baseURL: String?
    var api: String?
    var apiKey: String?
    var models: [ProviderModelConfiguration]
    /// Fields not exposed by PiCode's editor. Native exporters preserve these
    /// where the target harness supports the same wire shape.
    var extra: [String: JSONValue] = [:]

    var isLocalServer: Bool {
        guard let baseURL, let host = URL(string: baseURL)?.host() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }

    var keyIsReference: Bool {
        guard let apiKey else { return false }
        return apiKey.hasPrefix("$") || apiKey.hasPrefix("!")
    }
}
