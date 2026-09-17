import Foundation

/// Reads Pi's own append-only session file without modifying it. This avoids the
/// expensive `get_entries` walk when opening a long conversation.
struct PiSessionHistoryReader: Sendable {
    func entries(at path: String) async -> [JSONValue] {
        await Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe) else {
                return [JSONValue]()
            }
            return data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
                .compactMap { try? JSONCoding.decode(Data($0)) }
                .filter { $0.string("type") != "session" }
        }.value
    }
}
