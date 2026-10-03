import Foundation
import Testing
@testable import WorkspaceStore

struct GlobalIndexTests {
    private func makeIndex() throws -> GlobalIndex {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return try GlobalIndex(path: folder.appendingPathComponent("index.sqlite"))
    }

    @Test func recordsAndFindsWorkspaceByHash() throws {
        let index = try makeIndex()
        try index.recordOpen(contentHash: "h1", workspaceID: "w1", title: "Book", path: "/a.pdf")
        #expect(try index.workspaceID(contentHash: "h1") == "w1")
        #expect(try index.workspaceID(contentHash: "h2") == nil)
    }

    @Test func recentsAreNewestFirstAndUpdatedOnReopen() throws {
        let index = try makeIndex()
        try index.recordOpen(contentHash: "h1", workspaceID: "w1", title: "One", path: "/1.pdf", at: Date(timeIntervalSince1970: 100))
        try index.recordOpen(contentHash: "h2", workspaceID: "w2", title: "Two", path: "/2.pdf", at: Date(timeIntervalSince1970: 200))
        try index.recordOpen(contentHash: "h1", workspaceID: "w1", title: "One", path: "/moved/1.pdf", at: Date(timeIntervalSince1970: 300))
        let recents = try index.recents()
        #expect(recents.map(\.contentHash) == ["h1", "h2"])
        #expect(recents[0].lastPath == "/moved/1.pdf")
    }
}
