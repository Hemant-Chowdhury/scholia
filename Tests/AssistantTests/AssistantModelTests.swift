import AgentKit
import DocumentKit
import Foundation
import Testing
import TestSupport
import WorkspaceStore
@testable import Assistant

@MainActor
struct AssistantModelTests {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let defaults = UserDefaults(suiteName: UUID().uuidString)!

    struct Fixture {
        let model: AssistantModel
        let backend: FakeBackend
        let workspace: OpenedWorkspace
        let locator: PDFLocator
        let url: URL
    }

    func make(backend: FakeBackend = FakeBackend(), url: URL? = nil) throws -> Fixture {
        let url = try url ?? FixturePDF.make(pages: [
            FixturePDF.paragraph(["Agents call tools in a loop."], top: 700)
                + FixturePDF.paragraph(["The loop stops when done."], top: 660),
        ], title: "Agent Book")
        let workspace = try WorkspaceManager(paths: AppPaths(root: root)).open(pdfAt: url)
        let source = try PDFDocumentSource(url: url)
        let paragraph = try #require(source.paragraphs(onPage: 0).first)
        let locator = PDFLocator(segments: [.init(pageIndex: 0, location: paragraph.textRange.location, length: paragraph.textRange.length)])
        defaults.set("I know Java.", forKey: AssistantModel.aboutMeKey)
        let model = AssistantModel(workspace: workspace, source: source, backend: backend, defaults: defaults)
        return Fixture(model: model, backend: backend, workspace: workspace, locator: locator, url: url)
    }

    func waitUntilIdle(_ model: AssistantModel) async throws {
        try await Task.sleep(for: .milliseconds(20))
        for _ in 0..<300 where model.isRunning { try await Task.sleep(for: .milliseconds(10)) }
    }

    @Test func explainCreatesAThreadAndStreamsTheAnswer() async throws {
        let backend = FakeBackend()
        backend.scripts = [.events([.tool(id: "t", title: "Read 01-chapter.md", status: "pending"),
                                    .text("An agent "), .text("is a loop."), .done(stopReason: "end_turn")])]
        let f = try make(backend: backend)
        await f.model.refreshAgents()
        f.model.start(action: .explain, question: nil, locator: f.locator, selectedText: "Agents call tools\nin a loop.")
        try await waitUntilIdle(f.model)

        #expect(f.model.messages.map(\.role) == ["user", "assistant"])
        #expect(f.model.messages[0].text == "Explain")
        #expect(f.model.messages[1].text == "An agent is a loop.")
        #expect(f.model.messages[1].status == "complete")
        let prompt = try #require(backend.prompts.first)
        #expect(prompt.contains("Agents call tools in a loop."))
        #expect(prompt.contains("I know Java."))
        #expect(prompt.contains("Book: \"Agent Book\""))
        #expect(prompt.contains("Task: Explain the selected text"))

        let thread = try #require(f.model.currentThread)
        #expect(thread.title == "Agents call tools in a loop.")
        #expect(try f.workspace.database.messages(threadID: thread.id).map(\.content) == ["Explain", "An agent is a loop."])
        #expect(try f.workspace.database.anchor(id: try #require(thread.anchorID))?.firstPage == 0)
        #expect(f.model.pageThreads.map(\.id) == [thread.id])
    }

    @Test func followUpUsesTheSameSession() async throws {
        let f = try make()
        await f.model.refreshAgents()
        f.model.start(action: .explain, question: nil, locator: f.locator, selectedText: "Agents call tools in a loop.")
        try await waitUntilIdle(f.model)
        f.model.followUp("And tools?")
        try await waitUntilIdle(f.model)
        #expect(f.backend.sessionsOpened == 1)
        #expect(f.backend.prompts.last == "And tools?")
        #expect(f.model.messages.map(\.text) == ["Explain", "ok", "And tools?", "ok"])
    }

    @Test func followUpAfterReopenSendsTheConversationAgain() async throws {
        let backend = FakeBackend()
        let first = try make(backend: backend)
        await first.model.refreshAgents()
        first.model.start(action: .explain, question: nil, locator: first.locator, selectedText: "Agents call tools in a loop.")
        try await waitUntilIdle(first.model)
        let thread = try #require(first.model.currentThread)

        let second = AssistantModel(workspace: first.workspace, source: try PDFDocumentSource(url: first.url),
                                    backend: backend, defaults: defaults)
        await second.refreshAgents()
        second.open(thread: thread)
        #expect(second.messages.map(\.text) == ["Explain", "ok"])
        second.quick(.simpler)
        try await waitUntilIdle(second)
        #expect(backend.sessionsOpened == 2)
        let prompt = try #require(backend.prompts.last)
        #expect(prompt.contains("This continues an earlier conversation"))
        #expect(prompt.contains("Tutor: ok"))
        #expect(prompt.hasSuffix("Now answer this: " + QuickFollowUp.simpler.prompt))
    }

    @Test func agentErrorIsShownAndSaved() async throws {
        let backend = FakeBackend()
        backend.scripts = [.fail("Usage limit reached.")]
        let f = try make(backend: backend)
        await f.model.refreshAgents()
        f.model.start(action: .define, question: nil, locator: f.locator, selectedText: "Agents call tools.")
        try await waitUntilIdle(f.model)
        #expect(f.model.messages.last?.status == "failed")
        #expect(f.model.messages.last?.error == "Usage limit reached.")
        #expect(f.model.errorMessage == "Usage limit reached.")
    }

    @Test func stopCancelsTheAnswer() async throws {
        let backend = FakeBackend()
        backend.scripts = [.waitForCancel([.text("Half an ans")])]
        let f = try make(backend: backend)
        await f.model.refreshAgents()
        f.model.start(action: .explain, question: nil, locator: f.locator, selectedText: "Agents.")
        for _ in 0..<200 where f.model.messages.last?.text != "Half an ans" { try await Task.sleep(for: .milliseconds(5)) }
        f.model.stop()
        try await waitUntilIdle(f.model)
        #expect(f.model.messages.last?.status == "cancelled")
        #expect(f.model.messages.last?.text == "Half an ans")
    }

    @Test func chosenModelIsSetOnTheSession() async throws {
        let f = try make()
        await f.model.refreshAgents()
        f.model.selectModel("haiku")
        f.model.start(action: .explain, question: nil, locator: f.locator, selectedText: "Agents.")
        try await waitUntilIdle(f.model)
        #expect(f.backend.optionsSet.map(\.1) == ["haiku"])
        #expect(f.model.modelChoices.map(\.value) == ["opus", "haiku"])
        #expect(f.model.selectedModel == "haiku")
    }

    @Test func agentThatIsNotInstalledGivesAClearMessage() async throws {
        let backend = FakeBackend()
        backend.installed = false
        let f = try make(backend: backend)
        await f.model.refreshAgents()
        f.model.selectAgent("claude")
        f.model.start(action: .explain, question: nil, locator: f.locator, selectedText: "Agents.")
        try await waitUntilIdle(f.model)
        #expect(f.model.errorMessage == "Claude Code is not installed. Scholia cannot find: claude.")
        #expect(f.model.messages.last?.status == "failed")
    }

    @Test func secondQuestionAboutAnotherPartGetsTheFirstAsContext() async throws {
        let backend = FakeBackend()
        backend.scripts = [.events([.text("Tools are functions."), .done(stopReason: "end_turn")])]
        let f = try make(backend: backend)
        await f.model.refreshAgents()
        f.model.start(action: .ask, question: "What are tools?", locator: f.locator, selectedText: "Agents call tools in a loop.")
        try await waitUntilIdle(f.model)
        f.model.start(action: .explain, question: nil, locator: f.locator, selectedText: "The loop stops when tools are done.")
        try await waitUntilIdle(f.model)
        let prompt = try #require(backend.prompts.last)
        #expect(prompt.contains("Q: What are tools? A: Tools are functions."))
    }

    @Test func veryLongSelectionDoesNotBlockTheWindow() async throws {
        let f = try make()
        await f.model.refreshAgents()
        let long = (0..<20_000).map { "word\($0 % 3000)" }.joined(separator: " ")
        let start = Date()
        f.model.start(action: .explain, question: nil, locator: f.locator, selectedText: long)
        #expect(Date().timeIntervalSince(start) < 0.5)
        try await waitUntilIdle(f.model)
        #expect((f.model.currentAnchor?.text.count ?? 0) <= ContextBuilder.selectionLimit + 1)
        #expect((f.backend.prompts.first?.count ?? .max) < 40_000)
    }

    @Test func stopWhileTheAgentStartsEndsTheAnswerAtOnce() async throws {
        let backend = FakeBackend()
        backend.openDelay = 5
        let f = try make(backend: backend)
        await f.model.refreshAgents()
        f.model.start(action: .explain, question: nil, locator: f.locator, selectedText: "Agents.")
        try await Task.sleep(for: .milliseconds(50))
        f.model.stop()
        #expect(!f.model.isRunning)
        #expect(f.model.messages.last?.status == "cancelled")
    }

    @Test func newActionDuringAnAnswerStopsItAndStartsTheNewOne() async throws {
        let backend = FakeBackend()
        backend.scripts = [.waitForCancel([.text("First answer")]), .events([.text("Second"), .done(stopReason: "end_turn")])]
        let f = try make(backend: backend)
        await f.model.refreshAgents()
        f.model.start(action: .explain, question: nil, locator: f.locator, selectedText: "Agents call tools.")
        for _ in 0..<200 where f.model.messages.last?.text != "First answer" { try await Task.sleep(for: .milliseconds(5)) }
        f.model.start(action: .define, question: nil, locator: f.locator, selectedText: "The loop stops.")
        try await waitUntilIdle(f.model)
        #expect(f.model.messages.map(\.text) == ["Define", "Second"])
        #expect(f.model.allThreads.count == 2)
    }

    @Test func retryAfterAFailedFirstActionSendsTheFullPrompt() async throws {
        let backend = FakeBackend()
        backend.scripts = [.fail("Network error.")]
        let f = try make(backend: backend)
        await f.model.refreshAgents()
        f.model.start(action: .explain, question: nil, locator: f.locator, selectedText: "Agents call tools in a loop.")
        try await waitUntilIdle(f.model)
        f.model.retry()
        try await waitUntilIdle(f.model)
        #expect(backend.prompts.count == 2)
        #expect(backend.prompts[1].contains("Task: Explain the selected text"))
        #expect(f.model.messages.map(\.status) == ["complete", "complete"])
    }

    @Test func textBeforeAndAfterAToolGetsAParagraphBreak() async throws {
        let backend = FakeBackend()
        backend.scripts = [.events([.text("I will check the chapter."), .tool(id: "t", title: "Read", status: "pending"),
                                    .text("**Summary:** a loop."), .done(stopReason: "end_turn")])]
        let f = try make(backend: backend)
        await f.model.refreshAgents()
        f.model.start(action: .explain, question: nil, locator: f.locator, selectedText: "Agents.")
        try await waitUntilIdle(f.model)
        #expect(f.model.messages.last?.text == "I will check the chapter.\n\n**Summary:** a loop.")
    }
}
