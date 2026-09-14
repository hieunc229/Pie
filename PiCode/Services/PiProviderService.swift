//
//  PiProviderService.swift
//  PiCode
//
//  Providers, models, and credentials are Pi's, not PiCode's. This service only
//  reads and writes the files Pi itself documents, so anything configured here
//  also works in the terminal:
//
//  * `auth.json`   — Pi's credential store. `/login` writes it; PiCode writes only
//                    the documented `{ "type": "api_key", "key": "…" }` shape and
//                    never touches OAuth entries.
//  * `models.json` — Pi's custom/third-party provider catalog (OpenAI-compatible
//                    servers, Anthropic-compatible proxies, Google, local models).
//
//  Two rules keep this honest:
//
//  1. **Secrets are write-only.** A stored key is never read back into the UI or
//     into logs; PiCode shows a fingerprint (`sk-ant…4f2a`). References like
//     `$MY_KEY` or `!op read …` are configuration, not secrets, so they stay
//     visible.
//  2. **Nothing is written unless the user asks.** Every mutation is an explicit
//     call from Settings; there is no "fix it for me" path that runs on launch.
//
//  Readiness comes from Pi's own answer (`pi auth check --json --no-refresh`),
//  never from guessing: `--no-refresh` matters because the default would refresh
//  OAuth tokens, i.e. mutate Pi's credential file as a side effect of a status
//  query. `--credentials` is never used.
//

import Foundation

enum PiProviderService {

    // MARK: - Credentials in Pi's auth.json

    struct Credential: Identifiable, Equatable {
        enum Kind: Equatable {
            /// A literal secret. PiCode masks it after reading.
            case apiKey
            /// Provider-scoped environment map (`env` in Pi's format).
            case apiKeyWithEnvironment
            /// `$VAR` / `!command` reference — configuration, not a secret.
            case reference(String)
            case oauth
        }

        var provider: String
        var kind: Kind
        /// Masked form of a literal key: never the key itself.
        var fingerprint: String?

        var id: String { provider }

        var kindLabel: String {
            switch kind {
            case .apiKey: return "API key"
            case .apiKeyWithEnvironment: return "API key + environment"
            case .reference: return "Key reference"
            case .oauth: return "OAuth"
            }
        }
    }

    /// An entry Pi cannot read. Worth surfacing loudly: Pi's credential store
    /// fails as a whole, so *every* provider reports `invalid_state` while one
    /// malformed entry sits in the file.
    struct Problem: Identifiable, Equatable {
        var provider: String
        var reason: String

        var id: String { provider }
    }

    enum CredentialError: LocalizedError {
        case unreadableFile(String)
        case providerMissing(String)
        case emptyKey

        var errorDescription: String? {
            switch self {
            case .unreadableFile(let detail):
                return "Pi's auth.json could not be parsed: \(detail). Fix or remove the entry first; PiCode will not overwrite a file it cannot read."
            case .providerMissing(let provider):
                return "There is no credential for “\(provider)” to remove."
            case .emptyKey:
                return "The API key was empty."
            }
        }
    }

    // MARK: Reading

    /// Credentials Pi owns, with secrets reduced to fingerprints.
    static func credentials(at url: URL = PiPaths.authFile) -> [Credential] {
        guard let root = try? readObject(at: url) else { return [] }
        return root.keys.sorted().compactMap { provider in
            guard let entry = root[provider]?.objectValue else { return nil }
            switch entry["type"]?.stringValue {
            case "api_key":
                let key = entry["key"]?.stringValue
                let hasEnvironment = entry["env"]?.objectValue?.isEmpty == false
                if let key, key.hasPrefix("$") || key.hasPrefix("!") {
                    return Credential(provider: provider, kind: .reference(key), fingerprint: nil)
                }
                let kind: Credential.Kind = hasEnvironment ? .apiKeyWithEnvironment : .apiKey
                return Credential(provider: provider, kind: kind, fingerprint: key.map(fingerprint(of:)))
            case "oauth":
                return Credential(provider: provider, kind: .oauth, fingerprint: nil)
            default:
                return nil
            }
        }
    }

    /// Mirrors the validation Pi applies when it loads the file
    /// (`ReadOnlyAuthStorage.load`): one bad entry makes the whole store
    /// unreadable, which Pi reports only as `invalid_state`.
    static func problems(at url: URL = PiPaths.authFile) -> [Problem] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        guard let root = try? readObject(at: url) else {
            return [Problem(provider: url.lastPathComponent, reason: "the file is not a JSON object")]
        }
        var problems: [Problem] = []
        for provider in root.keys.sorted() {
            guard let entry = root[provider]?.objectValue else {
                problems.append(Problem(provider: provider, reason: "the entry is not an object"))
                continue
            }
            switch entry["type"]?.stringValue {
            case "api_key":
                let keyIsValid = entry["key"] == nil || entry["key"]?.stringValue != nil
                let environmentIsValid = entry["env"] == nil || (entry["env"]?.objectValue.map { env in
                    env.values.allSatisfy { $0.stringValue != nil }
                } ?? false)
                if !keyIsValid || !environmentIsValid {
                    problems.append(Problem(provider: provider, reason: "key/env must be strings"))
                }
            case "oauth":
                let hasAccess = entry["access"]?.stringValue != nil
                let hasRefresh = entry["refresh"]?.stringValue != nil
                let hasExpiry = entry["expires"]?.doubleValue.map { $0.isFinite } ?? false
                if !hasAccess || !hasRefresh || !hasExpiry {
                    problems.append(Problem(provider: provider, reason: "OAuth entry needs access, refresh, and expires"))
                }
            case .some(let other):
                problems.append(Problem(provider: provider, reason: "unknown type “\(other)”"))
            case nil:
                // This is the shape this machine actually had: a models.json
                // provider block pasted into auth.json. Pi cannot read it.
                problems.append(Problem(provider: provider, reason: "missing “type”; provider configuration belongs in models.json"))
            }
        }
        return problems
    }

    /// Providers Pi can currently use, as Pi itself reports them.
    enum Readiness: Equatable {
        case ready(authType: String)
        case unavailable(status: String, reason: String?)
        case unknown(String)

        var isReady: Bool { if case .ready = self { return true }; return false }

        var summary: String {
            switch self {
            case .ready(let authType):
                return authType == "oauth" ? "Ready · subscription" : "Ready"
            case .unavailable(_, let reason):
                // Pi answers with machine codes; say what they mean, because
                // "invalid_state" is what a *file* problem looks like.
                switch reason {
                case "invalid_state":
                    return "Pi could not load its credential or model configuration"
                case "credentials_not_configured":
                    return "No credentials configured"
                case "provider_not_found":
                    return "This Pi does not offer that provider"
                case .some(let other):
                    return other.replacingOccurrences(of: "_", with: " ")
                case nil:
                    return "Not ready"
                }
            case .unknown(let status):
                return status
            }
        }

        /// `invalid_state` is a file problem, not a provider problem. PiCode
        /// shows the offending entries next to this message instead of asking
        /// the user to guess.
        var isConfigurationFailure: Bool {
            if case .unavailable(_, let reason) = self { return reason == "invalid_state" }
            return false
        }
    }

    /// Asks Pi about each provider. `--no-refresh` keeps this a pure query.
    static func readiness(for providers: [String],
                          executable: URL,
                          shellPath: String?,
                          limit: Int = 8) async -> [String: Readiness] {
        let unique = Array(Set(providers)).sorted()
        guard !unique.isEmpty else { return [:] }
        let environment = PiDiscoveryService.launchEnvironment(executable: executable, shellPath: shellPath)
        let discovery = PiDiscoveryService()
        var results: [String: Readiness] = [:]
        // Pi spawns a Node process per check (~0.1 s each), so a small window
        // keeps the pane responsive without stampeding the machine.
        await withTaskGroup(of: (String, Readiness).self) { group in
            var index = 0
            func addNext() {
                guard index < unique.count else { return }
                let provider = unique[index]
                index += 1
                group.addTask {
                    let result = await discovery.run(
                        executable: executable,
                        arguments: ["auth", "check", "--provider", provider, "--json", "--no-refresh"],
                        directory: URL(fileURLWithPath: NSHomeDirectory()),
                        environment: environment
                    )
                    return (provider, parseReadiness(stdout: result.stdout, exitCode: result.exitCode))
                }
            }
            for _ in 0..<min(limit, unique.count) { addNext() }
            for await (provider, readiness) in group {
                results[provider] = readiness
                addNext()
            }
        }
        return results
    }

    static func parseReadiness(stdout: String, exitCode: Int32) -> Readiness {
        let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let line = trimmed.split(whereSeparator: \.isNewline).last(where: { $0.hasPrefix("{") }),
              let value = try? JSONCoding.decode(Data(line.utf8)),
              let status = value["status"]?.stringValue
        else {
            return .unknown(exitCode == 0 ? "no answer" : "check failed (exit \(exitCode))")
        }
        if status == "ready" {
            return .ready(authType: value["authType"]?.stringValue ?? "credentials")
        }
        return .unavailable(status: status, reason: value["reason"]?.stringValue)
    }

    // MARK: Writing credentials

    /// Stores an API key the way `/login` does. OAuth entries and unknown fields
    /// in the file are preserved; only this provider's `api_key` entry changes.
    static func setAPIKey(_ key: String, for provider: String, at url: URL = PiPaths.authFile) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CredentialError.emptyKey }
        var root = try mutableRoot(at: url)
        var entry = root[provider]?.objectValue ?? [:]
        entry["type"] = .string("api_key")
        entry["key"] = .string(trimmed)
        root[provider] = .object(entry)
        try write(.object(root), to: url)
    }

    static func removeCredential(for provider: String, at url: URL = PiPaths.authFile) throws {
        var root = try mutableRoot(at: url)
        guard root[provider] != nil else { throw CredentialError.providerMissing(provider) }
        root.removeValue(forKey: provider)
        try write(.object(root), to: url)
    }

    /// Drops entries Pi cannot read. Offered as an explicit repair because a
    /// single bad entry disables every provider; the user still chooses it.
    @discardableResult
    static func removeUnreadableEntries(at url: URL = PiPaths.authFile) throws -> [String] {
        let broken = Set(problems(at: url).map(\.provider))
        guard !broken.isEmpty else { return [] }
        var root = try mutableRoot(at: url)
        // A file that is not an object at all cannot be repaired selectively.
        guard root.isEmpty || !broken.contains(url.lastPathComponent) else {
            throw CredentialError.unreadableFile(url.lastPathComponent)
        }
        for provider in broken where root[provider] != nil { root.removeValue(forKey: provider) }
        try write(.object(root), to: url)
        return broken.sorted()
    }

    private static func mutableRoot(at url: URL) throws -> [String: JSONValue] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        do {
            return try readObject(at: url)
        } catch {
            throw CredentialError.unreadableFile(error.localizedDescription)
        }
    }

    private static func readObject(at url: URL) throws -> [String: JSONValue] {
        let data = try Data(contentsOf: url)
        guard let object = try JSONCoding.decode(data).objectValue else {
            throw CredentialError.unreadableFile("expected a JSON object")
        }
        return object
    }

    /// Writes `0600` like Pi does, via a sibling temporary file so an interrupted
    /// write cannot truncate credentials.
    static func write(_ value: JSONValue, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let temporary = directory.appendingPathComponent(".\(url.lastPathComponent).picode-\(UUID().uuidString)")
        let data = Data(JSONScanner.serialize(value, pretty: true).utf8)
        try data.write(to: temporary, options: [.atomic])
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

    static func fingerprint(of key: String) -> String {
        guard key.count > 10 else { return String(repeating: "•", count: max(key.count, 4)) }
        return "\(key.prefix(5))…\(key.suffix(4))"
    }

    // MARK: - Custom (third-party) providers in Pi's models.json

    struct CustomModel: Identifiable, Equatable {
        var id: String
        var name: String?
        var reasoning: Bool
        var acceptsImages: Bool
        var contextWindow: Int?
        var maxTokens: Int?

        var identifier: String { id }
        var displayName: String { name ?? id }
    }

    struct CustomProvider: Identifiable, Equatable {
        var id: String
        var baseURL: String?
        var api: String?
        var apiKey: String?
        var models: [CustomModel]
        /// Everything else Pi supports for this provider (`headers`, `oauth`,
        /// `compat`, `modelOverrides`, …), kept so editing here never drops it.
        var extra: [String: JSONValue] = [:]

        var isLocalServer: Bool {
            guard let baseURL, let host = URL(string: baseURL)?.host() else { return false }
            return host == "localhost" || host == "127.0.0.1" || host == "::1"
        }

        /// A literal key lives in plain text in Pi's file; a `$VAR`/`!command`
        /// reference does not. The UI says which one is in use.
        var keyIsReference: Bool {
            guard let apiKey else { return false }
            return apiKey.hasPrefix("$") || apiKey.hasPrefix("!")
        }
    }

    static let supportedAPIs = ["openai-completions", "openai-responses", "anthropic-messages", "google-generative-ai"]

    static func customProviders(at url: URL = PiPaths.modelsFile) -> [CustomProvider] {
        guard let root = try? readObject(at: url),
              let providers = root["providers"]?.objectValue
        else { return [] }
        return providers.keys.sorted().compactMap { id -> CustomProvider? in
            guard let entry = providers[id]?.objectValue else { return nil }
            var extra = entry
            for key in ["baseUrl", "api", "apiKey", "models"] { extra.removeValue(forKey: key) }
            let models = (entry["models"]?.arrayValue ?? []).compactMap { model -> CustomModel? in
                guard let object = model.objectValue, let modelId = object["id"]?.stringValue else { return nil }
                return CustomModel(
                    id: modelId,
                    name: object["name"]?.stringValue,
                    reasoning: object["reasoning"]?.boolValue ?? false,
                    acceptsImages: (object["input"]?.arrayValue ?? []).contains(.string("image")),
                    contextWindow: object["contextWindow"]?.doubleValue.map { Int($0) },
                    maxTokens: object["maxTokens"]?.doubleValue.map { Int($0) }
                )
            }
            return CustomProvider(
                id: id,
                baseURL: entry["baseUrl"]?.stringValue,
                api: entry["api"]?.stringValue,
                apiKey: entry["apiKey"]?.stringValue,
                models: models,
                extra: extra
            )
        }
    }

    /// Replaces the `providers` map while preserving the rest of the file,
    /// including per-model fields this UI does not edit.
    static func saveCustomProviders(_ providers: [CustomProvider], at url: URL = PiPaths.modelsFile) throws {
        var root: [String: JSONValue] = (try? readObject(at: url)) ?? [:]
        let previous = root["providers"]?.objectValue ?? [:]
        var encoded: [String: JSONValue] = [:]
        for provider in providers {
            var entry = provider.extra
            if let baseURL = provider.baseURL, !baseURL.isEmpty { entry["baseUrl"] = .string(baseURL) }
            else { entry.removeValue(forKey: "baseUrl") }
            if let api = provider.api, !api.isEmpty { entry["api"] = .string(api) }
            else { entry.removeValue(forKey: "api") }
            if let key = provider.apiKey, !key.isEmpty { entry["apiKey"] = .string(key) }
            else { entry.removeValue(forKey: "apiKey") }
            // Keep each model's unedited fields by merging onto its old object.
            let oldModels = (previous[provider.id]?.objectValue?["models"]?.arrayValue ?? [])
                .compactMap { $0.objectValue }
                .reduce(into: [String: [String: JSONValue]]()) { result, object in
                    if let id = object["id"]?.stringValue { result[id] = object }
                }
            entry["models"] = .array(provider.models.map { model in
                var object = oldModels[model.id] ?? [:]
                object["id"] = .string(model.id)
                if let name = model.name, !name.isEmpty, name != model.id { object["name"] = .string(name) }
                else { object.removeValue(forKey: "name") }
                object["reasoning"] = .bool(model.reasoning)
                object["input"] = .array(model.acceptsImages ? [.string("text"), .string("image")] : [.string("text")])
                if let window = model.contextWindow { object["contextWindow"] = .number(Double(window)) }
                else { object.removeValue(forKey: "contextWindow") }
                if let maxTokens = model.maxTokens { object["maxTokens"] = .number(Double(maxTokens)) }
                else { object.removeValue(forKey: "maxTokens") }
                return .object(object)
            })
            encoded[provider.id] = .object(entry)
        }
        if encoded.isEmpty { root.removeValue(forKey: "providers") }
        else { root["providers"] = .object(encoded) }
        try write(.object(root), to: url)
    }

    /// Problems Pi will complain about when it loads models.json. Pi reports
    /// these through `getError()` / `/model`; PiCode shows them next to the entry.
    static func customProviderProblems(at url: URL = PiPaths.modelsFile) -> [Problem] {
        guard let root = try? readObject(at: url), let providers = root["providers"]?.objectValue else { return [] }
        var problems: [Problem] = []
        for id in providers.keys.sorted() {
            guard let entry = providers[id]?.objectValue else {
                problems.append(Problem(provider: id, reason: "the entry is not an object"))
                continue
            }
            let modelAPIs = (entry["models"]?.arrayValue ?? []).compactMap { $0.objectValue?["api"]?.stringValue }
            let hasAPI = entry["api"]?.stringValue != nil || !modelAPIs.isEmpty
            if entry["baseUrl"]?.stringValue == nil {
                problems.append(Problem(provider: id, reason: "baseUrl is required for a custom provider"))
            } else if !hasAPI {
                problems.append(Problem(provider: id, reason: "api is required at provider or model level"))
            }
        }
        return problems
    }

    /// True when Pi is configured with the community wizard extension, in which
    /// case PiCode points at it instead of reimplementing model discovery.
    static func hasCustomProviderWizard(settingsURL: URL = PiPaths.settingsFile) -> Bool {
        guard let root = try? readObject(at: settingsURL),
              let packages = root["packages"]?.arrayValue
        else { return false }
        return packages.contains { ($0.stringValue ?? "").contains("pi-setup-custom-providers") }
    }
}
