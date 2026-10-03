import DocumentKit
import GRDB

public struct StoredParagraph: Equatable, Sendable {
    public let pageIndex: Int
    public let paragraphIndex: Int
    public let text: String

    public init(pageIndex: Int, paragraphIndex: Int, text: String) {
        self.pageIndex = pageIndex
        self.paragraphIndex = paragraphIndex
        self.text = text
    }
}

public struct TextHit: Equatable, Sendable {
    public let documentID: String
    public let pageIndex: Int
    public let paragraphIndex: Int
    public let text: String

    public init(documentID: String, pageIndex: Int, paragraphIndex: Int, text: String) {
        self.documentID = documentID
        self.pageIndex = pageIndex
        self.paragraphIndex = paragraphIndex
        self.text = text
    }
}

extension WorkspaceDatabase {
    /// Replaces the paragraphs of one page and marks the pages up to it as indexed, in one transaction.
    public func storeParagraphs(_ paragraphs: [Paragraph], page: Int, documentID: String) throws {
        try queue.write { db in
            try db.execute(sql: "DELETE FROM document_text WHERE document_id = ? AND page_index = ?",
                           arguments: [documentID, page])
            for paragraph in paragraphs {
                try db.execute(
                    sql: "INSERT INTO document_text (document_id, page_index, paragraph_index, text) VALUES (?, ?, ?, ?)",
                    arguments: [documentID, page, paragraph.index, paragraph.text])
            }
            try db.execute(sql: "UPDATE document SET indexed_pages = MAX(indexed_pages, ?) WHERE id = ?",
                           arguments: [page + 1, documentID])
        }
    }

    public func paragraphs(documentID: String, pages: Range<Int>) throws -> [StoredParagraph] {
        try queue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT page_index, paragraph_index, text FROM document_text
                WHERE document_id = ? AND page_index >= ? AND page_index < ?
                ORDER BY page_index, paragraph_index
                """, arguments: [documentID, pages.lowerBound, pages.upperBound])
            .map { StoredParagraph(pageIndex: $0["page_index"], paragraphIndex: $0["paragraph_index"], text: $0["text"]) }
        }
    }

    /// Finds paragraphs that contain any word of the query, best match first.
    public func searchText(_ query: String, limit: Int = 10) throws -> [TextHit] {
        guard let match = FTSQuery.anyTerm(query) else { return [] }
        return try queue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT document_id, page_index, paragraph_index, text FROM document_text
                WHERE document_text MATCH ? ORDER BY bm25(document_text) LIMIT ?
                """, arguments: [match, limit])
            .map {
                TextHit(documentID: $0["document_id"], pageIndex: $0["page_index"],
                        paragraphIndex: $0["paragraph_index"], text: $0["text"])
            }
        }
    }
}
