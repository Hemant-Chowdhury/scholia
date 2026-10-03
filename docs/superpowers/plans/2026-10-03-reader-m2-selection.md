# Reader M2 (Selection) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The reader can select a full paragraph with Option-click, add the next paragraph with a second Option-click, and keep highlights that are saved as anchors and come back when the document opens again.

**Architecture:** `DocumentKit` gets character ranges for lines and paragraphs, a page-number filter, and `PDFLocator` (a stable, serializable pointer to text in a PDF). `WorkspaceStore` gets the `anchor` and `highlight` tables. `ReaderModel` gets the selection logic and the highlight actions. The views get a `PDFView` subclass for Option-click and the `H` key, a small selection bar above the selection, highlight annotations, and a Highlights list in the sidebar.

**Tech Stack:** Swift 6.1, SwiftUI, PDFKit, GRDB.swift 7, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-03-reader-design.md`. This plan implements milestone **M2** (spec Section 11), and spec Sections 4.1, 4.2 (Highlight action), 3.1 (Anchor) and 7 (`anchor`, `highlight` tables).

## Global Constraints

- Minimum platform: macOS 15. Swift tools version 6.0. Swift 6 language mode.
- Only one third-party dependency: GRDB.swift.
- No App Sandbox. No API keys. No telemetry.
- Tests use temporary folders and never write to `~/Library/Application Support/Reader/`.
- UI modules only show data and send user actions. Logic goes in models and lower modules.
- Test framework: Swift Testing. Run all tests with `swift test` from the repository root.
- Documentation and user-visible text use ASD-STE100 Simplified Technical English.
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.

## Notes on the spec and on M1

- **Selection menu.** Spec 4.2 lists Explain, Simplify, Define, Ask and Highlight. M2 has no agents, so the selection bar shows only **Highlight** and **Remove highlight**. M3 adds the LLM actions to the same bar.
- **Anchor rectangles.** Spec 3.1 says that a PDF anchor has a page, a character range and rectangles. The document file never changes (the workspace is found by its content hash), so the app stores only page and character ranges, and calculates rectangles from them when it draws.
- **Option-click again.** Spec 4.1 says: "Option-click again to add the next paragraph." In this plan, an Option-click inside the current paragraph selection adds the next paragraph. An Option-click on a different paragraph selects only that paragraph.
- **Deferred from M1 — page numbers.** Running page numbers became one-line paragraphs. Task 1 removes them.
- **Deferred from M1 — missing spaces.** This is not in M2. A probe on the real book showed that PDFKit reports zero-width gaps between all characters on the bad lines, so character positions cannot recover the spaces. A fix needs a content-stream parser or word segmentation. This is a known limitation.
- **Deferred from M1 — hyphen at a line break.** This is not in M2. PDFKit gives no signal that separates a soft hyphen from a real one, and the system word list does not contain inflected words. The current rule (remove the hyphen before a lowercase letter) stays.

## Review Focus

1. **A paragraph that continues on the next page.** Option-click again must add the first paragraph of the next page. A highlight of that selection must have two segments and must show on both pages. (Task 4 and Task 5 tests)
2. **Option-click on a point with no text** (margin, image, empty page). The app must not change the selection, and normal PDFView behavior must continue. (Task 4 test)
3. **Highlight the same text two times.** The app must not make a duplicate highlight. (Task 5 test)
4. **Close and open the document again.** Highlights must come back at the same text. (Task 5 test)
5. **A damaged locator in the database** (bad JSON or a page that does not exist). The app must skip it and must not stop. (Task 2 and Task 5 tests)

## File Structure

```
Sources/DocumentKit/
  DocumentModels.swift        # MODIFY: TextLine.range, Paragraph.textRange
  PDFDocumentSource.swift     # MODIFY: line ranges, page-number filter
  PageFurniture.swift         # NEW: page-number detection
  ParagraphGrouper.swift      # MODIFY: textRange(of:)
  PDFLocator.swift            # NEW: serializable pointer to PDF text
Sources/WorkspaceStore/
  WorkspaceDatabase.swift     # MODIFY: migration v2
  HighlightRecords.swift      # NEW: AnchorRecord, HighlightRecord, StoredHighlight
  WorkspaceDatabase+Highlights.swift  # NEW: add, list, remove
Sources/ReaderUI/
  ReaderModel.swift           # MODIFY: selection and highlights
  HighlightGeometry.swift     # NEW: line rectangles for a locator
  ReaderPDFView.swift         # NEW: Option-click and H key
  SelectionBar.swift          # NEW: bar above the selection
  PDFKitView.swift            # MODIFY: selection sync, annotations, bar
  ReaderView.swift            # MODIFY: Highlights section
```

---

### Task 1: Character ranges and page-number filter

**Files:**
- Modify: `Sources/DocumentKit/DocumentModels.swift`, `Sources/DocumentKit/ParagraphGrouper.swift`, `Sources/DocumentKit/PDFDocumentSource.swift`
- Create: `Sources/DocumentKit/PageFurniture.swift`
- Test: `Tests/DocumentKitTests/TextRangeTests.swift`, `Tests/DocumentKitTests/PageFurnitureTests.swift`

**Interfaces:**
- Produces:
  - `TextLine.range: NSRange` and `init(text:rect:range: NSRange = NSRange(location: NSNotFound, length: 0))`
  - `Paragraph.textRange: NSRange` and `init(pageIndex:index:text:rect:textRange: NSRange = NSRange(location: NSNotFound, length: 0))`
  - `ParagraphGrouper.textRange(of lines: [TextLine]) -> NSRange`
  - `PageFurniture.isPageNumber(_ lines: [TextLine], pageBounds: CGRect) -> Bool`
  - `PDFDocumentSource.paragraphs(onPage:)` now leaves out page numbers and fills `textRange`.

- [ ] **Step 1: Write the failing tests**

`Tests/DocumentKitTests/TextRangeTests.swift`:

```swift
import Foundation
import Testing
import TestSupport
@testable import DocumentKit

func collapsed(_ text: String?) -> String {
    (text ?? "").split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}

struct TextRangeTests {
    @Test func linesHaveCharacterRangesInThePageText() throws {
        let source = try PDFDocumentSource(url: FixturePDF.make(pages: [
            FixturePDF.paragraph(["First line here", "Second line here"], top: 700),
        ]))
        let pageText = try #require(source.pdf.page(at: 0)?.string) as NSString
        for line in source.lines(onPage: 0) {
            #expect(line.range.location != NSNotFound)
            #expect(collapsed(pageText.substring(with: line.range)) == line.text)
        }
    }

    @Test func paragraphRangeCoversAllItsLines() throws {
        var page = FixturePDF.paragraph(["An agent is a loop that", "calls a model and tools."], top: 700, firstIndent: 18)
        page += FixturePDF.paragraph(["The loop stops when the", "task is complete."], top: 672, firstIndent: 18)
        let source = try PDFDocumentSource(url: FixturePDF.make(pages: [page]))
        let pageText = try #require(source.pdf.page(at: 0)?.string) as NSString
        let paragraphs = source.paragraphs(onPage: 0)
        #expect(paragraphs.count == 2)
        for paragraph in paragraphs {
            #expect(collapsed(pageText.substring(with: paragraph.textRange)) == paragraph.text)
        }
    }

    @Test func textRangeIsUnknownWhenALineHasNoRange() {
        let lines = [
            TextLine(text: "a", rect: .zero, range: NSRange(location: 0, length: 1)),
            TextLine(text: "b", rect: .zero),
        ]
        #expect(ParagraphGrouper.textRange(of: lines).location == NSNotFound)
    }

    @Test func outOfRangePageHasNoParagraphs() throws {
        let source = try PDFDocumentSource(url: FixturePDF.make(pages: [[FixtureLine("One", y: 700)]]))
        #expect(source.paragraphs(onPage: 3).isEmpty)
        #expect(source.paragraphs(onPage: -1).isEmpty)
    }
}
```

`Tests/DocumentKitTests/PageFurnitureTests.swift`:

```swift
import CoreGraphics
import Testing
import TestSupport
@testable import DocumentKit

struct PageFurnitureTests {
    let page = CGRect(x: 0, y: 0, width: 612, height: 792)

    private func line(_ text: String, y: CGFloat) -> TextLine {
        TextLine(text: text, rect: CGRect(x: 300, y: y, width: 12, height: 10))
    }

    @Test func numberAtBottomIsPageNumber() {
        #expect(PageFurniture.isPageNumber([line("26", y: 30)], pageBounds: page))
    }

    @Test func romanNumberAtTopIsPageNumber() {
        #expect(PageFurniture.isPageNumber([line("xiv", y: 760)], pageBounds: page))
    }

    @Test func numberInTheMiddleIsText() {
        #expect(!PageFurniture.isPageNumber([line("26", y: 400)], pageBounds: page))
    }

    @Test func wordsAtBottomAreText() {
        #expect(!PageFurniture.isPageNumber([line("Chapter 2", y: 30)], pageBounds: page))
    }

    @Test func twoLinesAreNeverAPageNumber() {
        #expect(!PageFurniture.isPageNumber([line("26", y: 30), line("27", y: 16)], pageBounds: page))
    }

    @Test func pdfParagraphsLeaveOutTheRunningPageNumber() throws {
        var lines = FixturePDF.paragraph(["Body text of the page."], top: 700)
        lines.append(FixtureLine("26", x: 300, y: 30))
        let source = try PDFDocumentSource(url: FixturePDF.make(pages: [lines]))
        #expect(source.paragraphs(onPage: 0).map(\.text) == ["Body text of the page."])
    }
}
```

- [ ] **Step 2: Run the tests and make sure that they fail**

Run: `swift test --filter "TextRangeTests|PageFurnitureTests"`
Expected: the build fails with `extra argument 'range' in call` or `cannot find 'PageFurniture' in scope`.

- [ ] **Step 3: Write the implementation**

In `Sources/DocumentKit/DocumentModels.swift`, replace the `TextLine` and `Paragraph` structs with:

```swift
/// One line of text on a page. `rect` is in page coordinates, with the origin at the bottom left.
public struct TextLine: Equatable, Sendable {
    public let text: String
    public let rect: CGRect
    /// Character range of the line in the page text. The location is `NSNotFound` when it is not known.
    public let range: NSRange

    public init(text: String, rect: CGRect, range: NSRange = NSRange(location: NSNotFound, length: 0)) {
        self.text = text
        self.rect = rect
        self.range = range
    }
}

public struct Paragraph: Equatable, Sendable {
    public let pageIndex: Int
    /// Position of the paragraph on its page, from 0.
    public let index: Int
    public let text: String
    public let rect: CGRect
    /// Character range of the paragraph in the page text. The location is `NSNotFound` when it is not known.
    public let textRange: NSRange

    public init(pageIndex: Int, index: Int, text: String, rect: CGRect,
                textRange: NSRange = NSRange(location: NSNotFound, length: 0)) {
        self.pageIndex = pageIndex
        self.index = index
        self.text = text
        self.rect = rect
        self.textRange = textRange
    }
}
```

`Sources/DocumentKit/PageFurniture.swift`:

```swift
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
```

Add to `Sources/DocumentKit/ParagraphGrouper.swift`, inside `enum ParagraphGrouper`, after `joinText`:

```swift
    /// The union of the line ranges, or a range with location `NSNotFound` when a line has no range.
    public static func textRange(of lines: [TextLine]) -> NSRange {
        guard let first = lines.first, lines.allSatisfy({ $0.range.location != NSNotFound }) else {
            return NSRange(location: NSNotFound, length: 0)
        }
        return lines.dropFirst().reduce(first.range) { NSUnionRange($0, $1.range) }
    }
```

Also add `import Foundation` at the top of `ParagraphGrouper.swift` (for `NSRange` and `NSUnionRange`).

In `Sources/DocumentKit/PDFDocumentSource.swift`, replace `lines(onPage:)` and the `DocumentSource` extension with:

```swift
    public func lines(onPage pageIndex: Int) -> [TextLine] {
        guard pageIndex >= 0, pageIndex < pdf.pageCount,
              let page = pdf.page(at: pageIndex),
              let selection = page.selection(for: page.bounds(for: .mediaBox))
        else { return [] }
        return selection.selectionsByLine().compactMap { line in
            guard let text = line.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            return TextLine(text: text, rect: line.bounds(for: page), range: Self.characterRange(of: line, on: page))
        }
    }

    private static func characterRange(of selection: PDFSelection, on page: PDFPage) -> NSRange {
        let count = selection.numberOfTextRanges(on: page)
        guard count > 0 else { return NSRange(location: NSNotFound, length: 0) }
        return (1..<count).reduce(selection.range(at: 0, on: page)) { NSUnionRange($0, selection.range(at: $1, on: page)) }
    }
}

extension PDFDocumentSource: DocumentSource {
    public func paragraphs(onPage pageIndex: Int) -> [Paragraph] {
        guard pageIndex >= 0, pageIndex < pdf.pageCount, let page = pdf.page(at: pageIndex) else { return [] }
        let pageBounds = page.bounds(for: .mediaBox)
        return ParagraphGrouper.group(lines(onPage: pageIndex))
            .filter { !PageFurniture.isPageNumber($0, pageBounds: pageBounds) }
            .enumerated()
            .map { index, group in
                Paragraph(
                    pageIndex: pageIndex,
                    index: index,
                    text: ParagraphGrouper.joinText(group),
                    rect: group.reduce(CGRect.null) { $0.union($1.rect) },
                    textRange: ParagraphGrouper.textRange(of: group))
            }
    }
}
```

The closing `}` of the class moves: `characterRange` is the last member of `PDFDocumentSource`.

- [ ] **Step 4: Run the tests and make sure that they pass**

Run: `swift test --filter "TextRangeTests|PageFurnitureTests"`
Expected: 10 tests pass.

- [ ] **Step 5: Run all tests**

Run: `swift test`
Expected: all tests pass. The M1 paragraph and indexer tests still pass.

- [ ] **Step 6: Commit**

```bash
git add Sources Tests
git commit -m "feat: character ranges for lines and paragraphs, skip running page numbers"
```

---

### Task 2: PDFLocator

**Files:**
- Create: `Sources/DocumentKit/PDFLocator.swift`
- Test: `Tests/DocumentKitTests/PDFLocatorTests.swift`

**Interfaces:**
- Consumes: `Paragraph.textRange` (Task 1).
- Produces:
  - `public struct PDFLocator: Codable, Equatable, Sendable` with `struct Segment: Codable, Equatable, Sendable { pageIndex: Int; location: Int; length: Int; init(pageIndex:location:length:); var range: NSRange }`, `let segments: [Segment]`, `init(segments:)`, `init?(selection: PDFSelection, in: PDFDocument)`, `var firstPage: Int`, `func selection(in: PDFDocument) -> PDFSelection?`, `func overlaps(_: PDFLocator) -> Bool`, `func json() throws -> String`, `static func from(json: String) throws -> PDFLocator`
  - The segments are always sorted by page, then by location.

- [ ] **Step 1: Write the failing tests**

`Tests/DocumentKitTests/PDFLocatorTests.swift`:

```swift
import Foundation
import PDFKit
import Testing
import TestSupport
@testable import DocumentKit

struct PDFLocatorTests {
    private func twoPageSource() throws -> PDFDocumentSource {
        try PDFDocumentSource(url: FixturePDF.make(pages: [
            FixturePDF.paragraph(["Agents call tools in a loop."], top: 700),
            FixturePDF.paragraph(["Planning needs memory."], top: 700),
        ]))
    }

    @Test func roundTripFromSelectionKeepsTheText() throws {
        let source = try twoPageSource()
        let range = try #require(source.paragraphs(onPage: 0).first?.textRange)
        let selection = try #require(source.pdf.page(at: 0)?.selection(for: range))
        let locator = try #require(PDFLocator(selection: selection, in: source.pdf))
        #expect(locator.segments == [PDFLocator.Segment(pageIndex: 0, location: range.location, length: range.length)])
        #expect(collapsed(locator.selection(in: source.pdf)?.string) == "Agents call tools in a loop.")
    }

    @Test func selectionOverTwoPagesHasTwoSortedSegments() throws {
        let source = try twoPageSource()
        let second = try #require(source.paragraphs(onPage: 1).first)
        let first = try #require(source.paragraphs(onPage: 0).first)
        let locator = PDFLocator(segments: [
            PDFLocator.Segment(pageIndex: 1, location: second.textRange.location, length: second.textRange.length),
            PDFLocator.Segment(pageIndex: 0, location: first.textRange.location, length: first.textRange.length),
        ])
        #expect(locator.segments.map(\.pageIndex) == [0, 1])
        #expect(locator.firstPage == 0)
        let roundTrip = try #require(PDFLocator(selection: try #require(locator.selection(in: source.pdf)), in: source.pdf))
        #expect(roundTrip == locator)
    }

    @Test func emptySelectionGivesNoLocator() throws {
        let source = try twoPageSource()
        #expect(PDFLocator(selection: PDFSelection(document: source.pdf), in: source.pdf) == nil)
    }

    @Test func overlapNeedsSamePageAndSharedCharacters() {
        let a = PDFLocator(segments: [.init(pageIndex: 0, location: 10, length: 10)])
        #expect(a.overlaps(PDFLocator(segments: [.init(pageIndex: 0, location: 15, length: 10)])))
        #expect(!a.overlaps(PDFLocator(segments: [.init(pageIndex: 0, location: 20, length: 5)])))
        #expect(!a.overlaps(PDFLocator(segments: [.init(pageIndex: 1, location: 10, length: 10)])))
    }

    @Test func jsonRoundTrip() throws {
        let locator = PDFLocator(segments: [.init(pageIndex: 3, location: 7, length: 42)])
        #expect(try PDFLocator.from(json: locator.json()) == locator)
    }

    @Test func damagedJSONThrows() {
        #expect(throws: (any Error).self) { try PDFLocator.from(json: "{not json") }
    }

    @Test func pageThatDoesNotExistGivesNoSelection() throws {
        let source = try twoPageSource()
        let locator = PDFLocator(segments: [.init(pageIndex: 99, location: 0, length: 5)])
        #expect(locator.selection(in: source.pdf) == nil)
    }
}
```

`collapsed` comes from `TextRangeTests.swift` (Task 1), in the same test target.

- [ ] **Step 2: Run the tests and make sure that they fail**

Run: `swift test --filter PDFLocatorTests`
Expected: the build fails with `cannot find 'PDFLocator' in scope`.

- [ ] **Step 3: Write the implementation**

`Sources/DocumentKit/PDFLocator.swift`:

```swift
import Foundation
import PDFKit

/// A stable pointer to text in a PDF: character ranges on pages. The workspace finds a document
/// by its content hash, so the ranges stay correct for the life of the workspace.
public struct PDFLocator: Codable, Equatable, Sendable {
    public struct Segment: Codable, Equatable, Sendable {
        public let pageIndex: Int
        public let location: Int
        public let length: Int

        public init(pageIndex: Int, location: Int, length: Int) {
            self.pageIndex = pageIndex
            self.location = location
            self.length = length
        }

        public var range: NSRange { NSRange(location: location, length: length) }
    }

    public let segments: [Segment]

    public init(segments: [Segment]) {
        self.segments = segments.sorted { ($0.pageIndex, $0.location) < ($1.pageIndex, $1.location) }
    }

    public init?(selection: PDFSelection, in document: PDFDocument) {
        var segments: [Segment] = []
        for page in selection.pages {
            let pageIndex = document.index(for: page)
            for rangeIndex in 0..<selection.numberOfTextRanges(on: page) {
                let range = selection.range(at: rangeIndex, on: page)
                if range.location != NSNotFound && range.length > 0 {
                    segments.append(Segment(pageIndex: pageIndex, location: range.location, length: range.length))
                }
            }
        }
        guard !segments.isEmpty else { return nil }
        self.init(segments: segments)
    }

    public var firstPage: Int { segments.first?.pageIndex ?? 0 }

    /// Rebuilds the selection. Segments on pages that do not exist are skipped.
    public func selection(in document: PDFDocument) -> PDFSelection? {
        var result: PDFSelection?
        for segment in segments where segment.pageIndex >= 0 && segment.pageIndex < document.pageCount {
            guard let page = document.page(at: segment.pageIndex),
                  let part = page.selection(for: segment.range) else { continue }
            if let result { result.add(part) } else { result = part }
        }
        return result
    }

    public func overlaps(_ other: PDFLocator) -> Bool {
        segments.contains { mine in
            other.segments.contains { theirs in
                mine.pageIndex == theirs.pageIndex && NSIntersectionRange(mine.range, theirs.range).length > 0
            }
        }
    }

    public func json() throws -> String {
        String(decoding: try JSONEncoder().encode(self), as: UTF8.self)
    }

    public static func from(json: String) throws -> PDFLocator {
        try JSONDecoder().decode(PDFLocator.self, from: Data(json.utf8))
    }
}
```

- [ ] **Step 4: Run the tests and make sure that they pass**

Run: `swift test --filter PDFLocatorTests`
Expected: 7 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources Tests
git commit -m "feat: add PDFLocator for stable text anchors"
```

---

### Task 3: Anchor and highlight tables

**Files:**
- Modify: `Sources/WorkspaceStore/WorkspaceDatabase.swift` (migration v2)
- Create: `Sources/WorkspaceStore/HighlightRecords.swift`, `Sources/WorkspaceStore/WorkspaceDatabase+Highlights.swift`
- Test: `Tests/WorkspaceStoreTests/HighlightStoreTests.swift`

**Interfaces:**
- Consumes: `WorkspaceDatabase`, `DocumentRecord` (M1).
- Produces:
  - `public struct AnchorRecord: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord { id; documentID; kind; locatorJSON; text; structuralPath; firstPage: Int; createdAt: Date }`
  - `public struct HighlightRecord: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord { id; anchorID; color; createdAt: Date }`
  - `public struct StoredHighlight: Equatable, Sendable { highlight: HighlightRecord; anchor: AnchorRecord }`
  - `WorkspaceDatabase.addHighlight(_: HighlightRecord, anchor: AnchorRecord) throws`
  - `WorkspaceDatabase.highlights(documentID: String) throws -> [StoredHighlight]`, sorted by `first_page`, then `created_at`
  - `WorkspaceDatabase.removeHighlight(id: String) throws`. It also removes the anchor when no other highlight uses it. It does nothing for an unknown ID.

- [ ] **Step 1: Write the failing tests**

`Tests/WorkspaceStoreTests/HighlightStoreTests.swift`:

```swift
import Foundation
import Testing
@testable import WorkspaceStore

struct HighlightStoreTests {
    private func anchor(_ id: String, page: Int, documentID: String = "doc-1", at seconds: TimeInterval = 1000) -> AnchorRecord {
        AnchorRecord(id: id, documentID: documentID, kind: "pdf", locatorJSON: "{\"segments\":[]}", text: "text \(id)",
                     structuralPath: "Chapter 1", firstPage: page, createdAt: Date(timeIntervalSince1970: seconds))
    }

    private func highlight(_ id: String, anchorID: String) -> HighlightRecord {
        HighlightRecord(id: id, anchorID: anchorID, color: "yellow", createdAt: Date(timeIntervalSince1970: 1000))
    }

    private func database() throws -> WorkspaceDatabase {
        let database = try WorkspaceDatabase.inMemory()
        try database.insertDocument(makeDocument())
        try database.insertDocument(makeDocument(id: "doc-2", hash: "hash-2"))
        return database
    }

    @Test func addedHighlightsComeBackSortedByPage() throws {
        let database = try database()
        try database.addHighlight(highlight("h2", anchorID: "a2"), anchor: anchor("a2", page: 5))
        try database.addHighlight(highlight("h1", anchorID: "a1"), anchor: anchor("a1", page: 2))
        let stored = try database.highlights(documentID: "doc-1")
        #expect(stored.map(\.highlight.id) == ["h1", "h2"])
        #expect(stored[0].anchor == anchor("a1", page: 2))
    }

    @Test func highlightsOfOtherDocumentsAreNotListed() throws {
        let database = try database()
        try database.addHighlight(highlight("h1", anchorID: "a1"), anchor: anchor("a1", page: 0, documentID: "doc-2"))
        #expect(try database.highlights(documentID: "doc-1").isEmpty)
    }

    @Test func removingAHighlightAlsoRemovesItsAnchor() throws {
        let database = try database()
        try database.addHighlight(highlight("h1", anchorID: "a1"), anchor: anchor("a1", page: 0))
        try database.removeHighlight(id: "h1")
        #expect(try database.highlights(documentID: "doc-1").isEmpty)
        #expect(try database.queue.read { try AnchorRecord.fetchCount($0) } == 0)
    }

    @Test func removingAnUnknownHighlightDoesNothing() throws {
        let database = try database()
        try database.addHighlight(highlight("h1", anchorID: "a1"), anchor: anchor("a1", page: 0))
        try database.removeHighlight(id: "nope")
        #expect(try database.highlights(documentID: "doc-1").count == 1)
    }

    @Test func anchorForAMissingDocumentIsRejected() throws {
        let database = try database()
        #expect(throws: (any Error).self) {
            try database.addHighlight(highlight("h1", anchorID: "a1"), anchor: anchor("a1", page: 0, documentID: "missing"))
        }
    }
}
```

`makeDocument(id:hash:)` comes from `WorkspaceDatabaseTests.swift` (M1), in the same test target.

- [ ] **Step 2: Run the tests and make sure that they fail**

Run: `swift test --filter HighlightStoreTests`
Expected: the build fails with `cannot find 'AnchorRecord' in scope`.

- [ ] **Step 3: Write the implementation**

In `Sources/WorkspaceStore/WorkspaceDatabase.swift`, inside `static var migrator`, add this before `return migrator`:

```swift
        migrator.registerMigration("v2-highlight") { db in
            try db.execute(sql: """
                CREATE TABLE anchor (
                    id TEXT PRIMARY KEY,
                    document_id TEXT NOT NULL REFERENCES document(id) ON DELETE CASCADE,
                    kind TEXT NOT NULL,
                    locator_json TEXT NOT NULL,
                    text TEXT NOT NULL,
                    structural_path TEXT NOT NULL,
                    first_page INTEGER NOT NULL,
                    created_at DATETIME NOT NULL
                );
                CREATE INDEX anchor_document_page ON anchor(document_id, first_page);
                CREATE TABLE highlight (
                    id TEXT PRIMARY KEY,
                    anchor_id TEXT NOT NULL REFERENCES anchor(id) ON DELETE CASCADE,
                    color TEXT NOT NULL,
                    created_at DATETIME NOT NULL
                );
                CREATE INDEX highlight_anchor ON highlight(anchor_id);
                """)
        }
```

`Sources/WorkspaceStore/HighlightRecords.swift`:

```swift
import Foundation
import GRDB

/// A saved location in a document. Highlights use anchors now; M3 threads will use them too.
public struct AnchorRecord: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "anchor"

    public var id: String
    public var documentID: String
    public var kind: String
    /// For a PDF: `PDFLocator` as JSON.
    public var locatorJSON: String
    public var text: String
    /// For example "Chapter 4 › 4.2 Tool use".
    public var structuralPath: String
    public var firstPage: Int
    public var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, kind, text
        case documentID = "document_id"
        case locatorJSON = "locator_json"
        case structuralPath = "structural_path"
        case firstPage = "first_page"
        case createdAt = "created_at"
    }

    public init(id: String, documentID: String, kind: String, locatorJSON: String, text: String,
                structuralPath: String, firstPage: Int, createdAt: Date) {
        self.id = id
        self.documentID = documentID
        self.kind = kind
        self.locatorJSON = locatorJSON
        self.text = text
        self.structuralPath = structuralPath
        self.firstPage = firstPage
        self.createdAt = createdAt
    }
}

public struct HighlightRecord: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "highlight"

    public var id: String
    public var anchorID: String
    public var color: String
    public var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, color
        case anchorID = "anchor_id"
        case createdAt = "created_at"
    }

    public init(id: String, anchorID: String, color: String, createdAt: Date) {
        self.id = id
        self.anchorID = anchorID
        self.color = color
        self.createdAt = createdAt
    }
}

public struct StoredHighlight: Equatable, Sendable {
    public let highlight: HighlightRecord
    public let anchor: AnchorRecord

    public init(highlight: HighlightRecord, anchor: AnchorRecord) {
        self.highlight = highlight
        self.anchor = anchor
    }
}
```

`Sources/WorkspaceStore/WorkspaceDatabase+Highlights.swift`:

```swift
import GRDB

extension WorkspaceDatabase {
    public func addHighlight(_ highlight: HighlightRecord, anchor: AnchorRecord) throws {
        try queue.write { db in
            try anchor.insert(db)
            try highlight.insert(db)
        }
    }

    public func highlights(documentID: String) throws -> [StoredHighlight] {
        try queue.read { db in
            let anchors = try AnchorRecord
                .filter(Column("document_id") == documentID)
                .order(Column("first_page"), Column("created_at"))
                .fetchAll(db)
            let highlights = try HighlightRecord.filter(anchors.map(\.id).contains(Column("anchor_id"))).fetchAll(db)
            let byAnchor = Dictionary(grouping: highlights, by: \.anchorID)
            return anchors.flatMap { anchor in
                (byAnchor[anchor.id] ?? []).map { StoredHighlight(highlight: $0, anchor: anchor) }
            }
        }
    }

    /// Removes the highlight, and its anchor when no other highlight uses the anchor.
    public func removeHighlight(id: String) throws {
        try queue.write { db in
            guard let highlight = try HighlightRecord.fetchOne(db, key: id) else { return }
            try highlight.delete(db)
            let anchorInUse = try HighlightRecord.filter(Column("anchor_id") == highlight.anchorID).fetchCount(db) > 0
            if !anchorInUse {
                try AnchorRecord.deleteOne(db, key: highlight.anchorID)
            }
        }
    }
}
```

- [ ] **Step 4: Run the tests and make sure that they pass**

Run: `swift test --filter HighlightStoreTests`
Expected: 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources Tests
git commit -m "feat: store anchors and highlights"
```

---

### Task 4: Paragraph selection in ReaderModel

**Files:**
- Modify: `Sources/ReaderUI/ReaderModel.swift`
- Test: `Tests/ReaderUITests/ParagraphSelectionTests.swift`

**Interfaces:**
- Consumes: `PDFDocumentSource.paragraphs(onPage:)`, `Paragraph.textRange` (Task 1). `PDFLocator` (Task 2).
- Produces (on `ReaderModel`):
  - `public private(set) var selection: PDFSelection?`
  - `public var selectedText: String?`
  - `public private(set) var selectionRequest: SelectionRequest?`, where `public struct SelectionRequest: Equatable { id: UUID; selection: PDFSelection? }`
  - `public func selectionDidChange(_ selection: PDFSelection?)`. The view calls it when the user changes the selection.
  - `@discardableResult public func optionClick(at point: CGPoint, onPage pageIndex: Int) -> Bool`. It returns false when no paragraph is at the point. Then the view must do its normal action.

Rules for `optionClick`:
- If the point is in a paragraph that is in the current paragraph selection, add the next paragraph. The next paragraph is the next one on the same page, or the first paragraph of one of the next 3 pages.
- If the point is in another paragraph, select only that paragraph.
- A selection change from the user (`selectionDidChange`) ends the paragraph selection.

- [ ] **Step 1: Write the failing tests**

`Tests/ReaderUITests/ParagraphSelectionTests.swift`:

```swift
import DocumentKit
import Foundation
import Testing
import TestSupport
import WorkspaceStore
@testable import ReaderUI

func collapsed(_ text: String?) -> String {
    (text ?? "").split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}

@MainActor
struct ParagraphSelectionTests {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    /// Page 0 has two paragraphs. Page 1 has one paragraph.
    func makeBook() throws -> URL {
        var first = FixturePDF.paragraph(["Agents call tools", "in a loop."], top: 700, firstIndent: 18)
        first += FixturePDF.paragraph(["The loop stops", "when done."], top: 672, firstIndent: 18)
        return try FixturePDF.make(pages: [first, FixturePDF.paragraph(["Memory keeps state."], top: 700)])
    }

    func openModel(_ url: URL) throws -> ReaderModel {
        let workspace = try WorkspaceManager(paths: AppPaths(root: root)).open(pdfAt: url)
        return try ReaderModel(workspace: workspace, pdfURL: url)
    }

    func center(of paragraph: Int, onPage page: Int, in url: URL) throws -> CGPoint {
        let paragraphs = try PDFDocumentSource(url: url).paragraphs(onPage: page)
        return CGPoint(x: paragraphs[paragraph].rect.midX, y: paragraphs[paragraph].rect.midY)
    }

    @Test func optionClickSelectsTheParagraph() throws {
        let url = try makeBook()
        let model = try openModel(url)
        #expect(model.optionClick(at: try center(of: 1, onPage: 0, in: url), onPage: 0))
        #expect(collapsed(model.selectedText) == "The loop stops when done.")
        #expect(model.selectionRequest?.selection != nil)
    }

    @Test func optionClickAgainAddsTheNextParagraph() throws {
        let url = try makeBook()
        let model = try openModel(url)
        let point = try center(of: 0, onPage: 0, in: url)
        model.optionClick(at: point, onPage: 0)
        model.optionClick(at: point, onPage: 0)
        #expect(collapsed(model.selectedText) == "Agents call tools in a loop. The loop stops when done.")
    }

    @Test func optionClickAgainContinuesOnTheNextPage() throws {
        let url = try makeBook()
        let model = try openModel(url)
        let point = try center(of: 1, onPage: 0, in: url)
        model.optionClick(at: point, onPage: 0)
        model.optionClick(at: point, onPage: 0)
        #expect(collapsed(model.selectedText) == "The loop stops when done. Memory keeps state.")
        #expect(model.selection?.pages.count == 2)
    }

    @Test func optionClickOnAnotherParagraphStartsANewSelection() throws {
        let url = try makeBook()
        let model = try openModel(url)
        model.optionClick(at: try center(of: 0, onPage: 0, in: url), onPage: 0)
        model.optionClick(at: try center(of: 1, onPage: 0, in: url), onPage: 0)
        #expect(collapsed(model.selectedText) == "The loop stops when done.")
    }

    @Test func optionClickOnEmptySpaceChangesNothing() throws {
        let url = try makeBook()
        let model = try openModel(url)
        model.optionClick(at: try center(of: 0, onPage: 0, in: url), onPage: 0)
        #expect(!model.optionClick(at: CGPoint(x: 5, y: 5), onPage: 0))
        #expect(collapsed(model.selectedText) == "Agents call tools in a loop.")
    }

    @Test func userSelectionChangeEndsParagraphSelection() throws {
        let url = try makeBook()
        let model = try openModel(url)
        let point = try center(of: 0, onPage: 0, in: url)
        model.optionClick(at: point, onPage: 0)
        model.selectionDidChange(nil)
        #expect(model.selection == nil)
        model.optionClick(at: point, onPage: 0)
        #expect(collapsed(model.selectedText) == "Agents call tools in a loop.")
    }
}
```

- [ ] **Step 2: Run the tests and make sure that they fail**

Run: `swift test --filter ParagraphSelectionTests`
Expected: the build fails with `value of type 'ReaderModel' has no member 'optionClick'`.

- [ ] **Step 3: Write the implementation**

In `Sources/ReaderUI/ReaderModel.swift`:

1. After the `NavigationRequest` struct, add:

```swift
/// A request to set the selection in the PDF view. Each request has a new ID.
public struct SelectionRequest: Equatable {
    public let id = UUID()
    public let selection: PDFSelection?

    public static func == (lhs: SelectionRequest, rhs: SelectionRequest) -> Bool { lhs.id == rhs.id }
}
```

2. In `ReaderModel`, after `public private(set) var lastError: String?`, add:

```swift
    public private(set) var selection: PDFSelection?
    public private(set) var selectionRequest: SelectionRequest?
    @ObservationIgnored private let source: PDFDocumentSource
    @ObservationIgnored private var paragraphCache: [Int: [Paragraph]] = [:]
    @ObservationIgnored private var selectedParagraphs: [Paragraph] = []
```

3. In `init`, after `self.pdfURL = pdfURL`, add `self.source = source`.

4. Add these methods to `ReaderModel`:

```swift
    public var selectedText: String? { selection?.string }

    public func selectionDidChange(_ selection: PDFSelection?) {
        let text = selection?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.selection = text.isEmpty ? nil : selection
        selectedParagraphs = []
    }

    @discardableResult
    public func optionClick(at point: CGPoint, onPage pageIndex: Int) -> Bool {
        guard let hit = paragraphs(onPage: pageIndex).first(where: { $0.rect.insetBy(dx: -2, dy: -2).contains(point) })
        else { return false }
        if selectedParagraphs.contains(hit) {
            if let last = selectedParagraphs.last, let next = paragraph(after: last) {
                selectedParagraphs.append(next)
            }
        } else {
            selectedParagraphs = [hit]
        }
        let segments = selectedParagraphs
            .filter { $0.textRange.location != NSNotFound }
            .map { PDFLocator.Segment(pageIndex: $0.pageIndex, location: $0.textRange.location, length: $0.textRange.length) }
        let newSelection = PDFLocator(segments: segments).selection(in: pdf)
        selection = newSelection
        selectionRequest = SelectionRequest(selection: newSelection)
        return true
    }

    private func paragraphs(onPage pageIndex: Int) -> [Paragraph] {
        if let cached = paragraphCache[pageIndex] { return cached }
        let paragraphs = source.paragraphs(onPage: pageIndex)
        paragraphCache[pageIndex] = paragraphs
        return paragraphs
    }

    private func paragraph(after paragraph: Paragraph) -> Paragraph? {
        let samePage = paragraphs(onPage: paragraph.pageIndex)
        if paragraph.index + 1 < samePage.count { return samePage[paragraph.index + 1] }
        let upper = min(paragraph.pageIndex + 4, pdf.pageCount)
        guard paragraph.pageIndex + 1 < upper else { return nil }
        for page in (paragraph.pageIndex + 1)..<upper {
            if let first = paragraphs(onPage: page).first { return first }
        }
        return nil
    }
```

- [ ] **Step 4: Run the tests and make sure that they pass**

Run: `swift test --filter ParagraphSelectionTests`
Expected: 6 tests pass.

- [ ] **Step 5: Add a test for the last page**

Add to `ParagraphSelectionTests`:

```swift
    @Test func optionClickAgainOnTheLastParagraphKeepsTheSelection() throws {
        let url = try makeBook()
        let model = try openModel(url)
        let point = try center(of: 0, onPage: 1, in: url)
        model.optionClick(at: point, onPage: 1)
        model.optionClick(at: point, onPage: 1)
        #expect(collapsed(model.selectedText) == "Memory keeps state.")
    }
```

Run: `swift test --filter ParagraphSelectionTests`
Expected: 7 tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources Tests
git commit -m "feat: select paragraphs with Option-click"
```

---

### Task 5: Highlights in ReaderModel

**Files:**
- Modify: `Sources/ReaderUI/ReaderModel.swift`
- Create: `Sources/ReaderUI/HighlightGeometry.swift`
- Test: `Tests/ReaderUITests/HighlightTests.swift`

**Interfaces:**
- Consumes: `PDFLocator` (Task 2). `AnchorRecord`, `HighlightRecord`, `StoredHighlight`, `addHighlight`, `highlights(documentID:)`, `removeHighlight(id:)` (Task 3). `selection`, `optionClick` (Task 4).
- Produces (on `ReaderModel`):
  - `public private(set) var highlights: [StoredHighlight]` (loaded in `init`)
  - `public var selectionHighlights: [StoredHighlight]` (highlights that overlap the current selection)
  - `public func highlightSelection()`. It does nothing when there is no selection or when a highlight already overlaps the selection.
  - `public func removeSelectionHighlights()`
  - `public func show(_ highlight: StoredHighlight)`. It makes a navigation request to the highlight.
- Produces: `enum HighlightGeometry { static func lineRects(for: PDFLocator, in: PDFDocument) -> [(pageIndex: Int, rect: CGRect)] }`

- [ ] **Step 1: Write the failing tests**

`Tests/ReaderUITests/HighlightTests.swift`:

```swift
import DocumentKit
import Foundation
import Testing
import TestSupport
import WorkspaceStore
@testable import ReaderUI

@MainActor
struct HighlightTests {
    let helper = ParagraphSelectionTests()

    @Test func highlightIsSavedAndComesBackAfterReopen() throws {
        let url = try helper.makeBook()
        let model = try helper.openModel(url)
        model.optionClick(at: try helper.center(of: 0, onPage: 0, in: url), onPage: 0)
        model.highlightSelection()
        #expect(model.highlights.count == 1)
        #expect(collapsed(model.highlights[0].anchor.text) == "Agents call tools in a loop.")
        #expect(model.highlights[0].anchor.firstPage == 0)

        let reopened = try helper.openModel(url)
        #expect(reopened.highlights.map(\.highlight.id) == model.highlights.map(\.highlight.id))
        let locator = try PDFLocator.from(json: reopened.highlights[0].anchor.locatorJSON)
        #expect(collapsed(locator.selection(in: reopened.pdf)?.string) == "Agents call tools in a loop.")
    }

    @Test func sameTextIsNotHighlightedTwice() throws {
        let url = try helper.makeBook()
        let model = try helper.openModel(url)
        model.optionClick(at: try helper.center(of: 0, onPage: 0, in: url), onPage: 0)
        model.highlightSelection()
        model.highlightSelection()
        #expect(model.highlights.count == 1)
        #expect(model.selectionHighlights.count == 1)
    }

    @Test func removeSelectionHighlightsDeletesThem() throws {
        let url = try helper.makeBook()
        let model = try helper.openModel(url)
        model.optionClick(at: try helper.center(of: 0, onPage: 0, in: url), onPage: 0)
        model.highlightSelection()
        model.removeSelectionHighlights()
        #expect(model.highlights.isEmpty)
        #expect(try helper.openModel(url).highlights.isEmpty)
    }

    @Test func noSelectionMeansNoHighlight() throws {
        let model = try helper.openModel(helper.makeBook())
        model.highlightSelection()
        #expect(model.highlights.isEmpty)
    }

    @Test func highlightOverAPageBreakHasTwoSegmentsAndRectsOnBothPages() throws {
        let url = try helper.makeBook()
        let model = try helper.openModel(url)
        let point = try helper.center(of: 1, onPage: 0, in: url)
        model.optionClick(at: point, onPage: 0)
        model.optionClick(at: point, onPage: 0)
        model.highlightSelection()
        let locator = try PDFLocator.from(json: model.highlights[0].anchor.locatorJSON)
        #expect(locator.segments.map(\.pageIndex) == [0, 1])
        let rects = HighlightGeometry.lineRects(for: locator, in: model.pdf)
        #expect(Set(rects.map(\.pageIndex)) == [0, 1])
        #expect(rects.allSatisfy { !$0.rect.isEmpty })
    }

    @Test func damagedLocatorIsSkipped() throws {
        let url = try helper.makeBook()
        let model = try helper.openModel(url)
        let anchor = AnchorRecord(id: "bad", documentID: model.workspace.document.id, kind: "pdf", locatorJSON: "{broken",
                                  text: "x", structuralPath: "", firstPage: 0, createdAt: Date())
        try model.workspace.database.addHighlight(
            HighlightRecord(id: "hbad", anchorID: "bad", color: "yellow", createdAt: Date()), anchor: anchor)
        let reopened = try helper.openModel(url)
        reopened.optionClick(at: try helper.center(of: 0, onPage: 0, in: url), onPage: 0)
        #expect(reopened.selectionHighlights.isEmpty)
        reopened.show(reopened.highlights[0])
        #expect(reopened.navigationRequest?.pageIndex == 0)
        #expect(HighlightGeometry.lineRects(for: PDFLocator(segments: [.init(pageIndex: 99, location: 0, length: 3)]),
                                            in: reopened.pdf).isEmpty)
    }
}
```

- [ ] **Step 2: Run the tests and make sure that they fail**

Run: `swift test --filter HighlightTests`
Expected: the build fails with `value of type 'ReaderModel' has no member 'highlightSelection'`.

- [ ] **Step 3: Write the implementation**

`Sources/ReaderUI/HighlightGeometry.swift`:

```swift
import DocumentKit
import PDFKit

/// Calculates the line rectangles that a highlight covers. Segments on pages that do not exist give no rectangles.
enum HighlightGeometry {
    static func lineRects(for locator: PDFLocator, in document: PDFDocument) -> [(pageIndex: Int, rect: CGRect)] {
        locator.segments.flatMap { segment -> [(pageIndex: Int, rect: CGRect)] in
            guard segment.pageIndex >= 0, segment.pageIndex < document.pageCount,
                  let page = document.page(at: segment.pageIndex),
                  let selection = page.selection(for: segment.range) else { return [] }
            return selection.selectionsByLine()
                .map { (pageIndex: segment.pageIndex, rect: $0.bounds(for: page)) }
                .filter { !$0.rect.isEmpty }
        }
    }
}
```

In `Sources/ReaderUI/ReaderModel.swift`:

1. After `public private(set) var selectionRequest: SelectionRequest?`, add:

```swift
    public private(set) var highlights: [StoredHighlight]
```

2. In `init`, after `self.navigationRequest = ...`, add:

```swift
        self.highlights = try workspace.database.highlights(documentID: workspace.document.id)
```

3. Add these methods:

```swift
    public var selectionHighlights: [StoredHighlight] {
        guard let selection, let locator = PDFLocator(selection: selection, in: pdf) else { return [] }
        return highlights.filter { (try? PDFLocator.from(json: $0.anchor.locatorJSON))?.overlaps(locator) == true }
    }

    public func highlightSelection() {
        guard let selection, let locator = PDFLocator(selection: selection, in: pdf), selectionHighlights.isEmpty else { return }
        do {
            let now = Date()
            let anchor = AnchorRecord(
                id: UUID().uuidString, documentID: workspace.document.id, kind: DocumentKind.pdf.rawValue,
                locatorJSON: try locator.json(), text: selection.string ?? "",
                structuralPath: StructuralPath.path(forPage: locator.firstPage, in: outline).joined(separator: " › "),
                firstPage: locator.firstPage, createdAt: now)
            let highlight = HighlightRecord(id: UUID().uuidString, anchorID: anchor.id, color: "yellow", createdAt: now)
            try workspace.database.addHighlight(highlight, anchor: anchor)
            highlights = try workspace.database.highlights(documentID: workspace.document.id)
        } catch {
            lastError = "Reader cannot save the highlight: \(error.localizedDescription)"
        }
    }

    public func removeSelectionHighlights() {
        do {
            for stored in selectionHighlights {
                try workspace.database.removeHighlight(id: stored.highlight.id)
            }
            highlights = try workspace.database.highlights(documentID: workspace.document.id)
        } catch {
            lastError = "Reader cannot remove the highlight: \(error.localizedDescription)"
        }
    }

    public func show(_ highlight: StoredHighlight) {
        let selection = (try? PDFLocator.from(json: highlight.anchor.locatorJSON))?.selection(in: pdf)
        navigationRequest = NavigationRequest(pageIndex: highlight.anchor.firstPage, selection: selection)
    }
```

- [ ] **Step 4: Run the tests and make sure that they pass**

Run: `swift test --filter HighlightTests`
Expected: 6 tests pass.

- [ ] **Step 5: Run all tests**

Run: `swift test`
Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources Tests
git commit -m "feat: highlight the selection and restore highlights"
```

---

### Task 6: Views — Option-click, H key, selection bar, annotations, Highlights list

**Files:**
- Create: `Sources/ReaderUI/ReaderPDFView.swift`, `Sources/ReaderUI/SelectionBar.swift`
- Modify: `Sources/ReaderUI/PDFKitView.swift`, `Sources/ReaderUI/ReaderView.swift`

**Interfaces:**
- Consumes: `ReaderModel.optionClick`, `selectionDidChange`, `selectionRequest`, `selection`, `highlights`, `selectionHighlights`, `highlightSelection`, `removeSelectionHighlights`, `show(_: StoredHighlight)` (Tasks 4 and 5). `HighlightGeometry.lineRects` (Task 5).
- Produces: UI only. There are no unit tests; Step 4 is the manual check.

- [ ] **Step 1: Write the PDF view subclass and the selection bar**

`Sources/ReaderUI/ReaderPDFView.swift`:

```swift
import PDFKit

/// PDFView with Option-click paragraph selection and the H key for highlight.
final class ReaderPDFView: PDFView {
    /// Gets the page index and the point in page coordinates. Returns true when it handled the click.
    var onOptionClick: ((Int, CGPoint) -> Bool)?
    var onHighlightKey: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.option), let onOptionClick, let document {
            let point = convert(event.locationInWindow, from: nil)
            if let page = page(for: point, nearest: false),
               onOptionClick(document.index(for: page), convert(point, to: page)) {
                return
            }
        }
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if modifiers.isEmpty, event.charactersIgnoringModifiers == "h",
           currentSelection?.string?.isEmpty == false, let onHighlightKey {
            onHighlightKey()
            return
        }
        super.keyDown(with: event)
    }
}
```

`Sources/ReaderUI/SelectionBar.swift`:

```swift
import SwiftUI

/// The small bar above the selection. M3 adds the LLM actions here.
struct SelectionBar: View {
    let model: ReaderModel

    var body: some View {
        HStack(spacing: 4) {
            if model.selectionHighlights.isEmpty {
                Button { model.highlightSelection() } label: {
                    Label("Highlight", systemImage: "highlighter")
                }
                .help("Highlight (H)")
            } else {
                Button { model.removeSelectionHighlights() } label: {
                    Label("Remove highlight", systemImage: "eraser")
                }
            }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.regularMaterial, in: Capsule())
        .shadow(radius: 2)
        .fixedSize()
    }
}
```

- [ ] **Step 2: Replace the PDF view bridge**

`Sources/ReaderUI/PDFKitView.swift`:

```swift
import DocumentKit
import PDFKit
import SwiftUI
import WorkspaceStore

/// Shows the PDF, reports page and selection changes to the model, follows its requests,
/// draws the highlights, and shows the selection bar.
struct PDFKitView: NSViewRepresentable {
    let model: ReaderModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> ReaderPDFView {
        let view = ReaderPDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displaysPageBreaks = true
        view.document = model.pdf
        let model = self.model
        view.onOptionClick = { pageIndex, point in model.optionClick(at: point, onPage: pageIndex) }
        view.onHighlightKey = { model.highlightSelection() }
        context.coordinator.observe(view)
        return view
    }

    func updateNSView(_ view: ReaderPDFView, context: Context) {
        let coordinator = context.coordinator
        coordinator.apply(model.navigationRequest, to: view)
        coordinator.apply(model.selectionRequest, to: view)
        coordinator.sync(model.highlights, in: view)
        coordinator.positionBar(for: model.selection, in: view)
    }

    @MainActor
    final class Coordinator: NSObject {
        let model: ReaderModel
        private var handledNavigationID: UUID?
        private var handledSelectionID: UUID?
        private var applyingSelection = false
        private var drawn: [String: [PDFAnnotation]] = [:]
        private lazy var bar = NSHostingView(rootView: SelectionBar(model: model))

        init(model: ReaderModel) {
            self.model = model
        }

        func observe(_ view: PDFView) {
            let center = NotificationCenter.default
            center.addObserver(self, selector: #selector(pageChanged(_:)), name: .PDFViewPageChanged, object: view)
            center.addObserver(self, selector: #selector(selectionChanged(_:)), name: .PDFViewSelectionChanged, object: view)
            center.addObserver(self, selector: #selector(layoutChanged(_:)), name: .PDFViewScaleChanged, object: view)
        }

        @objc private func pageChanged(_ notification: Notification) {
            guard let view = notification.object as? PDFView,
                  let page = view.currentPage, let document = view.document else { return }
            model.pageDidChange(to: document.index(for: page))
        }

        @objc private func selectionChanged(_ notification: Notification) {
            guard !applyingSelection, let view = notification.object as? PDFView else { return }
            model.selectionDidChange(view.currentSelection)
        }

        @objc private func layoutChanged(_ notification: Notification) {
            guard let view = notification.object as? PDFView else { return }
            positionBar(for: model.selection, in: view)
        }

        func apply(_ request: NavigationRequest?, to view: PDFView) {
            guard let request, request.id != handledNavigationID,
                  let page = view.document?.page(at: request.pageIndex) else { return }
            handledNavigationID = request.id
            view.layoutDocumentView()
            if let selection = request.selection {
                view.setCurrentSelection(selection, animate: true)
                view.go(to: selection)
            } else {
                view.go(to: page)
            }
        }

        func apply(_ request: SelectionRequest?, to view: PDFView) {
            guard let request, request.id != handledSelectionID else { return }
            handledSelectionID = request.id
            applyingSelection = true
            view.setCurrentSelection(request.selection, animate: false)
            applyingSelection = false
        }

        /// Adds annotations for new highlights and removes annotations for deleted highlights.
        func sync(_ highlights: [StoredHighlight], in view: PDFView) {
            guard let document = view.document else { return }
            let wanted = Set(highlights.map(\.highlight.id))
            for (id, annotations) in drawn where !wanted.contains(id) {
                annotations.forEach { $0.page?.removeAnnotation($0) }
                drawn[id] = nil
            }
            for stored in highlights where drawn[stored.highlight.id] == nil {
                guard let locator = try? PDFLocator.from(json: stored.anchor.locatorJSON) else { continue }
                drawn[stored.highlight.id] = HighlightGeometry.lineRects(for: locator, in: document).compactMap { item in
                    guard let page = document.page(at: item.pageIndex) else { return nil }
                    let annotation = PDFAnnotation(bounds: item.rect, forType: .highlight, withProperties: nil)
                    let size = item.rect.size
                    annotation.quadrilateralPoints = [
                        NSValue(point: CGPoint(x: 0, y: size.height)), NSValue(point: CGPoint(x: size.width, y: size.height)),
                        NSValue(point: .zero), NSValue(point: CGPoint(x: size.width, y: 0)),
                    ]
                    annotation.color = NSColor.systemYellow.withAlphaComponent(0.45)
                    page.addAnnotation(annotation)
                    return annotation
                }
            }
        }

        /// Puts the bar above the first line of the selection, in the scrolling document view.
        func positionBar(for selection: PDFSelection?, in view: PDFView) {
            guard let selection, let page = selection.pages.first, let documentView = view.documentView else {
                bar.isHidden = true
                return
            }
            if bar.superview !== documentView { documentView.addSubview(bar) }
            let inView = view.convert(selection.bounds(for: page), from: page)
            let inDocument = documentView.convert(inView, from: view)
            let size = bar.fittingSize
            let y = documentView.isFlipped ? inDocument.minY - size.height - 6 : inDocument.maxY + 6
            bar.frame = CGRect(x: max(inDocument.minX, 4), y: max(y, 4), width: size.width, height: size.height)
            bar.isHidden = false
        }
    }
}
```

In `Sources/ReaderUI/ReaderView.swift`, in `ReaderSidebar.body`, add this section between the Results section and the Contents section:

```swift
            if !model.highlights.isEmpty {
                Section("Highlights (\(model.highlights.count))") {
                    ForEach(model.highlights, id: \.highlight.id) { stored in
                        Button { model.show(stored) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(stored.anchor.text).lineLimit(2)
                                Text("Page \(stored.anchor.firstPage + 1)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
```

- [ ] **Step 3: Build and run all tests**

Run: `swift build && swift test`
Expected: the build succeeds with no new warnings, and all tests pass.

- [ ] **Step 4: Build the app and do the manual check**

Run: `scripts/make-app.sh`. Do check 0 first, because it deletes the M1 workspace data (only the index and the last page; there are no highlights yet).

0. Run `rm -rf ~/Library/Application\ Support/Reader/workspaces`, then `open build/Reader.app`, open `/Users/hc/Documents/books/2606.24937v2.pdf`, and wait until indexing is complete. Run `grep -c '^[0-9]*$' ~/Library/Application\ Support/Reader/workspaces/*/text/*.md`. The counts are 0 or near 0, because the running page numbers are gone.

Then do these checks with the same book:

1. Option-click a body paragraph. The full paragraph is selected, and the bar with **Highlight** shows above it.
2. Option-click the same paragraph again. The next paragraph is added. At the end of a page, the first paragraph of the next page is added.
3. Press `H`. The selection gets a yellow highlight, and the sidebar shows it under **Highlights**.
4. Select the highlighted text again. The bar shows **Remove highlight**. Click it. The yellow highlight goes away.
5. Make a highlight, quit the app, and open the book again. The highlight is at the same text.
6. Option-click in a margin. Nothing is selected, and no error shows.
7. Zoom in and out (⌘+ and ⌘−) with a selection. The bar stays above the selection.

If a check fails, use superpowers:systematic-debugging, fix the problem, and add a test in the task that owns the code.

- [ ] **Step 5: Commit**

```bash
git add Sources
git commit -m "feat: Option-click, H key, selection bar, highlight annotations and Highlights list"
```
