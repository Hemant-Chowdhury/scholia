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

    @Test func closingTheLastReaderWindowIsReported() {
        let library = Library(paths: paths)
        library.readerWindowOpened()
        library.readerWindowOpened()
        #expect(library.readerWindowClosed() == false)
        #expect(library.readerWindowClosed() == true)
    }

    @Test func extraCloseIsNotReportedAsLast() {
        let library = Library(paths: paths)
        #expect(library.readerWindowClosed() == false)
        library.readerWindowOpened()
        #expect(library.readerWindowClosed() == true)
    }

    @Test func closedBookWindowIsNoLongerTheReaderOfItsWorkspace() async throws {
        let library = Library(paths: paths)
        let url = try FixturePDF.make(pages: [[FixtureLine("Text", y: 700)]])
        let first = try await library.openModel(for: url)
        let id = first.workspace.id
        #expect(library.reader(forWorkspace: id) === first)
        let version = library.readerVersion
        library.readerClosed(first)
        #expect(library.reader(forWorkspace: id) == nil)
        #expect(library.readerVersion > version)
        let second = try await library.openModel(for: url)
        #expect(library.reader(forWorkspace: id) === second)
        library.readerClosed(first)
        #expect(library.reader(forWorkspace: id) === second)
    }
}
