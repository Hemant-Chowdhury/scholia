import CoreGraphics
import Foundation
import Testing
import DocumentKit
@testable import WorkspaceStore

func makeDocument(id: String = "doc-1", hash: String = "hash-1", pageCount: Int = 3) -> DocumentRecord {
    DocumentRecord(id: id, kind: "pdf", contentHash: hash, lastPath: "/tmp/book.pdf", title: "Book",
                   author: nil, pageCount: pageCount, lastPage: 0, indexedPages: 0, textExported: false)
}

func paragraph(_ page: Int, _ index: Int, _ text: String) -> Paragraph {
    Paragraph(pageIndex: page, index: index, text: text, rect: CGRect(x: 0, y: 0, width: 10, height: 10))
}

struct WorkspaceDatabaseTests {
    @Test func insertsAndFindsDocumentByIDAndHash() throws {
        let database = try WorkspaceDatabase.inMemory()
        try database.insertDocument(makeDocument())
        #expect(try database.document(id: "doc-1") == makeDocument())
        #expect(try database.document(contentHash: "hash-1")?.id == "doc-1")
        #expect(try database.document(contentHash: "other") == nil)
    }

    @Test func updatesLastPageLastPathAndTextExported() throws {
        let database = try WorkspaceDatabase.inMemory()
        try database.insertDocument(makeDocument())
        try database.setLastPage(2, documentID: "doc-1")
        try database.updateLastPath("/new/book.pdf", documentID: "doc-1")
        try database.setTextExported(documentID: "doc-1")
        let stored = try #require(try database.document(id: "doc-1"))
        #expect(stored.lastPage == 2)
        #expect(stored.lastPath == "/new/book.pdf")
        #expect(stored.textExported)
    }

    @Test func storingAPageAgainReplacesItsParagraphs() throws {
        let database = try WorkspaceDatabase.inMemory()
        try database.insertDocument(makeDocument())
        try database.storeParagraphs([paragraph(0, 0, "old text")], page: 0, documentID: "doc-1")
        try database.storeParagraphs([paragraph(0, 0, "new text"), paragraph(0, 1, "second")], page: 0, documentID: "doc-1")
        #expect(try database.paragraphs(documentID: "doc-1", pages: 0..<1).map(\.text) == ["new text", "second"])
        #expect(try database.document(id: "doc-1")?.indexedPages == 1)
    }

    @Test func paragraphsComeInPageOrder() throws {
        let database = try WorkspaceDatabase.inMemory()
        try database.insertDocument(makeDocument())
        try database.storeParagraphs([paragraph(1, 0, "page two")], page: 1, documentID: "doc-1")
        try database.storeParagraphs([paragraph(0, 1, "b"), paragraph(0, 0, "a")], page: 0, documentID: "doc-1")
        #expect(try database.paragraphs(documentID: "doc-1", pages: 0..<2).map(\.text) == ["a", "b", "page two"])
        #expect(try database.paragraphs(documentID: "doc-1", pages: 1..<2) == [StoredParagraph(pageIndex: 1, paragraphIndex: 0, text: "page two")])
    }

    @Test func searchFindsStemmedWordsWithPages() throws {
        let database = try WorkspaceDatabase.inMemory()
        try database.insertDocument(makeDocument())
        try database.storeParagraphs([paragraph(0, 0, "Agents call tools in a loop.")], page: 0, documentID: "doc-1")
        try database.storeParagraphs([paragraph(2, 0, "Planning is hard.")], page: 2, documentID: "doc-1")
        let hits = try database.searchText("agent loops")
        #expect(hits == [TextHit(documentID: "doc-1", pageIndex: 0, paragraphIndex: 0, text: "Agents call tools in a loop.")])
    }

    @Test func searchWithFTSSyntaxCharactersDoesNotThrow() throws {
        let database = try WorkspaceDatabase.inMemory()
        try database.insertDocument(makeDocument())
        try database.storeParagraphs([paragraph(0, 0, "A multi-agent system.")], page: 0, documentID: "doc-1")
        #expect(try database.searchText("\"multi-agent\" AND (system*").count == 1)
        #expect(try database.searchText("---").isEmpty)
    }

    @Test func fileDatabaseKeepsDataAfterReopen() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        try WorkspaceDatabase(path: path).insertDocument(makeDocument())
        #expect(try WorkspaceDatabase(path: path).document(id: "doc-1") != nil)
    }

    @Test func appPathsArePlacedUnderRoot() {
        let paths = AppPaths(root: URL(fileURLWithPath: "/tmp/ReaderTest"))
        #expect(paths.globalIndexFile.path == "/tmp/ReaderTest/index.sqlite")
        #expect(paths.workspaceFolder(id: "abc").path == "/tmp/ReaderTest/workspaces/abc")
    }
}
