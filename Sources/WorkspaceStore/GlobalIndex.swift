import Foundation
import GRDB

public struct RecentDocument: Equatable, Sendable {
    public let contentHash: String
    public let workspaceID: String
    public let title: String
    public let lastPath: String
    public let lastOpenedAt: Date
}

/// Maps each document hash to its workspace, and keeps the recent documents list.
public final class GlobalIndex: Sendable {
    private let queue: DatabaseQueue

    public init(path: URL) throws {
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        queue = try DatabaseQueue(path: path.path)
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1-index") { db in
            try db.execute(sql: """
                CREATE TABLE workspace_index (
                    content_hash TEXT PRIMARY KEY,
                    workspace_id TEXT NOT NULL,
                    title TEXT NOT NULL,
                    last_path TEXT NOT NULL,
                    last_opened_at DATETIME NOT NULL
                );
                """)
        }
        try migrator.migrate(queue)
    }

    public func workspaceID(contentHash: String) throws -> String? {
        try queue.read {
            try String.fetchOne($0, sql: "SELECT workspace_id FROM workspace_index WHERE content_hash = ?", arguments: [contentHash])
        }
    }

    public func recordOpen(contentHash: String, workspaceID: String, title: String, path: String, at date: Date = Date()) throws {
        try queue.write {
            try $0.execute(sql: """
                INSERT INTO workspace_index (content_hash, workspace_id, title, last_path, last_opened_at)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(content_hash) DO UPDATE SET
                    title = excluded.title, last_path = excluded.last_path, last_opened_at = excluded.last_opened_at
                """, arguments: [contentHash, workspaceID, title, path, date])
        }
    }

    public func recents(limit: Int = 20) throws -> [RecentDocument] {
        try queue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM workspace_index ORDER BY last_opened_at DESC LIMIT ?", arguments: [limit])
                .map {
                    RecentDocument(contentHash: $0["content_hash"], workspaceID: $0["workspace_id"], title: $0["title"],
                                   lastPath: $0["last_path"], lastOpenedAt: $0["last_opened_at"])
                }
        }
    }
}
