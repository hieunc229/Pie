//
//  SessionTitleService.swift
//  PiCode
//
//  Names a new chat from its first message.
//
//  Pi's RPC protocol has no "summarize this" command, so the name comes from the
//  same binary the session does: a one-shot `pi --print` run in text mode with
//  sessions, tools, extensions and prompt context turned off. Pi stays the only
//  model caller — PiCode asks once and trims the answer. When Pi cannot answer
//  (no credentials, no network, a refusal), `fallback` names the chat from the
//  message's own words, so a chat always has a name.
//

import Foundation

enum SessionTitleService {
    /// The instruction that turns the first message into a title. Deliberately
    /// terse: the model sees one message and one rule, and the answer is trimmed
    /// again below, because a completion is prose until it is made a title.
    private static let instruction = """
    Write a 3-6 word title for the conversation that begins with the user message
    below. Reply with the title only: no quotes, no punctuation at the end, and no
    explanation.

    User message:
    """

    /// Runs one non-interactive `pi` process and returns the title it printed, or
    /// `nil` when the answer cannot be used.
    ///
    /// A non-zero exit is a failure, not a title: a missing credential or a
    /// refused request exits non-zero and may still print something on stderr.
    /// Only stdout is read, and only on a clean exit, so an error message never
    /// becomes a session name.
    static func generate(for prompt: String,
                         installation: PiInstallation,
                         directory: String,
                         model: String?) async -> String? {
        let message = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return nil }

        var arguments = [
            "--print",
            "--mode", "text",
            "--no-session",
            "--no-tools",
            "--no-extensions",
            "--no-skills",
            "--no-prompt-templates",
            "--no-context-files",
            "--no-approve"
        ]
        if let model, !model.isEmpty {
            arguments.append(contentsOf: ["--model", model])
        }
        // The message is clipped because a prompt can be a pasted document; the
        // title only needs its opening.
        arguments.append(instruction + "\n" + String(message.prefix(4000)))

        let result = await PiDiscoveryService().run(
            executable: installation.executableURL,
            arguments: arguments,
            directory: URL(fileURLWithPath: directory),
            environment: PiDiscoveryService.launchEnvironment(
                executable: installation.executableURL,
                shellPath: installation.shellPath
            )
        )
        guard result.exitCode == 0 else { return nil }
        return sanitize(result.stdout)
    }

    /// Reduces a completion to a title: the first non-empty line, no wrapping
    /// quotes, no trailing punctuation, and never more than a title's length.
    static func sanitize(_ text: String) -> String? {
        let line = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        guard var title = line else { return nil }

        title = title.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`“”‘’ "))
        while let last = title.last, ".,;:!?".contains(last) { title.removeLast() }
        title = title.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }

        if title.count > 60 {
            title = String(title.prefix(60)).trimmingCharacters(in: .whitespaces)
        }
        return title.isEmpty ? nil : title
    }

    /// The name used when Pi cannot answer: the opening words of the message,
    /// clipped to a title's length. It is not clever, but it is stable, offline,
    /// and recognisably the chat's own.
    static func fallback(for prompt: String) -> String? {
        let message = prompt
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        // A leading slash command is not a task on its own, but its word is part
        // of the task: `/review src` is a review of `src`, not a chat about
        // `src`, so only the slash goes and the command word stays.
        let withoutCommand = message.hasPrefix("/")
            ? String(message.dropFirst())
            : message
        let source = withoutCommand.trimmingCharacters(in: .whitespaces).isEmpty
            ? message
            : withoutCommand
        let words = source
            .split(whereSeparator: \.isWhitespace)
            .prefix(6)
            .joined(separator: " ")
        let clipped = String(words.prefix(48)).trimmingCharacters(in: .whitespaces)
        return clipped.isEmpty ? nil : clipped
    }
}
