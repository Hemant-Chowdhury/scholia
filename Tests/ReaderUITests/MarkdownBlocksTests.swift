import Foundation
import Testing
@testable import ReaderUI

struct MarkdownBlocksTests {
    @Test func parsesHeadingsListsCodeQuotesAndParagraphs() {
        let text = """
            # Summary
            An agent is a loop.
            It calls tools.

            - First point
            - Second point
            1. One
            2. Two

            > A quote

            ```swift
            let x = 1
            ```
            """
        #expect(MarkdownBlocks.parse(text) == [
            .heading(level: 1, text: "Summary"),
            .paragraph("An agent is a loop. It calls tools."),
            .bullet(marker: "•", text: "First point"),
            .bullet(marker: "•", text: "Second point"),
            .bullet(marker: "1.", text: "One"),
            .bullet(marker: "2.", text: "Two"),
            .quote("A quote"),
            .code("let x = 1"),
        ])
    }

    @Test func unfinishedCodeBlockWhileStreamingIsStillCode() {
        #expect(MarkdownBlocks.parse("```\nlet x") == [.code("let x")])
    }

    @Test func pageCitationsBecomeLinks() {
        #expect(MarkdownBlocks.linkingPages("See [p. 12] and [p. 3].") == "See [p. 12](reader-page://12) and [p. 3](reader-page://3).")
        #expect(MarkdownBlocks.pageNumber(in: URL(string: "reader-page://12")!) == 12)
        #expect(MarkdownBlocks.pageNumber(in: URL(string: "https://example.com")!) == nil)
    }
}
