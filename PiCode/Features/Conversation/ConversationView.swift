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
    /// last row. The room is drawn *above* the bottom anchor, not as padding below
    /// it: `scrollTo(_:anchor: .bottom)` aligns the identified view's bottom edge
    /// with the viewport's, so room drawn after the anchor gets scrolled out of
    /// sight while a running turn auto-scrolls and the newest row ends flush against
    /// the box. Keeping the anchor itself 1pt (rather than giving it the room's
    /// height) keeps "pinned" meaning the very bottom. The gap is then the same
    /// whether the transcript is short (nothing to scroll) or long (auto-scrolled
    /// while a turn streams).
    var bottomInset: CGFloat = 0

    @State private var isPinnedToBottom = true

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
                            // `controller.rows` is the folded layout, computed
                            // once per transcript change. A finished turn's
                            // work is one “Worked for” line with Pi's answer left
                            // in the open; while a turn streams each task is its
                            // own line instead, so the work is visible as it
                            // happens. The rows are built from the same array the
                            // controller holds, so a line grows in place while a
                            // turn is streaming.
                            ForEach(controller.rows) { row in
                                switch row {
                                case .item(let item):
                                    TranscriptRowView(item: item, controller: controller)
                                case .group(let items, let isLiveTurn):
                                    ToolGroupView(row: .group(items, isLiveTurn: isLiveTurn), controller: controller)
                                }
                            }
                        }

                        statusFooter

                        // The room for the composer, then the content's true 1pt
                        // bottom. The room sits *above* the anchor so scrolling
                        // the anchor to the bottom keeps the room on screen; the
                        // anchor stays 1pt so `isPinnedToBottom` still means the
                        // very bottom rather than "within the composer's height".
                        VStack(spacing: 0) {
                            Color.clear
                                .frame(height: 8 + bottomInset)

                            Color.clear
                                .frame(height: 1)
                                .id(bottomAnchor)
                        }
                        .onAppear { isPinnedToBottom = true }
                        .onDisappear { isPinnedToBottom = false }
                    }
                    .padding(.top, 26)
                }
                .frame(maxWidth: .infinity)
            }
            .background(AppTheme.background)
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
            .environment(\.piCodeOpenTool, PiCodeOpenToolAction { id in
                state.openInInspector(toolId: id)
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
            // The composer grows and shrinks as the prompt does; when it does, the
            // room at the end of the transcript has to move with it or the last row
            // drifts back under the box until the next streaming update.
            .onChange(of: bottomInset) { _, _ in
                scrollIfPinned(proxy, animated: false)
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
        }
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

    // The rows are `PiSessionController.rows`: `TranscriptRows`' layout, minus the
    // runs that have nothing to show, computed once per transcript change rather
    // than inside this body.

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
