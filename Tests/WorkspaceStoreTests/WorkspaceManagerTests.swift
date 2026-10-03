import Foundation
import Testing
import DocumentKit
import TestSupport
@testable import WorkspaceStore

struct WorkspaceManagerTests {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    private func makeManager() throws -> WorkspaceManager {
        try WorkspaceManager(paths: AppPaths(root: root))
    }

    private func samplePDF() throws -> URL {
        try FixturePDF.make(pages: [[FixtureLine("Hello", y: 700)], [FixtureLine("World", y: 700)]], title: "Sample")
    }

    @Test func firstOpenMakesWorkspaceFolderDatabaseAndRecord() throws {
        let manager = try makeManager()
        let workspace = try manager.open(pdfAt: samplePDF())
        #expect(FileManager.default.fileExists(atPath: workspace.folder.appendingPathComponent("workspace.sqlite").path))
        #expect(FileManager.default.fileExists(atPath: workspace.textFolder.path))
        #expect(workspace.document.title == "Sample")
        #expect(workspace.document.pageCount == 2)
        #expect(workspace.document.kind == DocumentKind.pdf.rawValue)
        #expect(try manager.recents().map(\.workspaceID) == [workspace.id])
    }

    @Test func reopenGivesSameWorkspaceAndDatabase() throws {
        let manager = try makeManager()
        let url = try samplePDF()
        let first = try manager.open(pdfAt: url)
        let second = try manager.open(pdfAt: url)
        #expect(first.id == second.id)
        #expect(first.document.id == second.document.id)
        #expect(first.database === second.database)
    }

    @Test func movedCopyOpensSameWorkspaceAndUpdatesPath() throws {
        let manager = try makeManager()
        let url = try samplePDF()
        let first = try manager.open(pdfAt: url)
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        try FileManager.default.copyItem(at: url, to: copy)
        let second = try manager.open(pdfAt: copy)
        #expect(second.id == first.id)
        #expect(second.document.lastPath == copy.path)
        #expect(try second.database.document(id: second.document.id)?.lastPath == copy.path)
    }

    @Test func newManagerFindsExistingWorkspace() throws {
        let url = try samplePDF()
        let first = try makeManager().open(pdfAt: url)
        let second = try makeManager().open(pdfAt: url)
        #expect(first.id == second.id)
    }

    @Test func corruptFileThrowsAndMakesNoWorkspace() throws {
        let manager = try makeManager()
        let url = try FixturePDF.makeCorrupt()
        #expect(throws: DocumentError.cannotOpen(url)) { try manager.open(pdfAt: url) }
        let workspaces = root.appendingPathComponent("workspaces")
        #expect((try? FileManager.default.contentsOfDirectory(atPath: workspaces.path))?.isEmpty ?? true)
    }

    @Test func lockedFileThrowsLocked() throws {
        let url = try FixturePDF.makeLocked()
        #expect(throws: DocumentError.locked(url)) { try makeManager().open(pdfAt: url) }
    }
}
