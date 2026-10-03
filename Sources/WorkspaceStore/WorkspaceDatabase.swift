import Foundation
import GRDB
import Synchronization

/// The SQLite database of one workspace.
public final class WorkspaceDatabase: Sendable {
    let queue: DatabaseQueue
    /// Held while an indexer runs, so two windows of one workspace never index or export at the same time.
    let indexLock = Mutex(())

    public convenience init(path: URL) throws {
        try self.init(queue: DatabaseQueue(path: path.path))
    }

    public static func inMemory() throws -> WorkspaceDatabase {
        try WorkspaceDatabase(queue: DatabaseQueue())
    }

    private init(queue: DatabaseQueue) throws {
        self.queue = queue
        try Self.migrator.migrate(queue)
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1-document") { db in
            try db.execute(sql: """
                CREATE TABLE document (
                    id TEXT PRIMARY KEY,
                    kind TEXT NOT NULL,
                    content_hash TEXT NOT NULL UNIQUE,
                    last_path TEXT NOT NULL,
                    title TEXT NOT NULL,
                    author TEXT,
                    page_count INTEGER NOT NULL,
                    last_page INTEGER NOT NULL DEFAULT 0,
                    indexed_pages INTEGER NOT NULL DEFAULT 0,
                    text_exported INTEGER NOT NULL DEFAULT 0
                );
                CREATE VIRTUAL TABLE document_text USING fts5(
                    document_id UNINDEXED,
                    page_index UNINDEXED,
                    paragraph_index UNINDEXED,
                    text,
                    tokenize = 'porter unicode61'
                );
                """)
        }
        migrator.registerMigration("v2-highlight") { db in
            try db.execute(sql: """
                CREATE TABLE anchor (
                    id TEXT PRIMARY KEY,
                    document_id TEXT NOT NULL REFERENCES document(id) ON DELETE CASCADE,
                    kind TEXT NOT NULL,
                    locator_json TEXT NOT NULL,
                    text TEXT NOT NULL,
                    structural_path TEXT NOT NULL,
                    first_page INTEGER NOT NULL,
                    created_at DATETIME NOT NULL
                );
                CREATE INDEX anchor_document_page ON anchor(document_id, first_page);
                CREATE TABLE highlight (
                    id TEXT PRIMARY KEY,
                    anchor_id TEXT NOT NULL REFERENCES anchor(id) ON DELETE CASCADE,
                    color TEXT NOT NULL,
                    created_at DATETIME NOT NULL
                );
                CREATE INDEX highlight_anchor ON highlight(anchor_id);
                """)
        }
        return migrator
    }

    public func insertDocument(_ document: DocumentRecord) throws {
        try queue.write { try document.insert($0) }
    }

    public func document(id: String) throws -> DocumentRecord? {
        try queue.read { try DocumentRecord.fetchOne($0, key: id) }
    }

    public func document(contentHash: String) throws -> DocumentRecord? {
        try queue.read { try DocumentRecord.filter(Column("content_hash") == contentHash).fetchOne($0) }
    }

    public func updateLastPath(_ path: String, documentID: String) throws {
        try queue.write { try $0.execute(sql: "UPDATE document SET last_path = ? WHERE id = ?", arguments: [path, documentID]) }
    }

    public func setLastPage(_ page: Int, documentID: String) throws {
        try queue.write { try $0.execute(sql: "UPDATE document SET last_page = ? WHERE id = ?", arguments: [page, documentID]) }
    }

    public func setTextExported(documentID: String) throws {
        try queue.write { try $0.execute(sql: "UPDATE document SET text_exported = 1 WHERE id = ?", arguments: [documentID]) }
    }
}
