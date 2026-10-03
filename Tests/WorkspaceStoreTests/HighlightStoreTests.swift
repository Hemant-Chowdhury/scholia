import Foundation
import Testing
@testable import WorkspaceStore

struct HighlightStoreTests {
    private func anchor(_ id: String, page: Int, documentID: String = "doc-1", at seconds: TimeInterval = 1000) -> AnchorRecord {
        AnchorRecord(id: id, documentID: documentID, kind: "pdf", locatorJSON: "{\"segments\":[]}", text: "text \(id)",
                     structuralPath: "Chapter 1", firstPage: page, createdAt: Date(timeIntervalSince1970: seconds))
    }

    private func highlight(_ id: String, anchorID: String) -> HighlightRecord {
        HighlightRecord(id: id, anchorID: anchorID, color: "yellow", createdAt: Date(timeIntervalSince1970: 1000))
    }

    private func database() throws -> WorkspaceDatabase {
        let database = try WorkspaceDatabase.inMemory()
        try database.insertDocument(makeDocument())
        try database.insertDocument(makeDocument(id: "doc-2", hash: "hash-2"))
        return database
    }

    @Test func addedHighlightsComeBackSortedByPage() throws {
        let database = try database()
        try database.addHighlight(highlight("h2", anchorID: "a2"), anchor: anchor("a2", page: 5))
        try database.addHighlight(highlight("h1", anchorID: "a1"), anchor: anchor("a1", page: 2))
        let stored = try database.highlights(documentID: "doc-1")
        #expect(stored.map(\.highlight.id) == ["h1", "h2"])
        #expect(stored[0].anchor == anchor("a1", page: 2))
    }

    @Test func highlightsOfOtherDocumentsAreNotListed() throws {
        let database = try database()
        try database.addHighlight(highlight("h1", anchorID: "a1"), anchor: anchor("a1", page: 0, documentID: "doc-2"))
        #expect(try database.highlights(documentID: "doc-1").isEmpty)
    }

    @Test func removingAHighlightAlsoRemovesItsAnchor() throws {
        let database = try database()
        try database.addHighlight(highlight("h1", anchorID: "a1"), anchor: anchor("a1", page: 0))
        try database.removeHighlight(id: "h1")
        #expect(try database.highlights(documentID: "doc-1").isEmpty)
        #expect(try database.queue.read { try AnchorRecord.fetchCount($0) } == 0)
    }

    @Test func removingAnUnknownHighlightDoesNothing() throws {
        let database = try database()
        try database.addHighlight(highlight("h1", anchorID: "a1"), anchor: anchor("a1", page: 0))
        try database.removeHighlight(id: "nope")
        #expect(try database.highlights(documentID: "doc-1").count == 1)
    }

    @Test func anchorForAMissingDocumentIsRejected() throws {
        let database = try database()
        #expect(throws: (any Error).self) {
            try database.addHighlight(highlight("h1", anchorID: "a1"), anchor: anchor("a1", page: 0, documentID: "missing"))
        }
    }
}
