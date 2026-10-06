import Foundation

/// PiCode-only presentation metadata. Native histories remain untouched.
enum SessionCatalogMetadata {
    private static let titlesKey = "sessionCatalog.titles"

    static func title(for session: SessionRef) -> String? {
        UserDefaults.standard.dictionary(forKey: titlesKey)?[session.id] as? String
    }

    static func rename(_ session: SessionRef, to title: String) {
        var titles = UserDefaults.standard.dictionary(forKey: titlesKey) ?? [:]
        titles[session.id] = title
        UserDefaults.standard.set(titles, forKey: titlesKey)
    }
}
