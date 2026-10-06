//
//  HarnessDescriptor.swift
//  PiCode
//
//  The static catalog of coding-agent harnesses PiCode knows how to detect,
//  install, and (when an adapter exists) embed.
//

import Foundation

/// One way to install a harness. Commands run through the user's login shell so
/// `npm`, `bun`, `pnpm`, `pip`, or `brew` resolve exactly as they do in a
/// terminal, instead of whatever minimal PATH a GUI app inherits.
struct HarnessInstallMethod: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable {
        case npm
        case bun
        case pnpm
        case pip
        case brew
        case script
    }

    var id: String { "\(kind.rawValue):\(command)" }
    var kind: Kind
    /// Short label shown next to the install button, e.g. "npm".
    var label: String
    /// Human-readable command, shown and copied to the pasteboard.
    var command: String
    /// The script handed to the login shell. Usually equal to `command`.
    var shellScript: String

    init(kind: Kind, label: String, command: String, shellScript: String? = nil) {
        self.kind = kind
        self.label = label
        self.command = command
        self.shellScript = shellScript ?? command
    }
}

/// Everything PiCode knows about one harness without launching it.
struct HarnessDescriptor: Identifiable, Sendable, Hashable {
    var id: HarnessID
    var displayName: String
    var tagline: String
    /// Binary looked up on the login-shell PATH.
    var binaryName: String
    /// Arguments that print a version, if the harness supports one.
    var versionArguments: [String]
    var installMethods: [HarnessInstallMethod]
    var capabilities: HarnessCapabilities
    var documentationURL: URL?
    /// Extra candidate paths tried when the login shell cannot answer.
    var fallbackBinaries: [String]
    /// Whether a session can be started with this harness today.
    var hasAdapter: Bool
    /// Honest note shown in Settings when support is partial or planned.
    var supportNote: String? = nil

    var isBuiltIn: Bool { id == .pi }

    static let all: [HarnessDescriptor] = [
        HarnessDescriptor(
            id: .pi,
            displayName: HarnessID.pi.displayName,
            tagline: "The agent runtime PiCode was built around.",
            binaryName: "pi",
            versionArguments: ["--version"],
            installMethods: [
                HarnessInstallMethod(
                    kind: .npm,
                    label: "npm",
                    command: "npm install -g --ignore-scripts @earendil-works/pi-coding-agent"
                ),
                HarnessInstallMethod(
                    kind: .script,
                    label: "curl",
                    command: "curl -fsSL https://pi.dev/install.sh | sh"
                )
            ],
            capabilities: .piFamily,
            documentationURL: URL(string: "https://pi.dev/docs/latest"),
            fallbackBinaries: ["/opt/homebrew/bin/pi", "/usr/local/bin/pi", "/usr/bin/pi"],
            hasAdapter: true
        ),
        HarnessDescriptor(
            id: .ohMyPi,
            displayName: HarnessID.ohMyPi.displayName,
            tagline: "A Pi fork with IDE tooling; speaks the same RPC shape.",
            binaryName: "omp",
            versionArguments: ["--version"],
            installMethods: [
                HarnessInstallMethod(
                    kind: .npm,
                    label: "npm",
                    command: "npm install -g @oh-my-pi/pi-coding-agent"
                ),
                HarnessInstallMethod(
                    kind: .bun,
                    label: "bun",
                    command: "bun install -g @oh-my-pi/pi-coding-agent"
                )
            ],
            // OMP shares Pi's RPC transport, but not Pi's project-trust CLI
            // flags (`--approve` / `--no-approve`).  Keeping `.trust` here made
            // every OMP process exit before the RPC session could start.
            capabilities: .piFamily.subtracting(.trust),
            documentationURL: URL(string: "https://omp.sh/docs"),
            fallbackBinaries: ["/opt/homebrew/bin/omp", "/usr/local/bin/omp"],
            hasAdapter: true,
            supportNote: "Runs over the Pi-family RPC transport. Session indexing and a few command/event names differ from Pi; a protocol profile is the next step."
        ),
        HarnessDescriptor(
            id: .deepseekHarness,
            displayName: HarnessID.deepseekHarness.displayName,
            tagline: "DeepSeek's plugin-composed harness; drives over JSON-RPC stdio.",
            binaryName: "dsh",
            versionArguments: ["--version"],
            installMethods: [
                HarnessInstallMethod(
                    kind: .npm,
                    label: "npm",
                    command: "npm install -g @deepseek-ai/dsh"
                )
            ],
            capabilities: [
                .streamingText, .toolCalls, .abort, .sessions, .modelCatalog,
                .thinkingLevels, .providerConfig, .completionSignal
            ],
            documentationURL: URL(string: "https://github.com/deepseek-ai/deepseek-harness"),
            fallbackBinaries: ["/opt/homebrew/bin/dsh", "/usr/local/bin/dsh"],
            hasAdapter: true,
            supportNote: "Drives the SDK profile's newline-delimited JSON-RPC server. Streams whole-agent status and durable session events; there is no per-token stream."
        ),
        HarnessDescriptor(
            id: .claudeCode,
            displayName: HarnessID.claudeCode.displayName,
            tagline: "Anthropic's CLI, driven over its stream-json control protocol.",
            binaryName: "claude",
            versionArguments: ["--version"],
            installMethods: [
                HarnessInstallMethod(
                    kind: .npm,
                    label: "npm",
                    command: "npm install -g @anthropic-ai/claude-code"
                )
            ],
            capabilities: [
                .streamingText, .toolCalls, .toolStreamingOutput, .thinking, .images,
                .abort, .sessions, .compaction, .modelCatalog, .thinkingLevels,
                .providerConfig, .completionSignal
            ],
            documentationURL: URL(string: "https://code.claude.com/docs/en/headless"),
            fallbackBinaries: ["/opt/homebrew/bin/claude", "/usr/local/bin/claude"],
            hasAdapter: true,
            supportNote: "Runs `claude --print` with stream-json input and output. Tools stream as content blocks; session tree, fork, and extension dialogs are Pi-only and hidden."
        ),
        HarnessDescriptor(
            id: .codex,
            displayName: HarnessID.codex.displayName,
            tagline: "OpenAI's Codex CLI, driven over `codex exec --json`.",
            binaryName: "codex",
            versionArguments: ["--version"],
            installMethods: [
                HarnessInstallMethod(
                    kind: .npm,
                    label: "npm",
                    command: "npm install -g @openai/codex"
                ),
                HarnessInstallMethod(
                    kind: .brew,
                    label: "brew",
                    command: "brew install codex"
                )
            ],
            capabilities: [
                .toolCalls, .thinking, .abort, .sessions, .modelCatalog,
                .providerConfig, .completionSignal
            ],
            documentationURL: URL(string: "https://github.com/openai/codex"),
            fallbackBinaries: ["/opt/homebrew/bin/codex", "/usr/local/bin/codex"],
            hasAdapter: true,
            supportNote: "`codex exec --json` completes each message as a whole, so assistant text appears per item rather than token by token. Follow-ups resume the same thread id."
        ),
        HarnessDescriptor(
            id: .opencode,
            displayName: HarnessID.opencode.displayName,
            tagline: "Multi-provider coding agent using your local OpenCode accounts.",
            binaryName: "opencode",
            versionArguments: ["--version"],
            installMethods: [
                HarnessInstallMethod(
                    kind: .npm,
                    label: "npm",
                    command: "npm install -g opencode-ai"
                ),
                HarnessInstallMethod(
                    kind: .script,
                    label: "curl",
                    command: "curl -fsSL https://opencode.ai/install | bash"
                )
            ],
            capabilities: [.toolCalls, .thinking, .abort, .sessions, .modelCatalog, .completionSignal],
            documentationURL: URL(string: "https://opencode.ai/docs/cli"),
            fallbackBinaries: ["/opt/homebrew/bin/opencode", "/usr/local/bin/opencode"],
            hasAdapter: true,
            supportNote: "Runs `opencode run --format json` and reuses providers connected with `opencode auth login`. Models come from the installed OpenCode catalog."
        )
    ]

    static func descriptor(for id: HarnessID) -> HarnessDescriptor {
        all.first { $0.id == id } ?? all[0]
    }
}
