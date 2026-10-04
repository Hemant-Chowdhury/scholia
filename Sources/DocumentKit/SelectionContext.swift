import Foundation

/// What the reader gives to the agent about a selection: the text, its location, and the paragraphs around it.
public struct SelectionContext: Sendable, Equatable {
    public let text: String
    /// Page index (from 0) of the start of the selection.
    public let pageIndex: Int
    public let structuralPath: [String]
    public let before: [String]
    public let after: [String]

    public init(text: String, pageIndex: Int, structuralPath: [String], before: [String], after: [String]) {
        self.text = text
        self.pageIndex = pageIndex
        self.structuralPath = structuralPath
        self.before = before
        self.after = after
    }

    /// Reads up to two paragraphs before and one paragraph after the selection, also across a page break.
    public static func make(locator: PDFLocator, selectedText: String, source: PDFDocumentSource,
                            outline: [OutlineEntry], beforeCount: Int = 2, afterCount: Int = 1) -> SelectionContext {
        let firstPage = locator.firstPage
        let lastPage = locator.segments.last?.pageIndex ?? firstPage
        let firstStart = locator.segments.first?.location ?? 0
        let lastEnd = locator.segments.last.map { $0.location + $0.length } ?? 0

        var before: [String] = []
        let firstParagraphs = source.paragraphs(onPage: firstPage)
        before = firstParagraphs.filter { $0.textRange.location != NSNotFound && $0.textRange.location + $0.textRange.length <= firstStart }
            .suffix(beforeCount).map(\.text)
        if before.count < beforeCount, firstPage > 0 {
            before = source.paragraphs(onPage: firstPage - 1).suffix(beforeCount - before.count).map(\.text) + before
        }

        var after = source.paragraphs(onPage: lastPage)
            .filter { $0.textRange.location != NSNotFound && $0.textRange.location >= lastEnd }
            .prefix(afterCount).map(\.text)
        if after.count < afterCount, lastPage + 1 < source.pdf.pageCount {
            after += source.paragraphs(onPage: lastPage + 1).prefix(afterCount - after.count).map(\.text)
        }

        return SelectionContext(text: TextCleaner.clean(selectedText), pageIndex: firstPage,
                                structuralPath: StructuralPath.path(forPage: firstPage, in: outline),
                                before: before, after: Array(after))
    }

}

public enum TextCleaner {
    /// Joins the lines of selected PDF text: a soft hyphen before a lowercase letter is removed,
    /// and all whitespace becomes single spaces.
    public static func clean(_ text: String) -> String {
        var result = ""
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        for line in lines {
            if result.hasSuffix("-"), line.first?.isLowercase == true {
                result.removeLast()
                result += line
            } else {
                result += result.isEmpty ? line : " " + line
            }
        }
        return result.split(whereSeparator: { $0 == " " }).joined(separator: " ")
    }
}
