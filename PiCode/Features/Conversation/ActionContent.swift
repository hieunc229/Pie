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
            ActionCodeBlock(text: transcript, language: .shell, isPlain: true)
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
            ActionCodeBlock(text: output, language: language, isPlain: true)
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
            ActionCodeBlock(text: ToolDiff.unified(blocks), language: .diff)
        } else if item.isStreaming {
            ToolRunningLine()
        }
    }
}

/// The well the three quiet actions draw their machine text in.
///
/// A command's terminal transcript, a file's contents and a diff are all the same
/// kind of thing — a block of text to be scanned rather than read — so they share
/// one container. A diff keeps the well: its red/green lines are a class of their
/// own and the recessed background is what makes them read as one block. A command
/// and a read do not — in the panel they are the only thing on screen, so they are
/// drawn as plain machine text with no border or background to box them in.
/// All three are set two steps below the app's reading size, because the panel is
/// a reference to glance at beside the conversation, not a second reading column.
struct ActionCodeBlock: View {
    var text: String
    var language: SyntaxLanguage
    /// Plain machine text, without the recessed well. Commands and reads use this;
    /// diffs and any other caller get the well.
    var isPlain: Bool = false

    var body: some View {
        if isPlain {
            SyntaxText(text: text, language: language, font: Typography.codeBlockCompact)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            SyntaxText(text: text, language: language, font: Typography.codeBlockCompact)
                .padding(9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06))
                )
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
