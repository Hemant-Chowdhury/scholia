import CoreGraphics
import Foundation

/// Groups text lines (in reading order) into paragraphs with layout rules. The rules are not exact;
/// manual selection is always available to the reader.
public enum ParagraphGrouper {
    public static func group(_ lines: [TextLine]) -> [[TextLine]] {
        guard let first = lines.first else { return [] }
        let lineHeight = medianHeight(of: lines)
        var groups: [[TextLine]] = [[first]]
        var groupMaxX = first.rect.maxX
        for (previous, line) in zip(lines, lines.dropFirst()) {
            if startsParagraph(line, after: previous, groupMaxX: groupMaxX, lineHeight: lineHeight) {
                groups.append([line])
                groupMaxX = line.rect.maxX
            } else {
                groups[groups.count - 1].append(line)
                groupMaxX = max(groupMaxX, line.rect.maxX)
            }
        }
        return groups
    }

    public static func joinText(_ lines: [TextLine]) -> String {
        var result = ""
        for line in lines {
            if result.isEmpty {
                result = line.text
            } else if result.hasSuffix("-") {
                // A soft hyphen before a lowercase letter splits one word; otherwise the hyphen is part of the text.
                if line.text.first?.isLowercase == true { result.removeLast() }
                result += line.text
            } else {
                result += " " + line.text
            }
        }
        return result
    }

    /// The union of the line ranges, or a range with location `NSNotFound` when a line has no range.
    public static func textRange(of lines: [TextLine]) -> NSRange {
        guard let first = lines.first, lines.allSatisfy({ $0.range.location != NSNotFound }) else {
            return NSRange(location: NSNotFound, length: 0)
        }
        return lines.dropFirst().reduce(first.range) { NSUnionRange($0, $1.range) }
    }

    static func startsParagraph(_ line: TextLine, after previous: TextLine, groupMaxX: CGFloat, lineHeight: CGFloat) -> Bool {
        let gap = previous.rect.minY - line.rect.maxY
        if gap < -lineHeight { return true }
        if gap > lineHeight * 0.8 { return true }
        if abs(line.rect.height - previous.rect.height) > lineHeight * 0.3 { return true }
        if line.rect.minX - previous.rect.minX > lineHeight * 0.8 { return true }
        let endsSentence = previous.text.last.map { ".:?!".contains($0) } ?? false
        if endsSentence && previous.rect.maxX < groupMaxX - lineHeight * 3 { return true }
        return false
    }

    private static func medianHeight(of lines: [TextLine]) -> CGFloat {
        let heights = lines.map(\.rect.height).sorted()
        return max(heights[heights.count / 2], 1)
    }
}
