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
//  Context pane, and the live ones — streaming, compacting, retrying, the queue —
//  are in the transcript's own footer.
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

            ComposerView(state: state, controller: controller, focusTick: composerFocusTick)
        }
        .padding(.top, 8)
        .padding(.bottom, 16)
        .background(GeometryReader { proxy in
            Color.clear.preference(key: ComposerHeightKey.self, value: proxy.size.height)
        })
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
