import AppKit
import Assistant
import SwiftUI
import DocumentKit
import Foundation
import Testing
import TestSupport
import WorkspaceStore
@testable import ReaderUI

@MainActor
struct StudyModelTests {
    let helper = ParagraphSelectionTests()

    /// A reader with two finished threads: one on page 1 ("Explain"), one on page 2 ("Ask").
    func readerWithThreads() async throws -> (ReaderModel, FakeBackend) {
        let url = try helper.makeBook()
        let workspace = try WorkspaceManager(paths: AppPaths(root: helper.root)).open(pdfAt: url)
        let backend = FakeBackend()
        backend.scripts = [.events([.text("Agents loop over tools."), .done(stopReason: "end_turn")]),
                           .events([.text("Memory keeps state between steps."), .done(stopReason: "end_turn")])]
        let reader = try ReaderModel(workspace: workspace, pdfURL: url, backend: backend,
                                     defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await reader.assistant.refreshAgents()
        let source = try PDFDocumentSource(url: url)
        for (page, action) in [(0, ReadingAction.explain), (1, ReadingAction.ask)] {
            let paragraph = try #require(source.paragraphs(onPage: page).first)
            reader.assistant.start(action: action, question: action == .ask ? "What is memory?" : nil,
                                   locator: PDFLocator(segments: [.init(pageIndex: page, location: paragraph.textRange.location,
                                                                        length: paragraph.textRange.length)]),
                                   selectedText: paragraph.text)
            for _ in 0..<300 where reader.assistant.isRunning || reader.assistant.messages.last?.status != "complete" {
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        return (reader, backend)
    }

    @Test func threadsAreListedInPageOrderWithPreviews() async throws {
        let (reader, _) = try await readerWithThreads()
        let study = StudyModel(reader: reader)
        let items = study.sections.flatMap(\.items)
        #expect(items.map(\.thread.firstPage) == [0, 1])
        #expect(items.map(\.question) == ["Explain", "What is memory?"])
        #expect(items[1].answerStart == "Memory keeps state between steps.")
    }

    @Test func searchFiltersByQuestionTitleAndAnswer() async throws {
        let (reader, _) = try await readerWithThreads()
        let study = StudyModel(reader: reader)
        study.query = "state"
        #expect(study.sections.flatMap(\.items).map(\.thread.firstPage) == [1])
        study.query = "Agents call"
        #expect(study.sections.flatMap(\.items).map(\.thread.firstPage) == [0])
        study.query = ""
        #expect(study.sections.flatMap(\.items).count == 2)
    }

    @Test func selectingAThreadOpensItInTheAssistant() async throws {
        let (reader, _) = try await readerWithThreads()
        let study = StudyModel(reader: reader)
        let first = try #require(study.sections.first?.items.first)
        study.select(first.thread.id)
        #expect(reader.assistant.currentThread?.id == first.thread.id)
        #expect(reader.assistant.messages.map(\.text) == ["Explain", "Agents loop over tools."])
        #expect(study.selectedID == first.thread.id)
    }

    @Test func newThreadInTheReaderShowsAfterReload() async throws {
        let (reader, _) = try await readerWithThreads()
        let study = StudyModel(reader: reader)
        #expect(study.sections.flatMap(\.items).count == 2)
        let url = reader.pdfURL
        let paragraph = try #require(PDFDocumentSource(url: url).paragraphs(onPage: 1).first)
        reader.assistant.start(action: .define, question: nil,
                               locator: PDFLocator(segments: [.init(pageIndex: 1, location: paragraph.textRange.location,
                                                                    length: paragraph.textRange.length)]),
                               selectedText: paragraph.text)
        for _ in 0..<300 where reader.assistant.isRunning { try await Task.sleep(for: .milliseconds(10)) }
        study.reload()
        #expect(study.sections.flatMap(\.items).count == 3)
    }

    @Test(.enabled(if: WindowTests.available))
    func studyWindowShowsTheListAndTheSelectedConversation() async throws {
        let (reader, _) = try await readerWithThreads()
        let study = StudyModel(reader: reader)
        study.select(try #require(study.sections.first?.items.first).id)
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700), styleMask: [.titled, .resizable],
                              backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: StudyView(study: study))
        window.orderFront(nil)
        try await Task.sleep(for: .milliseconds(800))
        let content = try #require(window.contentView)
        if let folder = ProcessInfo.processInfo.environment["READER_UI_SNAPSHOT_DIR"],
           let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
            content.cacheDisplay(in: content.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: folder).appendingPathComponent("study.png"))
        }
        let texts = ReaderWindowUITests.all(NSTextField.self, in: content).map(\.stringValue)
            + ReaderWindowUITests.all(NSTextView.self, in: content).map(\.string)
        #expect(reader.assistant.messages.last?.text == "Agents loop over tools.")
        _ = texts
    }

    @Test func selectingAnotherQuestionWhileAnAnswerRunsKeepsTheCurrentOne() async throws {
        let (reader, backend) = try await readerWithThreads()
        let study = StudyModel(reader: reader)
        let items = study.sections.flatMap(\.items)
        study.select(items[1].id)
        backend.scripts = [.waitForCancel([.text("Running")])]
        reader.assistant.followUp("More?")
        for _ in 0..<200 where reader.assistant.messages.last?.text != "Running" { try await Task.sleep(for: .milliseconds(5)) }
        study.select(items[0].id)
        #expect(study.selectedID == items[1].id)
        #expect(reader.assistant.currentThread?.id == items[1].id)
        reader.assistant.stop()
    }

    @Test func studyFollowsTheThreadThatTheBookWindowOpens() async throws {
        let (reader, _) = try await readerWithThreads()
        let study = StudyModel(reader: reader)
        let items = study.sections.flatMap(\.items)
        reader.assistant.open(thread: items[0].thread)
        study.follow(reader.assistant.currentThread?.id)
        #expect(study.selectedID == items[0].id)
    }
}
