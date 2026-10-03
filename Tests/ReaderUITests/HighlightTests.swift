import DocumentKit
import Foundation
import Testing
import TestSupport
import WorkspaceStore
@testable import ReaderUI

@MainActor
struct HighlightTests {
    let helper = ParagraphSelectionTests()

    @Test func highlightIsSavedAndComesBackAfterReopen() throws {
        let url = try helper.makeBook()
        let model = try helper.openModel(url)
        model.optionClick(at: try helper.center(of: 0, onPage: 0, in: url), onPage: 0)
        model.highlightSelection()
        #expect(model.highlights.count == 1)
        #expect(collapsed(model.highlights[0].anchor.text) == "Agents call tools in a loop.")
        #expect(model.highlights[0].anchor.firstPage == 0)

        let reopened = try helper.openModel(url)
        #expect(reopened.highlights.map(\.highlight.id) == model.highlights.map(\.highlight.id))
        let locator = try PDFLocator.from(json: reopened.highlights[0].anchor.locatorJSON)
        #expect(collapsed(locator.selection(in: reopened.pdf)?.string) == "Agents call tools in a loop.")
    }

    @Test func sameTextIsNotHighlightedTwice() throws {
        let url = try helper.makeBook()
        let model = try helper.openModel(url)
        model.optionClick(at: try helper.center(of: 0, onPage: 0, in: url), onPage: 0)
        model.highlightSelection()
        model.highlightSelection()
        #expect(model.highlights.count == 1)
        #expect(model.selectionHighlights.count == 1)
    }

    @Test func removeSelectionHighlightsDeletesThem() throws {
        let url = try helper.makeBook()
        let model = try helper.openModel(url)
        model.optionClick(at: try helper.center(of: 0, onPage: 0, in: url), onPage: 0)
        model.highlightSelection()
        model.removeSelectionHighlights()
        #expect(model.highlights.isEmpty)
        #expect(try helper.openModel(url).highlights.isEmpty)
    }

    @Test func noSelectionMeansNoHighlight() throws {
        let model = try helper.openModel(helper.makeBook())
        model.highlightSelection()
        #expect(model.highlights.isEmpty)
    }

    @Test func highlightOverAPageBreakHasTwoSegmentsAndRectsOnBothPages() throws {
        let url = try helper.makeBook()
        let model = try helper.openModel(url)
        let point = try helper.center(of: 1, onPage: 0, in: url)
        model.optionClick(at: point, onPage: 0)
        model.optionClick(at: point, onPage: 0)
        model.highlightSelection()
        let locator = try PDFLocator.from(json: model.highlights[0].anchor.locatorJSON)
        #expect(locator.segments.map(\.pageIndex) == [0, 1])
        let rects = HighlightGeometry.lineRects(for: locator, in: model.pdf)
        #expect(Set(rects.map(\.pageIndex)) == [0, 1])
        #expect(rects.allSatisfy { !$0.rect.isEmpty })
    }

    @Test func damagedLocatorIsSkipped() throws {
        let url = try helper.makeBook()
        let model = try helper.openModel(url)
        let anchor = AnchorRecord(id: "bad", documentID: model.workspace.document.id, kind: "pdf", locatorJSON: "{broken",
                                  text: "x", structuralPath: "", firstPage: 0, createdAt: Date())
        try model.workspace.database.addHighlight(
            HighlightRecord(id: "hbad", anchorID: "bad", color: "yellow", createdAt: Date()), anchor: anchor)
        let reopened = try helper.openModel(url)
        reopened.optionClick(at: try helper.center(of: 0, onPage: 0, in: url), onPage: 0)
        #expect(reopened.selectionHighlights.isEmpty)
        reopened.show(reopened.highlights[0])
        #expect(reopened.navigationRequest?.pageIndex == 0)
        #expect(HighlightGeometry.lineRects(for: PDFLocator(segments: [.init(pageIndex: 99, location: 0, length: 3)]),
                                            in: reopened.pdf).isEmpty)
    }
}
