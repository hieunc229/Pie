//
//  DSHProviderService.swift
//  PiCode
//
//  Builds a PiCode-owned DeepSeek Harness profile patch. Credentials remain out
//  of the patch and are injected into the child process environment.
//

import Foundation

enum DSHProviderService {
    static var patchFile: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("PiCode/Harnesses/deepseek-providers.json")
    }

    static func saveCustomProviders(_ providers: [ProviderConfiguration]) throws {
        var routes: [String: JSONValue] = [:]
        for (index, provider) in providers.sorted(by: { $0.id < $1.id }).enumerated() {
            var route: [String: JSONValue] = [:]
            if let api = provider.api { route["api"] = .string(api) }
            if let baseURL = provider.baseURL { route["baseURL"] = .string(baseURL) }
            if provider.apiKey != nil { route["apiKeyEnv"] = .string(environmentKey(index: index)) }
            for key in ["compat", "headers", "reasoning", "thinkingBudgets", "transport"] {
                if let value = provider.extra[key] { route[key] = value }
            }
            route["models"] = .array(provider.models.map { model in
                var object: [String: JSONValue] = [
                    "id": .string(model.id),
                    "input": .array(model.acceptsImages
                        ? [.string("text"), .string("image")]
                        : [.string("text")])
                ]
                if let name = model.name { object["name"] = .string(name) }
                if let contextWindow = model.contextWindow {
                    object["contextWindow"] = .number(Double(contextWindow))
                }
                if let maxTokens = model.maxTokens { object["maxTokens"] = .number(Double(maxTokens)) }
                if model.reasoning {
                    object["reasoningEfforts"] = .object([
                        "off": .null,
                        "low": .string("low"),
                        "medium": .string("medium"),
                        "high": .string("high")
                    ])
                }
                return .object(object)
            })
            routes[provider.id] = .object(route)
        }

        let patch: JSONValue = .array([.object([
            "id": .string("llm-pi-ai"),
            "config": .object(["providers": .object(routes)])
        ])])
        let directory = patchFile.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try Data(JSONScanner.serialize(patch, pretty: true).utf8).write(to: patchFile, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: patchFile.path)
    }

    static func launchEnvironment(_ providers: [ProviderConfiguration]) -> [String: String] {
        var result: [String: String] = [:]
        for (index, provider) in providers.sorted(by: { $0.id < $1.id }).enumerated() {
            if let apiKey = HarnessProviderCatalog.apiKey(provider) {
                result[environmentKey(index: index)] = apiKey
            }
        }
        return result
    }

    private static func environmentKey(index: Int) -> String {
        "PICODE_DSH_PROVIDER_\(index)_API_KEY"
    }
}
