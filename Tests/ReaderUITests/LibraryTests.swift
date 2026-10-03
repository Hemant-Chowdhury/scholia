import DocumentKit
import Foundation
import Testing
import TestSupport
import WorkspaceStore
@testable import ReaderUI

@MainActor
struct LibraryTests {
    let paths = AppPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))

    @Test func openingADocumentAddsItToRecents() async throws {
        let library = Library(paths: paths)
        #expect(library.startupError == nil)
        #expect(library.recents.isEmpty)
        let url = try FixturePDF.make(pages: [[FixtureLine("Text", y: 700)]], title: "Recent Book")
        let model = try await library.openModel(for: url)
        #expect(model.pdf.pageCount == 1)
        #expect(library.recents.map(\.title) == ["Recent Book"])
    }

    @Test func openingADamagedFileThrows() async throws {
        let library = Library(paths: paths)
        let url = try FixturePDF.makeCorrupt()
        await #expect(throws: DocumentError.cannotOpen(url)) { try await library.openModel(for: url) }
    }
}
