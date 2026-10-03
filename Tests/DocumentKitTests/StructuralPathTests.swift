import Testing
@testable import DocumentKit

struct StructuralPathTests {
    let outline = [
        OutlineEntry(title: "Chapter 1", level: 0, pageIndex: 0),
        OutlineEntry(title: "1.1 Basics", level: 1, pageIndex: 2),
        OutlineEntry(title: "1.2 Tools", level: 1, pageIndex: 5),
        OutlineEntry(title: "Chapter 2", level: 0, pageIndex: 9),
        OutlineEntry(title: "2.1 Loops", level: 1, pageIndex: 10),
    ]

    @Test func pathHasChapterAndSection() {
        #expect(StructuralPath.path(forPage: 6, in: outline) == ["Chapter 1", "1.2 Tools"])
    }

    @Test func newChapterDropsOldSection() {
        #expect(StructuralPath.path(forPage: 9, in: outline) == ["Chapter 2"])
    }

    @Test func firstPage() {
        #expect(StructuralPath.path(forPage: 0, in: outline) == ["Chapter 1"])
    }

    @Test func emptyOutlineGivesEmptyPath() {
        #expect(StructuralPath.path(forPage: 3, in: []) == [])
    }
}
