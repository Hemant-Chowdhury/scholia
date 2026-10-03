import CoreGraphics

/// Finds text that repeats on each page and is not part of the content, such as running page numbers.
public enum PageFurniture {
    /// True for a one-line paragraph that holds only a page number (digits or roman numerals)
    /// in the top or bottom 10% of the page.
    public static func isPageNumber(_ lines: [TextLine], pageBounds: CGRect) -> Bool {
        guard lines.count == 1, let line = lines.first else { return false }
        let text = line.text.trimmingCharacters(in: .whitespaces).lowercased()
        let isNumber = text.allSatisfy(\.isNumber) || text.allSatisfy { "ivxlcdm".contains($0) }
        guard (1...6).contains(text.count), isNumber else { return false }
        let margin = pageBounds.height * 0.1
        return line.rect.midY < pageBounds.minY + margin || line.rect.midY > pageBounds.maxY - margin
    }

    /// True for a paragraph of one or two lines that is fully in the top or bottom 10% of the page.
    public static func isInEdgeBand(_ lines: [TextLine], pageBounds: CGRect) -> Bool {
        guard !lines.isEmpty, lines.count <= 2 else { return false }
        let margin = pageBounds.height * 0.1
        return lines.allSatisfy { $0.rect.midY < pageBounds.minY + margin || $0.rect.midY > pageBounds.maxY - margin }
    }

    /// The text that identifies a running header or footer: lowercase, with no digits, and with single spaces.
    public static func runningHeadKey(_ text: String) -> String {
        text.lowercased()
            .filter { !$0.isNumber }
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    /// True for an edge-band paragraph whose key is also in the edge band of a page near it.
    public static func isRunningHead(_ lines: [TextLine], pageBounds: CGRect, nearbyKeys: Set<String>) -> Bool {
        guard isInEdgeBand(lines, pageBounds: pageBounds) else { return false }
        let key = runningHeadKey(ParagraphGrouper.joinText(lines))
        return !key.isEmpty && nearbyKeys.contains(key)
    }
}
