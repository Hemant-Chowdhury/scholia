import Foundation

/// One text file in the workspace `text/` folder.
public struct TextChunk: Equatable, Sendable {
    public let fileName: String
    public let title: String
    public let pages: Range<Int>

    public init(fileName: String, title: String, pages: Range<Int>) {
        self.fileName = fileName
        self.title = title
        self.pages = pages
    }
}

/// Splits a document into chapter-sized text files, so an agent can read one chapter at a time.
public enum ChapterSplitter {
    public static func chunks(outline: [OutlineEntry], pageCount: Int, pagesPerChunk: Int = 20) -> [TextChunk] {
        guard pageCount > 0 else { return [] }
        var starts: [(title: String, page: Int)] = []
        let topLevel = outline
            .filter { $0.level == 0 && $0.pageIndex >= 0 && $0.pageIndex < pageCount }
            .enumerated()
            .sorted { ($0.element.pageIndex, $0.offset) < ($1.element.pageIndex, $1.offset) }
            .map(\.element)
        for entry in topLevel where starts.last?.page != entry.pageIndex {
            starts.append((entry.title, entry.pageIndex))
        }
        if starts.isEmpty {
            starts = stride(from: 0, to: pageCount, by: pagesPerChunk).map { start in
                ("Pages \(start + 1)–\(min(start + pagesPerChunk, pageCount))", start)
            }
        } else if let first = starts.first, first.page > 0 {
            starts.insert(("Front matter", 0), at: 0)
        }
        return starts.enumerated().map { number, start in
            let end = number + 1 < starts.count ? starts[number + 1].page : pageCount
            let fileName = String(format: "%02d-%@.md", number + 1, slug(start.title))
            return TextChunk(fileName: fileName, title: start.title, pages: start.page..<end)
        }
    }

    public static func slug(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        var result = ""
        for scalar in folded.lowercased().unicodeScalars {
            if scalar.isASCII && CharacterSet.alphanumerics.contains(scalar) {
                result.unicodeScalars.append(scalar)
            } else if !result.isEmpty && !result.hasSuffix("-") {
                result.append("-")
            }
        }
        result = String(result.prefix(50))
        while result.hasSuffix("-") { result.removeLast() }
        return result.isEmpty ? "section" : result
    }
}
