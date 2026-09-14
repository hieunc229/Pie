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

struct SessionView: View {
    @Bindable var state: AppState
    var controller: PiSessionController
    var composerFocusTick: Int

    @State private var composerHeight: CGFloat = 0

    /// The transcript's own backdrop, so the fade under the composer hides
    /// scrolled-away rows in the colour they were already drawn on.
    private var backdrop: Color { Color(nsColor: .textBackgroundColor) }

    var body: some View {
        VStack(spacing: 0) {
            if showsConnectionBanner {
                connectionBanner
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
            }

            ConversationView(state: state, controller: controller,
                             bottomInset: composerHeight + 16)
                .overlay(alignment: .bottom) { floatingComposer }
        }
        .overlay(alignment: .topTrailing) {
            NotificationStack(controller: controller)
                .padding(12)
        }
        .animation(.easeInOut(duration: 0.18), value: controller.trustState)
    }

    // MARK: - Floating composer

    /// The gradient and the composer share one bottom-aligned stack so the fade
    /// sits *behind* the box, in the same colours, and clicks anywhere on it go
    /// through to the transcript.
    ///
    /// The box is put in `ConversationColumn`, the same column the transcript's
    /// rows are in, so it is exactly as wide as the text it floats over instead
    /// of as wide as the pane.
    private var floatingComposer: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [backdrop.opacity(0), backdrop],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: composerHeight + 28)
                .allowsHitTesting(false)

            ConversationColumn { composerStack }
                .onPreferenceChange(ComposerHeightKey.self) { composerHeight = $0 }
        }
    }

    /// The widgets an extension set. Both placements are drawn above the box:
    /// PiCode has nothing below the composer any more (§6), and a widget that is
    /// received but never shown is worse than one in the other slot.
    private var composerStack: some View {
        VStack(spacing: 8) {
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

            ComposerView(state: state, controller: controller, focusTick: composerFocusTick)
        }
        .padding(.top, 8)
        .padding(.bottom, 16)
        .background(GeometryReader { proxy in
            Color.clear.preference(key: ComposerHeightKey.self, value: proxy.size.height)
        })
    }

    // MARK: - Queue

    /// Prompts typed while Pi was busy, in the order Pi will take them: steers
    /// first, then follow-ups. They stack directly above the composer, so a
    /// prompt that is still waiting its turn can never scroll out of sight — and
    /// "one after another" is visible as a numbered list rather than implied.
    private var queuedPrompts: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "text.append")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
                Text(queuedMessages.count == 1 ? "1 message queued" : "\(queuedMessages.count) messages queued")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button("Clear") { Task { await controller.clearQueue() } }
                    .font(.caption)
                    .buttonStyle(.borderless)
                    .help("Drop everything Pi has queued")
            }
            .padding(.horizontal, 10)
            .padding(.top, 7)
            .padding(.bottom, 5)

            queuedMessageList
                .padding(.bottom, 5)
        }
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.separator.opacity(0.6))
        )
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
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 16, alignment: .trailing)
            VStack(alignment: .leading, spacing: 1) {
                Text(message.text)
                    .font(Typography.body)
                    .lineLimit(2)
                    .truncationMode(.tail)
                Text(message.kind.caption)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
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
            actionTitle: "Restart Pi",
            action: { Task { await controller.restart() } }
        )
    }

    private var connectionTitle: String {
        switch controller.connection {
        case .failed: return "Pi could not start"
        case .disconnected(let reason): return "Pi stopped\(reason.map { " (\($0))" } ?? "")"
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
