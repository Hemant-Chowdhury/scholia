import Foundation
import PDFKit

public final class PDFDocumentSource {
    public let url: URL
    public let pdf: PDFDocument

    public init(url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { throw DocumentError.notFound(url) }
        guard let pdf = PDFDocument(url: url) else { throw DocumentError.cannotOpen(url) }
        if pdf.isLocked { throw DocumentError.locked(url) }
        self.url = url
        self.pdf = pdf
    }

    public var kind: DocumentKind { .pdf }

    public var metadata: DocumentMetadata {
        let attributes = pdf.documentAttributes ?? [:]
        let title = (attributes[PDFDocumentAttribute.titleAttribute] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let author = (attributes[PDFDocumentAttribute.authorAttribute] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return DocumentMetadata(
            title: title?.isEmpty == false ? title! : url.deletingPathExtension().lastPathComponent,
            author: author?.isEmpty == false ? author : nil,
            pageCount: pdf.pageCount)
    }

    public var outline: [OutlineEntry] {
        guard let root = pdf.outlineRoot else { return [] }
        var entries: [OutlineEntry] = []
        func walk(_ node: PDFOutline, level: Int) {
            for childIndex in 0..<node.numberOfChildren {
                guard let child = node.child(at: childIndex) else { continue }
                let destination = child.destination ?? (child.action as? PDFActionGoTo)?.destination
                if let label = child.label, let page = destination?.page {
                    entries.append(OutlineEntry(title: label, level: level, pageIndex: pdf.index(for: page)))
                }
                walk(child, level: level + 1)
            }
        }
        walk(root, level: 0)
        return entries
    }

    public func lines(onPage pageIndex: Int) -> [TextLine] {
        guard pageIndex >= 0, pageIndex < pdf.pageCount,
              let page = pdf.page(at: pageIndex),
              let selection = page.selection(for: page.bounds(for: .mediaBox))
        else { return [] }
        return selection.selectionsByLine().compactMap { line in
            guard let text = line.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            return TextLine(text: text, rect: line.bounds(for: page))
        }
    }
}

extension PDFDocumentSource: DocumentSource {
    public func paragraphs(onPage pageIndex: Int) -> [Paragraph] {
        ParagraphGrouper.group(lines(onPage: pageIndex)).enumerated().map { index, group in
            Paragraph(
                pageIndex: pageIndex,
                index: index,
                text: ParagraphGrouper.joinText(group),
                rect: group.reduce(CGRect.null) { $0.union($1.rect) })
        }
    }
}
