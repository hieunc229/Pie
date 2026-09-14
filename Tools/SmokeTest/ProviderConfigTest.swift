//
//  Provider configuration smoke test.
//
//  PiCode writes two files Pi owns — `auth.json` (credentials) and `models.json`
//  (custom providers). Guessing their format is not acceptable, so every check
//  here asks Pi itself to confirm the result: `pi auth check` for credentials and
//  a real `pi --mode rpc` `get_available_models` for custom providers.
//
//  Everything happens in a throwaway `PI_CODING_AGENT_DIR`, so the user's own
//  credentials are never read, written, or printed. No model is called: Pi's auth
//  check explicitly disables model network access, and `get_available_models`
//  only reads the local catalog. No credits are spent.
//
//      ./Tools/SmokeTest/run-providers.sh
//

import Foundation

@main
enum ProviderConfigTest {
    static func main() async {
        exit(await runProviders())
    }
}

let executable = URL(fileURLWithPath: "/usr/bin/env")

func runProviders() async -> Int32 {
    var failures = 0
    func check(_ name: String, _ condition: Bool, _ detail: String = "") {
        if condition {
            print("  ok   \(name)\(detail.isEmpty ? "" : " — \(detail)")")
        } else {
            failures += 1
            print("  FAIL \(name)\(detail.isEmpty ? "" : " — \(detail)")")
        }
    }

    guard let root = ProcessInfo.processInfo.environment["PI_CODING_AGENT_DIR"].map({ URL(fileURLWithPath: $0) }),
          ProcessInfo.processInfo.environment["PICODE_TEST_PI"] != nil
    else {
        print("This harness must be run through Tools/SmokeTest/run-providers.sh")
        return 2
    }
    let pi = URL(fileURLWithPath: ProcessInfo.processInfo.environment["PICODE_TEST_PI"]!)
    let discovery = PiDiscoveryService()
    let environment = PiDiscoveryService.launchEnvironment(executable: pi, shellPath: nil)

    func piAuthCheck(_ provider: String) async -> PiProviderService.Readiness {
        let result = await discovery.run(
            executable: pi,
            arguments: ["auth", "check", "--provider", provider, "--json", "--no-refresh"],
            directory: URL(fileURLWithPath: NSHomeDirectory()),
            environment: environment
        )
        return PiProviderService.parseReadiness(stdout: result.stdout, exitCode: result.exitCode)
    }

    let authFile = root.appendingPathComponent("auth.json")
    let modelsFile = root.appendingPathComponent("models.json")

    print("== a fresh Pi configuration directory ==")
    check("nothing is configured yet", PiProviderService.credentials(at: authFile).isEmpty)
    check("nothing is reported as broken", PiProviderService.problems(at: authFile).isEmpty)

    print("== PiCode's readiness answer matches Pi's own ==")
    // Pick a provider this shell has no credentials for: provider API keys can
    // also come from environment variables, and those count as configured.
    let unconfigured = "minimax"
    let before = await piAuthCheck(unconfigured)
    check("unconfigured provider is not ready", !before.isReady, before.summary)

    print("== storing an API key the way /login does ==")
    let secret = "sk-ant-test-0123456789abcdef"
    let keyedProvider = "ant-ling"
    do {
        try PiProviderService.setAPIKey(secret, for: keyedProvider, at: authFile)
    } catch {
        check("write an API key", false, String(describing: error))
        return 1
    }
    check("Pi's auth.json now exists", FileManager.default.fileExists(atPath: authFile.path))
    let attributes = try? FileManager.default.attributesOfItem(atPath: authFile.path)
    let mode = (attributes?[.posixPermissions] as? NSNumber)?.intValue ?? 0
    check("the file is 0600 like Pi writes it", mode == 0o600, String(format: "0o%o", mode))

    let ready = await piAuthCheck(keyedProvider)
    check("Pi accepts the credential PiCode wrote", ready.isReady, ready.summary)
    if case .ready(let authType) = ready { check("Pi reads it as an API key", authType == "api_key", authType) }

    print("== the secret never reaches the UI layer ==")
    let summaries = PiProviderService.credentials(at: authFile)
    check("the provider is listed", summaries.map(\.provider) == [keyedProvider])
    let rendered = String(describing: summaries) + summaries.map { "\($0.kind)\($0.kindLabel)\($0.fingerprint ?? "")" }.joined()
    check("no summary contains the raw key", !rendered.contains(secret))
    check("the fingerprint is masked", summaries.first?.fingerprint?.contains("…") == true,
          summaries.first?.fingerprint ?? "none")
    check("the file itself is the only place the key lives",
          (try? String(contentsOf: authFile, encoding: .utf8))?.contains(secret) == true)

    print("== the file is written atomically ==")
    let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: root.path))?
        .filter { $0.contains(".picode-") } ?? []
    check("no temporary files are left behind", leftovers.isEmpty, leftovers.joined(separator: ", "))

    print("== editing one provider leaves the others alone ==")
    // Seed an OAuth entry (with an unknown extra field) the way /login would.
    let seeded = """
    {
      "openai": { "type": "oauth", "access": "a", "refresh": "r", "expires": 9999999999999, "accountId": "keep-me" },
      "deepseek": { "type": "api_key", "key": "$DEEPSEEK_API_KEY" }
    }
    """
    try? seeded.write(to: authFile, atomically: true, encoding: .utf8)
    try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: authFile.path)
    try? PiProviderService.setAPIKey(secret, for: keyedProvider, at: authFile)
    let merged = (try? String(contentsOf: authFile, encoding: .utf8)) ?? ""
    let kinds = PiProviderService.credentials(at: authFile)
    check("the OAuth entry survives", kinds.contains { $0.provider == "openai" && $0.kind == .oauth })
    check("its unknown field survives", merged.contains("keep-me"))
    check("a $VAR reference stays visible, not masked",
          kinds.contains { $0.provider == "deepseek" && $0.kind == .reference("$DEEPSEEK_API_KEY") })
    check("the new key was added", kinds.contains { $0.provider == keyedProvider })

    try? PiProviderService.removeCredential(for: keyedProvider, at: authFile)
    let afterRemoval = PiProviderService.credentials(at: authFile)
    check("removing one provider keeps the rest", afterRemoval.map(\.provider) == ["deepseek", "openai"])

    print("== one unreadable entry disables every provider ==")
    // This is not hypothetical: a models.json provider block pasted into
    // auth.json makes Pi report `invalid_state` for every provider at once.
    let broken = """
    {
      "deepseek": { "baseUrl": "https://api.deepseek.com", "api": "openai-completions", "apiKey": "sk-x", "models": [] },
      "ant-ling": { "type": "api_key", "key": "sk-ant-test-0123456789abcdef" }
    }
    """
    try? broken.write(to: authFile, atomically: true, encoding: .utf8)
    try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: authFile.path)
    let problems = PiProviderService.problems(at: authFile)
    check("PiCode names the offending entry", problems.map(\.provider) == ["deepseek"], problems.first?.reason ?? "")
    let poisoned = await piAuthCheck("ant-ling")
    check("Pi reports the valid provider as invalid too", !poisoned.isReady, poisoned.summary)
    check("PiCode explains that as a configuration failure", poisoned.isConfigurationFailure)

    let removed = (try? PiProviderService.removeUnreadableEntries(at: authFile)) ?? []
    check("the repair drops exactly the broken entry", removed == ["deepseek"], removed.joined(separator: ", "))
    let healed = await piAuthCheck("ant-ling")
    check("Pi accepts the credential again", healed.isReady, healed.summary)
    check("nothing is left to repair", PiProviderService.problems(at: authFile).isEmpty)

    print("== PiCode refuses to clobber a file it cannot parse ==")
    try? "not json at all".write(to: authFile, atomically: true, encoding: .utf8)
    do {
        try PiProviderService.setAPIKey("sk-test", for: keyedProvider, at: authFile)
        check("writing over an unparseable file is refused", false)
    } catch {
        check("writing over an unparseable file is refused", true)
    }
    check("the damaged file is untouched",
          (try? String(contentsOf: authFile, encoding: .utf8)) == "not json at all")
    try? FileManager.default.removeItem(at: authFile)

    print("== custom third-party providers in models.json ==")
    let provider = PiProviderService.CustomProvider(
        id: "picode-test-local",
        baseURL: "http://localhost:11434/v1",
        api: "openai-completions",
        apiKey: "ollama",
        models: [PiProviderService.CustomModel(id: "picode-test-model", name: "PiCode Test Model",
                                               reasoning: true, acceptsImages: true,
                                               contextWindow: 128_000, maxTokens: 8192)]
    )
    do {
        try PiProviderService.saveCustomProviders([provider], at: modelsFile)
    } catch {
        check("write a custom provider", false, String(describing: error))
        return 1
    }
    let reloaded = PiProviderService.customProviders(at: modelsFile)
    check("the provider round-trips", reloaded.first?.id == "picode-test-local")
    check("model capability flags round-trip",
          reloaded.first?.models.first?.reasoning == true && reloaded.first?.models.first?.acceptsImages == true)
    check("PiCode sees no problems in what it wrote", PiProviderService.customProviderProblems(at: modelsFile).isEmpty)
    check("a local server is recognised as local", reloaded.first?.isLocalServer == true)

    // The real proof: Pi lists the model. This also pins down that Pi reads
    // models.json at process start, so the UI must say a restart is needed.
    let client = PiRPCClient(
        executableURL: pi,
        workingDirectory: root,
        arguments: ["--mode", "rpc"],
        environment: environment
    )
    do {
        try client.start()
    } catch {
        check("start pi", false, String(describing: error))
        return 1
    }
    do {
        let response = try await client.send(.getAvailableModels, timeout: 60)
        let providers = Set(response.data?["models"]?.arrayValue?.compactMap { $0["provider"]?.stringValue } ?? [])
        check("Pi offers the custom provider to the GUI", providers.contains("picode-test-local"),
              providers.sorted().prefix(6).joined(separator: ", "))

        print("== what a running session picks up without a restart ==")
        // A credential is read through Pi's file-revision check, so a key added
        // while a session runs does take effect. models.json is only read when a
        // process starts, which is why the Settings pane asks to restart.
        try PiProviderService.setAPIKey(secret, for: "ant-ling", at: authFile)
        // Pi re-reads the credential file, but the model catalog it answers from
        // refreshes on a short debounce, so allow a moment before insisting.
        var becameAvailable = false
        for _ in 0..<8 {
            try? await Task.sleep(nanoseconds: 250_000_000)
            let afterKey = try await client.send(.getAvailableModels, timeout: 60)
            let names = Set(afterKey.data?["models"]?.arrayValue?.compactMap { $0["provider"]?.stringValue } ?? [])
            if names.contains("ant-ling") { becameAvailable = true; break }
        }
        check("a credential written mid-session is picked up", becameAvailable,
              becameAvailable ? "no restart needed" : "still missing after 2s")

        let late = PiProviderService.CustomProvider(
            id: "picode-test-added-later",
            baseURL: "http://localhost:11434/v1",
            api: "openai-completions",
            apiKey: "ollama",
            models: [PiProviderService.CustomModel(id: "late-model", name: nil, reasoning: false,
                                                   acceptsImages: false, contextWindow: nil, maxTokens: nil)]
        )
        try PiProviderService.saveCustomProviders([provider, late], at: modelsFile)
        let afterModels = try await client.send(.getAvailableModels, timeout: 60)
        let afterModelsProviders = Set(afterModels.data?["models"]?.arrayValue?.compactMap { $0["provider"]?.stringValue } ?? [])
        check("a models.json provider is not live until the process restarts",
              !afterModelsProviders.contains("picode-test-added-later"))
        try PiProviderService.saveCustomProviders([provider], at: modelsFile)
    } catch {
        check("get_available_models", false, String(describing: error))
    }
    client.stop()

    print("== editing a provider keeps fields the UI does not edit ==")
    var edited = provider
    edited.models[0].contextWindow = 200_000
    edited.extra["headers"] = .object(["x-test": .string("1")])
    try? PiProviderService.saveCustomProviders([edited], at: modelsFile)
    let text = (try? String(contentsOf: modelsFile, encoding: .utf8)) ?? ""
    check("the extra field is preserved", text.contains("x-test"))
    check("the edited limit is written", text.contains("200000"))

    let brokenModels = """
    { "providers": { "half-configured": { "models": [{ "id": "x" }] } } }
    """
    try? brokenModels.write(to: modelsFile, atomically: true, encoding: .utf8)
    let modelProblems = PiProviderService.customProviderProblems(at: modelsFile)
    check("a provider without baseUrl is flagged", modelProblems.first?.provider == "half-configured",
          modelProblems.first?.reason ?? "")

    print("== Pi's own provider wizard is offered, not reimplemented ==")
    let settingsFile = root.appendingPathComponent("settings.json")
    try? #"{ "packages": ["npm:pi-setup-custom-providers"] }"#.write(to: settingsFile, atomically: true, encoding: .utf8)
    check("the wizard is detected", PiProviderService.hasCustomProviderWizard(settingsURL: settingsFile))
    try? #"{ "packages": [] }"#.write(to: settingsFile, atomically: true, encoding: .utf8)
    check("and not claimed when absent", !PiProviderService.hasCustomProviderWizard(settingsURL: settingsFile))

    print("== the user's real configuration is only ever read ==")
    // The harness overrides PI_CODING_AGENT_DIR, so address the real directory
    // explicitly: reads are the whole story, and reading must change nothing.
    let realAgent = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".pi/agent")
    let realAuth = realAgent.appendingPathComponent("auth.json")
    let realModels = realAgent.appendingPathComponent("models.json")
    var stampBefore: [String] = []
    func stamp(_ url: URL) -> String {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return "missing" }
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "\(size)-\(modified)"
    }
    stampBefore = [stamp(realAuth), stamp(realModels)]
    _ = PiProviderService.credentials(at: realAuth)
    _ = PiProviderService.problems(at: realAuth)
    _ = PiProviderService.customProviders(at: realModels)
    _ = PiProviderService.customProviderProblems(at: realModels)
    _ = PiProviderService.hasCustomProviderWizard()
    check("reading Pi's configuration changes nothing", [stamp(realAuth), stamp(realModels)] == stampBefore)
    let realProblems = PiProviderService.problems(at: realAuth)
    if !realProblems.isEmpty {
        print("  note  \(realAuth.path.abbreviatingHomeDirectory) has entries Pi cannot read:")
        for problem in realProblems { print("        \(problem.provider): \(problem.reason)") }
        print("        Pi reports every provider as invalid_state while these exist.")
    } else {
        check("the real auth.json is readable by Pi", true)
    }

    print(failures == 0 ? "\nRESULT: all checks passed" : "\nRESULT: \(failures) check(s) failed")
    return failures == 0 ? 0 : 1
}
