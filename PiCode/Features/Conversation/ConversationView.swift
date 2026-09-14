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
                LazyVStack(alignment: .leading, spacing: 20) {
                    if controller.items.isEmpty {
                        emptyState
                    } else {
                        ForEach(controller.items) { item in
                            TranscriptRowView(item: item, controller: controller)
                                .id(item.id)
                        }
                    }

                    statusFooter

                    Color.clear
                        .frame(height: 1)
                        .id(bottomAnchor)
                        .onAppear { isPinnedToBottom = true }
                        .onDisappear { isPinnedToBottom = false }
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 8 + bottomInset)
                .frame(maxWidth: 860, alignment: .leading)
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
            if !controller.queue.isEmpty {
                queuePreview
            }
        }
    }

    /// A running turn is one compact line: what Pi is doing, which model, and how
    /// long it has been going. Expanding it shows the recent activity timeline
    /// inline, so the user does not have to leave the transcript to find out why
    /// nothing has appeared yet.
    private var streamingRow: some View {
        DisclosureGroup(isExpanded: $isActivityExpanded) {
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
        } label: {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Pi is working")
                    .font(.callout)
                if let model = controller.streamingModel ?? controller.model?.displayName {
                    Text(model)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let started = controller.streamingStartedAt {
                    TimelineView(.periodic(from: started, by: 1)) { context in
                        Text(Format.duration(context.date.timeIntervalSince(started)))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .disclosureGroupStyle(.automatic)
        .accessibilityLabel("Pi is working. Expand for recent activity.")
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

    private var queuePreview: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !controller.queue.steering.isEmpty {
                Text("Queued steering messages")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(controller.queue.steering) { message in
                    queuedRow(message.text, icon: "arrow.turn.down.right")
                }
            }
            if !controller.queue.followUp.isEmpty {
                Text("Queued follow-ups")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(controller.queue.followUp) { message in
                    queuedRow(message.text, icon: "text.append")
                }
            }
        }
        .padding(.top, 4)
    }

    private func queuedRow(_ text: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon)
                .imageScale(.small)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
    }

    private var emptyState: some View {
        EmptyStateView(
            systemImage: "text.bubble",
            title: "Nothing here yet",
            message: "Ask Pi to do something below. PiCode streams Pi's real messages, tool calls, and diffs as they happen."
        )
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
