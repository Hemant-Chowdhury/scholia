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
    public static func chunks(
        outline: [OutlineEntry], pageCount: Int, pagesPerChunk: Int = 20, maxPages: Int = 40
    ) -> [TextChunk] {
        guard pageCount > 0 else { return [] }
        var pieces: [(title: String, pages: Range<Int>)] = []
        let chapters = ranges(of: starts(outline, level: 0, in: 0..<pageCount), in: 0..<pageCount)
        if chapters.isEmpty {
            pieces = stride(from: 0, to: pageCount, by: pagesPerChunk).map { start in
                let end = min(start + pagesPerChunk, pageCount)
                return ("Pages \(start + 1)–\(end)", start..<end)
            }
        } else {
            let withFrontMatter = chapters[0].pages.lowerBound > 0
                ? [("Front matter", 0..<chapters[0].pages.lowerBound)] + chapters
                : chapters
            for chapter in withFrontMatter {
                pieces += split(chapter, outline: outline, pagesPerChunk: pagesPerChunk, maxPages: maxPages)
            }
        }
        return pieces.enumerated().map { number, piece in
            TextChunk(fileName: String(format: "%02d-%@.md", number + 1, slug(piece.title)),
                      title: piece.title, pages: piece.pages)
        }
    }

    /// Splits a chapter that is longer than `maxPages` at its level-1 sections, then into page blocks.
    private static func split(
        _ chapter: (title: String, pages: Range<Int>), outline: [OutlineEntry], pagesPerChunk: Int, maxPages: Int
    ) -> [(title: String, pages: Range<Int>)] {
        guard chapter.pages.count > maxPages else { return [chapter] }
        var sectionStarts = starts(outline, level: 1, in: chapter.pages)
        if let first = sectionStarts.first, first.page > chapter.pages.lowerBound {
            sectionStarts.insert((chapter.title, chapter.pages.lowerBound), at: 0)
        }
        let sections = sectionStarts.isEmpty ? [chapter] : ranges(of: sectionStarts, in: chapter.pages)
        return sections.flatMap { section -> [(title: String, pages: Range<Int>)] in
            guard section.pages.count > maxPages else { return [section] }
            return stride(from: section.pages.lowerBound, to: section.pages.upperBound, by: pagesPerChunk).map { start in
                let end = min(start + pagesPerChunk, section.pages.upperBound)
                return ("\(section.title), pages \(start + 1)–\(end)", start..<end)
            }
        }
    }

    /// Outline entries of one level inside `pages`, sorted by page, with one entry for each page.
    private static func starts(_ outline: [OutlineEntry], level: Int, in pages: Range<Int>) -> [(title: String, page: Int)] {
        var result: [(title: String, page: Int)] = []
        let entries = outline
            .filter { $0.level == level && pages.contains($0.pageIndex) }
            .enumerated()
            .sorted { ($0.element.pageIndex, $0.offset) < ($1.element.pageIndex, $1.offset) }
            .map(\.element)
        for entry in entries where result.last?.page != entry.pageIndex {
            result.append((entry.title, entry.pageIndex))
        }
        return result
    }

    private static func ranges(of starts: [(title: String, page: Int)], in pages: Range<Int>) -> [(title: String, pages: Range<Int>)] {
        starts.enumerated().map { index, start in
            let end = index + 1 < starts.count ? starts[index + 1].page : pages.upperBound
            return (start.title, start.page..<end)
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
