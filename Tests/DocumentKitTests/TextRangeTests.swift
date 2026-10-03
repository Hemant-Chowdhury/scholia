import Foundation
import Testing
import TestSupport
@testable import DocumentKit

func collapsed(_ text: String?) -> String {
    (text ?? "").split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}

struct TextRangeTests {
    @Test func linesHaveCharacterRangesInThePageText() throws {
        let source = try PDFDocumentSource(url: FixturePDF.make(pages: [
            FixturePDF.paragraph(["First line here", "Second line here"], top: 700),
        ]))
        let pageText = try #require(source.pdf.page(at: 0)?.string) as NSString
        for line in source.lines(onPage: 0) {
            #expect(line.range.location != NSNotFound)
            #expect(collapsed(pageText.substring(with: line.range)) == line.text)
        }
    }

    @Test func paragraphRangeCoversAllItsLines() throws {
        var page = FixturePDF.paragraph(["An agent is a loop that", "calls a model and tools."], top: 700, firstIndent: 18)
        page += FixturePDF.paragraph(["The loop stops when the", "task is complete."], top: 672, firstIndent: 18)
        let source = try PDFDocumentSource(url: FixturePDF.make(pages: [page]))
        let pageText = try #require(source.pdf.page(at: 0)?.string) as NSString
        let paragraphs = source.paragraphs(onPage: 0)
        #expect(paragraphs.count == 2)
        for paragraph in paragraphs {
            #expect(collapsed(pageText.substring(with: paragraph.textRange)) == paragraph.text)
        }
    }

    @Test func textRangeIsUnknownWhenALineHasNoRange() {
        let lines = [
            TextLine(text: "a", rect: .zero, range: NSRange(location: 0, length: 1)),
            TextLine(text: "b", rect: .zero),
        ]
        #expect(ParagraphGrouper.textRange(of: lines).location == NSNotFound)
    }

    @Test func outOfRangePageHasNoParagraphs() throws {
        let source = try PDFDocumentSource(url: FixturePDF.make(pages: [[FixtureLine("One", y: 700)]]))
        #expect(source.paragraphs(onPage: 3).isEmpty)
        #expect(source.paragraphs(onPage: -1).isEmpty)
    }
}
