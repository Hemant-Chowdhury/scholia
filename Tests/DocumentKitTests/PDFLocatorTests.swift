import Foundation
import PDFKit
import Testing
import TestSupport
@testable import DocumentKit

struct PDFLocatorTests {
    private func twoPageSource() throws -> PDFDocumentSource {
        try PDFDocumentSource(url: FixturePDF.make(pages: [
            FixturePDF.paragraph(["Agents call tools in a loop."], top: 700),
            FixturePDF.paragraph(["Planning needs memory."], top: 700),
        ]))
    }

    @Test func roundTripFromSelectionKeepsTheText() throws {
        let source = try twoPageSource()
        let range = try #require(source.paragraphs(onPage: 0).first?.textRange)
        let selection = try #require(source.pdf.page(at: 0)?.selection(for: range))
        let locator = try #require(PDFLocator(selection: selection, in: source.pdf))
        #expect(locator.segments == [PDFLocator.Segment(pageIndex: 0, location: range.location, length: range.length)])
        #expect(collapsed(locator.selection(in: source.pdf)?.string) == "Agents call tools in a loop.")
    }

    @Test func selectionOverTwoPagesHasTwoSortedSegments() throws {
        let source = try twoPageSource()
        let second = try #require(source.paragraphs(onPage: 1).first)
        let first = try #require(source.paragraphs(onPage: 0).first)
        let locator = PDFLocator(segments: [
            PDFLocator.Segment(pageIndex: 1, location: second.textRange.location, length: second.textRange.length),
            PDFLocator.Segment(pageIndex: 0, location: first.textRange.location, length: first.textRange.length),
        ])
        #expect(locator.segments.map(\.pageIndex) == [0, 1])
        #expect(locator.firstPage == 0)
        let rebuilt = try #require(locator.selection(in: source.pdf))
        let roundTrip = try #require(PDFLocator(selection: rebuilt, in: source.pdf))
        #expect(roundTrip == locator)
    }

    @Test func emptySelectionGivesNoLocator() throws {
        let source = try twoPageSource()
        #expect(PDFLocator(selection: PDFSelection(document: source.pdf), in: source.pdf) == nil)
    }

    @Test func overlapNeedsSamePageAndSharedCharacters() {
        let a = PDFLocator(segments: [.init(pageIndex: 0, location: 10, length: 10)])
        #expect(a.overlaps(PDFLocator(segments: [.init(pageIndex: 0, location: 15, length: 10)])))
        #expect(!a.overlaps(PDFLocator(segments: [.init(pageIndex: 0, location: 20, length: 5)])))
        #expect(!a.overlaps(PDFLocator(segments: [.init(pageIndex: 1, location: 10, length: 10)])))
    }

    @Test func jsonRoundTrip() throws {
        let locator = PDFLocator(segments: [.init(pageIndex: 3, location: 7, length: 42)])
        #expect(try PDFLocator.from(json: locator.json()) == locator)
    }

    @Test func damagedJSONThrows() {
        #expect(throws: (any Error).self) { try PDFLocator.from(json: "{not json") }
    }

    @Test func pageThatDoesNotExistGivesNoSelection() throws {
        let source = try twoPageSource()
        let locator = PDFLocator(segments: [.init(pageIndex: 99, location: 0, length: 5)])
        #expect(locator.selection(in: source.pdf) == nil)
    }
}

struct PDFLocatorResolveTests {
    private func source() throws -> PDFDocumentSource {
        try PDFDocumentSource(url: FixturePDF.make(pages: [
            FixturePDF.paragraph(["Agents call tools in a loop."], top: 700)
                + FixturePDF.paragraph(["Planning needs memory."], top: 660),
        ]))
    }

    @Test func locatorWithMatchingTextIsUnchanged() throws {
        let source = try source()
        let range = try #require(source.paragraphs(onPage: 0).last?.textRange)
        let locator = PDFLocator(segments: [.init(pageIndex: 0, location: range.location, length: range.length)])
        #expect(locator.resolved(expectedText: "Planning needs memory.", in: source.pdf) == locator)
    }

    @Test func shiftedLocatorIsFoundAgainByItsText() throws {
        let source = try source()
        let range = try #require(source.paragraphs(onPage: 0).last?.textRange)
        let shifted = PDFLocator(segments: [.init(pageIndex: 0, location: range.location - 5, length: range.length)])
        let resolved = try #require(shifted.resolved(expectedText: "Planning needs memory.", in: source.pdf))
        #expect(resolved.segments == [.init(pageIndex: 0, location: range.location, length: range.length)])
    }

    @Test func textThatIsNotOnThePageGivesNil() throws {
        let source = try source()
        let locator = PDFLocator(segments: [.init(pageIndex: 0, location: 0, length: 10)])
        #expect(locator.resolved(expectedText: "Words that are not there.", in: source.pdf) == nil)
    }
}
