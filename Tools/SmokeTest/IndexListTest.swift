//
//  PiCode session-index smoke test.
//
//  Answers one question with evidence: is what the sidebar shows real? Every
//  project and session in the sidebar is supposed to be a projection of Pi's own
//  session directory — PiCode has no database of its own to disagree with. So this
//  harness lists exactly what the sidebar would render and checks each entry
//  against the filesystem.
//
//  It is read-only: nothing is created, moved, or deleted in Pi's directory.
//
//      ./Tools/SmokeTest/run-index.sh [--verbose]
//

import Foundation

@main
enum IndexListTest {
    static func main() async {
        exit(await run())
    }
}

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

    let verbose = CommandLine.arguments.contains("--verbose")
    let index = SessionIndex()

    print("== where Pi keeps sessions on this machine ==")
    print("  agent dir:   \(PiPaths.agentDirectory.path.abbreviatingHomeDirectory)")
    print("  sessions:    \(PiPaths.sessionsDirectory.path.abbreviatingHomeDirectory)")
    check("the sessions directory exists", FileManager.default.fileExists(atPath: PiPaths.sessionsDirectory.path),
          PiPaths.sessionsDirectory.path.abbreviatingHomeDirectory)

    let files = index.sessionFileURLs()
    print("  session dirs: \(index.sessionDirectories().count), session files: \(files.count)")
    check("Pi's session directory has files to index", !files.isEmpty)

    // A session file Pi wrote but PiCode failed to parse is the only way the
    // sidebar can be *missing* something Pi knows about.
    let refs = index.loadAllSessions()
    check("every session file parsed", refs.count == files.count,
          "\(refs.count) parsed of \(files.count) on disk")
    check("every session has an id and a cwd", refs.allSatisfy { !$0.id.isEmpty && !$0.cwd.isEmpty })

    let projects = index.group(refs)
    let grouped = projects.reduce(0) { $0 + $1.sessions.count }
    check("every session landed in exactly one project", grouped == refs.count,
          "\(grouped) grouped of \(refs.count) loaded")

    // The point of the exercise: nothing in the sidebar is invented. Each entry
    // must name a real file that really lives under Pi's directory, and each
    // project must be a real working directory.
    let sessionsRoot = PiPaths.sessionsDirectory.standardizedFileURL.path
    var missingFiles: [String] = []
    var outsideRoot: [String] = []
    var missingDirectories: [String] = []
    var sessionsInMissingDirectory: [SessionRef] = []
    for project in projects {
        if !FileManager.default.fileExists(atPath: project.path) {
            missingDirectories.append(project.path)
            sessionsInMissingDirectory.append(contentsOf: project.sessions)
        }
        for session in project.sessions {
            guard let filePath = session.filePath else { continue }
            if !FileManager.default.fileExists(atPath: filePath) { missingFiles.append(filePath) }
            if !URL(fileURLWithPath: filePath).standardizedFileURL.path.hasPrefix(sessionsRoot) {
                outsideRoot.append(filePath)
            }
            if CanonicalPath.of(session.cwd) != project.path {
                failures += 1
                print("  FAIL session is grouped under the wrong project — \(filePath)")
            }
        }
    }

    check("every session file still exists", missingFiles.isEmpty,
          missingFiles.prefix(3).joined(separator: ", "))
    check("every session file lives under Pi's session directory", outsideRoot.isEmpty,
          outsideRoot.prefix(3).joined(separator: ", "))
    check("every project still exists as a directory", missingDirectories.isEmpty,
          missingDirectories.joined(separator: ", "))

    print("== what the sidebar will show ==")
    for project in projects {
        let trust = ProjectTrustService().state(for: project.path)
        let flag = FileManager.default.fileExists(atPath: project.path) ? " " : "!"
        print("  \(flag) \(project.path.abbreviatingHomeDirectory)  [\(project.sessions.count) session(s), trust: \(trust)]")
        guard verbose else { continue }
        for session in project.sessions {
            let name = session.name ?? session.firstUserMessage ?? "(untitled)"
            let when = session.updatedAt.formatted(date: .abbreviated, time: .shortened)
            print("      · \(when)  \(session.messageCount) msg  \(name.prefix(70))")
            print("        \(session.filePath?.abbreviatingHomeDirectory ?? "(no file)")")
        }
    }
    if !missingDirectories.isEmpty {
        print("  ! = the working directory no longer exists; these sessions are still real")
        print("      Pi wrote them, but the project folder was moved or deleted.")
        for session in sessionsInMissingDirectory.prefix(5) {
            print("      · \(session.filePath?.abbreviatingHomeDirectory ?? "?")")
        }
    }

    print("== PiCode keeps no project list of its own ==")
    // Preferences may only *decorate* what the disk says (pins, hidden sessions).
    // If the app ever cached a project or session list, the sidebar could show an
    // entry Pi does not have, which is exactly the bug this harness exists to catch.
    let bundleID = Bundle.main.bundleIdentifier ?? "xyz.hieunguyen.PiCode"
    let stored = UserDefaults(suiteName: bundleID)?.dictionaryRepresentation() ?? [:]
    let decorationKeys = Set([
        "appearance", "sendKey", "showInspector", "showSidebar", "defaultThinkingLevel", "defaultModel",
        "confirmBeforeDeletingSessions", "notificationsEnabled", "recordRPCPayloads", "extraLaunchArguments",
        "pinnedProjects", "pinnedSessions", "hiddenSessions", "lastProjectPath", "reducedMotionOverride",
    ])
    let indexLikeKeys = stored.keys.filter { key in
        let lowered = key.lowercased()
        let namesAProjectList = lowered.contains("project") || lowered.contains("session")
        return namesAProjectList && !decorationKeys.contains(key)
    }
    check("no cached project or session list in app preferences", indexLikeKeys.isEmpty,
          indexLikeKeys.joined(separator: ", "))
    let pinned = Set((stored["pinnedProjects"] as? [String]) ?? [])
    check("pins are decoration, not a project list", pinned.count <= projects.count,
          "\(pinned.count) pinned, \(projects.count) on disk")
    let hidden = Set((stored["hiddenSessions"] as? [String]) ?? [])
    check("hidden sessions are decoration too", hidden.count <= refs.count,
          "\(hidden.count) hidden, \(refs.count) on disk")

    print(failures == 0 ? "\nRESULT: all checks passed" : "\nRESULT: \(failures) check(s) failed")
    return failures == 0 ? 0 : 1
}
