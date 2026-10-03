import Foundation
import Synchronization
import Testing
import TestSupport
@testable import WorkspaceStore

struct DocumentIndexerTests {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    private func threePagePDF() throws -> URL {
        try FixturePDF.make(pages: [
            FixturePDF.paragraph(["Agents use tools."], top: 700),
            FixturePDF.paragraph(["Planning needs memory."], top: 700),
            FixturePDF.paragraph(["Reflection improves answers."], top: 700),
        ], outline: [FixtureOutline("Basics", page: 0), FixtureOutline("Advanced", page: 2)])
    }

    @Test func indexesAllPagesAndReportsProgress() throws {
        let url = try threePagePDF()
        let workspace = try WorkspaceManager(paths: AppPaths(root: root)).open(pdfAt: url)
        let reports = Mutex<[IndexProgress]>([])
        try DocumentIndexer.run(workspace: workspace, pdfURL: url) { progress in reports.withLock { $0.append(progress) } }

        let document = try #require(try workspace.database.document(id: workspace.document.id))
        #expect(document.indexedPages == 3)
        #expect(document.textExported)
        #expect(reports.withLock { $0.last } == IndexProgress(indexedPages: 3, pageCount: 3))
        #expect(try workspace.database.searchText("memory").map(\.pageIndex) == [1])
    }

    @Test func writesOneTextFileForEachChapter() throws {
        let url = try threePagePDF()
        let workspace = try WorkspaceManager(paths: AppPaths(root: root)).open(pdfAt: url)
        try DocumentIndexer.run(workspace: workspace, pdfURL: url)

        let files = try FileManager.default.contentsOfDirectory(atPath: workspace.textFolder.path).sorted()
        #expect(files == ["01-basics.md", "02-advanced.md"])
        let basics = try String(contentsOf: workspace.textFolder.appendingPathComponent("01-basics.md"), encoding: .utf8)
        #expect(basics == "# Basics\n\n[p. 1]\n\nAgents use tools.\n\n[p. 2]\n\nPlanning needs memory.\n")
    }

    @Test func interruptedRunContinuesWithoutDuplicates() async throws {
        let url = try threePagePDF()
        let workspace = try WorkspaceManager(paths: AppPaths(root: root)).open(pdfAt: url)
        let task = Task {
            try DocumentIndexer.run(workspace: workspace, pdfURL: url) { progress in
                if progress.indexedPages == 1 { withUnsafeCurrentTask { $0?.cancel() } }
            }
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try workspace.database.document(id: workspace.document.id)?.indexedPages == 1)

        try DocumentIndexer.run(workspace: workspace, pdfURL: url)

        #expect(try workspace.database.document(id: workspace.document.id)?.indexedPages == 3)
        #expect(try workspace.database.paragraphs(documentID: workspace.document.id, pages: 0..<3).count == 3)
    }

    @Test func secondRunDuringFirstRunWaitsAndDoesNoWork() async throws {
        let url = try FixturePDF.make(pages: (0..<6).map { FixturePDF.paragraph(["Page \($0) text."], top: 700) })
        let workspace = try WorkspaceManager(paths: AppPaths(root: root)).open(pdfAt: url)
        let second = SecondRun()
        try DocumentIndexer.run(workspace: workspace, pdfURL: url) { progress in
            guard progress.indexedPages == 1 else { return }
            second.start { try DocumentIndexer.run(workspace: workspace, pdfURL: url, progress: second.record) }
            Thread.sleep(forTimeInterval: 0.3)
        }
        try await second.task?.value

        #expect(second.reports == [IndexProgress(indexedPages: 6, pageCount: 6)])
        let files = try FileManager.default.contentsOfDirectory(atPath: workspace.textFolder.path)
        #expect(files == ["01-pages-1-6.md"])
        #expect(try workspace.database.paragraphs(documentID: workspace.document.id, pages: 0..<6).count == 6)
    }

    @Test func secondRunAfterCompletionChangesNothing() throws {
        let url = try threePagePDF()
        let workspace = try WorkspaceManager(paths: AppPaths(root: root)).open(pdfAt: url)
        try DocumentIndexer.run(workspace: workspace, pdfURL: url)
        try DocumentIndexer.run(workspace: workspace, pdfURL: url)
        #expect(try workspace.database.paragraphs(documentID: workspace.document.id, pages: 0..<3).count == 3)
    }

    @Test func imageOnlyPDFCompletesWithNoParagraphs() throws {
        let url = try FixturePDF.makeImageOnly()
        let workspace = try WorkspaceManager(paths: AppPaths(root: root)).open(pdfAt: url)
        try DocumentIndexer.run(workspace: workspace, pdfURL: url)
        let document = try #require(try workspace.database.document(id: workspace.document.id))
        #expect(document.indexedPages == 1)
        #expect(document.textExported)
        let file = try String(contentsOf: workspace.textFolder.appendingPathComponent("01-pages-1-1.md"), encoding: .utf8)
        #expect(file == "# Pages 1–1\n")
    }
}

/// Starts a second indexer run on another thread and records its progress reports.
private final class SecondRun: @unchecked Sendable {
    private let lock = NSLock()
    private var _reports: [IndexProgress] = []
    private(set) var task: Task<Void, any Error>?

    var reports: [IndexProgress] { lock.withLock { _reports } }

    func record(_ progress: IndexProgress) { lock.withLock { _reports.append(progress) } }

    /// Returns after the second run has started.
    func start(_ body: @escaping @Sendable () throws -> Void) {
        let started = DispatchSemaphore(value: 0)
        task = Task.detached {
            started.signal()
            try body()
        }
        started.wait()
    }
}
