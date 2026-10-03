import Testing
import TestSupport
@testable import DocumentKit

struct PDFParagraphTests {
    @Test func headingAndIndentedParagraphsAreDetected() throws {
        var page = [FixtureLine("1.2 Tool use", y: 720, size: 18)]
        page += FixturePDF.paragraph(["An agent is a loop that", "calls a model and tools."], top: 690, firstIndent: 18)
        page += FixturePDF.paragraph(["The loop stops when the", "task is complete."], top: 662, firstIndent: 18)
        let source = try PDFDocumentSource(url: FixturePDF.make(pages: [page]))

        let paragraphs = source.paragraphs(onPage: 0)

        #expect(paragraphs.map(\.text) == [
            "1.2 Tool use",
            "An agent is a loop that calls a model and tools.",
            "The loop stops when the task is complete.",
        ])
        #expect(paragraphs.map(\.index) == [0, 1, 2])
        #expect(paragraphs.allSatisfy { $0.pageIndex == 0 && !$0.rect.isEmpty })
    }

    @Test func imageOnlyPageHasNoParagraphs() throws {
        let source = try PDFDocumentSource(url: FixturePDF.makeImageOnly())
        #expect(source.paragraphs(onPage: 0).isEmpty)
    }
}
