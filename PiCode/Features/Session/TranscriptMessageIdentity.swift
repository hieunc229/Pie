import Foundation

struct TranscriptMessageIdentity: Hashable {
    var role: String
    var timestamp: Date?
    var text: String
}
