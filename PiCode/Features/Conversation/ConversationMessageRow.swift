import SwiftUI

/// A concrete child per row keeps lazy layout and hover invalidation local.
struct ConversationMessageRow: View {
    var row: TranscriptRow
    var response: TranscriptResponseMetadata?
    var controller: PiSessionController
    var hover: TranscriptHoverState

    var body: some View {
        let responseText = response?.text ?? ""
        let responseEntryID = response?.entryID
        let responseHoverID = response?.hoverID
        let copyActionID = responseHoverID.map { "copy-\($0)" }
        let branchActionID = responseHoverID.map { "branch-\($0)" }

        VStack(alignment: .leading, spacing: 5) {
            switch row {
            case .item(let item):
                TranscriptRowView(item: item, controller: controller)
            case .group(let items, let isLiveTurn):
                ToolGroupView(row: .group(items, isLiveTurn: isLiveTurn), controller: controller)
            }

            // Actions belong to the completed Pi turn, not
            // to one text block inside it. Keeping them on
            // the final row also keeps the next thing below
            // them either the next user message or the
            // composer.
            if response?.endsTurn == true,
               !responseText.isEmpty,
               (response?.isLastTurn == false || !controller.runtime.isBusy) {
                HStack(spacing: 10) {
                    HStack(spacing: 12) {
                        Button {
                            WorkspaceLauncher.copyToPasteboard(responseText)
                        } label: {
                            Image(systemName: "doc.on.doc")
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
                                Image(systemName: "arrow.triangle.branch")
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

                    if let timestamp = response?.timestamp {
                        Text(Format.messageTime(timestamp))
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
                .opacity(responseHoverID != nil && hover.responseID == responseHoverID ? 1 : 0)
                .allowsHitTesting(responseHoverID != nil && hover.responseID == responseHoverID)
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
