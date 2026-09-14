//
//  ActionContent.swift
//  PiCode
//
//  What the three quiet actions draw when a run is opened. They are not tool
//  cards: a command and its output are one terminal block, a read is the file it
//  read, and an edit is the change it made. The generic “Arguments / Output” form
//  `ToolCallContent` draws would put Pi’s JSON in front of all three.
//

import SwiftUI

/// A command and what it printed, as one terminal transcript.
///
/// Pi’s `bash` carries the command in its arguments and the output in its result,
/// which the old content drew as two separate boxes under a JSON argument block.
/// A terminal shows one stream — the command, then its output — so that is what
/// this draws, in the shell’s own colours.
struct CommandStepContent: View {
    var item: TranscriptItem

    var body: some View {
        if let transcript {
            SyntaxText(text: transcript, language: .shell)
        } else if item.isStreaming {
            ToolRunningLine()
        }
    }

    /// The command, then the output, in one string: what was typed and what came
    /// back belong to the same stream, and separating them would be the form this
    /// view exists to avoid.
    private var transcript: String? {
        let command = item.commandText
        let output = item.toolOutput ?? ""
        switch (command, output.isEmpty) {
        case (let command?, false): return command + "\n" + output
        case (let command?, true): return command
        case (nil, false): return output
        default: return nil
        }
    }
}

/// The file a read returned, highlighted in the language its path names.
struct ReadStepContent: View {
    var item: TranscriptItem

    var body: some View {
        if let output = item.toolOutput, !output.isEmpty {
            SyntaxText(text: output, language: language)
        } else if item.isStreaming {
            ToolRunningLine()
        }
    }

    private var language: SyntaxLanguage {
        if let path = item.toolFilePath { return SyntaxLanguage(path: path) }
        return .plain
    }
}

/// An edit as a diff.
///
/// The two halves Pi sends — `oldText` and `newText` — are the removed and the
/// added lines, so the diff is rebuilt from them and coloured the way `git`
/// colours one: removals red, additions green. The output is not drawn: an edit’s
/// result is the change, not the sentence saying it succeeded.
struct EditStepContent: View {
    var item: TranscriptItem

    var body: some View {
        let blocks = item.editBlocks
        if !blocks.isEmpty {
            SyntaxText(text: ToolDiff.unified(blocks), language: .diff)
        } else if item.isStreaming {
            ToolRunningLine()
        }
    }
}

/// The one line a step shows while it has nothing to draw yet.
struct ToolRunningLine: View {
    var body: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            Text("Running…")
                .font(Typography.body)
                .foregroundStyle(.secondary)
        }
    }
}

/// A unified diff rebuilt from Pi’s edit arguments.
///
/// There is no file header, because the file is already named on the row this
/// opens under, and no line numbers, because the two halves are the hunk itself
/// rather than an offset into a file. Several edits are separated by a hunk line
/// so a multi-edit call does not read as one run-on change.
enum ToolDiff {
    static func unified(_ blocks: [(old: String, new: String)]) -> String {
        var lines: [String] = []
        for (index, block) in blocks.enumerated() {
            if blocks.count > 1 { lines.append("@@ edit \(index + 1)") }
            append(block.old, marker: "-", to: &lines)
            append(block.new, marker: "+", to: &lines)
        }
        return lines.joined(separator: "\n")
    }

    private static func append(_ text: String, marker: String, to lines: inout [String]) {
        guard !text.isEmpty else { return }
        var parts = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        // A trailing newline is a terminator, not a blank line: drop it so the last
        // real line is the last line the block shows.
        if parts.last == "" { parts.removeLast() }
        for part in parts { lines.append(marker + part) }
    }
}
