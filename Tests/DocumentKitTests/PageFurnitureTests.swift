import CoreGraphics
import Testing
import TestSupport
@testable import DocumentKit

struct PageFurnitureTests {
    let page = CGRect(x: 0, y: 0, width: 612, height: 792)

    private func line(_ text: String, y: CGFloat) -> TextLine {
        TextLine(text: text, rect: CGRect(x: 300, y: y, width: 12, height: 10))
    }

    @Test func numberAtBottomIsPageNumber() {
        #expect(PageFurniture.isPageNumber([line("26", y: 30)], pageBounds: page))
    }

    @Test func romanNumberAtTopIsPageNumber() {
        #expect(PageFurniture.isPageNumber([line("xiv", y: 760)], pageBounds: page))
    }

    @Test func numberInTheMiddleIsText() {
        #expect(!PageFurniture.isPageNumber([line("26", y: 400)], pageBounds: page))
    }

    @Test func wordsAtBottomAreText() {
        #expect(!PageFurniture.isPageNumber([line("Chapter 2", y: 30)], pageBounds: page))
    }

    @Test func twoLinesAreNeverAPageNumber() {
        #expect(!PageFurniture.isPageNumber([line("26", y: 30), line("27", y: 16)], pageBounds: page))
    }

    @Test func pdfParagraphsLeaveOutTheRunningPageNumber() throws {
        var lines = FixturePDF.paragraph(["Body text of the page."], top: 700)
        lines.append(FixtureLine("26", x: 300, y: 30))
        let source = try PDFDocumentSource(url: FixturePDF.make(pages: [lines]))
        #expect(source.paragraphs(onPage: 0).map(\.text) == ["Body text of the page."])
    }
}
