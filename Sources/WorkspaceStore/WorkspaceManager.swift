import DocumentKit
import Foundation
import Synchronization

public struct OpenedWorkspace: Sendable {
    public let id: String
    public let folder: URL
    public let database: WorkspaceDatabase
    public let document: DocumentRecord

    public var textFolder: URL { folder.appendingPathComponent("text", isDirectory: true) }
}

/// Opens the workspace of a document, and makes it when it does not exist.
public final class WorkspaceManager: Sendable {
    public let paths: AppPaths
    private let index: GlobalIndex
    /// One database instance for each workspace, so two windows never write through two connections.
    private let databases = Mutex<[String: WorkspaceDatabase]>([:])

    public init(paths: AppPaths) throws {
        self.paths = paths
        try FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
        index = try GlobalIndex(path: paths.globalIndexFile)
    }

    /// Reads the PDF before it writes anything, so a bad file makes no workspace.
    public func open(pdfAt url: URL) throws -> OpenedWorkspace {
        let source = try PDFDocumentSource(url: url)
        let hash = try ContentHash.sha256(of: url)
        let workspaceID = try index.workspaceID(contentHash: hash) ?? UUID().uuidString
        let folder = paths.workspaceFolder(id: workspaceID)
        try FileManager.default.createDirectory(
            at: folder.appendingPathComponent("text", isDirectory: true), withIntermediateDirectories: true)
        let database = try database(workspaceID: workspaceID, folder: folder)

        var document: DocumentRecord
        if let existing = try database.document(contentHash: hash) {
            document = existing
            if existing.lastPath != url.path {
                try database.updateLastPath(url.path, documentID: existing.id)
                document.lastPath = url.path
            }
        } else {
            let metadata = source.metadata
            document = DocumentRecord(
                id: UUID().uuidString, kind: DocumentKind.pdf.rawValue, contentHash: hash, lastPath: url.path,
                title: metadata.title, author: metadata.author, pageCount: metadata.pageCount,
                lastPage: 0, indexedPages: 0, textExported: false)
            try database.insertDocument(document)
        }
        try index.recordOpen(contentHash: hash, workspaceID: workspaceID, title: document.title, path: url.path)
        return OpenedWorkspace(id: workspaceID, folder: folder, database: database, document: document)
    }

    public func recents() throws -> [RecentDocument] {
        try index.recents()
    }

    private func database(workspaceID: String, folder: URL) throws -> WorkspaceDatabase {
        try databases.withLock { cache in
            if let cached = cache[workspaceID] { return cached }
            let database = try WorkspaceDatabase(path: folder.appendingPathComponent("workspace.sqlite"))
            cache[workspaceID] = database
            return database
        }
    }
}
