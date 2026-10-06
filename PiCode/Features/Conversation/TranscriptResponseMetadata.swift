import Foundation

struct TranscriptResponseMetadata: Equatable {
    var text: String
    var entryID: String?
    var hoverID: String?
    var timestamp: Date?
    var endsTurn: Bool
    var isLastTurn: Bool
}
