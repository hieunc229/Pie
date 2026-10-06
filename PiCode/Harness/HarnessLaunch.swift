//
//  HarnessLaunch.swift
//  PiCode
//
//  Builds the child-process argv for a harness. Each harness has its own flags
//  for sessions, system prompts, trust, and model selection; keeping that here
//  means the session controller never hard-codes one harness's CLI.
//

import Foundation

enum HarnessLaunch {
    /// Arguments that put a harness into its structured, headless session mode.
    static func sessionModeArguments(for id: HarnessID) -> [String] {
        switch id {
        case .pi, .ohMyPi:
            // The Pi-family RPC transport. `omp` accepts the same `--mode rpc`.
            return ["--mode", "rpc"]
        case .deepseekHarness:
            // The SDK profile owns the JSON-RPC server. `headless` is one-shot;
            // `sdk` is the long-lived session server.
            return ["--profile", "sdk"]
        case .claudeCode, .codex, .opencode:
            // These adapters build their own argv from their own launch profile.
            return []
        }
    }

    /// Full argv for a Pi-family runtime process.
    static func piFamilyArguments(for descriptor: HarnessDescriptor,
                                  sessionFile: String?,
                                  systemPrompt: String?,
                                  model: String?,
                                  trustArguments: [String],
                                  extra: [String]) -> [String] {
        var arguments = sessionModeArguments(for: descriptor.id)

        if let sessionFile {
            switch descriptor.id {
            case .pi:
                arguments.append(contentsOf: ["--session", sessionFile])
            case .ohMyPi:
                arguments.append(contentsOf: ["--resume", sessionFile])
            default:
                break
            }
        }

        // Trust semantics are Pi's; a harness without the capability gets none.
        if descriptor.capabilities.contains(.trust) {
            arguments.append(contentsOf: trustArguments)
        }

        if let systemPrompt, !systemPrompt.isEmpty {
            arguments.append(contentsOf: ["--append-system-prompt", systemPrompt])
        }

        // Only pass an explicit model on a brand-new session; resuming keeps the
        // session's own model and the picker can change it afterwards.
        if let model, !model.isEmpty, sessionFile == nil {
            arguments.append(contentsOf: ["--model", model])
        }

        arguments.append(contentsOf: extra)
        return arguments
    }
}
