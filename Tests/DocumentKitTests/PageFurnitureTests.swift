import CoreGraphics
import PDFKit
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

struct RunningHeadTests {
    private func page(header: String?, body: String) -> [FixtureLine] {
        var lines = FixturePDF.paragraph([body], top: 700)
        if let header { lines.append(FixtureLine(header, x: 72, y: 760, size: 9)) }
        return lines
    }

    @Test func headerThatRepeatsOnNearPagesIsLeftOut() throws {
        let source = try PDFDocumentSource(url: FixturePDF.make(pages: [
            page(header: "Agentic AI Guide 11", body: "First page body."),
            page(header: "Agentic AI Guide 12", body: "Second page body."),
            page(header: "Agentic AI Guide 13", body: "Third page body."),
        ]))
        #expect(source.paragraphs(onPage: 1).map(\.text) == ["Second page body."])
        #expect(source.paragraphs(onPage: 0).map(\.text) == ["First page body."])
    }

    @Test func topLineThatDoesNotRepeatIsKept() throws {
        let source = try PDFDocumentSource(url: FixturePDF.make(pages: [
            page(header: "Chapter One", body: "First page body."),
            page(header: "Agentic AI Guide", body: "Second page body."),
            page(header: "Agentic AI Guide", body: "Third page body."),
        ]))
        #expect(source.paragraphs(onPage: 0).map(\.text) == ["Chapter One", "First page body."])
    }

    @Test func pageNumberInsideTheCropBoxBandIsLeftOut() throws {
        var lines = FixturePDF.paragraph(["Body text of the page."], top: 600)
        lines.append(FixtureLine("33", x: 300, y: 670))
        let url = try FixturePDF.make(pages: [lines])
        let document = try #require(PDFDocument(url: url))
        document.page(at: 0)?.setBounds(CGRect(x: 0, y: 60, width: 612, height: 666), for: .cropBox)
        #expect(document.write(to: url))
        #expect(try PDFDocumentSource(url: url).paragraphs(onPage: 0).map(\.text) == ["Body text of the page."])
    }
}
