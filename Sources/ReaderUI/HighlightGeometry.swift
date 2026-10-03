import DocumentKit
import PDFKit

/// Calculates the line rectangles that a highlight covers. Segments on pages that do not exist give no rectangles.
enum HighlightGeometry {
    static func lineRects(for locator: PDFLocator, in document: PDFDocument) -> [(pageIndex: Int, rect: CGRect)] {
        locator.segments.flatMap { segment -> [(pageIndex: Int, rect: CGRect)] in
            guard segment.pageIndex >= 0, segment.pageIndex < document.pageCount,
                  let page = document.page(at: segment.pageIndex),
                  let selection = page.selection(for: segment.range) else { return [] }
            return selection.selectionsByLine()
                .map { (pageIndex: segment.pageIndex, rect: $0.bounds(for: page)) }
                .filter { !$0.rect.isEmpty }
        }
    }
}
