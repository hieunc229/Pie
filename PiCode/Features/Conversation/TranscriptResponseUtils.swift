import Foundation

enum TranscriptResponseUtils {
    /// One pass per transcript update, rather than a backwards scan and text
    /// concatenation for every row on every hover or scroll frame.
    static func metadata(for rows: [TranscriptRow]) -> [String: TranscriptResponseMetadata] {
        var result: [String: TranscriptResponseMetadata] = [:]
        var rowIDs: [String] = []
        var text: [String] = []
        var lastAssistant: TranscriptItem?

        func flush(isLastTurn: Bool) {
            guard let lastAssistant else { return }
            let response = text.joined(separator: "\n\n")
            for id in rowIDs {
                result[id] = TranscriptResponseMetadata(
                    text: response, entryID: lastAssistant.forkEntryId,
                    hoverID: lastAssistant.forkEntryId ?? lastAssistant.id,
                    timestamp: lastAssistant.timestamp, endsTurn: id == rowIDs.last,
                    isLastTurn: isLastTurn)
            }
        }

        for row in rows {
            if case .item(let item) = row, item.kind == .user {
                flush(isLastTurn: false)
                rowIDs.removeAll(keepingCapacity: true)
                text.removeAll(keepingCapacity: true)
                lastAssistant = nil
            } else {
                rowIDs.append(row.id)
                for item in row.items where item.kind == .assistant {
                    text.append(item.text)
                    lastAssistant = item
                }
            }
        }
        flush(isLastTurn: true)
        return result
    }
}
