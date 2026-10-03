import Foundation
import Testing
import TestSupport
@testable import DocumentKit

struct PDFDocumentSourceTests {
    @Test func readsMetadataFromThePDF() throws {
        let url = try FixturePDF.make(
            pages: [[FixtureLine("One", y: 700)], [FixtureLine("Two", y: 700)]],
            title: "Agentic AI", author: "A. Writer")
        let source = try PDFDocumentSource(url: url)
        #expect(source.kind == .pdf)
        #expect(source.metadata == DocumentMetadata(title: "Agentic AI", author: "A. Writer", pageCount: 2))
    }

    @Test func titleFallsBackToFileName() throws {
        let url = try FixturePDF.make(pages: [[FixtureLine("One", y: 700)]])
        let source = try PDFDocumentSource(url: url)
        #expect(source.metadata.title == url.deletingPathExtension().lastPathComponent)
        #expect(source.metadata.author == nil)
    }

    @Test func flattensNestedOutlineWithLevelsAndPages() throws {
        let pages = (0..<4).map { [FixtureLine("Page \($0)", y: 700)] }
        let url = try FixturePDF.make(pages: pages, outline: [
            FixtureOutline("Chapter 1", page: 0, children: [FixtureOutline("1.1 Tools", page: 1)]),
            FixtureOutline("Chapter 2", page: 3),
        ])
        let source = try PDFDocumentSource(url: url)
        #expect(source.outline == [
            OutlineEntry(title: "Chapter 1", level: 0, pageIndex: 0),
            OutlineEntry(title: "1.1 Tools", level: 1, pageIndex: 1),
            OutlineEntry(title: "Chapter 2", level: 0, pageIndex: 3),
        ])
    }

    @Test func outlineIsEmptyWhenThePDFHasNone() throws {
        let source = try PDFDocumentSource(url: FixturePDF.make(pages: [[FixtureLine("One", y: 700)]]))
        #expect(source.outline.isEmpty)
    }

    @Test func linesComeInReadingOrder() throws {
        let url = try FixturePDF.make(pages: [FixturePDF.paragraph(["First line", "Second line", "Third line"], top: 700)])
        let lines = try PDFDocumentSource(url: url).lines(onPage: 0)
        #expect(lines.map(\.text) == ["First line", "Second line", "Third line"])
        #expect(lines[0].rect.minY > lines[1].rect.minY)
    }

    @Test func imageOnlyPageHasNoLines() throws {
        let source = try PDFDocumentSource(url: FixturePDF.makeImageOnly())
        #expect(source.lines(onPage: 0).isEmpty)
    }

    @Test func pageOutOfRangeHasNoLines() throws {
        let source = try PDFDocumentSource(url: FixturePDF.make(pages: [[FixtureLine("One", y: 700)]]))
        #expect(source.lines(onPage: 5).isEmpty)
    }

    @Test func corruptFileThrowsCannotOpen() throws {
        let url = try FixturePDF.makeCorrupt()
        #expect(throws: DocumentError.cannotOpen(url)) { try PDFDocumentSource(url: url) }
    }

    @Test func missingFileThrowsNotFound() {
        let url = URL(fileURLWithPath: "/nonexistent/moved-book.pdf")
        #expect(throws: DocumentError.notFound(url)) { try PDFDocumentSource(url: url) }
        #expect(DocumentError.notFound(url).errorDescription
            == "Reader cannot find this file at /nonexistent/moved-book.pdf. If you moved it, open it again from its new location.")
    }

    @Test func lockedFileThrowsLocked() throws {
        let url = try FixturePDF.makeLocked()
        #expect(throws: DocumentError.locked(url)) { try PDFDocumentSource(url: url) }
    }

    @Test func errorsHaveUserMessages() {
        let url = URL(fileURLWithPath: "/tmp/a.pdf")
        #expect(DocumentError.locked(url).errorDescription == "This PDF has a password. Reader cannot open it.")
        #expect(DocumentError.cannotOpen(url).errorDescription == "This file is not a valid PDF, or it is damaged.")
    }
}
