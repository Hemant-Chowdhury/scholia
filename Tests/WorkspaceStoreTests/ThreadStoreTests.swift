import Foundation
import Testing
@testable import WorkspaceStore

struct ThreadStoreTests {
    func database() throws -> WorkspaceDatabase {
        let database = try WorkspaceDatabase.inMemory()
        try database.insertDocument(makeDocument())
        return database
    }

    func anchor(_ id: String, page: Int) -> AnchorRecord {
        AnchorRecord(id: id, documentID: "doc-1", kind: "pdf", locatorJSON: "{\"segments\":[]}", text: "selected \(id)",
                     structuralPath: "Chapter 1", firstPage: page, createdAt: Date(timeIntervalSince1970: 1000))
    }

    func thread(_ id: String, page: Int, anchorID: String?, updated: TimeInterval = 1000) -> ThreadRecord {
        ThreadRecord(id: id, documentID: "doc-1", anchorID: anchorID, title: "Thread \(id)", firstPage: page,
                     createdAt: Date(timeIntervalSince1970: 1000), updatedAt: Date(timeIntervalSince1970: updated),
                     agentID: "claude", modelID: "opus")
    }

    func message(_ id: String, thread: String, role: String, _ content: String, at seconds: TimeInterval,
                 status: String = "complete") -> MessageRecord {
        MessageRecord(id: id, threadID: thread, role: role, action: role == "user" ? "explain" : nil, content: content,
                      status: status, error: nil, createdAt: Date(timeIntervalSince1970: seconds))
    }

    @Test func threadWithAnchorIsSavedAndListedNewestFirst() throws {
        let database = try database()
        try database.createThread(thread("t1", page: 3, anchorID: "a1", updated: 1000), anchor: anchor("a1", page: 3))
        try database.createThread(thread("t2", page: 9, anchorID: "a2", updated: 2000), anchor: anchor("a2", page: 9))
        #expect(try database.threads(documentID: "doc-1").map(\.id) == ["t2", "t1"])
        #expect(try database.anchor(id: "a1")?.text == "selected a1")
    }

    @Test func threadsOnPagesAreFound() throws {
        let database = try database()
        try database.createThread(thread("t1", page: 3, anchorID: nil), anchor: nil)
        try database.createThread(thread("t2", page: 9, anchorID: nil), anchor: nil)
        #expect(try database.threads(documentID: "doc-1", pages: 2..<5).map(\.id) == ["t1"])
    }

    @Test func messagesKeepTheirOrderAndCanBeUpdated() throws {
        let database = try database()
        try database.createThread(thread("t1", page: 3, anchorID: nil), anchor: nil)
        try database.saveMessage(message("m1", thread: "t1", role: "user", "Explain this", at: 1001))
        try database.saveMessage(message("m2", thread: "t1", role: "assistant", "An agent", at: 1001, status: "streaming"))
        try database.saveMessage(message("m2", thread: "t1", role: "assistant", "An agent is a loop.", at: 1001))
        let messages = try database.messages(threadID: "t1")
        #expect(messages.map(\.id) == ["m1", "m2"])
        #expect(messages[1].content == "An agent is a loop.")
        #expect(messages[1].status == "complete")
        #expect(try database.thread(id: "t1")?.updatedAt ?? .distantPast > Date(timeIntervalSince1970: 1000))
    }

    @Test func relatedThreadsAreFoundByTheirWords() throws {
        let database = try database()
        try database.createThread(thread("t1", page: 3, anchorID: nil), anchor: nil)
        try database.saveMessage(message("m1", thread: "t1", role: "user", "What is tokenization?", at: 1001))
        try database.saveMessage(message("m2", thread: "t1", role: "assistant", "Tokenization splits text into tokens.", at: 1002))
        try database.createThread(thread("t2", page: 9, anchorID: nil), anchor: nil)
        try database.saveMessage(message("m3", thread: "t2", role: "user", "Explain reward models", at: 1003))
        #expect(try database.relatedThreads(to: "tokens and tokenizers", documentID: "doc-1", excluding: nil).map(\.id) == ["t1"])
        #expect(try database.relatedThreads(to: "tokens", documentID: "doc-1", excluding: "t1").isEmpty)
        #expect(try database.relatedThreads(to: "---", documentID: "doc-1", excluding: nil).isEmpty)
    }

    @Test func agentAndModelOfAThreadCanChange() throws {
        let database = try database()
        try database.createThread(thread("t1", page: 3, anchorID: nil), anchor: nil)
        try database.updateThreadAgent(threadID: "t1", agentID: "opencode", modelID: "big-pickle")
        #expect(try database.thread(id: "t1")?.agentID == "opencode")
        #expect(try database.thread(id: "t1")?.modelID == "big-pickle")
    }

    @Test func removingAHighlightKeepsAnAnchorThatAThreadUses() throws {
        let database = try database()
        let shared = anchor("a1", page: 3)
        try database.addHighlight(HighlightRecord(id: "h1", anchorID: "a1", color: "yellow", createdAt: Date()), anchor: shared)
        try database.createThread(thread("t1", page: 3, anchorID: "a1"), anchor: shared)
        try database.removeHighlight(id: "h1")
        #expect(try database.anchor(id: "a1") != nil)
    }
}
