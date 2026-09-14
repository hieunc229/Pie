//
//  PiCode RPC smoke test.
//
//  Compiles the Foundation-only parts of PiCode (models, services, shared text)
//  together with this file, starts a real `pi --mode rpc` child in a throwaway
//  directory using the same PiRPCClient the app uses, and checks the read-only
//  RPC surface: state, models, commands, stats, tree, fork messages, bash.
//
//  It deliberately does NOT send a prompt: that would spend the user's credits.
//

import Foundation

@main
enum RPCSmokeTest {
    static func main() async {
        exit(await runSmokeTest())
    }
}

@MainActor
func runSmokeTest() async -> Int32 {    var failures = 0
    func check(_ name: String, _ condition: Bool, _ detail: String = "") {
        if condition {
            print("  ok   \(name)\(detail.isEmpty ? "" : " — \(detail)")")
        } else {
            failures += 1
            print("  FAIL \(name)\(detail.isEmpty ? "" : " — \(detail)")")
        }
    }

    print("== outgoing wire format ==")
    checkWireFormat(check)

    print("== discovery ==")
    let discovery = PiDiscoveryService()
    let result = await discovery.discover()
    guard case .found(let installation) = result else {
        print("  FAIL pi not found: \(result)")
        return 1
    }
    check("pi found", true, "\(installation.displayPath) v\(installation.version) via \(installation.origin)")

    let sandbox = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("picode-smoke-project", isDirectory: true)
    try? FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)

    print("== session index (before) ==")
    let index = SessionIndex()
    let before = index.loadAllSessions()
    print("  indexed \(before.count) session(s) from \(PiPaths.sessionsDirectory.path.abbreviatingHomeDirectory)")

    print("== launch `pi --mode rpc` ==")
    let client = PiRPCClient(
        executableURL: installation.executableURL,
        workingDirectory: sandbox,
        arguments: ["--mode", "rpc", "--approve"],
        environment: PiDiscoveryService.launchEnvironment(executable: installation.executableURL, shellPath: installation.shellPath)
    )

    let eventCounter = Counter()
    let stderrBox = StringBox()
    client.onEvent = { event, _ in
        eventCounter.increment(event.typeName)
    }
    client.onStderr = { text in
        stderrBox.append(text)
    }
    client.recordsPayloads = false

    do {
        try client.start()
    } catch {
        print("  FAIL start: \(error)")
        return 1
    }
    check("process started", true, "pid \(ProcessInfo.processInfo.processIdentifier) parent")

    // Give Pi a moment to boot, then ask the read-only surface.
    try? await Task.sleep(nanoseconds: 400_000_000)

    func request(_ command: RPCCommand, _ label: String) async -> JSONValue? {
        do {
            let response = try await client.send(command, timeout: 30)
            check("\(label) answered", response.success, response.error ?? "")
            return response.data
        } catch {
            check("\(label) answered", false, "\(error)")
            return nil
        }
    }

    let state = await request(.getState, "get_state")
    // Pi reports the session file it will write, which is the authoritative way
    // to find (and later clean up) this run's session.
    let sessionFileFromState = state?.string("sessionFile")
    if let state {
        check("state has cwd-independent session info", state.object("sessionFile") != nil || state.string("sessionId") != nil,
              state.string("sessionFile") ?? state.string("sessionId") ?? "")
        check("state reports a model", state.object("model") != nil, state.object("model")?.string("id") ?? "")
    }

    let models = await request(.getAvailableModels, "get_available_models")
    let modelList = models?.array("models")?.compactMap(PiModel.init(json:)) ?? []
    check("models parsed by PiModel", !modelList.isEmpty, "\(modelList.count) models, e.g. \(modelList.first?.qualifiedID ?? "-")")

    let commands = await request(.getCommands, "get_commands")
    let commandList = commands?.array("commands")?.map(PiCommand.init(json:)) ?? []
    check("commands parsed by PiCommand", !commandList.isEmpty, "\(commandList.count) commands, first: \(commandList.first?.invocation ?? "-")")

    let levels = await request(.getAvailableThinkingLevels, "get_available_thinking_levels")
    check("thinking levels returned", levels != nil, (levels?.array("levels")?.compactMap(\.stringValue) ?? []).joined(separator: ","))

    let stats = await request(.getSessionStats, "get_session_stats")
    if let stats {
        let parsed = PiSessionStats(json: stats)
        check("stats parsed", parsed.totalMessages >= 0, "messages \(parsed.totalMessages)")
    }

    let tree = await request(.getTree, "get_tree")
    if let tree {
        let nodes = tree.array("tree")?.map(PiTreeNode.init(json:)) ?? []
        check("tree parsed", true, "\(nodes.count) root node(s), leaf \(tree.string("leafId") ?? "-")")
    }

    let forks = await request(.getForkMessages, "get_fork_messages")
    let forkPoints = forks?.array("messages")?.map(PiForkPoint.init(json:)) ?? []
    check("fork points parsed", forks != nil, "\(forkPoints.count) fork points")

    let messages = await request(.getMessages, "get_messages")
    if let messages {
        let decoded = messages.array("messages")?.map(PiMessage.init(raw:)) ?? []
        check("messages parsed", true, "\(decoded.count) message(s)")
    }

    print("== bash through Pi's own tool ==")
    if let bash = await request(.bash(command: "echo picode-smoke:$(pwd)"), "bash") {
        let output = bash.string("output") ?? ""
        check("bash output captured", output.contains("picode-smoke:"), output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    print("== trust file untouched ==")
    check("no trust decision was written", !FileManager.default.fileExists(atPath: PiPaths.trustFile.path),
          PiPaths.trustFile.path.abbreviatingHomeDirectory)

    print("== unknown command is rejected, not ignored ==")
    do {
        _ = try await client.sendAwaitingResponse(
            .object(["id": .string("smoke-unknown"), "type": .string("picode_no_such_command")]),
            timeout: 20
        )
        check("unknown command reports failure", false, "Pi accepted an unknown command")
    } catch let error as PiRPCError {
        switch error {
        case .commandFailed(let command, let message):
            check("unknown command reports failure", true, "\(command): \(message)")
        default:
            check("unknown command reports failure", false, "\(error)")
        }
    } catch {
        check("unknown command reports failure", false, "\(error)")
    }

    client.stop()
    try? await Task.sleep(nanoseconds: 300_000_000)

    print("== session index (after) ==")
    let after = index.loadAllSessions()
    print("  indexed \(after.count) session(s)")
    let created = after.filter { !before.contains($0) }
    for session in created {
        print("  new session: \(session.filePath ?? "-")")
        if let path = session.filePath {
            let content = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
            let records = content
                .split(separator: "\n", omittingEmptySubsequences: true)
                .compactMap { line -> JSONValue? in
                    guard let data = line.data(using: .utf8) else { return nil }
                    return try? JSONCoding.decode(data)
                }
            check("session file is valid jsonl", !records.isEmpty, "\(records.count) records, \(content.count) bytes")
            check("session header has cwd", records.first?.string("cwd") == sandbox.path,
                  records.first?.string("cwd") ?? "-")
            check("session header has type/id", records.first?.string("type") != nil && records.first?.string("id") != nil,
                  records.first.map { "\($0.string("type") ?? "-")/\($0.string("id") ?? "-")" } ?? "-")
        }
    }
    check("events were delivered", eventCounter.total > 0, "\(eventCounter.total) events: \(eventCounter.summary)")

    print("== cleanup ==")
    for session in created {
        if let path = session.filePath {
            try? FileManager.default.removeItem(atPath: path)
            print("  removed \(path.abbreviatingHomeDirectory)")
        }
    }
    // Pi creates the project's session folder eagerly. This run never sent a
    // prompt, so there is no session file, and the empty folder can go.
    try? FileManager.default.removeItem(at: sandbox)
    if let sessionFileFromState {
        let file = URL(fileURLWithPath: sessionFileFromState)
        if FileManager.default.fileExists(atPath: file.path) {
            try? FileManager.default.removeItem(at: file)
            print("  removed session \(file.lastPathComponent)")
        }
        let folder = file.deletingLastPathComponent()
        if (try? FileManager.default.contentsOfDirectory(atPath: folder.path))?.isEmpty == true {
            try? FileManager.default.removeItem(at: folder)
            print("  removed \(folder.path.abbreviatingHomeDirectory)")
        }
    }
    if !stderrBox.text.isEmpty {
        print("== pi stderr ==")
        print(stderrBox.text.prefix(2000))
    }

    print(failures == 0 ? "\nRESULT: all checks passed" : "\nRESULT: \(failures) check(s) failed")
    return failures == 0 ? 0 : 1
}

final class Counter: @unchecked Sendable {    private let lock = NSLock()
    private var counts: [String: Int] = [:]
    func increment(_ key: String) {
        lock.lock(); counts[key, default: 0] += 1; lock.unlock()
    }
    var total: Int { lock.lock(); defer { lock.unlock() }; return counts.values.reduce(0, +) }
    var summary: String {
        lock.lock(); defer { lock.unlock() }
        return counts.sorted { $0.value > $1.value }.prefix(6).map { "\($0.key)×\($0.value)" }.joined(separator: ", ")
    }
}

final class StringBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = ""
    func append(_ text: String) { lock.lock(); storage += text; lock.unlock() }
    var text: String { lock.lock(); defer { lock.unlock() }; return storage }
}

/// Pi silently ignores unknown and misspelled fields, so an encoding mistake
/// looks like success in the app and does nothing on the wire. These checks pin
/// the documented shape of every field we depend on.
///
/// Reference: `docs/rpc.md` in the installed Pi package.
func checkWireFormat(_ report: (String, Bool, String) -> Void) {
    func check(_ name: String, _ condition: Bool, _ detail: String = "") {
        report(name, condition, detail)
    }

    let image = PiImagePayload(data: "aGk=", mimeType: "image/png")
    let cases: [RPCCommand] = [
        .getState, .getMessages, .getAvailableModels, .getAvailableThinkingLevels,
        .getCommands, .getSessionStats, .getEntries(since: "abc"), .getTree,
        .getForkMessages, .getLastAssistantText,
        .setModel(provider: "anthropic", modelId: "claude"), .cycleModel,
        .setThinkingLevel(level: "high"), .cycleThinkingLevel,
        .setSteeringMode(mode: "one-at-a-time"), .setFollowUpMode(mode: "one-at-a-time"),
        .setAutoCompaction(enabled: true), .setAutoRetry(enabled: false),
        .setSessionName(name: "n"),
        .prompt(message: "m", images: [image], behavior: .steer),
        .steer(message: "m", images: []), .followUp(message: "m", images: []),
        .abort, .abortRetry, .abortBash, .clearQueue,
        .newSession(parentSession: "/tmp/p.jsonl"), .switchSession(path: "/tmp/s.jsonl"),
        .fork(entryId: "e"), .clone, .compact(customInstructions: "focus"),
        .exportHTML(outputPath: "/tmp/o.html"), .bash(command: "ls"),
    ]

    // Every case must carry the documented method name and its own id.
    let mismatched = cases.filter { $0.json(id: "x").string("type") != $0.name }
    check("every command encodes its method name", mismatched.isEmpty,
          mismatched.map(\.name).joined(separator: ", "))

    let expectations: [(String, RPCCommand, JSONValue)] = [
        ("prompt+images+behavior",
         .prompt(message: "hi", images: [image], behavior: .followUp),
         .object(["id": .string("1"), "type": .string("prompt"), "message": .string("hi"),
                  "images": .array([image.json]), "streamingBehavior": .string("followUp")])),
        ("set_model", .setModel(provider: "anthropic", modelId: "claude"),
         .object(["id": .string("1"), "type": .string("set_model"),
                  "provider": .string("anthropic"), "modelId": .string("claude")])),
        ("set_thinking_level", .setThinkingLevel(level: "high"),
         .object(["id": .string("1"), "type": .string("set_thinking_level"), "level": .string("high")])),
        ("set_steering_mode", .setSteeringMode(mode: "all"),
         .object(["id": .string("1"), "type": .string("set_steering_mode"), "mode": .string("all")])),
        ("set_follow_up_mode", .setFollowUpMode(mode: "all"),
         .object(["id": .string("1"), "type": .string("set_follow_up_mode"), "mode": .string("all")])),
        ("set_auto_compaction", .setAutoCompaction(enabled: true),
         .object(["id": .string("1"), "type": .string("set_auto_compaction"), "enabled": .bool(true)])),
        ("set_session_name", .setSessionName(name: "x"),
         .object(["id": .string("1"), "type": .string("set_session_name"), "name": .string("x")])),
        ("new_session+parent", .newSession(parentSession: "/tmp/p.jsonl"),
         .object(["id": .string("1"), "type": .string("new_session"), "parentSession": .string("/tmp/p.jsonl")])),
        ("switch_session", .switchSession(path: "/tmp/s.jsonl"),
         .object(["id": .string("1"), "type": .string("switch_session"), "sessionPath": .string("/tmp/s.jsonl")])),
        ("fork", .fork(entryId: "e1"),
         .object(["id": .string("1"), "type": .string("fork"), "entryId": .string("e1")])),
        ("compact", .compact(customInstructions: "focus"),
         .object(["id": .string("1"), "type": .string("compact"), "customInstructions": .string("focus")])),
        ("export_html", .exportHTML(outputPath: "/tmp/o.html"),
         .object(["id": .string("1"), "type": .string("export_html"), "outputPath": .string("/tmp/o.html")])),
        ("bash", .bash(command: "ls"),
         .object(["id": .string("1"), "type": .string("bash"), "command": .string("ls")])),
        ("get_entries+since", .getEntries(since: "abc"),
         .object(["id": .string("1"), "type": .string("get_entries"), "since": .string("abc")])),
        // Omitted optionals must not be sent as null: Pi treats a present-but-null
        // field differently from an absent one for several commands.
        ("compact without instructions", .compact(customInstructions: nil),
         .object(["id": .string("1"), "type": .string("compact")])),
        ("new_session without parent", .newSession(parentSession: nil),
         .object(["id": .string("1"), "type": .string("new_session")])),
    ]

    for (label, command, expected) in expectations {
        let actual = command.json(id: "1")
        check("encodes \(label)", actual == expected,
              actual == expected ? "" : "got \(actual.prettyDescription)")
    }

    // Extension UI answers are the only messages with no response, so a wrong
    // key here fails silently forever.
    let request = ExtensionUIRequest(
        json: .object([
            "type": .string("extension_ui_request"),
            "id": .string("dlg-1"),
            "method": .string("select"),
            "title": .string("Pick"),
            "options": .array([.string("a"), .string("b")]),
        ])
    )
    check("decodes a select dialog", request.methodName == "select" && request.id == "dlg-1",
          "\(request.methodName) \(request.options)")
    check("encodes a value response",
          request.valueResponse("b") == .object(["type": .string("extension_ui_response"),
                                                 "id": .string("dlg-1"), "value": .string("b")]))
    check("encodes a confirm response",
          request.confirmResponse(true) == .object(["type": .string("extension_ui_response"),
                                                    "id": .string("dlg-1"), "confirmed": .bool(true)]))
    check("encodes a cancel response",
          request.cancelResponse() == .object(["type": .string("extension_ui_response"),
                                               "id": .string("dlg-1"), "cancelled": .bool(true)]))
}
