import SwiftUI

/// A concrete child per row keeps layout and hover invalidation local.
///
/// Equatable on its inputs: every streaming flush hands the transcript a new
/// `rows` array, and the transcript lays out every loaded row, not only the
/// visible ones. Comparing first means a flush re-renders the one row that grew
/// rather than the whole history.
///
/// The row's own body reads neither hover nor busy state — only
/// `TranscriptResponseFooter` does. Hover is one shared observable, so a row
/// that read it would be invalidated (content and all) every time the pointer
/// crossed any turn; reading it in the footer keeps that to a line of buttons.
struct ConversationMessageRow: View, Equatable {
    var row: TranscriptRow
    var response: TranscriptResponseMetadata?
    var controller: PiSessionController
    var hover: TranscriptHoverState

    static func == (lhs: ConversationMessageRow, rhs: ConversationMessageRow) -> Bool {
        lhs.controller === rhs.controller && lhs.hover === rhs.hover
            && lhs.row == rhs.row && lhs.response == rhs.response
    }

    var body: some View {
        let responseHoverID = response?.hoverID

        VStack(alignment: .leading, spacing: 5) {
            switch row {
            case .item(let item):
                TranscriptRowView(item: item, controller: controller)
            case .group:
                ToolGroupView(row: row, controller: controller)
            }

            // Actions belong to the completed Pi turn, not
            // to one text block inside it. Keeping them on
            // the final row also keeps the next thing below
            // them either the next user message or the
            // composer.
            if let response, response.endsTurn, !response.text.isEmpty {
                TranscriptResponseFooter(response: response, controller: controller, hover: hover)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            guard let responseHoverID else { return }
            if hovering {
                hover.responseID = responseHoverID
            } else if hover.responseID == responseHoverID {
                hover.responseID = nil
            }
        }
    }
}

/// A finished turn's copy / branch line. The only part of a row that observes
/// hover and busy state, so either changing redraws this line, not the reply.
private struct TranscriptResponseFooter: View {
    var response: TranscriptResponseMetadata
    var controller: PiSessionController
    var hover: TranscriptHoverState

    var body: some View {
        let responseText = response.text
        let responseEntryID = response.entryID
        let responseHoverID = response.hoverID
        let copyActionID = responseHoverID.map { "copy-\($0)" }
        let branchActionID = responseHoverID.map { "branch-\($0)" }

        if !response.isLastTurn || !controller.runtime.isBusy {
            // Built only while the turn is hovered, on a line of fixed height,
            // so a quiet transcript carries no hidden buttons.
            let isShowingActions = responseHoverID != nil && hover.responseID == responseHoverID
            HStack(spacing: 10) {
                if isShowingActions {
                HStack(spacing: 12) {
                    Button {
                        WorkspaceLauncher.copyToPasteboard(responseText)
                    } label: {
                        HugeIcon(name: "copy-01")
                            .font(.system(size: 13))
                    }
                    .foregroundStyle(hover.actionID == copyActionID ? Color.white : Color.secondary)
                    .onHover { hover.actionID = $0 ? copyActionID : nil }
                    .help("Copy")
                    .accessibilityLabel("Copy")

                    // Retain this response by forking
                    // before the following user prompt,
                    // or cloning the latest turn.
                    if let entryId = responseEntryID {
                        Button {
                            Task { await controller.branch(afterUserEntryId: entryId) }
                        } label: {
                            HugeIcon(name: "git-branch")
                                .font(.system(size: 13))
                        }
                        .foregroundStyle(hover.actionID == branchActionID ? Color.white : Color.secondary)
                        .onHover { hover.actionID = $0 ? branchActionID : nil }
                        .help("Start a new Pi branch from this response")
                        .accessibilityLabel("Branch from response")
                        .disabled(controller.runtime.isBusy || controller.isChangingBranch)
                    }
                }
                .buttonStyle(.plain)

                if let timestamp = response.timestamp {
                    Text(Format.messageTime(timestamp))
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                }
            }
            .frame(height: TranscriptStyle.actionRowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 12)
            .contextMenu {
                Button("Copy Response") {
                    WorkspaceLauncher.copyToPasteboard(responseText)
                }
                if let entryId = responseEntryID {
                    Button("Branch from This Response…") {
                        Task { await controller.branch(afterUserEntryId: entryId) }
                    }
                }
            }
        }
    }
}
