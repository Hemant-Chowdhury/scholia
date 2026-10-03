import Foundation
import PDFKit

/// A stable pointer to text in a PDF: character ranges on pages. The workspace finds a document
/// by its content hash, so the ranges stay correct for the life of the workspace.
public struct PDFLocator: Codable, Equatable, Sendable {
    public struct Segment: Codable, Equatable, Sendable {
        public let pageIndex: Int
        public let location: Int
        public let length: Int

        public init(pageIndex: Int, location: Int, length: Int) {
            self.pageIndex = pageIndex
            self.location = location
            self.length = length
        }

        public var range: NSRange { NSRange(location: location, length: length) }
    }

    public let segments: [Segment]

    public init(segments: [Segment]) {
        self.segments = segments.sorted { ($0.pageIndex, $0.location) < ($1.pageIndex, $1.location) }
    }

    public init?(selection: PDFSelection, in document: PDFDocument) {
        var segments: [Segment] = []
        for page in selection.pages {
            let pageIndex = document.index(for: page)
            for rangeIndex in 0..<selection.numberOfTextRanges(on: page) {
                let range = selection.range(at: rangeIndex, on: page)
                if range.location != NSNotFound && range.length > 0 {
                    segments.append(Segment(pageIndex: pageIndex, location: range.location, length: range.length))
                }
            }
        }
        guard !segments.isEmpty else { return nil }
        self.init(segments: segments)
    }

    public var firstPage: Int { segments.first?.pageIndex ?? 0 }

    /// Rebuilds the selection. Segments on pages that do not exist are skipped.
    public func selection(in document: PDFDocument) -> PDFSelection? {
        var result: PDFSelection?
        for segment in segments where segment.pageIndex >= 0 && segment.pageIndex < document.pageCount {
            guard let page = document.page(at: segment.pageIndex),
                  let part = page.selection(for: segment.range) else { continue }
            if let result { result.add(part) } else { result = part }
        }
        return result
    }

    /// Checks the locator against the text that was saved with it. If the text is different (for example,
    /// after a PDFKit update changed the character offsets), it searches for the text on the same page.
    /// Returns nil when the text cannot be found. Only one-page locators are searched again.
    public func resolved(expectedText: String, in document: PDFDocument) -> PDFLocator? {
        let words = expectedText.split(whereSeparator: { $0.isWhitespace })
        guard !words.isEmpty else { return nil }
        if let current = selection(in: document)?.string,
           current.split(whereSeparator: { $0.isWhitespace }) == words {
            return self
        }
        let pages = Set(segments.map(\.pageIndex))
        guard pages.count == 1, let pageIndex = pages.first, pageIndex >= 0, pageIndex < document.pageCount,
              let pageText = document.page(at: pageIndex)?.string else { return nil }
        let pattern = words.map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: "\\s+")
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: pageText, range: NSRange(location: 0, length: (pageText as NSString).length))
        else { return nil }
        return PDFLocator(segments: [Segment(pageIndex: pageIndex, location: match.range.location, length: match.range.length)])
    }

    public func overlaps(_ other: PDFLocator) -> Bool {
        segments.contains { mine in
            other.segments.contains { theirs in
                mine.pageIndex == theirs.pageIndex && NSIntersectionRange(mine.range, theirs.range).length > 0
            }
        }
    }

    public func json() throws -> String {
        String(decoding: try JSONEncoder().encode(self), as: UTF8.self)
    }

    public static func from(json: String) throws -> PDFLocator {
        try JSONDecoder().decode(PDFLocator.self, from: Data(json.utf8))
    }
}
