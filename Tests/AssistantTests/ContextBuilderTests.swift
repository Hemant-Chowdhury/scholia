import DocumentKit
import Foundation
import PDFKit
import Testing
import TestSupport
@testable import Assistant

struct ContextBuilderTests {
    let selection = SelectionContext(
        text: "An agent is a loop that calls a model and tools.", pageIndex: 11,
        structuralPath: ["Part I", "Agents"], before: ["Before one.", "Before two."], after: ["After one."])

    func input(action: ReadingAction = .explain, question: String? = nil, about: String = "Backend engineer.",
               threads: [RelatedThread] = [], passages: [RelatedPassage] = []) -> PromptInput {
        PromptInput(book: BookInfo(title: "Agentic AI", author: "H. Roitman"), aboutMe: about, selection: selection,
                    action: action, question: question, relatedThreads: threads, relatedPassages: passages)
    }

    @Test func firstPromptHasAllPartsInOrder() {
        let prompt = ContextBuilder.firstPrompt(input(
            threads: [RelatedThread(question: "What is a tool?", answerStart: "A tool is a function.", page: 9)],
            passages: [RelatedPassage(page: 30, text: "Loops stop when done.")]))
        #expect(prompt == """
            You are a reading tutor in the Scholia app. You help the reader understand a book, one passage at a time.

            Rules:
            - Explain in the context of this book and of the reader's background.
            - Be clear and concrete. Use short paragraphs, examples and analogies. Use Markdown.
            - When you use content from the book, cite the page as [p. N].
            - If the passage depends on an earlier part of the book, say which part.
            - Do not change files and do not run commands.

            Book: "Agentic AI" by H. Roitman
            Location: Part I › Agents (page 12)

            About the reader:
            Backend engineer.

            The full text of the book is in the folder `text/` in your working directory (one Markdown file for each chapter, with [p. N] page markers). Read it when you need more context.

            Earlier questions about this book:
            - (p. 10) Q: What is a tool? A: A tool is a function.

            Related passages from the book:
            [p. 31] Loops stop when done.

            Text before the selection:
            Before one.

            Before two.

            Selected text (page 12):
            \"\"\"
            An agent is a loop that calls a model and tools.
            \"\"\"

            Text after the selection:
            After one.

            Task: Explain the selected text so that I understand it fully. Start with a one-sentence summary. Then explain it step by step, define each technical term, and give an example.
            """)
    }

    @Test func emptyPartsAreLeftOut() {
        let prompt = ContextBuilder.firstPrompt(input(about: "  "))
        #expect(!prompt.contains("About the reader"))
        #expect(!prompt.contains("Earlier questions"))
        #expect(!prompt.contains("Related passages"))
    }

    @Test func askUsesTheQuestion() {
        let prompt = ContextBuilder.firstPrompt(input(action: .ask, question: "Why a loop?"))
        #expect(prompt.hasSuffix("Task: Answer my question about the selected text: Why a loop?"))
    }

    @Test func longPartsAreCutToTheirLimits() {
        let long = String(repeating: "word ", count: 5000)
        let prompt = ContextBuilder.firstPrompt(input(about: long, passages: (0..<10).map { RelatedPassage(page: $0, text: long) }))
        #expect(prompt.count < 30_000)
        #expect(prompt.components(separatedBy: "\n[p. ").count - 1 == 4)
    }

    @Test func resumePromptRepeatsTheConversation() {
        let prompt = ContextBuilder.resumePrompt(input(action: .followup, question: "And tools?"),
                                                 transcript: [("user", "Explain"), ("assistant", "An agent loops.")])
        #expect(prompt.contains("Reader: Explain\n\nTutor: An agent loops."))
        #expect(prompt.hasSuffix("Now answer this: And tools?"))
    }

    @Test func quickFollowUpsHaveFixedTexts() {
        #expect(QuickFollowUp.simpler.prompt == "Explain that again in simpler words, with an everyday example.")
        #expect(QuickFollowUp.allCases.count == 4)
    }

    @Test func cleanTextJoinsLinesAndSoftHyphens() {
        #expect(TextCleaner.clean("An agent com-\nputes a\n result.  ") == "An agent computes a result.")
    }
}

struct SelectionContextTests {
    @Test func paragraphsAroundTheSelectionAreRead() throws {
        var page = FixturePDF.paragraph(["First paragraph here."], top: 700)
        page += FixturePDF.paragraph(["Second paragraph here."], top: 672)
        page += FixturePDF.paragraph(["Third paragraph here."], top: 644)
        page += FixturePDF.paragraph(["Fourth paragraph here."], top: 616)
        let source = try PDFDocumentSource(url: FixturePDF.make(pages: [page]))
        let third = try #require(source.paragraphs(onPage: 0).dropFirst(2).first)
        let locator = PDFLocator(segments: [.init(pageIndex: 0, location: third.textRange.location, length: third.textRange.length)])
        let context = SelectionContext.make(locator: locator, selectedText: "Third paragraph\nhere.", source: source,
                                            outline: [OutlineEntry(title: "Intro", level: 0, pageIndex: 0)])
        #expect(context.text == "Third paragraph here.")
        #expect(context.before == ["First paragraph here.", "Second paragraph here."])
        #expect(context.after == ["Fourth paragraph here."])
        #expect(context.structuralPath == ["Intro"])
        #expect(context.pageIndex == 0)
    }

    @Test func paragraphThatContainsAShortSelectionIsInThePrompt() throws {
        var page = FixturePDF.paragraph(["First paragraph here."], top: 700)
        page += FixturePDF.paragraph(["An agent calls a model and tools in a loop."], top: 672)
        let source = try PDFDocumentSource(url: FixturePDF.make(pages: [page]))
        let second = try #require(source.paragraphs(onPage: 0).last)
        let locator = PDFLocator(segments: [.init(pageIndex: 0, location: second.textRange.location + 3, length: 5)])
        let context = SelectionContext.make(locator: locator, selectedText: "agent", source: source, outline: [])
        #expect(context.containing == "An agent calls a model and tools in a loop.")
        #expect(context.before == ["First paragraph here."])
        let prompt = ContextBuilder.firstPrompt(PromptInput(
            book: BookInfo(title: "B", author: nil), aboutMe: "", selection: context, action: .define, question: nil,
            relatedThreads: [], relatedPassages: []))
        #expect(prompt.contains("Paragraph with the selection:\nAn agent calls a model and tools in a loop."))
    }
}
