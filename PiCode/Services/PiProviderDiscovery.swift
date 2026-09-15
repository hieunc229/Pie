//
//  PiProviderDiscovery.swift
//  PiCode
//
//  Model discovery compatible with pi-setup-custom-providers: Ollama uses
//  `/api/tags`, Google uses `/v1beta/models`, and other discoverable adapters use
//  OpenAI-style `/models` candidates.
//

import Foundation

enum PiProviderDiscovery {
    static func discover(
        baseURL: String,
        api: String,
        apiKey: String?
    ) async throws -> ProviderDiscoveryResult {
        guard var base = URL(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = base.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            throw ProviderDiscoveryError.invalidEndpoint
        }
        while base.path.count > 1 && base.path.hasSuffix("/") { base.deleteLastPathComponent() }

        if api == "anthropic-messages" || api == "bedrock-converse-stream" {
            throw ProviderDiscoveryError.unsupportedAPI(api)
        }

        let endpoints = endpointCandidates(base: base, api: api)
        var lastFailure = "Could not connect to the provider."
        for endpoint in endpoints {
            do {
                let models = try await requestModels(endpoint: endpoint, api: api, apiKey: apiKey)
                if !models.isEmpty { return ProviderDiscoveryResult(endpoint: endpoint, models: models) }
                lastFailure = "\(endpoint.absoluteString) returned no models."
            } catch {
                lastFailure = error.localizedDescription
            }
        }
        if lastFailure.contains("returned no models") { throw ProviderDiscoveryError.noModels }
        throw ProviderDiscoveryError.unavailable(lastFailure)
    }

    private static func endpointCandidates(base: URL, api: String) -> [URL] {
        let raw = base.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if raw.lowercased().contains("ollama") || raw.contains(":11434") {
            let host = raw.replacingOccurrences(of: "/v1", with: "")
            return [URL(string: host + "/api/tags")].compactMap { $0 }
        }
        if api == "google-generative-ai" {
            let endpoint = raw.contains("/v1beta") ? raw + "/models" : raw + "/v1beta/models"
            return [URL(string: endpoint)].compactMap { $0 }
        }
        if raw.range(of: #"/v\d+$"#, options: .regularExpression) != nil {
            let rootModels = raw.replacingOccurrences(
                of: #"/v\d+$"#,
                with: "/models",
                options: .regularExpression
            )
            return [raw + "/models", rootModels].compactMap { URL(string: $0) }
        }
        return [raw + "/v1/models", raw + "/models"].compactMap { URL(string: $0) }
    }

    private static func requestModels(
        endpoint: URL,
        api: String,
        apiKey: String?
    ) async throws -> [PiProviderService.CustomModel] {
        var resolvedEndpoint = endpoint
        var request = URLRequest(url: endpoint, timeoutInterval: 12)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let key = resolvedKey(apiKey) {
            if api == "google-generative-ai" {
                var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
                let existingQueryItems = components?.queryItems ?? []
                components?.queryItems = existingQueryItems + [URLQueryItem(name: "key", value: key)]
                if let url = components?.url { resolvedEndpoint = url; request.url = url }
            } else {
                request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            }
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderDiscoveryError.unavailable("The provider did not return an HTTP response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ProviderDiscoveryError.unavailable(
                "\(resolvedEndpoint.host ?? "Provider") returned HTTP \(http.statusCode)."
            )
        }
        let value = try JSONCoding.decode(data)
        let rawModels = value.array("data") ?? value.array("models") ?? []
        var seen = Set<String>()
        return rawModels.compactMap(customModel).filter { seen.insert($0.id).inserted }
    }

    private static func customModel(_ value: JSONValue) -> PiProviderService.CustomModel? {
        let object = value.objectValue ?? [:]
        guard let id = object["id"]?.stringValue ?? object["name"]?.stringValue, !id.isEmpty else { return nil }
        let input = object["input"]?.arrayValue?.compactMap(\.stringValue)
            ?? object["input_modalities"]?.arrayValue?.compactMap(\.stringValue)
            ?? []
        let capabilities = object["capabilities"]?.objectValue ?? [:]
        let reasoning = object["reasoning"]?.boolValue
            ?? object["supports_reasoning"]?.boolValue
            ?? capabilities["reasoning"]?.boolValue
            ?? false
        let acceptsImages = input.contains(where: { $0.lowercased().contains("image") })
            || object["supports_vision"]?.boolValue == true
            || capabilities["vision"]?.boolValue == true
        let contextWindow = firstInteger(object, keys: [
            "contextWindow", "context_window", "context_length", "max_context_window", "max_input_tokens"
        ])
        let maxTokens = firstInteger(object, keys: [
            "maxTokens", "max_tokens", "max_output_tokens", "max_completion_tokens"
        ])
        return PiProviderService.CustomModel(
            id: id,
            name: object["name"]?.stringValue,
            reasoning: reasoning,
            acceptsImages: acceptsImages,
            contextWindow: contextWindow ?? 128_000,
            maxTokens: maxTokens ?? 16_384
        )
    }

    private static func firstInteger(_ object: [String: JSONValue], keys: [String]) -> Int? {
        for key in keys {
            if let value = object[key]?.doubleValue { return Int(value) }
            if let text = object[key]?.stringValue, let value = Int(text) { return value }
        }
        return nil
    }

    private static func resolvedKey(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        if value.hasPrefix("$") { return ProcessInfo.processInfo.environment[String(value.dropFirst())] }
        let dummy = ["no-key", "no-key-required", "sk-no-key-required", "dummy", "none", "local"]
        if dummy.contains(value.lowercased()) { return nil }
        // The package accepts `!command`; PiCode does not execute shell commands
        // from Settings. The saved reference remains valid for Pi itself.
        if value.hasPrefix("!") { return nil }
        return value
    }
}
