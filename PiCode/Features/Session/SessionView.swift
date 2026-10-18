//
//  SessionView.swift
//  PiCode
//
//  One active session: transcript, trust gate, and the composer.
//
//  The composer *floats over* the transcript rather than sitting under it. It is
//  the only thing at the bottom of the window, and the transcript keeps the whole
//  height behind it — so a long conversation is never pushed up by the prompt
//  box, and the box never grows past two lines (§6). Nothing is rendered below
//  the composer: the facts a footer used to repeat (runtime, model, thinking,
//  context, tool counts, git branch, extension status) are in the inspector's
//  Context pane. The live status — streaming, compacting, retrying — is in the
//  transcript's own footer; the queue sits directly above the composer, because
//  it is the next thing the user is about to send, not something to scroll past.
//

import SwiftUI

/// How tall the floating composer turned out to be, so the transcript can leave
/// exactly that much room at the bottom of its content.
private struct ComposerHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Where the composer's top edge sits in the pane, so the first prompt of a new
/// chat can take off from the box it was typed in.
private struct ComposerTopKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct SessionView: View {
    @Bindable var state: AppState
    var controller: PiSessionController
    var composerFocusTick: Int

    @State private var composerHeight: CGFloat = 0
    @State private var composerTop: CGFloat = 0
    /// Whether the empty-chat landing is drawn: the question with the composer
    /// right under it, both centred in the pane. It trails `isLanding` so the
    /// change can be animated (or not) depending on what caused it.
    @State private var showsLanding: Bool?
    /// The controller `showsLanding` was last synced for; a landing change that
    /// comes with a different controller is a session switch, not a send.
    @State private var landingControllerID: ObjectIdentifier?
    /// The first prompt of a new chat while it flies from the composer to the
    /// top of the transcript. The transcript is hidden until it lands.
    @State private var flyingPrompt: FlyingPrompt?

    private static let paneSpace = "picode-session-pane"
    private static let landingAnimation = Animation.spring(response: 0.5, dampingFraction: 0.86)

    /// The transcript's own backdrop, so the fade under the composer hides
    /// scrolled-away rows in the colour they were already drawn on.
    private var backdrop: Color { AppTheme.background }

    var body: some View {
        VStack(spacing: 0) {
            if showsConnectionBanner {
                connectionBanner
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
            }

            ConversationView(state: state, controller: controller,
                             bottomInset: composerHeight + 16)
                .id(ObjectIdentifier(controller))
                // Hidden, not removed, while the landing shows and while the
                // first prompt is in flight: the transcript keeps measuring
                // itself, and its first row appears exactly where the flying
                // copy lands.
                .opacity(isShowingLanding || flyingPrompt != nil ? 0 : 1)
                .overlay(alignment: .bottom) { composerFade }
                .overlay { composerLayer }
                .overlay(alignment: .top) { promptFlight }
                .coordinateSpace(name: Self.paneSpace)
        }
        // Notifications no longer float over the transcript: the content header's
        // bell opens them in the right panel, where the list has the full height
        // of the column and cannot cover the conversation.
        .animation(.easeInOut(duration: 0.18), value: controller.trustState)
        .onAppear { syncLanding() }
        .onChange(of: isLanding) { wasLanding, landing in
            syncLanding(sent: wasLanding && !landing)
        }
    }

    // MARK: - Landing

    /// An empty chat with nothing left to load: the question and the composer
    /// sit together in the middle of the pane until the first prompt is sent.
    private var isLanding: Bool {
        let waitingForOpen = state.sessionOpeningKey == state.selectedSessionKey
            && state.sessionOpenRevision != state.sessionOpenCompletedRevision
        return controller.items.isEmpty
            && !controller.isLoadingTranscriptHistory
            && !waitingForOpen
    }

    private var isShowingLanding: Bool { showsLanding ?? isLanding }

    /// Follows `isLanding`. Sending the first prompt animates: the composer
    /// drops to the bottom while the prompt flies from it to the top of the
    /// transcript. Anything else — opening another session, a failed send
    /// putting the chat back to empty — just changes the layout.
    private func syncLanding(sent: Bool = false) {
        let controllerID = ObjectIdentifier(controller)
        defer { landingControllerID = controllerID }
        guard landingControllerID == controllerID, showsLanding != nil else {
            showsLanding = isLanding
            return
        }

        if sent, controller.items.count == 1,
           let first = controller.items.first, first.kind == .user {
            let flight = FlyingPrompt(text: first.text, from: composerTop + 8)
            flyingPrompt = flight
            withAnimation(Self.landingAnimation) { showsLanding = false }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(550))
                guard flyingPrompt?.id == flight.id else { return }
                withAnimation(.easeOut(duration: 0.15)) { flyingPrompt = nil }
            }
        } else {
            flyingPrompt = nil
            withAnimation(Self.landingAnimation) { showsLanding = isLanding }
        }
    }

    /// The composer, at the bottom of the pane in a conversation and under the
    /// question in the middle of it in an empty chat. It is the same view in
    /// both places (only the spacers around it come and go), so it keeps its
    /// focus and draft while it moves.
    private var composerLayer: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            if isShowingLanding {
                BuildPromptHero(projectName: controller.projectName)
                    .padding(.bottom, 6)
                    .transition(.opacity.combined(with: .offset(y: -16)))
            }
            ConversationColumn { composerStack }
                .onPreferenceChange(ComposerHeightKey.self) { composerHeight = $0 }
                .onPreferenceChange(ComposerTopKey.self) { composerTop = $0 }
            if isShowingLanding {
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private var promptFlight: some View {
        if let flyingPrompt {
            FlyingPromptBubble(prompt: flyingPrompt, to: 12, animation: Self.landingAnimation)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }

    // MARK: - Floating composer

    /// The fade sits *behind* the box, in the transcript's colours, and clicks
    /// anywhere on it go through to the transcript. The landing has nothing
    /// under the box to fade, so it is drawn only in a conversation.
    ///
    /// The box is put in `ConversationColumn`, the same column the transcript's
    /// rows are in, so it is exactly as wide as the text it floats over instead
    /// of as wide as the pane.
    private var composerFade: some View {
        LinearGradient(colors: [backdrop.opacity(0), backdrop],
                       startPoint: .top, endPoint: .bottom)
            .frame(height: composerHeight + 28)
            .opacity(isShowingLanding ? 0 : 1)
            .allowsHitTesting(false)
    }

    /// The widgets an extension set. Both placements are drawn above the box:
    /// PiCode has nothing below the composer any more (§6), and a widget that is
    /// received but never shown is worse than one in the other slot.
    private var composerStack: some View {
        VStack(spacing: 8) {
            ComposerView(
                state: state,
                controller: controller,
                focusTick: composerFocusTick,
                tray: hasTrayContent ? AnyView(trayContent) : nil
            )
        }
        .padding(.top, 8)
        .padding(.bottom, 16)
        .background(GeometryReader { proxy in
            Color.clear
                .preference(key: ComposerHeightKey.self, value: proxy.size.height)
                .preference(key: ComposerTopKey.self,
                            value: proxy.frame(in: .named(Self.paneSpace)).minY)
        })
    }

    // MARK: - Tray

    /// Everything the agent has to say above the composer, drawn in the
    /// composer's tray: one light, borderless band tucked behind the box.
    private var trayContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            ExtensionWidgetStrip(controller: controller, placement: .aboveEditor)
            ExtensionWidgetStrip(controller: controller, placement: .belowEditor)

            if let notice = controller.compatibilityNotices.last {
                BannerView(
                    level: .info,
                    title: "Pi offered a surface PiCode cannot render: \(notice.surface)",
                    message: notice.detail
                )
            }

            if needsTrustDecision {
                ProjectTrustPrompt(controller: controller)
            } else if controller.trustState == .untrusted {
                UntrustedProjectNotice(controller: controller)
            }

            if !controller.queue.isEmpty {
                queuedPrompts
            }
        }
    }

    private var hasTrayContent: Bool {
        !(controller.extensionWidgets[.aboveEditor] ?? [:]).isEmpty
            || !(controller.extensionWidgets[.belowEditor] ?? [:]).isEmpty
            || !controller.compatibilityNotices.isEmpty
            || needsTrustDecision
            || controller.trustState == .untrusted
            || !controller.queue.isEmpty
    }

    // MARK: - Queue

    /// Prompts typed while Pi was busy, in the order Pi will take them: steers
    /// first, then follow-ups. They stack directly above the composer, so a
    /// prompt that is still waiting its turn can never scroll out of sight — and
    /// "one after another" is visible as a numbered list rather than implied.
    private var queuedPrompts: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                HugeIcon(name: "task-add-01")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button("Clear") { Task { await controller.clearQueue() } }
                    .font(Typography.notice)
                    .buttonStyle(.borderless)
                    .help("Drop everything Pi has queued")
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 6)

            queuedMessageList
                .padding(.bottom, 5)
        }
    }

    /// A short queue grows to fit; a long one scrolls rather than shouldering the
    /// composer off the bottom of the window.
    @ViewBuilder
    private var queuedMessageList: some View {
        let rows = VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(queuedMessages.enumerated()), id: \.element.id) { index, message in
                if index > 0 {
                    Divider().padding(.leading, 32)
                }
                queuedMessageRow(position: index + 1, message)
            }
        }
        if queuedMessages.count > 3 {
            ScrollView { rows }
                .frame(maxHeight: 140)
        } else {
            rows
        }
    }

    private func queuedMessageRow(position: Int, _ message: QueuedPrompt) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(position)")
                .font(Typography.notice.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 16, alignment: .trailing)
            VStack(alignment: .leading, spacing: 1) {
                Text(message.text)
                    .font(Typography.notice)
                    .lineLimit(2)
                    .truncationMode(.tail)
                Text(message.kind.caption)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            queueActions(for: message)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
    }

    /// The three things a queued message can have done to it, as icon buttons so
    /// the row still reads as a line of text. Steering is offered only for a
    /// follow-up: a steering message is already going in at the current tool
    /// boundary, so steering it again would move it for no reason.
    @ViewBuilder
    private func queueActions(for message: QueuedPrompt) -> some View {
        HStack(spacing: 2) {
            if message.kind == .followUp {
                queueButton("arrow-up-right-01", help: "Steer into the current turn") {
                    Task { await controller.act(on: .steer, message: message.text) }
                }
            }
            queueButton("edit-02", help: "Edit in the composer") {
                Task { await controller.act(on: .edit, message: message.text) }
            }
            queueButton("delete-01", help: "Remove from the queue") {
                Task { await controller.act(on: .remove, message: message.text) }
            }
        }
    }

    private func queueButton(
        _ systemImage: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HugeIcon(name: systemImage)
                .imageScale(.small)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help(help)
        .accessibilityLabel(help)
    }

    private var queuedMessages: [QueuedPrompt] {
        controller.queue.steering.map { QueuedPrompt(id: $0.id, text: $0.text, kind: .steer) }
            + controller.queue.followUp.map { QueuedPrompt(id: $0.id, text: $0.text, kind: .followUp) }
    }

    private struct QueuedPrompt: Identifiable {
        enum Kind {
            case steer, followUp

            var caption: String {
                switch self {
                case .steer: return "steers this turn"
                case .followUp: return "runs after this turn"
                }
            }
        }

        var id: UUID
        var text: String
        var kind: Kind
    }

    // MARK: - Connection

    private var showsConnectionBanner: Bool {
        switch controller.connection {
        case .disconnected, .failed: return true
        default: return false
        }
    }

    private var needsTrustDecision: Bool {
        controller.trustState == .asked
    }

    private var connectionBanner: some View {
        BannerView(
            level: .warning,
            title: connectionTitle,
            message: connectionMessage,
            actionTitle: "Restart \(controller.harness.displayName)",
            action: { Task { await controller.restart() } }
        )
    }

    private var connectionTitle: String {
        switch controller.connection {
        case .failed: return "\(controller.harness.displayName) could not start"
        case .disconnected(let reason):
            return "\(controller.harness.displayName) stopped\(reason.map { " (\($0))" } ?? "")"
        default: return controller.connection.label
        }
    }

    private var connectionMessage: String? {
        switch controller.connection {
        case .failed(let message): return message
        case .disconnected: return "The session transcript is still shown. Restart to continue working in this session."
        default: return nil
        }
    }
}

// MARK: - First prompt flight

struct FlyingPrompt: Equatable {
    let id = UUID()
    var text: String
    /// The composer's text line, in the pane's coordinates.
    var from: CGFloat
}

/// A copy of the first prompt that travels from where it was typed — leading
/// edge, in the composer — to where the transcript draws it: a bubble on the
/// trailing edge at the top. It is drawn like `TranscriptRowView`'s user row so
/// the hand-off to the real row is invisible.
private struct FlyingPromptBubble: View {
    var prompt: FlyingPrompt
    var to: CGFloat
    var animation: Animation

    @Environment(\.colorScheme) private var colorScheme
    @State private var landed = false

    var body: some View {
        ConversationColumn {
            Text(prompt.text)
                .font(TranscriptStyle.text)
                .lineSpacing(TranscriptStyle.lineSpacing)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(TranscriptStyle.userBubbleFill(colorScheme).opacity(landed ? 1 : 0),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .frame(maxWidth: 520, alignment: .trailing)
                .frame(maxWidth: .infinity, alignment: landed ? .trailing : .leading)
        }
        .offset(y: landed ? to : prompt.from)
        .onAppear {
            withAnimation(animation) { landed = true }
        }
    }
}
