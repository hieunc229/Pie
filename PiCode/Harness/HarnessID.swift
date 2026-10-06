//
//  HarnessID.swift
//  PiCode
//
//  Stable identifier for a coding-agent harness.
//
//  A *harness* is the runtime PiCode embeds: the agent loop, tools, providers,
//  and session store. PiCode talks to each harness over a documented headless
//  protocol and keeps harness-specific wire shapes inside that harness adapter.
//

import Foundation

enum HarnessID: String, Codable, CaseIterable, Identifiable, Sendable {
    case pi
    case ohMyPi = "oh-my-pi"
    case deepseekHarness = "deepseek-harness"
    case claudeCode = "claude-code"
    case codex
    case opencode

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pi: return "Pi"
        case .ohMyPi: return "Oh My Pi"
        case .deepseekHarness: return "DeepSeek Harness"
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        case .opencode: return "OpenCode"
        }
    }

    /// The command users type in a terminal, shown in setup text.
    var commandName: String {
        switch self {
        case .pi: return "pi"
        case .ohMyPi: return "omp"
        case .deepseekHarness: return "dsh"
        case .claudeCode: return "claude"
        case .codex: return "codex"
        case .opencode: return "opencode"
        }
    }

    /// Whether the harness can be embedded over a structured stdio protocol
    /// today. Harnesses without an adapter are shown in Settings but cannot be
    /// selected for a session yet.
    var hasAdapter: Bool {
        switch self {
        case .pi, .ohMyPi, .deepseekHarness, .claudeCode, .codex, .opencode: return true
        }
    }
}
