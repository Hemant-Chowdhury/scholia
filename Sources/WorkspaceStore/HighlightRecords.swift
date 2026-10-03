import Foundation
import GRDB

/// A saved location in a document. Highlights use anchors now; M3 threads will use them too.
public struct AnchorRecord: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "anchor"

    public var id: String
    public var documentID: String
    public var kind: String
    /// For a PDF: `PDFLocator` as JSON.
    public var locatorJSON: String
    public var text: String
    /// For example "Chapter 4 › 4.2 Tool use".
    public var structuralPath: String
    public var firstPage: Int
    public var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, kind, text
        case documentID = "document_id"
        case locatorJSON = "locator_json"
        case structuralPath = "structural_path"
        case firstPage = "first_page"
        case createdAt = "created_at"
    }

    public init(id: String, documentID: String, kind: String, locatorJSON: String, text: String,
                structuralPath: String, firstPage: Int, createdAt: Date) {
        self.id = id
        self.documentID = documentID
        self.kind = kind
        self.locatorJSON = locatorJSON
        self.text = text
        self.structuralPath = structuralPath
        self.firstPage = firstPage
        self.createdAt = createdAt
    }
}

public struct HighlightRecord: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "highlight"

    public var id: String
    public var anchorID: String
    public var color: String
    public var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, color
        case anchorID = "anchor_id"
        case createdAt = "created_at"
    }

    public init(id: String, anchorID: String, color: String, createdAt: Date) {
        self.id = id
        self.anchorID = anchorID
        self.color = color
        self.createdAt = createdAt
    }
}

public struct StoredHighlight: Equatable, Sendable {
    public let highlight: HighlightRecord
    public let anchor: AnchorRecord

    public init(highlight: HighlightRecord, anchor: AnchorRecord) {
        self.highlight = highlight
        self.anchor = anchor
    }
}
