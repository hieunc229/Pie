//
//  PiCode extension UI smoke test.
//
//  Drives the real `PiSessionController` against a real `pi --mode rpc` and a
//  throwaway extension, exercising the whole extension UI sub-protocol:
//  select / confirm / input / editor dialogs, cancellation, Pi's own dialog
//  timeout, notify, setStatus (set + clear), setWidget (both placements + clear),
//  setTitle and setEditorText.
//
//  No model request is sent and no provider is needed: Pi executes extension
//  commands locally (`session.prompt` returns as soon as an extension command
//  handles the text), so this costs nothing. The harness refuses to send the
//  command unless `get_commands` lists it first — if that check failed, the text
//  would be a normal prompt and would spend the user's credits.
//
//  Everything lives in a temporary directory, including Pi's agent directory
//  (via PI_CODING_AGENT_DIR, see run-extension.sh), PiCode's preferences
//  (private UserDefaults suite) and PiCode's drafts (temp file). Nothing in
//  ~/.pi is read or written except the session directory that Pi derives from
//  the temporary project path.
//
//      ./Tools/SmokeTest/run-extension.sh
//

import Foundation

@main
enum ExtensionUITest {
    static func main() async {
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

    let arguments = CommandLine.arguments
    guard let rootIndex = arguments.firstIndex(of: "--root"), rootIndex + 1 < arguments.count else {
        print("  FAIL missing --root <dir>")
        return 1
    }
    let root = URL(fileURLWithPath: arguments[rootIndex + 1], isDirectory: true).standardizedFileURL
    let agentDirectory = PiPaths.agentDirectory
    guard agentDirectory.path.hasPrefix(root.path) else {
        print("  FAIL PI_CODING_AGENT_DIR must point inside \(root.path) for this test, got \(agentDirectory.path)")
        return 1
    }

    let fixture = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/ExtensionUI/picode-ui-test.ts")
    let extensionDirectory = agentDirectory.appendingPathComponent("extensions", isDirectory: true)
    try? FileManager.default.createDirectory(at: extensionDirectory, withIntermediateDirectories: true)
    guard let extensionSource = try? String(contentsOf: fixture, encoding: .utf8) else {
        print("  FAIL cannot read \(fixture.path)")
        return 1
    }
    let installed = extensionDirectory.appendingPathComponent("picode-ui-test.ts")
    try? extensionSource.write(to: installed, atomically: true, encoding: .utf8)

    print("== launch ==")
    let discovery = PiDiscoveryService()
    guard case .found(let installation) = await discovery.discover() else {
        print("  FAIL pi not found")
        return 1
    }
    print("  pi: \(installation.displayPath) v\(installation.version)")
    print("  agent dir: \(agentDirectory.path)")

    let project = root.appendingPathComponent("project", isDirectory: true)
    try? FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)

    let suiteName = "picode.extension-ui-test.\(UUID().uuidString.prefix(8))"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        print("  FAIL cannot create a private preferences suite")
        return 1
    }
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

    let draftsURL = root.appendingPathComponent("drafts.json")
    let dependencies = Dependencies(
        installation: installation,
        preferences: PreferencesStore(defaults: defaults),
        drafts: DraftStore(fileURL: draftsURL)
    )
    let controller = PiSessionController(
        projectPath: project.path,
        sessionFile: nil,
        installation: dependencies.installation,
        preferences: dependencies.preferences,
        drafts: dependencies.drafts
    )

    await controller.start()
    var waited = 0.0
    while !controller.connection.isConnected && waited < 25 {
        try? await Task.sleep(nanoseconds: 100_000_000)
        waited += 0.1
    }
    check("controller connected", controller.connection.isConnected, "after \(String(format: "%.1f", waited))s")
    guard controller.connection.isConnected else {
        print("  last error: \(controller.lastError ?? "-")")
        controller.stop()
        return 1
    }

    print("== the command must exist before we send it ==")
    await controller.refreshCommands()
    let command = controller.commands.first { $0.name == "picode-ui-test" }
    check("extension command is registered with Pi", command?.source == .extension,
          command.map { "\($0.name) from \($0.source.rawValue)" } ?? "not in get_commands")
    guard command != nil else {
        // Sending the text anyway could reach a model and spend credits.
        controller.stop()
        return 1
    }

    print("== run /picode-ui-test (no model call) ==")
    // Pi answers `prompt` only after the extension command's handler returns, and
    // this harness is what answers the dialogs — so the send must not block the
    // loop that drives them.
    let sendTask = Task { await controller.send(text: "/picode-ui-test") }

    // Answer every dialog the way a user would, and watch the fire-and-forget
    // state. `dialogs` is ordered; only the first is presented at a time.
    var answered: [String] = []
    var overlapped = false
    var timeoutDialogChecks = 0
    var results: String?

    var elapsed = 0.0
    while elapsed < 60 {
        if controller.dialogs.count > 1 { overlapped = true }
        if let dialog = controller.dialogs.first {
            let title = dialog.request.title ?? ""
            switch title {
            case "PICODE:select":
                answered.append(title)
                // Not the default first option: that would hide a "selection"
                // bug where PiCode sends the wrong value.
                controller.respond(to: dialog, value: "beta")
            case "PICODE:confirm":
                answered.append(title)
                check("dialog exposes its message", dialog.message == "PICODE:message", dialog.message ?? "-")
                controller.confirm(dialog, confirmed: true)
            case "PICODE:input":
                answered.append(title)
                check("dialog exposes its placeholder", dialog.request.placeholder == "PICODE:placeholder",
                      dialog.request.placeholder ?? "-")
                controller.respond(to: dialog, value: "PICODE:typed")
            case "PICODE:editor":
                answered.append(title)
                check("editor prefill becomes the draft", dialog.draftText == "PICODE:prefill", dialog.draftText)
                controller.respond(to: dialog, value: "PICODE:edited")
            case "PICODE:cancel":
                answered.append(title)
                controller.cancel(dialog)
            case "PICODE:timeout":
                // Deliberately unanswered: Pi resolves it at 1.5s. Its own
                // `timeout=false` result below proves the expiry really happened.
                timeoutDialogChecks += 1
                if timeoutDialogChecks == 1 {
                    check("timed dialog reports its timeout", dialog.request.timeout != nil,
                          dialog.request.timeout.map { String(format: "%.0f ms", $0) } ?? "none")
                    check("timed dialog says who will resolve it",
                          controller.activity.contains { $0.detail?.contains("resolve this itself") == true })
                }
            default:
                answered.append("unexpected:\(title)")
                controller.cancel(dialog)
            }
        }
        if results == nil {
            results = controller.notifications
                .map(\.message)
                .last { $0.hasPrefix("PICODE:results") }
        }
        if results != nil && !controller.dialogs.contains(where: { $0.request.title == "PICODE:timeout" }) {
            break
        }
        try? await Task.sleep(nanoseconds: 50_000_000)
        elapsed += 0.05
    }

    // The timed dialog never enters `answered`: nobody answers it.
    let sent = await sendTask.value
    check("command was accepted", sent, controller.lastError ?? "")
    check("every dialog was presented in order", answered == [
        "PICODE:select", "PICODE:confirm", "PICODE:input", "PICODE:editor", "PICODE:cancel"
    ], answered.joined(separator: ", "))
    check("only one dialog was ever on screen", !overlapped)
    check("the timed dialog arrived", timeoutDialogChecks > 0)
    check("the timed dialog was closed once Pi resolved it, not left waiting",
          !controller.dialogs.contains { $0.request.title == "PICODE:timeout" },
          "\(timeoutDialogChecks) sighting(s); Pi answered it with the default")
    check("the expiry is explained in the activity timeline",
          controller.activity.contains { $0.title == "Extension request expired" })

    print("== dialog answers reached the extension ==")
    if let results {
        // `cancel` => undefined, `timeout` => false: both are Pi's documented
        // defaults, so seeing them means the round trip really happened.
        for expected in [
            "select=beta", "confirm=true", "input=PICODE:typed",
            "editor=PICODE:edited", "cancel=undefined", "timeout=false"
        ] {
            check(expected, results.contains(expected), results)
        }
    } else {
        check("extension reported its results", false, "no PICODE:results notification arrived")
    }

    print("== fire-and-forget surfaces ==")
    check("notifications arrived", controller.notifications.contains { $0.message == "PICODE:notify info" })
    let levels = Set(controller.notifications.map(\.level))
    check("all three notification levels", levels.contains(.info) && levels.contains(.warning) && levels.contains(.error),
          levels.map(\.rawValue).sorted().joined(separator: ","))
    check("status was set", controller.extensionStatuses["picode-status"] == "PICODE:status",
          controller.extensionStatuses["picode-status"] ?? "-")
    check("cleared status is gone", controller.extensionStatuses["picode-status-cleared"] == nil,
          controller.extensionStatuses["picode-status-cleared"] ?? "(nil)")
    check("widget above the composer", controller.extensionWidgets[.aboveEditor]?["picode-widget"]?.count == 2,
          (controller.extensionWidgets[.aboveEditor]?["picode-widget"] ?? []).joined(separator: " / "))
    check("widget below the composer",
          controller.extensionWidgets[.belowEditor]?["picode-widget-below"]?.first == "PICODE:widget below",
          (controller.extensionWidgets[.belowEditor]?["picode-widget-below"] ?? []).joined(separator: " / "))
    check("cleared widget is gone", controller.extensionWidgets[.aboveEditor]?["picode-widget-cleared"] == nil)
    check("window title was set", controller.windowTitle == "PICODE:title", controller.windowTitle ?? "-")
    check("composer prefill was set", controller.composerPrefill == "PICODE:editor text", controller.composerPrefill ?? "-")

    print("== no model was involved ==")
    check("no assistant message was produced", controller.stats?.assistantMessages == 0,
          "assistant messages: \(controller.stats?.assistantMessages ?? -1)")
    check("transcript has no assistant row", !controller.items.contains { $0.kind == .assistant },
          "\(controller.items.count) transcript row(s)")
    check("no tokens were spent", (controller.stats?.tokens.totalTokens ?? 0) == 0,
          "tokens: \(controller.stats?.tokens.totalTokens ?? -1)")
    check("no protocol warnings", controller.protocolWarnings.isEmpty,
          controller.protocolWarnings.joined(separator: "; "))

    print("== Pi's config was not touched ==")
    check("no trust decision was written", !FileManager.default.fileExists(atPath: PiPaths.trustFile.path),
          PiPaths.trustFile.path)

    print("== unsupported method is labeled, not ignored silently ==")
    // Pi never emits these in RPC mode (they are no-ops on its side), so the
    // decode path is checked directly: a future method must surface as a
    // compatibility notice rather than an unhandled event.
    let foreign = ExtensionUIRequest(json: .object([
        "type": .string("extension_ui_request"),
        "id": .string("future-1"),
        "method": .string("setFooter"),
        "text": .string("future footer")
    ]))
    check("unknown method decodes as unsupported", foreign.method == .unsupported("setFooter"))
    check("unknown method is not a dialog", !foreign.isDialog)

    controller.stop()
    print(failures == 0 ? "RESULT: all checks passed" : "RESULT: \(failures) check(s) failed")
    return failures == 0 ? 0 : 1
}

/// Groups the collaborators the controller needs, so the call site reads as a
/// list of what was injected rather than a long argument list.
private struct Dependencies {
    var installation: PiInstallation
    var preferences: PreferencesStore
    var drafts: DraftStore
}
