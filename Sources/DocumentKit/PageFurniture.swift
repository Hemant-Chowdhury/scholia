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
}
