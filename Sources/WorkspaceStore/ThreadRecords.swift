import Foundation
import GRDB

/// A conversation with an agent about a part of a document.
public struct ThreadRecord: Codable, Equatable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "thread"

    public var id: String
    public var documentID: String
    public var anchorID: String?
    public var title: String
    public var firstPage: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var agentID: String?
    public var modelID: String?

    enum CodingKeys: String, CodingKey {
        case id, title
        case documentID = "document_id"
        case anchorID = "anchor_id"
        case firstPage = "first_page"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case agentID = "agent_id"
        case modelID = "model_id"
    }

    public init(id: String, documentID: String, anchorID: String?, title: String, firstPage: Int,
                createdAt: Date, updatedAt: Date, agentID: String?, modelID: String?) {
        self.id = id
        self.documentID = documentID
        self.anchorID = anchorID
        self.title = title
        self.firstPage = firstPage
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.agentID = agentID
        self.modelID = modelID
    }
}

public struct MessageRecord: Codable, Equatable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "message"

    public var id: String
    public var threadID: String
    /// "user" or "assistant".
    public var role: String
    /// For a user message: "explain", "simplify", "define", "ask" or "followup".
    public var action: String?
    public var content: String
    /// "streaming", "complete", "failed" or "cancelled".
    public var status: String
    public var error: String?
    public var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, role, action, content, status, error
        case threadID = "thread_id"
        case createdAt = "created_at"
    }

    public init(id: String, threadID: String, role: String, action: String?, content: String,
                status: String, error: String?, createdAt: Date) {
        self.id = id
        self.threadID = threadID
        self.role = role
        self.action = action
        self.content = content
        self.status = status
        self.error = error
        self.createdAt = createdAt
    }
}
