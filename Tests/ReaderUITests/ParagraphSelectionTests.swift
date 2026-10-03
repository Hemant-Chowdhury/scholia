import DocumentKit
import Foundation
import Testing
import TestSupport
import WorkspaceStore
@testable import ReaderUI

func collapsed(_ text: String?) -> String {
    (text ?? "").split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}

@MainActor
struct ParagraphSelectionTests {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    /// Page 0 has two paragraphs. Page 1 has one paragraph.
    func makeBook() throws -> URL {
        var first = FixturePDF.paragraph(["Agents call tools", "in a loop."], top: 700, firstIndent: 18)
        first += FixturePDF.paragraph(["The loop stops", "when done."], top: 672, firstIndent: 18)
        return try FixturePDF.make(pages: [first, FixturePDF.paragraph(["Memory keeps state."], top: 700)])
    }

    func openModel(_ url: URL) throws -> ReaderModel {
        let workspace = try WorkspaceManager(paths: AppPaths(root: root)).open(pdfAt: url)
        return try ReaderModel(workspace: workspace, pdfURL: url)
    }

    func center(of paragraph: Int, onPage page: Int, in url: URL) throws -> CGPoint {
        let paragraphs = try PDFDocumentSource(url: url).paragraphs(onPage: page)
        return CGPoint(x: paragraphs[paragraph].rect.midX, y: paragraphs[paragraph].rect.midY)
    }

    @Test func optionClickSelectsTheParagraph() throws {
        let url = try makeBook()
        let model = try openModel(url)
        #expect(model.optionClick(at: try center(of: 1, onPage: 0, in: url), onPage: 0))
        #expect(collapsed(model.selectedText) == "The loop stops when done.")
        #expect(model.selectionRequest?.selection != nil)
    }

    @Test func optionClickAgainAddsTheNextParagraph() throws {
        let url = try makeBook()
        let model = try openModel(url)
        let point = try center(of: 0, onPage: 0, in: url)
        model.optionClick(at: point, onPage: 0)
        model.optionClick(at: point, onPage: 0)
        #expect(collapsed(model.selectedText) == "Agents call tools in a loop. The loop stops when done.")
    }

    @Test func optionClickAgainContinuesOnTheNextPage() throws {
        let url = try makeBook()
        let model = try openModel(url)
        let point = try center(of: 1, onPage: 0, in: url)
        model.optionClick(at: point, onPage: 0)
        model.optionClick(at: point, onPage: 0)
        #expect(collapsed(model.selectedText) == "The loop stops when done. Memory keeps state.")
        #expect(model.selection?.pages.count == 2)
    }

    @Test func optionClickOnAnotherParagraphStartsANewSelection() throws {
        let url = try makeBook()
        let model = try openModel(url)
        model.optionClick(at: try center(of: 0, onPage: 0, in: url), onPage: 0)
        model.optionClick(at: try center(of: 1, onPage: 0, in: url), onPage: 0)
        #expect(collapsed(model.selectedText) == "The loop stops when done.")
    }

    @Test func optionClickOnEmptySpaceChangesNothing() throws {
        let url = try makeBook()
        let model = try openModel(url)
        model.optionClick(at: try center(of: 0, onPage: 0, in: url), onPage: 0)
        #expect(!model.optionClick(at: CGPoint(x: 5, y: 5), onPage: 0))
        #expect(collapsed(model.selectedText) == "Agents call tools in a loop.")
    }

    @Test func userSelectionChangeEndsParagraphSelection() throws {
        let url = try makeBook()
        let model = try openModel(url)
        let point = try center(of: 0, onPage: 0, in: url)
        model.optionClick(at: point, onPage: 0)
        model.selectionDidChange(nil)
        #expect(model.selection == nil)
        model.optionClick(at: point, onPage: 0)
        #expect(collapsed(model.selectedText) == "Agents call tools in a loop.")
    }

    @Test func optionClickAgainOnTheLastParagraphKeepsTheSelection() throws {
        let url = try makeBook()
        let model = try openModel(url)
        let point = try center(of: 0, onPage: 1, in: url)
        model.optionClick(at: point, onPage: 1)
        model.optionClick(at: point, onPage: 1)
        #expect(collapsed(model.selectedText) == "Memory keeps state.")
    }
}
