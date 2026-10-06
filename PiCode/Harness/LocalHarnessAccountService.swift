//
//  LocalHarnessAccountService.swift
//  PiCode
//
//  Reads each CLI's own authentication status. PiCode never opens, copies, or
//  translates token files; the harness remains responsible for refresh/logout.
//

import Foundation

enum LocalHarnessAccountService {
    static func status(for descriptor: HarnessDescriptor,
                       installation: HarnessInstallation) async -> LocalHarnessAccountStatus {
        let arguments: [String]
        switch descriptor.id {
        case .codex:
            arguments = ["login", "status"]
        case .claudeCode:
            arguments = ["auth", "status", "--json"]
        case .opencode:
            arguments = ["auth", "list", "--format", "json"]
        default:
            return LocalHarnessAccountStatus(
                kind: .unavailable,
                title: "Managed by \(descriptor.displayName)",
                detail: "This harness does not expose a local account-status command."
            )
        }

        let environment = HarnessDiscoveryService.launchEnvironment(
            executable: installation.executableURL,
            shellPath: installation.shellPath
        )
        let runner = HarnessDiscoveryService(descriptor: descriptor)
        var result = await runner.run(
            executable: installation.executableURL,
            arguments: arguments,
            directory: URL(fileURLWithPath: NSHomeDirectory()),
            environment: environment
        )
        // Older OpenCode releases expose the same safe summary without the JSON
        // flag. Keep subscription reuse working while users roll forward.
        if descriptor.id == .opencode, result.exitCode != 0 {
            result = await runner.run(
                executable: installation.executableURL,
                arguments: ["auth", "list"],
                directory: URL(fileURLWithPath: NSHomeDirectory()),
                environment: environment
            )
        }
        let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        guard result.exitCode == 0 else {
            return LocalHarnessAccountStatus(
                kind: .signedOut,
                title: "Not signed in",
                detail: result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                    .nonEmpty ?? "Sign in with \(descriptor.displayName) to use a local subscription."
            )
        }

        switch descriptor.id {
        case .codex:
            let usesSubscription = output.localizedCaseInsensitiveContains("chatgpt")
            return LocalHarnessAccountStatus(
                kind: usesSubscription ? .subscription : .apiKey,
                title: usesSubscription ? "ChatGPT subscription" : "Local Codex credentials",
                detail: output.nonEmpty ?? "Codex is signed in."
            )

        case .claudeCode:
            let json = try? JSONCoding.decode(Data(output.utf8))
            let loggedIn = json?.bool("loggedIn") == true
            let method = json?.string("authMethod") ?? ""
            guard loggedIn else {
                return LocalHarnessAccountStatus(
                    kind: .signedOut,
                    title: "Not signed in",
                    detail: "Run `claude auth login` and choose your Claude subscription."
                )
            }
            let usesSubscription = method.localizedCaseInsensitiveContains("oauth")
            return LocalHarnessAccountStatus(
                kind: usesSubscription ? .subscription : .apiKey,
                title: usesSubscription ? "Claude subscription" : "Local Claude credentials",
                detail: usesSubscription ? "Claude Code OAuth is ready." : "Claude Code is using its saved account."
            )

        case .opencode:
            let normalized = output.lowercased()
            let hasCredentials = !output.isEmpty
                && output != "[]"
                && output != "{}"
                && !normalized.contains("no credentials")
                && !normalized.contains("not logged in")
            return LocalHarnessAccountStatus(
                kind: hasCredentials ? .localCredentials : .signedOut,
                title: hasCredentials ? "Local accounts ready" : "No local accounts",
                detail: hasCredentials
                    ? "OpenCode will use the providers and subscriptions in its local credential store."
                    : "Run `opencode auth login` to connect an OpenCode or supported provider subscription."
            )

        default:
            return LocalHarnessAccountStatus(kind: .unavailable,
                                             title: "Unavailable",
                                             detail: "Account status is unavailable.")
        }
    }

    static func loginCommand(for id: HarnessID) -> String {
        switch id {
        case .codex: return "codex login"
        case .claudeCode: return "claude auth login"
        case .opencode: return "opencode auth login"
        default: return id.commandName
        }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
