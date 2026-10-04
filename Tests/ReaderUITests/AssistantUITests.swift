import AppKit
import Assistant
import Foundation
import PDFKit
import Testing
import TestSupport
import WorkspaceStore
@testable import ReaderUI

/// The assistant in the real reader window, driven by real events, with a scripted agent.
@MainActor
struct AssistantUITests {
    let ui = ReaderWindowUITests()

    func hostWithAgent(_ backend: FakeBackend) throws -> (ReaderWindowUITests.Hosted, URL) {
        let url = try ui.helper.makeBook()
        let workspace = try WorkspaceManager(paths: AppPaths(root: ui.helper.root)).open(pdfAt: url)
        let model = try ReaderModel(workspace: workspace, pdfURL: url, backend: backend,
                                    defaults: UserDefaults(suiteName: UUID().uuidString)!)
        return (try ui.host(model: model), url)
    }

    /// Waits with Task.sleep, so the main actor is free to run the assistant's tasks.
    func waitFor(_ condition: () -> Bool) async throws {
        for _ in 0..<300 where !condition() { try await Task.sleep(for: .milliseconds(20)) }
    }

    @Test func eKeyExplainsTheSelectionInThePanel() async throws {
        let backend = FakeBackend()
        backend.scripts = [.events([.text("An agent is **a loop** [p. 1]."), .done(stopReason: "end_turn")])]
        let (hosted, url) = try hostWithAgent(backend)
        try ui.click(hosted, pageIndex: 0, pagePoint: ui.helper.center(of: 0, onPage: 0, in: url), modifiers: .option)
        try ui.press(hosted, key: "e")
        try await waitFor { hosted.model.assistant.messages.last?.status == "complete" }
        ui.snapshot(hosted, "assistant-explain")
        #expect(hosted.model.showAssistant)
        #expect(hosted.model.assistant.messages.map(\.text) == ["Explain", "An agent is **a loop** [p. 1]."])
        #expect(backend.prompts.first?.contains("Agents call tools in a loop.") == true)
    }

    @Test func explainButtonInTheBarRunsTheAction() async throws {
        let backend = FakeBackend()
        let (hosted, url) = try hostWithAgent(backend)
        try ui.click(hosted, pageIndex: 0, pagePoint: ui.helper.center(of: 0, onPage: 0, in: url), modifiers: .option)
        try await ui.settle()
        let point = try #require(ReaderWindowUITests.explainButtonPoint(hosted))
        let frameView = try #require(hosted.window.contentView?.superview)
        let hit = try #require(frameView.hitTest(frameView.convert(point, from: nil)))
        // The click reaches the native Explain button; performClick runs its target and action like a real click.
        let button = try #require(hit as? NSButton, "click at the Explain button goes to \(type(of: hit))")
        #expect(button.title == "Explain")
        button.performClick(nil)
        try await waitFor { hosted.model.assistant.messages.last?.status == "complete" }
        #expect(hosted.model.assistant.messages.first?.text == "Explain")
    }

    @Test func aKeyOpensTheQuestionFieldAndTheQuestionIsSent() async throws {
        let backend = FakeBackend()
        let (hosted, url) = try hostWithAgent(backend)
        try ui.click(hosted, pageIndex: 0, pagePoint: ui.helper.center(of: 0, onPage: 0, in: url), modifiers: .option)
        try ui.press(hosted, key: "a")
        #expect(hosted.model.pendingAsk != nil)
        hosted.model.submitAsk("Why a loop?")
        try await waitFor { hosted.model.assistant.messages.last?.status == "complete" }
        #expect(hosted.model.assistant.messages.first?.text == "Why a loop?")
        #expect(backend.prompts.first?.hasSuffix("Task: Answer my question about the selected text: Why a loop?") == true)
    }

    @Test func lettersTypedInTheSearchFieldAreNotActions() throws {
        let (hosted, url) = try hostWithAgent(FakeBackend())
        try ui.click(hosted, pageIndex: 0, pagePoint: ui.helper.center(of: 0, onPage: 0, in: url), modifiers: .option)
        let field = NSTextField(frame: .zero)
        hosted.window.contentView?.addSubview(field)
        hosted.window.makeFirstResponder(field)
        try ui.press(hosted, key: "e")
        #expect(hosted.model.assistant.messages.isEmpty)
    }

}
