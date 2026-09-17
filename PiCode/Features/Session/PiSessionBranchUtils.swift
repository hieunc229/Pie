import Foundation

extension PiSessionController {
    static func visibleUserEntryIDs(messages: [PiMessage], entries: [PiSessionEntry], leafId: String?, forkPoints: [PiForkPoint]) -> [String] {
        let branchUsers = TranscriptBuilder.activeBranchEntries(entries: entries, leafId: leafId)
            .filter { $0.message?.isUser == true }
        var entryIDs: [TranscriptMessageIdentity: [String]] = [:]
        for entry in branchUsers {
            guard let message = entry.message else { continue }
            let key = TranscriptMessageIdentity(role: message.role, timestamp: message.timestamp, text: message.textContent)
            entryIDs[key, default: []].append(entry.id)
        }
        let pointsByText = Dictionary(grouping: forkPoints, by: \.text)
        return messages.filter(\.isUser).map { message in
            let key = TranscriptMessageIdentity(role: message.role, timestamp: message.timestamp, text: message.textContent)
            if let matches = entryIDs[key], matches.count == 1 { return matches[0] }
            // The quick RPC includes abandoned branches. Only an unambiguous
            // text match is safe until the active branch entries have loaded.
            let points = pointsByText[message.textContent] ?? []
            return points.count == 1 ? points[0].entryId : ""
        }
    }

    /// RPC fork excludes its selected user message. Selecting the following
    /// user therefore retains the entire response the user chose to branch from.
    func branch(afterUserEntryId entryId: String) async {
        guard !runtime.isBusy, !isChangingBranch else { return }
        let users = items.filter { $0.kind == .user }
        guard let index = users.firstIndex(where: { $0.forkEntryId == entryId }) else { return }
        if index + 1 < users.count {
            guard let nextID = users[index + 1].forkEntryId else { return }
            await fork(fromEntryId: nextID, prefill: false)
        } else {
            isChangingBranch = true
            defer { isChangingBranch = false }
            await cloneSession()
        }
    }
}
