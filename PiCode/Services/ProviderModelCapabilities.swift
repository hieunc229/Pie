//
//  ProviderModelCapabilities.swift
//  PiCode
//
//  Resolves model-level capabilities that provider catalogs expose under
//  different field names, including known reasoning aliases.
//

import Foundation

enum ProviderModelCapabilities {
    static let standardThinking: JSONValue = .object([
        "mode": .string("effort"),
        "efforts": .array(["low", "medium", "high"].map(JSONValue.string))
    ])

    static func supportsReasoning(modelID: String,
                                  declared: Bool,
                                  supportedParameters: [String] = []) -> Bool {
        if declared { return true }
        let parameters = Set(supportedParameters.map { $0.lowercased() })
        if !parameters.isDisjoint(with: [
            "reasoning", "reasoning_effort", "include_reasoning", "thinking"
        ]) {
            return true
        }

        let id = modelID.lowercased()
        return id.contains("deepseek-flash")
            || id.contains("deepseek-pro")
            || id.contains("deepseek-reasoner")
            || id.contains("deepseek-r1")
            || id.contains("/r1")
            || id.contains("reasoning")
            || id.contains("reasoner")
    }

    static func normalized(_ providers: [ProviderConfiguration]) -> [ProviderConfiguration] {
        providers.map { provider in
            var provider = provider
            provider.models = provider.models.map { model in
                var model = model
                model.reasoning = supportsReasoning(modelID: model.id, declared: model.reasoning)
                return model
            }
            return provider
        }
    }
}
