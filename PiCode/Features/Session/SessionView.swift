//
//  SessionView.swift
//  PiCode
//
//  One active session: transcript, extension chrome, trust gate, and composer.
//
//  Ordering mirrors Pi's own TUI so nothing appears in an unexpected place:
//  widgets above the editor sit above the composer, status lines below it.
//

import SwiftUI

struct SessionView: View {
    @Bindable var state: AppState
    var controller: PiSessionController
    var composerFocusTick: Int

    var body: some View {
        VStack(spacing: 0) {
            if showsConnectionBanner {
                connectionBanner
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
            }

            ConversationView(state: state, controller: controller)

            VStack(spacing: 8) {
                ExtensionWidgetStrip(controller: controller, placement: .aboveEditor)

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

                ExtensionStatusBar(controller: controller)
                ExtensionWidgetStrip(controller: controller, placement: .belowEditor)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
            .padding(.top, 8)
            .background(.bar)
        }
        .overlay(alignment: .topTrailing) {
            NotificationStack(controller: controller)
                .padding(12)
        }
        .animation(.easeInOut(duration: 0.18), value: controller.trustState)
    }

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
