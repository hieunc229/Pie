//
//  ConversationView.swift
//  PiCode
//
//  The live transcript. Pi is the runtime, so this view is a projection of Pi's
//  messages plus the events PiCode received while they streamed.
//

import QuartzCore
import SwiftUI

/// The transcript viewport's height, measured behind the scroll view so the
/// prefetch below can reason in whole windows.
private struct TranscriptViewportHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// How far the content's top edge sits above the viewport's top while the
/// user scrolls up. Zero at the very top; it grows as the conversation
/// scrolls down, so a small value means the top is near.
private struct TranscriptTopGapKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// The transcript content's full height. While a session opens, every change
/// to it is a row that materialized or a Markdown block that finished sizing
/// — the bottom the first scroll landed on has moved, so opening follows it.
private struct TranscriptContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

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

    @State var isPinnedToBottom = true
    @State var isOpeningSession = true
    @State var scrollState = ConversationScrollState()
    @State var scrollAnchor = TranscriptScrollAnchor()
    @State var virtualizer = TranscriptVirtualizer()

    let bottomAnchor = "picode-transcript-bottom"
    private let transcriptSpace = "picode-transcript"

    var body: some View {
        ScrollViewReader { proxy in
            // Sized by what it is offered, never by its content: see
            // `TranscriptViewportLayout`.
            TranscriptViewportLayout {
                ScrollView {
                    // The rows' column, shared with the floating composer
                    // (`ConversationColumn`), so the box lines up with the text.
                    ConversationColumn {
                        // A transcript shorter than the viewport starts at the top,
                        // where the landing's first prompt flies to, instead of
                        // resting on `defaultScrollAnchor(.bottom)`. The filler is a
                        // sibling, so the measurements below still describe the
                        // rows alone.
                        ZStack(alignment: .top) {
                            Color.clear
                                .containerRelativeFrame(.vertical)
                                .allowsHitTesting(false)

                            // Eager, not lazy. A `LazyVStack` guesses the height of rows it
                            // has not built and corrects the guess as they scroll in, so
                            // the content height jumped by hundreds of points mid-scroll
                            // and every newly visible reply was built in the scroll frame.
                            // Only a window of history is loaded (it grows a turn at a time,
                            // ahead of the reader — `startIdleHistoryFill`), each row is
                            // built once, and rows are equatable, so a streaming flush
                            // re-renders the one row that grew.
                            TranscriptStackLayout(spacing: 20) {
                                if controller.isLoadingTranscriptHistory {
                                    HStack(spacing: 8) {
                                        ProgressView().controlSize(.small)
                                        Text("Loading earlier messages…")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .center)
                                }

                                // An empty chat draws nothing here: its landing (the
                                // question over a centred composer) belongs to
                                // `SessionView`, which owns the composer it moves.
                                if !controller.items.isEmpty {
                                    // `controller.rows` is the folded layout, computed
                                    // once per transcript change. A finished turn's
                                    // work is one “Worked for” line with Pi's answer left
                                    // in the open; while a turn streams each task is its
                                    // own line instead, so the work is visible as it
                                    // happens. The rows are built from the same array the
                                    // controller holds, so a line grows in place while a
                                    // turn is streaming.
                                    ConversationRowsView(controller: controller, virtualizer: virtualizer)
                                }

                                if showsThinkingIndicator {
                                    ThinkingIndicatorRow()
                                        .transition(.opacity)
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
                                }
                                .id(bottomAnchor)
                            }
                            .scrollTargetLayout()
                            .padding(.top, 12)
                            .background(
                                GeometryReader { geo in
                                    TranscriptScrollViewFinder { scrollAnchor.attach($0) }
                                    Color.clear.preference(key: TranscriptContentHeightKey.self,
                                                           value: geo.size.height)
                                        .preference(key: TranscriptBottomPositionKey.self,
                                                    value: geo.frame(in: .named(transcriptSpace)).maxY)
                                        .preference(key: TranscriptTopGapKey.self,
                                                    value: max(0, -geo.frame(in: .named(transcriptSpace)).minY))
                                }
                            )
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .defaultScrollAnchor(.bottom)
            }
            .coordinateSpace(name: transcriptSpace)
            .background(AppTheme.background)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: TranscriptViewportHeightKey.self,
                                           value: proxy.size.height)
                }
            )
            .onPreferenceChange(TranscriptViewportHeightKey.self) {
                scrollState.viewportHeight = $0
                followLatestWhileOpening(proxy)
            }
            .onPreferenceChange(TranscriptBottomPositionKey.self) { bottom in
                scrollState.bottomY = bottom
                guard let bottom, scrollState.viewportHeight > 0 else { return }
                if isOpeningSession {
                    followLatestWhileOpening(proxy)
                } else if !scrollState.isPrepending {
                    let pinned = bottom <= scrollState.viewportHeight + 2
                    if isPinnedToBottom != pinned { isPinnedToBottom = pinned }
                }
            }
            .onPreferenceChange(TranscriptContentHeightKey.self) { _ in
                followLatestWhileOpening(proxy)
            }
            .onPreferenceChange(TranscriptTopGapKey.self) { topGap in
                if topGap != scrollState.topGap { scrollState.lastScrollActivity = CACurrentMediaTime() }
                scrollState.topGap = topGap
                prefetchEarlierTranscript(topGap: topGap)
                virtualizer.update(topGap: topGap, viewportHeight: scrollState.viewportHeight)
            }
            // Assistant text names files the way the agent saw them — usually
            // relative to the project — and change chips name them the way Pi
            // reported them, so both are resolved and handed to the inspector
            // here rather than in every row.
            .environment(\.piCodeOpenFile, PiCodeOpenFileAction(identity: ObjectIdentifier(controller)) { path, line in
                state.openInInspector(path: resolve(path), line: line)
            })
            .environment(\.piCodeOpenChange, PiCodeOpenChangeAction(identity: ObjectIdentifier(controller)) { path in
                state.openInChanges(path: resolve(path))
            })
            .environment(\.piCodeOpenTool, PiCodeOpenToolAction(identity: ObjectIdentifier(controller)) { id in
                state.openInInspector(toolId: id)
            })
            .onAppear {
                virtualizer.screens = state.preferences.transcriptOffscreenScreens
                virtualizer.onHeightChangeAboveViewport = { [scrollAnchor] delta in
                    scrollAnchor.compensate(heightChangeAbove: delta)
                }
                beginOpeningSession(proxy)
            }
            .onChange(of: isOpeningSession) { _, opening in
                virtualizer.isEnabled = !opening
            }
            .onChange(of: state.preferences.transcriptOffscreenScreens) { _, screens in
                virtualizer.screens = screens
                virtualizer.update(topGap: scrollState.topGap, viewportHeight: scrollState.viewportHeight)
            }
            .onChange(of: state.sessionOpenRevision) { _, _ in
                beginOpeningSession(proxy)
            }
            .onChange(of: state.sessionOpenCompletedRevision) { _, _ in
                followLatestWhileOpening(proxy)
            }
            .onDisappear {
                scrollState.generation = UUID()
                scrollState.openingTask?.cancel()
                scrollState.pageTask?.cancel()
                scrollState.idleFillTask?.cancel()
                scrollAnchor.detach()
            }
            .onChange(of: ObjectIdentifier(controller)) { _, _ in
                beginOpeningSession(proxy)
            }
            .onChange(of: controller.sessionFile) { _, _ in
                beginOpeningSession(proxy)
            }
            .onChange(of: controller.items.count) { _, _ in
                if isOpeningSession {
                    showLatest(proxy)
                } else if !scrollState.isPrepending {
                    scrollIfPinned(proxy, animated: false)
                }
            }
            .onChange(of: controller.isLoadingTranscriptHistory) { _, isLoading in
                if isOpeningSession, !isLoading, !controller.items.isEmpty {
                    showLatest(proxy)
                }
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
            // Keep provisional layouts out of sight until the bottom has been
            // measured. Opacity preserves layout and all scroll measurements.
            .opacity(isOpeningSession ? 0 : 1)
            .allowsHitTesting(!isOpeningSession)
            .overlay {
                if isOpeningSession {
                    ProgressView("Loading conversation…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(AppTheme.background)
                }
            }
            // Centred, just above the composer. `bottomInset` is the room the
            // transcript leaves for the floating box (its height plus its own
            // chrome), so resting the pill's bottom edge on that line clears the
            // box by the box's top padding at every prompt size — while a
            // corner-anchored pill ended up *behind* the box on a narrow pane,
            // and always sat away from the text it returns to.
            .overlay(alignment: .bottom) {
                if !isOpeningSession, !isPinnedToBottom {
                    Button {
                        isPinnedToBottom = true
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(bottomAnchor, anchor: .bottom)
                        }
                    } label: {
                        Label("Jump to latest", huge: "arrow-down-01")
                            .font(.callout)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            // A solid fill, not a material: a live blur re-renders
                            // whatever scrolls under it on every frame.
                            .background(AppTheme.composerFill, in: Capsule())
                            .overlay(Capsule().stroke(AppTheme.cardStroke))
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, bottomInset)
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
                statusRow(icon: "shrink", text: "Compacting conversation context…", showsSpinner: true)
            }
            if let retry = controller.retryDescription {
                statusRow(icon: "refresh", text: "Retrying: \(retry)", showsSpinner: true)
            }
            if let note = controller.summarizationNote {
                statusRow(icon: "clock-01", text: note, showsSpinner: true)
            }
        }
    }

    /// The default “Thinking…” line: drawn whenever a reply is still coming but
    /// nothing on screen says so. That is right after a prompt is sent (before Pi
    /// has answered anything), while Pi reasons (reasoning has no row of its own),
    /// and between steps once the last thing drawn has finished. A row that is
    /// already visibly moving — a live run with its spinner, a running call, an
    /// answer still streaming — or a footer status (compacting, retrying) is the
    /// loading state instead, so the two never show at once.
    private var showsThinkingIndicator: Bool {
        guard let last = controller.rows.last else { return false }
        let lastItem = last.items.last
        let awaitingFirstEvent = lastItem?.kind == .user && lastItem?.isStreaming == true
        guard controller.hasPendingWork || awaitingFirstEvent else { return false }
        guard !controller.isCompacting,
              controller.retryDescription == nil,
              controller.summarizationNote == nil else { return false }

        switch last {
        case .group(let items, let isLiveTurn, _):
            // A live run spins on its own line unless it is showing a failure
            // or cancellation pill there instead.
            guard isLiveTurn else { return true }
            return items.contains { $0.toolStatus == .failure || $0.toolStatus == .cancelled }
        case .item(let item):
            switch item.kind {
            case .assistant: return !item.isStreaming
            case .toolCall: return item.toolStatus.isTerminal
            default: return true
            }
        }
    }

    private func statusRow(icon: String, text: String, showsSpinner: Bool) -> some View {
        HStack(spacing: 8) {
            if showsSpinner {
                ProgressView().controlSize(.small)
            } else {
                HugeIcon(name: icon).foregroundStyle(.secondary)
            }
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Rows

    // The rows are `PiSessionController.rows`: `TranscriptRows`' layout, minus the
    // runs that have nothing to show, computed once per transcript change rather
    // than inside this body.

    // MARK: - Scrolling

    /// Cheap change signal for streaming text so the view follows new output
    /// without re-reading the whole transcript array. UTF-8 lengths, not
    /// `count`: a native string knows its UTF-8 length, while `count` walks
    /// every grapheme — the whole reply, on every flush.
    private var streamingSignature: Int {
        guard let last = controller.items.last else { return 0 }
        return last.id.hashValue &+ last.text.utf8.count &+ (last.toolOutput?.utf8.count ?? 0)
    }

}

/// “[spinner] Thinking…” — the transcript's default loading state, laid out like
/// a run's folded line so it reads as the next step rather than a banner.
struct ThinkingIndicatorRow: View {
    var body: some View {
        HStack(spacing: 7) {
            ProgressView()
                .controlSize(.small)
                .frame(width: 16, alignment: .center)
            Text("Thinking…")
                .font(Typography.body)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Thinking")
    }
}
