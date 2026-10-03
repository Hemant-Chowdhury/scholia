import GRDB

public struct DocumentRecord: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "document"
    public static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy { .convertFromSnakeCase }
    public static var databaseColumnEncodingStrategy: DatabaseColumnEncodingStrategy { .convertToSnakeCase }

    public var id: String
    public var kind: String
    public var contentHash: String
    public var lastPath: String
    public var title: String
    public var author: String?
    public var pageCount: Int
    public var lastPage: Int
    /// Pages 0..<indexedPages are in the full-text index.
    public var indexedPages: Int
    /// True when the `text/` files are written.
    public var textExported: Bool

    public init(id: String, kind: String, contentHash: String, lastPath: String, title: String, author: String?,
                pageCount: Int, lastPage: Int, indexedPages: Int, textExported: Bool) {
        self.id = id
        self.kind = kind
        self.contentHash = contentHash
        self.lastPath = lastPath
        self.title = title
        self.author = author
        self.pageCount = pageCount
        self.lastPage = lastPage
        self.indexedPages = indexedPages
        self.textExported = textExported
    }
}
