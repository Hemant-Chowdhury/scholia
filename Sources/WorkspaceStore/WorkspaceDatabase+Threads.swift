import Foundation
import GRDB

extension WorkspaceDatabase {
    /// Saves a new thread, and its anchor when the anchor is not saved yet.
    public func createThread(_ thread: ThreadRecord, anchor: AnchorRecord?) throws {
        try queue.write { db in
            if let anchor, try !AnchorRecord.exists(db, key: anchor.id) {
                try anchor.insert(db)
            }
            try thread.insert(db)
        }
    }

    public func thread(id: String) throws -> ThreadRecord? {
        try queue.read { try ThreadRecord.fetchOne($0, key: id) }
    }

    public func anchor(id: String) throws -> AnchorRecord? {
        try queue.read { try AnchorRecord.fetchOne($0, key: id) }
    }

    /// Threads of a document, the last changed first.
    public func threads(documentID: String) throws -> [ThreadRecord] {
        try queue.read { db in
            try ThreadRecord.filter(Column("document_id") == documentID)
                .order(Column("updated_at").desc).fetchAll(db)
        }
    }

    public func threads(documentID: String, pages: Range<Int>) throws -> [ThreadRecord] {
        try queue.read { db in
            try ThreadRecord.filter(Column("document_id") == documentID
                                    && Column("first_page") >= pages.lowerBound && Column("first_page") < pages.upperBound)
                .order(Column("updated_at").desc).fetchAll(db)
        }
    }

    public func messages(threadID: String) throws -> [MessageRecord] {
        try queue.read { db in
            try MessageRecord.fetchAll(db, sql: "SELECT * FROM message WHERE thread_id = ? ORDER BY created_at, rowid",
                                       arguments: [threadID])
        }
    }

    /// Inserts or replaces a message, marks the thread as changed, and updates the thread search text.
    public func saveMessage(_ message: MessageRecord) throws {
        try queue.write { db in
            try message.save(db)
            try db.execute(sql: "UPDATE thread SET updated_at = ? WHERE id = ?", arguments: [Date(), message.threadID])
            try Self.refreshThreadText(db, threadID: message.threadID)
        }
    }

    public func deleteMessages(ids: [String], threadID: String) throws {
        try queue.write { db in
            _ = try MessageRecord.deleteAll(db, keys: ids)
            try Self.refreshThreadText(db, threadID: threadID)
        }
    }

    public func updateThreadAgent(threadID: String, agentID: String, modelID: String?) throws {
        try queue.write {
            try $0.execute(sql: "UPDATE thread SET agent_id = ?, model_id = ? WHERE id = ?", arguments: [agentID, modelID, threadID])
        }
    }

    /// Threads whose questions or answers share words with the text, best match first.
    public func relatedThreads(to text: String, documentID: String, excluding threadID: String?, limit: Int = 3) throws -> [ThreadRecord] {
        guard let match = FTSQuery.anyTerm(text) else { return [] }
        return try queue.read { db in
            let ids = try String.fetchAll(db, sql: """
                SELECT thread_id FROM thread_text WHERE thread_text MATCH ? ORDER BY bm25(thread_text) LIMIT ?
                """, arguments: [match, limit + 1])
            let threads = try ThreadRecord.filter(keys: ids).fetchAll(db)
            return ids.compactMap { id in threads.first { $0.id == id } }
                .filter { $0.documentID == documentID && $0.id != threadID }
                .prefix(limit).map { $0 }
        }
    }

    /// The search text of a thread: its title, the questions, and the start of each answer.
    private static func refreshThreadText(_ db: Database, threadID: String) throws {
        let title = try String.fetchOne(db, sql: "SELECT title FROM thread WHERE id = ?", arguments: [threadID]) ?? ""
        let parts = try MessageRecord.fetchAll(db, sql: "SELECT * FROM message WHERE thread_id = ? ORDER BY created_at, rowid",
                                               arguments: [threadID])
            .map { $0.role == "user" ? $0.content : String($0.content.prefix(400)) }
        try db.execute(sql: "DELETE FROM thread_text WHERE thread_id = ?", arguments: [threadID])
        try db.execute(sql: "INSERT INTO thread_text (thread_id, text) VALUES (?, ?)",
                       arguments: [threadID, ([title] + parts).joined(separator: "\n")])
    }
}

/// A thread with what a list of threads shows: the chapter, the first question and the start of the first answer.
public struct ThreadSummary: Sendable, Equatable, Identifiable {
    public let thread: ThreadRecord
    public let structuralPath: String
    public let question: String
    public let answerStart: String
    public let messageCount: Int

    public var id: String { thread.id }
}

extension WorkspaceDatabase {
    /// All threads of a document in page order.
    public func threadSummaries(documentID: String) throws -> [ThreadSummary] {
        try queue.read { db in
            let threads = try ThreadRecord.fetchAll(db, sql: """
                SELECT * FROM thread WHERE document_id = ? ORDER BY first_page, created_at
                """, arguments: [documentID])
            return try threads.map { thread in
                let path = try thread.anchorID.flatMap {
                    try String.fetchOne(db, sql: "SELECT structural_path FROM anchor WHERE id = ?", arguments: [$0])
                } ?? ""
                let question = try String.fetchOne(db, sql: """
                    SELECT content FROM message WHERE thread_id = ? AND role = 'user' ORDER BY created_at, rowid LIMIT 1
                    """, arguments: [thread.id]) ?? ""
                let answer = try String.fetchOne(db, sql: """
                    SELECT substr(content, 1, 300) FROM message WHERE thread_id = ? AND role = 'assistant' AND content != ''
                    ORDER BY created_at, rowid LIMIT 1
                    """, arguments: [thread.id]) ?? ""
                let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM message WHERE thread_id = ?", arguments: [thread.id]) ?? 0
                return ThreadSummary(thread: thread, structuralPath: path, question: question, answerStart: answer, messageCount: count)
            }
        }
    }

    /// IDs of the threads of a document whose title, questions or answers match the text.
    public func searchThreads(_ text: String, documentID: String) throws -> [String] {
        guard let match = FTSQuery.anyTerm(text) else { return [] }
        return try queue.read { db in
            try String.fetchAll(db, sql: """
                SELECT thread_text.thread_id FROM thread_text JOIN thread ON thread.id = thread_text.thread_id
                WHERE thread_text MATCH ? AND thread.document_id = ? ORDER BY bm25(thread_text) LIMIT 200
                """, arguments: [match, documentID])
        }
    }
}
