//
//  HarnessCapabilities.swift
//  PiCode
//
//  What a harness can do over its headless protocol. The UI gates controls on
//  these flags instead of assuming every harness behaves like Pi: a harness
//  without session trees never draws a tree pane, one without steering never
//  offers a steering menu, and so on.
//

import Foundation

struct HarnessCapabilities: OptionSet, Sendable, Hashable {
    let rawValue: Int

    init(rawValue: Int) { self.rawValue = rawValue }

    /// Assistant text streams token-by-token while a turn runs.
    static let streamingText = HarnessCapabilities(rawValue: 1 << 0)
    /// Live tool-call lifecycle (start/update/end) is reported.
    static let toolCalls = HarnessCapabilities(rawValue: 1 << 1)
    /// Partial tool output streams while a tool runs.
    static let toolStreamingOutput = HarnessCapabilities(rawValue: 1 << 2)
    /// Reasoning/thinking text is exposed by the provider.
    static let thinking = HarnessCapabilities(rawValue: 1 << 3)
    /// Image attachments can be sent with a prompt.
    static let images = HarnessCapabilities(rawValue: 1 << 4)
    /// A running turn can be steered mid-flight.
    static let steering = HarnessCapabilities(rawValue: 1 << 5)
    /// A follow-up can be queued behind the running turn.
    static let followUp = HarnessCapabilities(rawValue: 1 << 6)
    /// The queue can be inspected and edited message-by-message.
    static let queueEditing = HarnessCapabilities(rawValue: 1 << 7)
    /// The running turn can be aborted.
    static let abort = HarnessCapabilities(rawValue: 1 << 8)
    /// Sessions persist and can be resumed.
    static let sessions = HarnessCapabilities(rawValue: 1 << 9)
    /// The session has a parent/child branch tree.
    static let sessionTree = HarnessCapabilities(rawValue: 1 << 10)
    /// A new session can be forked from an earlier entry.
    static let fork = HarnessCapabilities(rawValue: 1 << 11)
    /// The active branch can be cloned into a new session.
    static let clone = HarnessCapabilities(rawValue: 1 << 12)
    /// Context compaction is available.
    static let compaction = HarnessCapabilities(rawValue: 1 << 13)
    /// Automatic retry of failed provider calls is reported.
    static let autoRetry = HarnessCapabilities(rawValue: 1 << 14)
    /// Extension/host UI dialogs (select, confirm, input, editor) can be rendered.
    static let extensionUI = HarnessCapabilities(rawValue: 1 << 15)
    /// A runtime model catalog is discoverable and selectable.
    static let modelCatalog = HarnessCapabilities(rawValue: 1 << 16)
    /// Thinking levels are discoverable and selectable per model.
    static let thinkingLevels = HarnessCapabilities(rawValue: 1 << 17)
    /// Project trust decisions are part of the harness.
    static let trust = HarnessCapabilities(rawValue: 1 << 18)
    /// Provider credentials/config can be managed by PiCode for this harness.
    static let providerConfig = HarnessCapabilities(rawValue: 1 << 19)
    /// Packages/extensions can be discovered and managed.
    static let packageManagement = HarnessCapabilities(rawValue: 1 << 20)
    /// The session can be exported to HTML.
    static let exportHTML = HarnessCapabilities(rawValue: 1 << 21)
    /// An interactive bash surface is available in-session.
    static let bash = HarnessCapabilities(rawValue: 1 << 22)
    /// The harness reports when a completed turn produced an answer.
    static let completionSignal = HarnessCapabilities(rawValue: 1 << 23)

    /// A reasonable baseline for a Pi-family RPC harness.
    static let piFamily: HarnessCapabilities = [
        .streamingText, .toolCalls, .toolStreamingOutput, .thinking, .images,
        .steering, .followUp, .queueEditing, .abort, .sessions, .sessionTree,
        .fork, .clone, .compaction, .autoRetry, .extensionUI, .modelCatalog,
        .thinkingLevels, .trust, .providerConfig, .packageManagement,
        .exportHTML, .bash, .completionSignal
    ]
}
