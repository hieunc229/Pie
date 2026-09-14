//
//  PiCode path-resolution smoke test.
//
//  Pi can be relocated: `PI_CODING_AGENT_DIR` moves `~/.pi/agent`,
//  `PI_CODING_AGENT_SESSION_DIR` (or `sessionDir` in Pi's settings.json) moves
//  the session directory. PiCode must resolve those exactly like Pi's own
//  `config.js`, because PiCode writes trust decisions into `trust.json` — if Pi
//  reads a different file, the user's answer is silently ignored while PiCode
//  reports the project as trusted.
//
//  This harness checks both sides of that contract:
//
//    1. `PiPaths` resolution, in a child process (environment variables are read
//       once per process, so each case needs a fresh one).
//    2. What Pi itself does, by launching a throwaway `pi --mode rpc` against
//       temp directories and watching where it actually writes.
//
//  Nothing outside the temporary directory is created or modified, and no model
//  request is ever sent.
//
//      ./Tools/SmokeTest/run-paths.sh
//

import Foundation

@main
enum PiPathsTest {
    static func main() async {
        if CommandLine.arguments.contains("--resolve") {
            // Child mode: print how this process resolves Pi's paths.
            print(PiPaths.agentDirectory.path)
            print(PiPaths.sessionsDirectory.path)
            exit(0)
        }
        exit(await run())
    }
}

@MainActor
func run() async -> Int32 {
    var failures = 0
    func check(_ name: String, _ condition: Bool, _ detail: String = "") {
        if condition {
            print("  ok   \(name)\(detail.isEmpty ? "" : " — \(detail)")")
        } else {
            failures += 1
            print("  FAIL \(name)\(detail.isEmpty ? "" : " — \(detail)")")
        }
    }

    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("picode-paths-test-\(UUID().uuidString.prefix(8))", isDirectory: true)
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    /// Resolves Pi's paths the way the app would, in a fresh process with the
    /// given environment. The parent's own environment is replaced, not merged,
    /// so a developer machine with these variables exported cannot skew results.
    func resolve(_ environment: [String: String] = [:]) -> (agent: String, sessions: String)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        process.arguments = ["--resolve"]
        var env: [String: String] = ["HOME": NSHomeDirectory(), "PATH": "/usr/bin:/bin"]
        for (key, value) in environment { env[key] = value }
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            print("  FAIL could not re-launch harness: \(error)")
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let lines = String(decoding: data, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
        guard lines.count >= 2 else { return nil }
        return (lines[0], lines[1])
    }

    /// Reads `sessionDir` from a settings file the way Pi's `SettingsManager`
    /// does, so the expected value is derived independently of `PiPaths`.
    func sessionDirInSettings(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let value = try? JSONCoding.decode(data),
              let raw = value["sessionDir"]?.stringValue,
              !raw.isEmpty
        else { return nil }
        return URL(fileURLWithPath: (raw as NSString).expandingTildeInPath).standardizedFileURL.path
    }

    print("== default resolution (no overrides) ==")
    let defaultAgent = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".pi/agent")
    if let resolved = resolve() {
        check("agent directory is ~/.pi/agent", resolved.agent == defaultAgent.path, resolved.agent.abbreviatingHomeDirectory)
        let expectedSessions = sessionDirInSettings(at: defaultAgent.appendingPathComponent("settings.json"))
            ?? defaultAgent.appendingPathComponent("sessions").path
        check("session directory matches Pi's rules", resolved.sessions == expectedSessions,
              resolved.sessions.abbreviatingHomeDirectory)
    } else {
        check("default resolution available", false)
    }

    print("== PI_CODING_AGENT_DIR ==")
    let agentOnly = root.appendingPathComponent("agent-only", isDirectory: true)
    try? FileManager.default.createDirectory(at: agentOnly, withIntermediateDirectories: true)
    if let resolved = resolve(["PI_CODING_AGENT_DIR": agentOnly.path]) {
        check("agent directory follows the override", resolved.agent == agentOnly.standardizedFileURL.path, resolved.agent)
        check("session directory follows the agent directory",
              resolved.sessions == agentOnly.appendingPathComponent("sessions").path, resolved.sessions)
    }

    print("== PI_CODING_AGENT_SESSION_DIR ==")
    let sessionOverride = root.appendingPathComponent("env-sessions", isDirectory: true)
    if let resolved = resolve([
        "PI_CODING_AGENT_DIR": agentOnly.path,
        "PI_CODING_AGENT_SESSION_DIR": sessionOverride.path
    ]) {
        check("session directory follows the override", resolved.sessions == sessionOverride.standardizedFileURL.path, resolved.sessions)
    }

    print("== settings.json sessionDir ==")
    let configured = root.appendingPathComponent("configured-sessions", isDirectory: true)
    let settingsAgent = root.appendingPathComponent("agent-settings", isDirectory: true)
    try? FileManager.default.createDirectory(at: settingsAgent, withIntermediateDirectories: true)
    let settingsJSON = "{\n  \"sessionDir\": \"\(configured.path)\"\n}\n"
    try? settingsJSON.data(using: .utf8)?.write(to: settingsAgent.appendingPathComponent("settings.json"))
    if let resolved = resolve(["PI_CODING_AGENT_DIR": settingsAgent.path]) {
        check("session directory follows settings.json",
              resolved.sessions == configured.standardizedFileURL.path, resolved.sessions)
    }
    if let resolved = resolve([
        "PI_CODING_AGENT_DIR": settingsAgent.path,
        "PI_CODING_AGENT_SESSION_DIR": sessionOverride.path
    ]) {
        check("environment beats settings.json", resolved.sessions == sessionOverride.standardizedFileURL.path, resolved.sessions)
    }

    print("== input sanitizing ==")
    if let resolved = resolve(["PI_CODING_AGENT_DIR": "~/picode-paths-tilde"]) {
        let expected = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("picode-paths-tilde").path
        check("tilde is expanded", resolved.agent == expected, resolved.agent.abbreviatingHomeDirectory)
    }
    if let resolved = resolve(["PI_CODING_AGENT_SESSION_DIR": "relative/sessions"]) {
        check("relative session directory is ignored, not guessed",
              resolved.sessions == defaultAgent.appendingPathComponent("sessions").path
                || resolved.sessions == (sessionDirInSettings(at: defaultAgent.appendingPathComponent("settings.json")) ?? ""),
              resolved.sessions.abbreviatingHomeDirectory)
    }

    // Pi may be absent or unauthenticated on a bare machine; the resolution
    // checks above still stand, so treat this as a skip rather than a failure.
    print("== Pi agrees (throwaway config directory) ==")
    let discovery = PiDiscoveryService()
    guard case .found(let installation) = await discovery.discover() else {
        print("  skip pi not installed")
        return failures == 0 ? 0 : 1
    }

    /// Launches `pi --mode rpc` in a throwaway config directory and asks where it
    /// intends to write this session.
    func piSessionFile(environment: [String: String], cwd: URL) async -> String? {
        let client = PiRPCClient(
            executableURL: installation.executableURL,
            workingDirectory: cwd,
            arguments: ["--mode", "rpc", "--approve"],
            environment: PiDiscoveryService.launchEnvironment(
                executable: installation.executableURL,
                shellPath: installation.shellPath
            ).merging(environment) { _, override in override }
        )
        client.recordsPayloads = false
        client.onEvent = { _, _ in }
        do {
            try client.start()
        } catch {
            return nil
        }
        defer { client.stop() }
        try? await Task.sleep(nanoseconds: 500_000_000)
        guard let response = try? await client.send(.getState, timeout: 30), response.success else { return nil }
        return response.data?.string("sessionFile")
    }

    let project = root.appendingPathComponent("project", isDirectory: true)
    try? FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)

    // (a) The agent directory override must be real: Pi writes its model cache
    //     and credential stub into whatever `getAgentDir()` returns.
    let liveAgent = root.appendingPathComponent("live-agent", isDirectory: true)
    let liveSessionFile = await piSessionFile(environment: ["PI_CODING_AGENT_DIR": liveAgent.path], cwd: project)
    let wroteIntoAgentDir = FileManager.default.fileExists(atPath: liveAgent.appendingPathComponent("models-store.json").path)
    check("Pi writes into the overridden agent directory", wroteIntoAgentDir,
          liveAgent.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
    if let file = liveSessionFile, let resolved = resolve(["PI_CODING_AGENT_DIR": liveAgent.path]) {
        check("Pi's session file lands under PiCode's session directory",
              file.hasPrefix(resolved.sessions + "/"),
              file.replacingOccurrences(of: root.path, with: "<temp>"))
    } else {
        check("Pi reported a session file", false)
    }

    // (b) The environment session override must be real.
    let liveEnvSessions = root.appendingPathComponent("live-env-sessions", isDirectory: true)
    let envSessionFile = await piSessionFile(
        environment: [
            "PI_CODING_AGENT_DIR": liveAgent.path,
            "PI_CODING_AGENT_SESSION_DIR": liveEnvSessions.path
        ],
        cwd: project
    )
    if let file = envSessionFile {
        check("Pi writes sessions to PI_CODING_AGENT_SESSION_DIR",
              file.hasPrefix(liveEnvSessions.standardizedFileURL.path + "/"),
              file.replacingOccurrences(of: root.path, with: "<temp>"))
    } else {
        check("Pi reported a session file for the env override", false)
    }

    // (c) And so must `sessionDir` in Pi's settings.json.
    let liveSettingsAgent = root.appendingPathComponent("live-agent-settings", isDirectory: true)
    let liveConfigured = root.appendingPathComponent("live-configured-sessions", isDirectory: true)
    try? FileManager.default.createDirectory(at: liveSettingsAgent, withIntermediateDirectories: true)
    let liveSettings = "{\n  \"sessionDir\": \"\(liveConfigured.path)\"\n}\n"
    try? liveSettings.data(using: .utf8)?.write(to: liveSettingsAgent.appendingPathComponent("settings.json"))
    let settingsSessionFile = await piSessionFile(environment: ["PI_CODING_AGENT_DIR": liveSettingsAgent.path], cwd: project)
    if let file = settingsSessionFile, let resolved = resolve(["PI_CODING_AGENT_DIR": liveSettingsAgent.path]) {
        check("Pi honours settings.json sessionDir", file.hasPrefix(liveConfigured.standardizedFileURL.path + "/"),
              file.replacingOccurrences(of: root.path, with: "<temp>"))
        check("PiCode agrees with Pi on the configured directory",
              resolved.sessions == liveConfigured.standardizedFileURL.path, resolved.sessions)
    } else {
        check("Pi reported a session file for settings.json sessionDir", false)
    }

    print(failures == 0 ? "RESULT: all checks passed" : "RESULT: \(failures) check(s) failed")
    return failures == 0 ? 0 : 1
}
