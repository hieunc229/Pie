//
//  ConversationView.swift
//  PiCode
//
//  The live transcript. Pi is the runtime, so this view is a projection of Pi's
//  messages plus the events PiCode received while they streamed.
//

import SwiftUI

struct ConversationView: View {
    @Bindable var state: AppState
    var controller: PiSessionController
    /// Room to leave at the end of the transcript for the floating composer. The
    /// composer is an overlay, so without this its own height would cover the
    /// last row — the padding goes *after* the bottom anchor, so "jump to latest"
    /// still lands the newest message above the box.
    var bottomInset: CGFloat = 0

    @State private var isPinnedToBottom = true
    @State private var isActivityExpanded = false

    private let bottomAnchor = "picode-transcript-bottom"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // The rows' column, shared with the floating composer
                // (`ConversationColumn`), so the box lines up with the text.
                ConversationColumn {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        if controller.items.isEmpty {
                            emptyState
                        } else {
                            // `TranscriptRows.group` folds a finished turn's
                            // work into one “Worked for” line and leaves Pi's
                            // answer in the open; while a turn is streaming it
                            // folds runs of neighbouring steps instead. The rows
                            // are built from the same array the controller holds,
                            // so a line grows in place while a turn is streaming.
                            ForEach(transcriptRows) { row in
                                switch row {
                                case .item(let item):
                                    TranscriptRowView(item: item, controller: controller)
                                case .group(let items):
                                    ToolGroupView(items: items, controller: controller)
                                }
                            }
                        }

                        statusFooter

                        Color.clear
                            .frame(height: 1)
                            .id(bottomAnchor)
                            .onAppear { isPinnedToBottom = true }
                            .onDisappear { isPinnedToBottom = false }
                    }
                    .padding(.top, 18)
                    .padding(.bottom, 8 + bottomInset)
                }
                .frame(maxWidth: .infinity)
            }
            .background(Color(nsColor: .textBackgroundColor))
            // Assistant text names files the way the agent saw them — usually
            // relative to the project — and change chips name them the way Pi
            // reported them, so both are resolved and handed to the inspector
            // here rather than in every row.
            .environment(\.piCodeOpenFile, PiCodeOpenFileAction { path, line in
                state.openInInspector(path: resolve(path), line: line)
            })
            .environment(\.piCodeOpenChange, PiCodeOpenChangeAction { path in
                state.openInChanges(path: resolve(path))
            })
            .onChange(of: controller.items.count) { _, _ in
                scrollIfPinned(proxy, animated: true)
            }
            .onChange(of: streamingSignature) { _, _ in
                scrollIfPinned(proxy, animated: false)
            }
            .onChange(of: controller.currentTurnStartedAt) { _, newValue in
                if newValue != nil { scrollIfPinned(proxy, animated: true) }
            }
            .overlay(alignment: .bottomTrailing) {
                if !isPinnedToBottom {
                    Button {
                        isPinnedToBottom = true
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(bottomAnchor, anchor: .bottom)
                        }
                    } label: {
                        Label("Jump to latest", systemImage: "arrow.down")
                            .font(.callout)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(.regularMaterial, in: Capsule())
                            .overlay(Capsule().stroke(.separator))
                    }
                    .buttonStyle(.plain)
                    .padding(16)
                    .transition(.opacity)
                }
            }
        }
    }

    func resolve(_ path: String) -> String {
        guard !path.isAbsolutePath else { return path }
        return URL(fileURLWithPath: controller.projectPath)
            .appendingPathComponent(path)
            .standardizedFileURL
            .path
    }

    // MARK: - Footer

    @ViewBuilder
    private var statusFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            if controller.isCompacting {
                statusRow(icon: "arrow.down.right.and.arrow.up.left", text: "Compacting conversation context…", showsSpinner: true)
            }
            if let retry = controller.retryDescription {
                statusRow(icon: "arrow.clockwise", text: "Retrying: \(retry)", showsSpinner: true)
            }
            if let note = controller.summarizationNote {
                statusRow(icon: "text.badge.clock", text: note, showsSpinner: true)
            }
            if controller.isStreaming, controller.retryDescription == nil, !controller.isCompacting {
                streamingRow
            }
        }
    }

    /// One line: that Pi is working, and how long the *whole turn* has taken. The
    /// clock deliberately runs from `currentTurnStartedAt`, not
    /// `streamingStartedAt` — the latter is cleared every time an assistant
    /// message folds, so a turn with several messages looked like several short
    /// ones. No disclosure triangle and no model name: the line states one fact,
    /// and the activity timeline stays one click away on the line itself.
    private var streamingRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { isActivityExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Pi is working")
                        .font(.callout)
                    if let started = controller.currentTurnStartedAt ?? controller.streamingStartedAt {
                        TimelineView(.periodic(from: started, by: 1)) { context in
                            Text(Format.duration(context.date.timeIntervalSince(started)))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isActivityExpanded ? "Hide recent activity" : "Show recent activity")

            if isActivityExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(recentActivity) { entry in
                        ActivityRowView(entry: entry, showsTimestamp: true)
                    }
                    if recentActivity.isEmpty {
                        Text("Nothing recorded yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 6)
                .padding(.leading, 2)
            }
        }
        .accessibilityLabel("Pi is working. Activate to show recent activity.")
    }

    private var recentActivity: [ActivityEntry] {
        Array(controller.activity.suffix(8).reversed())
    }

    private func statusRow(icon: String, text: String, showsSpinner: Bool) -> some View {
        HStack(spacing: 8) {
            if showsSpinner {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: icon).foregroundStyle(.secondary)
            }
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var emptyState: some View {
        EmptyStateView(
            systemImage: "text.bubble",
            title: "Nothing here yet",
            message: "Ask Pi to do something below. PiCode streams Pi's real messages, tool calls, and diffs as they happen."
        )
    }

    // MARK: - Rows

    /// The rows the transcript draws: `TranscriptRows`' layout, minus the runs
    /// that have nothing to show. Reasoning is hidden, so a run that is only
    /// reasoning would be a line that opens onto nothing.
    private var transcriptRows: [TranscriptRow] {
        TranscriptRows.group(controller.items).filter { row in
            guard case .group(let items) = row else { return true }
            return items.contains { $0.kind != .thinking }
        }
    }

    // MARK: - Scrolling

    /// Cheap change signal for streaming text so the view follows new output
    /// without re-reading the whole transcript array.
    private var streamingSignature: Int {
        guard let last = controller.items.last else { return 0 }
        return last.id.hashValue &+ last.text.count &+ (last.toolOutput?.count ?? 0)
    }

    private func scrollIfPinned(_ proxy: ScrollViewProxy, animated: Bool) {
        guard isPinnedToBottom else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo(bottomAnchor, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(bottomAnchor, anchor: .bottom)
        }
    }
}
