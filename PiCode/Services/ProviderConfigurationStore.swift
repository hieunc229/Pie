//
//  ProviderConfigurationStore.swift
//  PiCode
//
//  Lossless JSON-backed storage shared by the neutral registry and exporters.
//

import Foundation

enum ProviderConfigurationStore {
    static func load(from url: URL) -> [ProviderConfiguration] {
        guard let root = try? readObject(at: url),
              let providers = root["providers"]?.objectValue else { return [] }
        return providers.keys.sorted().compactMap { id in
            guard let entry = providers[id]?.objectValue else { return nil }
            var extra = entry
            for key in ["baseUrl", "api", "apiKey", "models"] { extra.removeValue(forKey: key) }
            let models = (entry["models"]?.arrayValue ?? []).compactMap { value -> ProviderModelConfiguration? in
                guard let object = value.objectValue, let modelID = object["id"]?.stringValue else { return nil }
                return ProviderModelConfiguration(
                    id: modelID,
                    name: object["name"]?.stringValue,
                    reasoning: object["reasoning"]?.boolValue ?? false,
                    acceptsImages: (object["input"]?.arrayValue ?? []).contains(.string("image")),
                    contextWindow: object["contextWindow"]?.doubleValue.map { Int($0) },
                    maxTokens: object["maxTokens"]?.doubleValue.map { Int($0) }
                )
            }
            return ProviderConfiguration(
                id: id,
                baseURL: entry["baseUrl"]?.stringValue,
                api: entry["api"]?.stringValue,
                apiKey: entry["apiKey"]?.stringValue,
                models: models,
                extra: extra
            )
        }
    }

    static func save(
        _ providers: [ProviderConfiguration],
        to url: URL,
        modelTransform: ((ProviderModelConfiguration, inout [String: JSONValue]) -> Void)? = nil
    ) throws {
        var root = (try? readObject(at: url)) ?? [:]
        let previous = root["providers"]?.objectValue ?? [:]
        var encoded: [String: JSONValue] = [:]
        for provider in providers {
            var entry = provider.extra
            set(provider.baseURL, key: "baseUrl", in: &entry)
            set(provider.api, key: "api", in: &entry)
            set(provider.apiKey, key: "apiKey", in: &entry)
            let oldModels = (previous[provider.id]?.objectValue?["models"]?.arrayValue ?? [])
                .compactMap(\.objectValue)
                .reduce(into: [String: [String: JSONValue]]()) { result, object in
                    if let id = object["id"]?.stringValue { result[id] = object }
                }
            entry["models"] = .array(provider.models.map { model in
                var object = oldModels[model.id] ?? [:]
                object["id"] = .string(model.id)
                set(model.name == model.id ? nil : model.name, key: "name", in: &object)
                object["reasoning"] = .bool(model.reasoning)
                object["input"] = .array(model.acceptsImages
                    ? [.string("text"), .string("image")]
                    : [.string("text")])
                set(model.contextWindow, key: "contextWindow", in: &object)
                set(model.maxTokens, key: "maxTokens", in: &object)
                modelTransform?(model, &object)
                return .object(object)
            })
            encoded[provider.id] = .object(entry)
        }
        if encoded.isEmpty { root.removeValue(forKey: "providers") }
        else { root["providers"] = .object(encoded) }
        try write(.object(root), to: url)
    }

    private static func set(_ value: String?, key: String, in object: inout [String: JSONValue]) {
        if let value, !value.isEmpty { object[key] = .string(value) }
        else { object.removeValue(forKey: key) }
    }

    private static func set(_ value: Int?, key: String, in object: inout [String: JSONValue]) {
        if let value { object[key] = .number(Double(value)) }
        else { object.removeValue(forKey: key) }
    }

    private static func readObject(at url: URL) throws -> [String: JSONValue] {
        let data = try Data(contentsOf: url)
        guard let object = try JSONCoding.decode(data).objectValue else {
            throw NSError(domain: "PiCode.ProviderStore", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Expected a JSON object at \(url.path)."])
        }
        return object
    }

    private static func write(_ value: JSONValue, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let temporary = directory.appendingPathComponent(".\(url.lastPathComponent).picode-\(UUID().uuidString)")
        try Data(JSONScanner.serialize(value, pretty: true).utf8).write(to: temporary, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
            } else {
                try FileManager.default.moveItem(at: temporary, to: url)
            }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }
}
