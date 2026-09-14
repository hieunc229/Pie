//
//  DraftStore.swift
//  PiCode
//
//  Per-session drafts live in PiCode's own app storage and are never injected
//  into the Pi session until the user sends them. Losing the Pi process must not
//  lose a draft.
//

import Foundation

@Observable
@MainActor
final class DraftStore {
    struct Draft: Codable, Equatable {
        var text: String
        var updatedAt: Date
        /// Attachment descriptors. Image bytes are intentionally not persisted;
        /// images are re-attached by the user after a relaunch.
        var attachmentNames: [String] = []
    }

    private var drafts: [String: Draft] = [:]
    private let fileURL: URL
    private var saveTask: Task<Void, Never>?

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? DraftStore.defaultURL()
        load()
    }

    static func defaultURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("PiCode", isDirectory: true)
            .appendingPathComponent("drafts.json")
    }

    func draft(for key: String) -> Draft? {
        drafts[key]
    }

    func text(for key: String) -> String {
        drafts[key]?.text ?? ""
    }

    func setText(_ text: String, for key: String, attachments: [Attachment] = []) {
        if text.isEmpty, attachments.isEmpty {
            drafts.removeValue(forKey: key)
        } else {
            drafts[key] = Draft(
                text: text,
                updatedAt: Date(),
                attachmentNames: attachments.map(\.fileName)
            )
        }
        scheduleSave()
    }

    func clear(for key: String) {
        guard drafts.removeValue(forKey: key) != nil else { return }
        scheduleSave()
    }

    func removeAll() {
        drafts.removeAll()
        scheduleSave()
    }

    // MARK: - Persistence

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        let snapshot = drafts
        let url = fileURL
        DispatchQueue.global(qos: .utility).async {
            do {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                let data = try JSONEncoder.piCode.encode(snapshot)
                try data.write(to: url, options: .atomic)
            } catch {
                // Draft persistence is best effort; the draft stays in memory.
            }
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        drafts = (try? JSONDecoder.piCode.decode([String: Draft].self, from: data)) ?? [:]
    }
}
