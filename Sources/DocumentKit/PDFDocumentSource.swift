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
            return TextLine(text: text, rect: line.bounds(for: page), range: Self.characterRange(of: line, on: page))
        }
    }

    private static func characterRange(of selection: PDFSelection, on page: PDFPage) -> NSRange {
        let count = selection.numberOfTextRanges(on: page)
        guard count > 0 else { return NSRange(location: NSNotFound, length: 0) }
        return (1..<count).reduce(selection.range(at: 0, on: page)) { NSUnionRange($0, selection.range(at: $1, on: page)) }
    }
}

extension PDFDocumentSource: DocumentSource {
    /// Paragraphs in reading order, without running page numbers, headers and footers.
    public func paragraphs(onPage pageIndex: Int) -> [Paragraph] {
        guard pageIndex >= 0, pageIndex < pdf.pageCount, let page = pdf.page(at: pageIndex) else { return [] }
        let pageBounds = page.bounds(for: .cropBox)
        let groups = ParagraphGrouper.group(lines(onPage: pageIndex))
        // Nearby pages are read only when this page has text in its edge bands.
        let nearbyKeys = groups.contains { PageFurniture.isInEdgeBand($0, pageBounds: pageBounds) }
            ? [pageIndex - 2, pageIndex - 1, pageIndex + 1, pageIndex + 2].reduce(into: Set<String>()) {
                $0.formUnion(edgeBandKeys(onPage: $1))
            }
            : []
        return groups
            .filter {
                !PageFurniture.isPageNumber($0, pageBounds: pageBounds)
                    && !PageFurniture.isRunningHead($0, pageBounds: pageBounds, nearbyKeys: nearbyKeys)
            }
            .enumerated()
            .map { index, group in
                Paragraph(
                    pageIndex: pageIndex,
                    index: index,
                    text: ParagraphGrouper.joinText(group),
                    rect: group.reduce(CGRect.null) { $0.union($1.rect) },
                    textRange: ParagraphGrouper.textRange(of: group))
            }
    }

    private func edgeBandKeys(onPage pageIndex: Int) -> Set<String> {
        guard pageIndex >= 0, pageIndex < pdf.pageCount, let page = pdf.page(at: pageIndex) else { return [] }
        let pageBounds = page.bounds(for: .cropBox)
        return Set(ParagraphGrouper.group(lines(onPage: pageIndex))
            .filter { PageFurniture.isInEdgeBand($0, pageBounds: pageBounds) }
            .map { PageFurniture.runningHeadKey(ParagraphGrouper.joinText($0)) }
            .filter { !$0.isEmpty })
    }
}
