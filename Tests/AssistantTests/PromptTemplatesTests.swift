import DocumentKit
import Foundation
import Testing
import TestSupport
import WorkspaceStore
@testable import Assistant

struct PromptTemplatesTests {
    let selection = SelectionContext(text: "An agent is a loop.", pageIndex: 0, structuralPath: [], before: [], after: [])

    func input(_ action: ReadingAction, _ templates: PromptTemplates, question: String? = nil) -> PromptInput {
        PromptInput(book: BookInfo(title: "B", author: nil), aboutMe: "", selection: selection, action: action,
                    question: question, relatedThreads: [], relatedPassages: [], templates: templates)
    }

    @Test func standardTemplatesGiveTheBuiltInTexts() {
        let prompt = ContextBuilder.firstPrompt(input(.simplify, .standard))
        #expect(prompt.hasPrefix("You are a reading tutor in the Reader app."))
        #expect(prompt.hasSuffix("Task: Explain the selected text in the simplest words, for a smart beginner. Use one concrete everyday example. Keep it short."))
    }

    @Test func customRulesAndTaskReplaceTheBuiltInTexts() {
        var templates = PromptTemplates.standard
        templates.rules = "You are a patient teacher."
        templates.explain = "Explain it like a podcast host."
        templates.ask = "Reply briefly to:"
        let explain = ContextBuilder.firstPrompt(input(.explain, templates))
        #expect(explain.hasPrefix("You are a patient teacher."))
        #expect(explain.hasSuffix("Task: Explain it like a podcast host."))
        #expect(ContextBuilder.firstPrompt(input(.ask, templates, question: "Why?")).hasSuffix("Task: Reply briefly to: Why?"))
    }

    @Test func templatesAreSavedAndLoadedAndMissingFieldsUseDefaults() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        #expect(PromptTemplates.load(from: defaults) == .standard)
        var templates = PromptTemplates.standard
        templates.define = "Define like a glossary."
        templates.save(to: defaults)
        #expect(PromptTemplates.load(from: defaults).define == "Define like a glossary.")
        defaults.set(Data(#"{"simplify":"Short please."}"#.utf8), forKey: PromptTemplates.defaultsKey)
        let partial = PromptTemplates.load(from: defaults)
        #expect(partial.simplify == "Short please.")
        #expect(partial.explain == PromptTemplates.standard.explain)
    }

    @Test func emptyFieldFallsBackToTheDefault() {
        var templates = PromptTemplates.standard
        templates.explain = "   "
        #expect(ContextBuilder.firstPrompt(input(.explain, templates)).hasSuffix("Task: " + PromptTemplates.standard.explain))
    }

    @Test func quickFollowUpTextComesFromTheTemplates() {
        var templates = PromptTemplates.standard
        templates.simpler = "Simpler, please."
        #expect(templates.text(for: .simpler) == "Simpler, please.")
        #expect(PromptTemplates.standard.text(for: .why) == QuickFollowUp.why.prompt)
    }
    @Test func findResourcesAsksForVideosArticlesAndBasicsWithLinksFromWebSearch() {
        let prompt = ContextBuilder.firstPrompt(input(.resources, .standard))
        #expect(prompt.contains("Task: Find learning resources for the topic of the selected text"))
        #expect(prompt.contains("## Watch"))
        #expect(prompt.contains("## Read"))
        #expect(prompt.contains("Use web search"))
        var templates = PromptTemplates.standard
        templates.resources = "Find two videos."
        #expect(ContextBuilder.firstPrompt(input(.resources, templates)).hasSuffix("Task: Find two videos."))
        #expect(ReadingAction.resources.title == "Resources")
    }
}

@MainActor
struct SavedTemplatesTests {
    @Test func assistantUsesTheSavedTemplates() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        var templates = PromptTemplates.standard
        templates.explain = "Explain with a cooking analogy."
        templates.simpler = "Shorter."
        templates.save(to: defaults)
        let url = try FixturePDF.make(pages: [FixturePDF.paragraph(["Agents call tools in a loop."], top: 700)])
        let workspace = try WorkspaceManager(paths: AppPaths(root: root)).open(pdfAt: url)
        let source = try PDFDocumentSource(url: url)
        let range = try #require(source.paragraphs(onPage: 0).first?.textRange)
        let backend = FakeBackend()
        let model = AssistantModel(workspace: workspace, source: source, backend: backend, defaults: defaults)
        await model.refreshAgents()
        model.start(action: .explain, question: nil,
                    locator: PDFLocator(segments: [.init(pageIndex: 0, location: range.location, length: range.length)]),
                    selectedText: "Agents call tools in a loop.")
        for _ in 0..<300 where model.isRunning || model.messages.last?.status != "complete" { try await Task.sleep(for: .milliseconds(10)) }
        model.quick(.simpler)
        for _ in 0..<300 where backend.prompts.count < 2 || model.isRunning { try await Task.sleep(for: .milliseconds(10)) }
        #expect(backend.prompts.first?.hasSuffix("Task: Explain with a cooking analogy.") == true)
        #expect(backend.prompts.last == "Shorter.")
        #expect(model.messages[2].text == "Simpler")
    }

}
