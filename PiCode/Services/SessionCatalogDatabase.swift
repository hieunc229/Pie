//
//  SessionCatalogDatabase.swift
//  PiCode
//
//  A rebuildable, non-authoritative cache of the session list. Pi pushes the
//  metadata into the database after every index refresh and reads it back at
//  launch, so the sidebar can draw the last known chats before the filesystem
//  scan finishes.
//
//  The database is only a cache: the native session files remain the source of
//  truth. A refresh replaces its contents wholesale, so it can never disagree
//  with disk about which sessions exist.
//

import Foundation
import SQLite3

/// SQLite-backed metadata cache. All access is serialized on a private queue, so
/// the type is safe to use from any thread.
final class SessionCatalogDatabase: @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.picode.session-catalog", qos: .utility)
    private let url: URL
    private var database: OpaquePointer?

    init(url: URL? = nil) {
        self.url = url ?? Self.defaultURL()
        queue.sync { open() }
    }

    deinit {
        if let database { sqlite3_close(database) }
    }

    static func defaultURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("PiCode", isDirectory: true)
            .appendingPathComponent("sessions.db")
    }

    // MARK: - Public API

    /// The last persisted project/session list, or an empty array when nothing
    /// has been cached yet. Cheap enough to call synchronously at launch.
    func loadProjects() -> [ProjectGroup] {
        queue.sync { loadLocked() }
    }

    /// Replaces the cache with `projects`. Best effort: a failure leaves the
    /// previous contents in place and the app keeps working from disk.
    func save(projects: [ProjectGroup]) {
        let snapshot = projects
        queue.async { [weak self] in self?.saveLocked(snapshot) }
    }

    // MARK: - Connection

    private func open() {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK else {
            sqlite3_close(handle)
            return
        }
        database = handle
        execute("PRAGMA journal_mode=WAL;")
        execute("PRAGMA synchronous=NORMAL;")
        execute(Self.schema)
    }

    private func execute(_ sql: String) {
        guard let database else { return }
        sqlite3_exec(database, sql, nil, nil, nil)
    }

    // MARK: - Loading

    private func loadLocked() -> [ProjectGroup] {
        guard let database else { return [] }
        var refs: [SessionRef] = []
        let sql = """
            SELECT id, session_id, file_path, name, cwd, created_at, updated_at,
                   message_count, first_user_message, parent_session, harness_id, is_pinned
            FROM sessions;
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = text(statement, 0), let cwd = text(statement, 4) else { continue }
            refs.append(SessionRef(
                id: id,
                sessionId: text(statement, 1),
                filePath: text(statement, 2),
                name: text(statement, 3),
                cwd: cwd,
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 5)),
                updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 6)),
                messageCount: Int(sqlite3_column_int64(statement, 7)),
                firstUserMessage: text(statement, 8),
                parentSession: text(statement, 9),
                isPinned: sqlite3_column_int(statement, 11) != 0,
                harnessID: HarnessID(rawValue: text(statement, 10) ?? "") ?? .pi
            ))
        }

        var byPath: [String: [SessionRef]] = [:]
        for ref in refs {
            byPath[CanonicalPath.of(ref.cwd), default: []].append(ref)
        }
        var groups = byPath.map { path, sessions in
            ProjectGroup(
                id: path,
                path: path,
                name: URL(fileURLWithPath: path).lastPathComponent,
                sessions: sessions.sorted { $0.updatedAt > $1.updatedAt }
            )
        }
        overlayProjects(into: &groups)
        return groups
    }

    /// Projects the user added that have no session files yet live only in the
    /// projects table, and a cached project's display name may have been renamed.
    private func overlayProjects(into groups: inout [ProjectGroup]) {
        guard let database else { return }
        var indexByPath = Dictionary(uniqueKeysWithValues: groups.enumerated().map { ($0.element.path, $0.offset) })
        let sql = "SELECT path, name, working_directory, is_pinned FROM projects;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let path = text(statement, 0) else { continue }
            let name = text(statement, 1)
            let workingDirectory = text(statement, 2)
            let isPinned = sqlite3_column_int(statement, 3) != 0
            if let index = indexByPath[path] {
                if let name, !name.isEmpty { groups[index].name = name }
                groups[index].workingDirectory = workingDirectory
                groups[index].isPinned = isPinned
            } else {
                groups.append(ProjectGroup(
                    id: path,
                    path: path,
                    name: name ?? URL(fileURLWithPath: path).lastPathComponent,
                    sessions: [],
                    isPinned: isPinned,
                    workingDirectory: workingDirectory
                ))
                indexByPath[path] = groups.count - 1
            }
        }
    }

    // MARK: - Saving

    private func saveLocked(_ projects: [ProjectGroup]) {
        guard let database else { return }
        execute("BEGIN IMMEDIATE;")
        execute("DELETE FROM sessions;")
        execute("DELETE FROM projects;")
        insertSessions(projects)
        insertProjects(projects)
        execute("COMMIT;")
    }

    private func insertSessions(_ projects: [ProjectGroup]) {
        let sql = """
            INSERT OR REPLACE INTO sessions
            (id, session_id, file_path, name, cwd, created_at, updated_at, message_count,
             first_user_message, parent_session, harness_id, is_pinned)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }

        for project in projects {
            for session in project.sessions {
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)
                bind(statement, 1, session.id)
                bind(statement, 2, session.sessionId)
                bind(statement, 3, session.filePath)
                bind(statement, 4, session.name)
                bind(statement, 5, session.cwd)
                bind(statement, 6, session.createdAt.timeIntervalSince1970)
                bind(statement, 7, session.updatedAt.timeIntervalSince1970)
                bind(statement, 8, session.messageCount)
                bind(statement, 9, session.firstUserMessage)
                bind(statement, 10, session.parentSession)
                bind(statement, 11, session.harnessID.rawValue)
                bind(statement, 12, session.isPinned ? 1 : 0)
                sqlite3_step(statement)
            }
        }
    }

    private func insertProjects(_ projects: [ProjectGroup]) {
        let sql = """
            INSERT OR REPLACE INTO projects (path, name, working_directory, is_pinned, updated_at)
            VALUES (?, ?, ?, ?, ?);
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }

        for project in projects {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            bind(statement, 1, project.path)
            bind(statement, 2, project.name)
            bind(statement, 3, project.workingDirectory)
            bind(statement, 4, project.isPinned ? 1 : 0)
            bind(statement, 5, project.mostRecentActivity.timeIntervalSince1970)
            sqlite3_step(statement)
        }
    }

    // MARK: - Column binding helpers

    private func text(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard let pointer = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: pointer)
    }

    private func bind(_ statement: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let value {
            sqlite3_bind_text(statement, index, value, -1, Self.transient)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func bind(_ statement: OpaquePointer?, _ index: Int32, _ value: Double) {
        sqlite3_bind_double(statement, index, value)
    }

    private func bind(_ statement: OpaquePointer?, _ index: Int32, _ value: Int) {
        sqlite3_bind_int64(statement, index, Int64(value))
    }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private static let schema = """
        CREATE TABLE IF NOT EXISTS sessions (
            id TEXT PRIMARY KEY,
            session_id TEXT,
            file_path TEXT,
            name TEXT,
            cwd TEXT NOT NULL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            message_count INTEGER NOT NULL,
            first_user_message TEXT,
            parent_session TEXT,
            harness_id TEXT NOT NULL,
            is_pinned INTEGER NOT NULL DEFAULT 0
        );
        CREATE INDEX IF NOT EXISTS idx_sessions_updated ON sessions(updated_at DESC);
        CREATE TABLE IF NOT EXISTS projects (
            path TEXT PRIMARY KEY,
            name TEXT,
            working_directory TEXT,
            is_pinned INTEGER NOT NULL DEFAULT 0,
            updated_at REAL NOT NULL
        );
        """
}
