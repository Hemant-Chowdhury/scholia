import DocumentKit
import Foundation

public struct IndexProgress: Equatable, Sendable {
    public let indexedPages: Int
    public let pageCount: Int

    public init(indexedPages: Int, pageCount: Int) {
        self.indexedPages = indexedPages
        self.pageCount = pageCount
    }

    public var isComplete: Bool { indexedPages >= pageCount }
}

/// Puts the document text into the full-text index and writes the `text/` files.
/// It continues from the last indexed page, so it is safe to run again after an interruption.
public enum DocumentIndexer {
    public static func run(
        workspace: OpenedWorkspace, pdfURL: URL, progress: @Sendable (IndexProgress) -> Void = { _ in }
    ) throws {
        let database = workspace.database
        guard let document = try database.document(id: workspace.document.id) else { return }
        if document.indexedPages >= document.pageCount && document.textExported {
            progress(IndexProgress(indexedPages: document.pageCount, pageCount: document.pageCount))
            return
        }
        let source = try PDFDocumentSource(url: pdfURL)
        for page in document.indexedPages..<max(document.indexedPages, document.pageCount) {
            try Task.checkCancellation()
            try database.storeParagraphs(source.paragraphs(onPage: page), page: page, documentID: document.id)
            progress(IndexProgress(indexedPages: page + 1, pageCount: document.pageCount))
        }
        try Task.checkCancellation()
        try exportText(source: source, database: database, documentID: document.id,
                       pageCount: document.pageCount, folder: workspace.textFolder)
        try database.setTextExported(documentID: document.id)
    }

    static func exportText(source: PDFDocumentSource, database: WorkspaceDatabase, documentID: String,
                           pageCount: Int, folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for old in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        where old.pathExtension == "md" {
            try FileManager.default.removeItem(at: old)
        }
        for chunk in ChapterSplitter.chunks(outline: source.outline, pageCount: pageCount) {
            let byPage = Dictionary(grouping: try database.paragraphs(documentID: documentID, pages: chunk.pages), by: \.pageIndex)
            var body = "# \(chunk.title)\n"
            for page in chunk.pages {
                guard let paragraphs = byPage[page], !paragraphs.isEmpty else { continue }
                body += "\n[p. \(page + 1)]\n\n" + paragraphs.map(\.text).joined(separator: "\n\n") + "\n"
            }
            try body.write(to: folder.appendingPathComponent(chunk.fileName), atomically: true, encoding: .utf8)
        }
    }
}
