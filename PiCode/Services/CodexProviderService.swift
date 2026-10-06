//
//  CodexProviderService.swift
//  PiCode
//
//  Converts one neutral Responses-compatible provider into ephemeral Codex
//  configuration overrides. Nothing is written into the user's Codex config.
//


import Foundation

enum CodexProviderService {
    private static let apiKeyEnvironment = "PICODE_CODEX_PROVIDER_API_KEY"

    static func configurationArguments(for provider: ProviderConfiguration) -> [String] {
        var values = [
            "model_provider=\(tomlString(provider.id))",
            "model_providers.\(tomlString(provider.id)).name=\(tomlString(provider.id))",
            "model_providers.\(tomlString(provider.id)).wire_api=\(tomlString("responses"))",
            "model_providers.\(tomlString(provider.id)).requires_openai_auth=false"
        ]
        if let baseURL = provider.baseURL, !baseURL.isEmpty {
            values.append("model_providers.\(tomlString(provider.id)).base_url=\(tomlString(baseURL))")
        }
        if HarnessProviderCatalog.apiKey(provider) != nil {
            values.append("model_providers.\(tomlString(provider.id)).env_key=\(tomlString(apiKeyEnvironment))")
        }
        return values.flatMap { ["-c", $0] }
    }

    static func launchEnvironment(for provider: ProviderConfiguration) -> [String: String] {
        guard let apiKey = HarnessProviderCatalog.apiKey(provider) else { return [:] }
        return [apiKeyEnvironment: apiKey]
    }

    private static func tomlString(_ value: String) -> String {
        JSONScanner.serialize(.string(value))
    }
}
