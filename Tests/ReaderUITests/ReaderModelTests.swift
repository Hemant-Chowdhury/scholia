import Foundation
import Testing
import TestSupport
import WorkspaceStore
@testable import ReaderUI

@MainActor
struct ReaderModelTests {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    private func book() throws -> URL {
        try FixturePDF.make(pages: [
            [FixtureLine("Introduction text", y: 700)],
            [FixtureLine("The orchestrator assigns work", y: 700)],
            [FixtureLine("Summary", y: 700)],
        ], outline: [FixtureOutline("Part One", page: 0, children: [FixtureOutline("Orchestration", page: 1)])])
    }

    private func openModel(_ url: URL) throws -> ReaderModel {
        let workspace = try WorkspaceManager(paths: AppPaths(root: root)).open(pdfAt: url)
        return try ReaderModel(workspace: workspace, pdfURL: url)
    }

    @Test func newDocumentStartsAtFirstPage() throws {
        let model = try openModel(book())
        #expect(model.currentPage == 0)
        #expect(model.navigationRequest?.pageIndex == 0)
    }

    @Test func pageChangeIsSavedAndRestoredOnReopen() throws {
        let url = try book()
        let model = try openModel(url)
        model.pageDidChange(to: 2)
        #expect(model.currentPage == 2)

        let reopened = try openModel(url)
        #expect(reopened.currentPage == 2)
        #expect(reopened.navigationRequest?.pageIndex == 2)
    }

    @Test func structuralPathFollowsCurrentPage() throws {
        let model = try openModel(book())
        model.pageDidChange(to: 1)
        #expect(model.structuralPath == ["Part One", "Orchestration"])
    }

    @Test func goToPageMakesNewNavigationRequest() throws {
        let model = try openModel(book())
        let before = model.navigationRequest
        model.go(toPage: 2)
        #expect(model.navigationRequest?.pageIndex == 2)
        #expect(model.navigationRequest != before)
    }

    @Test func searchFindsPagesAndShowNavigates() throws {
        let model = try openModel(book())
        model.search("orchestrator")
        #expect(model.searchResults.map(\.pageIndex) == [1])
        #expect(model.searchResults[0].snippet.contains("orchestrator"))
        model.show(model.searchResults[0])
        #expect(model.navigationRequest?.pageIndex == 1)
        #expect(model.navigationRequest?.selection != nil)
    }

    @Test func shortOrEmptySearchClearsResults() throws {
        let model = try openModel(book())
        model.search("orchestrator")
        model.search(" o ")
        #expect(model.searchResults.isEmpty)
    }

    @Test func indexingCompletesAndUpdatesProgress() async throws {
        let model = try openModel(book())
        model.startIndexing()
        for _ in 0..<200 where !model.indexProgress.isComplete {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(model.indexProgress == IndexProgress(indexedPages: 3, pageCount: 3))
        #expect(model.lastError == nil)
    }
}
