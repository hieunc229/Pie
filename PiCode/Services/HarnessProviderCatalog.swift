//
//  HarnessProviderCatalog.swift
//  PiCode
//
//  Translates the neutral provider registry into the subset each harness can
//  actually speak and into PiCode's canonical model-list payload.
//

import Foundation

enum HarnessProviderCatalog {
    static func providers(for harness: HarnessID) -> [ProviderConfiguration] {
        ProviderModelCapabilities.normalized(ProviderRegistry.providers()).filter { provider in
            switch harness {
            case .pi, .ohMyPi:
                return true
            case .deepseekHarness:
                guard let api = provider.api else { return false }
                return ["openai-completions", "openai-responses", "anthropic-messages"]
                    .contains(api)
            case .claudeCode:
                return provider.api == "anthropic-messages"
            case .codex:
                return provider.api == "openai-responses"
            case .opencode:
                return false
            }
        }
    }

    static func models(for harness: HarnessID) -> [JSONValue] {
        providers(for: harness).flatMap { provider in
            provider.models.map { model in
                var object: [String: JSONValue] = [
                    "id": .string(model.id),
                    "name": .string(model.displayName),
                    "provider": .string(provider.id),
                    "reasoning": .bool(model.reasoning),
                    "input": .array(model.acceptsImages
                        ? [.string("text"), .string("image")]
                        : [.string("text")])
                ]
                if let api = provider.api { object["api"] = .string(api) }
                if let baseURL = provider.baseURL { object["baseUrl"] = .string(baseURL) }
                if let contextWindow = model.contextWindow {
                    object["contextWindow"] = .number(Double(contextWindow))
                }
                if let maxTokens = model.maxTokens { object["maxTokens"] = .number(Double(maxTokens)) }
                if model.reasoning {
                    object["thinking"] = ProviderModelCapabilities.standardThinking
                }
                return .object(object)
            }
        }
    }

    static func provider(for modelSelection: String?, harness: HarnessID) -> ProviderConfiguration? {
        guard let modelSelection,
              let separator = modelSelection.firstIndex(of: "/") else { return nil }
        let providerID = String(modelSelection[..<separator])
        return providers(for: harness).first { $0.id == providerID }
    }

    static func providerID(for modelSelection: String?, fallback: String) -> String {
        guard let modelSelection,
              let separator = modelSelection.firstIndex(of: "/") else { return fallback }
        return String(modelSelection[..<separator])
    }

    static func supports(providerID: String, on harness: HarnessID) -> Bool {
        let nativeProvider: String?
        switch harness {
        case .deepseekHarness: nativeProvider = "deepseek-official"
        case .claudeCode: nativeProvider = "anthropic"
        case .codex: nativeProvider = "openai"
        case .pi, .ohMyPi: return true
        case .opencode: nativeProvider = nil
        }
        if harness == .opencode { return true }
        if providerID == nativeProvider { return true }
        return providers(for: harness).contains { $0.id == providerID }
    }

    static func apiKey(_ provider: ProviderConfiguration) -> String? {
        guard let value = provider.apiKey, !value.isEmpty else { return nil }
        if value.hasPrefix("$") { return ProcessInfo.processInfo.environment[String(value.dropFirst())] }
        if value.hasPrefix("!") { return nil }
        return value
    }
}
