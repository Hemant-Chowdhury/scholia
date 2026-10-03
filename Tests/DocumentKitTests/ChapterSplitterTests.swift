import Testing
@testable import DocumentKit

struct ChapterSplitterTests {
    @Test func withoutOutlineUsesTwentyPageBlocks() {
        #expect(ChapterSplitter.chunks(outline: [], pageCount: 45) == [
            TextChunk(fileName: "01-pages-1-20.md", title: "Pages 1–20", pages: 0..<20),
            TextChunk(fileName: "02-pages-21-40.md", title: "Pages 21–40", pages: 20..<40),
            TextChunk(fileName: "03-pages-41-45.md", title: "Pages 41–45", pages: 40..<45),
        ])
    }

    @Test func topLevelEntriesMakeChaptersWithFrontMatter() {
        let outline = [
            OutlineEntry(title: "Introduction", level: 0, pageIndex: 2),
            OutlineEntry(title: "Background", level: 1, pageIndex: 5),
            OutlineEntry(title: "Agents", level: 0, pageIndex: 10),
        ]
        #expect(ChapterSplitter.chunks(outline: outline, pageCount: 30) == [
            TextChunk(fileName: "01-front-matter.md", title: "Front matter", pages: 0..<2),
            TextChunk(fileName: "02-introduction.md", title: "Introduction", pages: 2..<10),
            TextChunk(fileName: "03-agents.md", title: "Agents", pages: 10..<30),
        ])
    }

    @Test func entriesOnTheSamePageAreMerged() {
        let outline = [
            OutlineEntry(title: "Part I", level: 0, pageIndex: 0),
            OutlineEntry(title: "Chapter 1", level: 0, pageIndex: 0),
        ]
        #expect(ChapterSplitter.chunks(outline: outline, pageCount: 5) == [
            TextChunk(fileName: "01-part-i.md", title: "Part I", pages: 0..<5),
        ])
    }

    @Test func entriesOutsideThePagesAreIgnored() {
        let outline = [OutlineEntry(title: "Ghost", level: 0, pageIndex: 99)]
        #expect(ChapterSplitter.chunks(outline: outline, pageCount: 3) == [
            TextChunk(fileName: "01-pages-1-3.md", title: "Pages 1–3", pages: 0..<3),
        ])
    }

    @Test func noPagesGiveNoChunks() {
        #expect(ChapterSplitter.chunks(outline: [], pageCount: 0).isEmpty)
    }

    @Test func slugIsSafeForFileNames() {
        #expect(ChapterSplitter.slug("Chapter 3: Tools / Agents — Ünïcode!") == "chapter-3-tools-agents-unicode")
        #expect(ChapterSplitter.slug("!!!") == "section")
        let long = ChapterSplitter.slug(String(repeating: "word ", count: 30))
        #expect(long.count <= 50)
        #expect(!long.hasSuffix("-"))
    }
}
