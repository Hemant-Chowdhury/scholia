import CoreGraphics
import Testing
@testable import DocumentKit

/// Makes a line whose top edge is at `top`.
private func line(_ text: String, x: CGFloat = 72, top: CGFloat, width: CGFloat = 400, height: CGFloat = 12) -> TextLine {
    TextLine(text: text, rect: CGRect(x: x, y: top - height, width: width, height: height))
}

struct ParagraphGrouperTests {
    private func texts(_ groups: [[TextLine]]) -> [[String]] { groups.map { $0.map(\.text) } }

    @Test func evenlySpacedLinesAreOneParagraph() {
        let lines = [line("a", top: 700), line("b", top: 686), line("c", top: 672)]
        #expect(texts(ParagraphGrouper.group(lines)) == [["a", "b", "c"]])
    }

    @Test func indentStartsParagraph() {
        let lines = [line("a", top: 700), line("b", top: 686), line("c", x: 90, top: 672), line("d", top: 658)]
        #expect(texts(ParagraphGrouper.group(lines)) == [["a", "b"], ["c", "d"]])
    }

    @Test func verticalSpaceStartsParagraph() {
        let lines = [line("a", top: 700), line("b", top: 686), line("c", top: 650)]
        #expect(texts(ParagraphGrouper.group(lines)) == [["a", "b"], ["c"]])
    }

    @Test func fontSizeChangeStartsParagraph() {
        let lines = [line("Heading", top: 700, height: 18), line("body", top: 680), line("more", top: 666)]
        #expect(texts(ParagraphGrouper.group(lines)) == [["Heading"], ["body", "more"]])
    }

    @Test func jumpToNextColumnStartsParagraph() {
        let lines = [line("left1", top: 700, width: 200), line("left2", top: 686, width: 200),
                     line("right1", x: 320, top: 700, width: 200)]
        #expect(texts(ParagraphGrouper.group(lines)) == [["left1", "left2"], ["right1"]])
    }

    @Test func shortLineEndingASentenceStartsParagraph() {
        let lines = [line("a long line", top: 700), line("end.", top: 686, width: 150), line("next", top: 672)]
        #expect(texts(ParagraphGrouper.group(lines)) == [["a long line", "end."], ["next"]])
    }

    @Test func shortLineWithoutSentenceEndContinues() {
        let lines = [line("a long line", top: 700), line("short", top: 686, width: 150), line("next", top: 672)]
        #expect(texts(ParagraphGrouper.group(lines)) == [["a long line", "short", "next"]])
    }

    @Test func noLinesGiveNoParagraphs() {
        #expect(ParagraphGrouper.group([]).isEmpty)
    }

    @Test func joinTextJoinsLinesAndRemovesSoftHyphen() {
        let lines = [line("The agent calls a tool and com-", top: 700), line("putes the result.", top: 686)]
        #expect(ParagraphGrouper.joinText(lines) == "The agent calls a tool and computes the result.")
    }

    @Test func joinTextKeepsHyphenBeforeCapital() {
        let lines = [line("a Self-", top: 700), line("Ask prompt", top: 686)]
        #expect(ParagraphGrouper.joinText(lines) == "a Self-Ask prompt")
    }
}
