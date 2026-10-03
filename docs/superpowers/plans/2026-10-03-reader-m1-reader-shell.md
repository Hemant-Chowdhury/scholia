# Reader M1 (Reader Shell) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make a macOS app that opens a PDF, shows its outline, searches it, reopens it at the last page, and makes a workspace for it. The workspace contains a full-text index and a text copy of the document.

**Architecture:** This is one Swift package with the library targets `DocumentKit` (PDF access, paragraphs, chapters), `WorkspaceStore` (SQLite through GRDB, workspaces, indexer) and `ReaderUI` (SwiftUI views and their models), plus the executable target `ReaderApp`. The tests use Swift Testing and fixture PDFs that the test code makes at run time. A shell script packs the release binary into `Reader.app`.

**Tech Stack:** Swift 6.1 (Swift 6 language mode), SwiftUI, PDFKit, CoreText (tests only), GRDB.swift 7, SQLite FTS5, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-03-reader-design.md`. This plan implements milestone **M1** (spec Section 11). Milestones M2 to M6 get their own plans after M1 works.

## Global Constraints

- Minimum platform: macOS 15. Swift tools version 6.0. Swift 6 language mode.
- Only one third-party dependency: GRDB.swift (`from: "7.0.0"`).
- No App Sandbox.
- No API keys and no telemetry.
- All app data is in `~/Library/Application Support/Reader/`. Tests use temporary folders and never write there.
- The app identifies a document by the SHA-256 hash of its contents (spec 3.2).
- UI modules only show data and send user actions. Logic goes in models and lower modules (spec 3.3).
- Test framework: Swift Testing (`import Testing`). Run all tests with `swift test` from the repository root.
- Documentation and user-visible text use ASD-STE100 Simplified Technical English.
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.

## Notes on the spec

- Spec Section 7 lists all tables. M1 makes only the `document` table and the `document_text` FTS5 table. Each later milestone adds its tables in a new migration when it uses them.
- M1 adds two columns to `document`: `indexed_pages` (to continue an interrupted index) and `text_exported` (to know that the `text/` files exist).
- The `opencode.json` file in the workspace folder (spec 3.4) is part of M3, because it concerns agents.
- In the `text/` files, page markers use the physical page number (`[p. N]`, where N = page index + 1). The reader also uses these numbers to go to a page.
- The spec asks for XCUITest smoke tests. A pure SwiftPM package cannot run XCUITest, so M1 uses a manual checklist (Task 9). M6 adds the UI tests together with CI.

## Review Focus

1. **A scanned PDF with no text layer.** The app must open it and show the pages. Indexing must complete with zero paragraphs and no error. (Task 2 and Task 7 tests)
2. **The same PDF at a different path, or opened two times.** The app must open the same workspace and the same database instance, and update the last known path. (Task 6 tests)
3. **The app quits or the window closes during indexing.** The next run must continue from the last indexed page, with no duplicate paragraphs. (Task 7 test)
4. **A password-protected or damaged PDF.** The app must show a clear message and make no workspace folder. (Task 2 and Task 6 tests)
5. **Search text with FTS5 syntax characters** (`"`, `-`, `(`, `*`, `AND`). The search must not throw and must find the words. (Task 5 tests)

## File Structure

```
Package.swift
LICENSE
.gitignore
scripts/make-app.sh                          # packs the release binary into build/Reader.app
Sources/DocumentKit/
  ContentHash.swift                          # SHA-256 of a file
  DocumentModels.swift                       # DocumentKind, DocumentMetadata, OutlineEntry, TextLine, Paragraph, DocumentError
  DocumentSource.swift                       # DocumentSource protocol
  PDFDocumentSource.swift                    # PDFKit implementation
  StructuralPath.swift                       # chapter path for a page
  ParagraphGrouper.swift                     # lines -> paragraphs
  ChapterSplitter.swift                      # outline -> text file chunks, slug
Sources/WorkspaceStore/
  AppPaths.swift                             # file locations
  DocumentRecord.swift                       # GRDB record for the document table
  WorkspaceDatabase.swift                    # database, migrations, document queries
  WorkspaceDatabase+Text.swift               # FTS5 paragraphs and search
  FTSQuery.swift                             # safe FTS5 MATCH expressions
  GlobalIndex.swift                          # content hash -> workspace ID, recents
  WorkspaceManager.swift                     # open or make a workspace
  DocumentIndexer.swift                      # page indexing and text export
Sources/ReaderUI/
  ReaderModel.swift                          # state and actions of one reader window
  Library.swift                              # opens workspaces, recents
  PDFKitView.swift                           # PDFView bridge
  ReaderView.swift                           # split view, sidebar, toolbar status
Sources/ReaderApp/
  ReaderApp.swift                            # app entry, scenes, commands
  LibraryView.swift                          # start window: open button and recents
  ReaderWindow.swift                         # loads a model for a URL
Tests/TestSupport/FixturePDF.swift           # makes test PDFs at run time
Tests/DocumentKitTests/...
Tests/WorkspaceStoreTests/...
Tests/ReaderUITests/...
```

---

### Task 1: Package skeleton and ContentHash

**Files:**
- Create: `Package.swift`, `LICENSE`, `.gitignore`
- Create: `Sources/DocumentKit/ContentHash.swift`
- Test: `Tests/DocumentKitTests/ContentHashTests.swift`

**Interfaces:**
- Produces: `public enum ContentHash { public static func sha256(of url: URL) throws -> String }`. The result is a lowercase hex string with 64 characters.

- [ ] **Step 1: Make the package files**

`Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Reader",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "DocumentKit"),
        .testTarget(name: "DocumentKitTests", dependencies: ["DocumentKit"]),
    ]
)
```

`.gitignore`:

```
.build/
build/
.swiftpm/
*.xcodeproj/
DerivedData/
.DS_Store
```

`LICENSE`: the standard MIT license text. Use this first line: `Copyright (c) 2026 Hemant Chowdhury`.

- [ ] **Step 2: Write the failing test**

`Tests/DocumentKitTests/ContentHashTests.swift`:

```swift
import Foundation
import Testing
@testable import DocumentKit

struct ContentHashTests {
    private func writeTemp(_ text: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data(text.utf8).write(to: url)
        return url
    }

    @Test func hashOfKnownBytesMatchesSHA256() throws {
        let url = try writeTemp("abc")
        #expect(try ContentHash.sha256(of: url) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test func sameBytesAtDifferentPathsGiveSameHash() throws {
        #expect(try ContentHash.sha256(of: writeTemp("same")) == ContentHash.sha256(of: writeTemp("same")))
    }

    @Test func missingFileThrows() {
        #expect(throws: (any Error).self) {
            try ContentHash.sha256(of: URL(fileURLWithPath: "/nonexistent/file.pdf"))
        }
    }
}
```

- [ ] **Step 3: Run the test and make sure that it fails**

Run: `swift test --filter ContentHashTests`
Expected: the build fails with `cannot find 'ContentHash' in scope`.

- [ ] **Step 4: Write the implementation**

`Sources/DocumentKit/ContentHash.swift`:

```swift
import CryptoKit
import Foundation

/// Identifies a document by its bytes, so a moved or renamed file keeps its workspace.
public enum ContentHash {
    public static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
```

- [ ] **Step 5: Run the tests and make sure that they pass**

Run: `swift test --filter ContentHashTests`
Expected: 3 tests pass.

- [ ] **Step 6: Commit**

```bash
git add Package.swift LICENSE .gitignore Sources Tests
git commit -m "feat: add package skeleton and content hash"
```

---

### Task 2: Fixture PDFs and PDFDocumentSource (metadata, outline, lines, errors)

**Files:**
- Modify: `Package.swift` (add the `TestSupport` target)
- Create: `Tests/TestSupport/FixturePDF.swift`
- Create: `Sources/DocumentKit/DocumentModels.swift`, `Sources/DocumentKit/DocumentSource.swift`, `Sources/DocumentKit/PDFDocumentSource.swift`, `Sources/DocumentKit/StructuralPath.swift`
- Test: `Tests/DocumentKitTests/PDFDocumentSourceTests.swift`, `Tests/DocumentKitTests/StructuralPathTests.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces:
  - `public enum DocumentKind: String, Sendable { case pdf }`
  - `public struct DocumentMetadata: Equatable, Sendable { title: String; author: String?; pageCount: Int }`
  - `public struct OutlineEntry: Equatable, Sendable { title: String; level: Int; pageIndex: Int }`
  - `public struct TextLine: Equatable, Sendable { text: String; rect: CGRect }`. The rect is in PDF page coordinates (origin at the bottom left).
  - `public struct Paragraph: Equatable, Sendable { pageIndex: Int; index: Int; text: String; rect: CGRect }`
  - `public enum DocumentError: Error, Equatable, LocalizedError { case cannotOpen(URL), locked(URL) }`
  - `public protocol DocumentSource { var kind; var metadata; var outline; func paragraphs(onPage:) -> [Paragraph] }`
  - `public final class PDFDocumentSource: DocumentSource` with `init(url: URL) throws`, `let url: URL`, `let pdf: PDFDocument`, `func lines(onPage: Int) -> [TextLine]`. Task 3 adds `paragraphs(onPage:)`.
  - `public enum StructuralPath { static func path(forPage: Int, in: [OutlineEntry]) -> [String] }`
  - TestSupport: `FixtureLine`, `FixtureOutline`, `FixturePDF.make(pages:title:author:outline:)`, `FixturePDF.makeImageOnly()`, `FixturePDF.makeLocked()`, `FixturePDF.makeCorrupt()`, `FixturePDF.paragraph(_:top:x:leading:firstIndent:size:)`

- [ ] **Step 1: Add the TestSupport target**

Replace the `targets` array in `Package.swift`:

```swift
    targets: [
        .target(name: "DocumentKit"),
        .target(name: "TestSupport", path: "Tests/TestSupport"),
        .testTarget(name: "DocumentKitTests", dependencies: ["DocumentKit", "TestSupport"]),
    ]
```

- [ ] **Step 2: Write the fixture helper**

`Tests/TestSupport/FixturePDF.swift`:

```swift
import AppKit
import CoreText
import Foundation
import PDFKit

/// One line of text that a fixture page draws at an exact baseline position.
public struct FixtureLine: Sendable {
    public var text: String
    public var x: CGFloat
    public var y: CGFloat
    public var size: CGFloat

    public init(_ text: String, x: CGFloat = 72, y: CGFloat, size: CGFloat = 11) {
        self.text = text
        self.x = x
        self.y = y
        self.size = size
    }
}

public struct FixtureOutline: Sendable {
    public var title: String
    public var page: Int
    public var children: [FixtureOutline]

    public init(_ title: String, page: Int, children: [FixtureOutline] = []) {
        self.title = title
        self.page = page
        self.children = children
    }
}

public enum FixtureError: Error { case cannotCreate }

/// Makes small PDFs at run time, so the tests do not need binary files in the repository.
public enum FixturePDF {
    public static let pageSize = CGSize(width: 612, height: 792)

    public static func make(
        pages: [[FixtureLine]],
        title: String? = nil,
        author: String? = nil,
        outline: [FixtureOutline] = []
    ) throws -> URL {
        let url = temporaryURL()
        var box = CGRect(origin: .zero, size: pageSize)
        var info: [String: Any] = [:]
        if let title { info[kCGPDFContextTitle as String] = title }
        if let author { info[kCGPDFContextAuthor as String] = author }
        guard let context = CGContext(url as CFURL, mediaBox: &box, info as CFDictionary) else {
            throw FixtureError.cannotCreate
        }
        for page in pages {
            context.beginPDFPage(nil)
            for line in page {
                let font = NSFont(name: "Helvetica", size: line.size) ?? NSFont.systemFont(ofSize: line.size)
                let text = NSAttributedString(string: line.text, attributes: [.font: font])
                context.textPosition = CGPoint(x: line.x, y: line.y)
                CTLineDraw(CTLineCreateWithAttributedString(text), context)
            }
            context.endPDFPage()
        }
        context.closePDF()
        if !outline.isEmpty { try addOutline(outline, to: url) }
        return url
    }

    /// Lines of one paragraph with a fixed leading. `top` is the baseline of the first line.
    public static func paragraph(
        _ lines: [String], top: CGFloat, x: CGFloat = 72, leading: CGFloat = 14, firstIndent: CGFloat = 0, size: CGFloat = 11
    ) -> [FixtureLine] {
        lines.enumerated().map { index, text in
            FixtureLine(text, x: x + (index == 0 ? firstIndent : 0), y: top - CGFloat(index) * leading, size: size)
        }
    }

    /// One page with a filled rectangle and no text, like a scanned page.
    public static func makeImageOnly() throws -> URL {
        let url = temporaryURL()
        var box = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { throw FixtureError.cannotCreate }
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(gray: 0.5, alpha: 1))
        context.fill(CGRect(x: 72, y: 72, width: 400, height: 600))
        context.endPDFPage()
        context.closePDF()
        return url
    }

    public static func makeLocked(password: String = "secret") throws -> URL {
        let source = try make(pages: [[FixtureLine("Locked text", y: 700)]])
        guard let document = PDFDocument(url: source) else { throw FixtureError.cannotCreate }
        let url = temporaryURL()
        let written = document.write(to: url, withOptions: [.userPasswordOption: password, .ownerPasswordOption: password])
        guard written else { throw FixtureError.cannotCreate }
        return url
    }

    public static func makeCorrupt() throws -> URL {
        let url = temporaryURL()
        try Data("this is not a pdf".utf8).write(to: url)
        return url
    }

    private static func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
    }

    private static func addOutline(_ entries: [FixtureOutline], to url: URL) throws {
        guard let document = PDFDocument(url: url) else { throw FixtureError.cannotCreate }
        let root = PDFOutline()
        func insert(_ entries: [FixtureOutline], into parent: PDFOutline) {
            for (index, entry) in entries.enumerated() {
                let node = PDFOutline()
                node.label = entry.title
                if let page = document.page(at: entry.page) {
                    node.destination = PDFDestination(page: page, at: CGPoint(x: 0, y: pageSize.height))
                }
                parent.insertChild(node, at: index)
                insert(entry.children, into: node)
            }
        }
        insert(entries, into: root)
        document.outlineRoot = root
        guard document.write(to: url) else { throw FixtureError.cannotCreate }
    }
}
```

- [ ] **Step 3: Write the failing tests**

`Tests/DocumentKitTests/PDFDocumentSourceTests.swift`:

```swift
import Foundation
import Testing
import TestSupport
@testable import DocumentKit

struct PDFDocumentSourceTests {
    @Test func readsMetadataFromThePDF() throws {
        let url = try FixturePDF.make(
            pages: [[FixtureLine("One", y: 700)], [FixtureLine("Two", y: 700)]],
            title: "Agentic AI", author: "A. Writer")
        let source = try PDFDocumentSource(url: url)
        #expect(source.kind == .pdf)
        #expect(source.metadata == DocumentMetadata(title: "Agentic AI", author: "A. Writer", pageCount: 2))
    }

    @Test func titleFallsBackToFileName() throws {
        let url = try FixturePDF.make(pages: [[FixtureLine("One", y: 700)]])
        let source = try PDFDocumentSource(url: url)
        #expect(source.metadata.title == url.deletingPathExtension().lastPathComponent)
        #expect(source.metadata.author == nil)
    }

    @Test func flattensNestedOutlineWithLevelsAndPages() throws {
        let pages = (0..<4).map { [FixtureLine("Page \($0)", y: 700)] }
        let url = try FixturePDF.make(pages: pages, outline: [
            FixtureOutline("Chapter 1", page: 0, children: [FixtureOutline("1.1 Tools", page: 1)]),
            FixtureOutline("Chapter 2", page: 3),
        ])
        let source = try PDFDocumentSource(url: url)
        #expect(source.outline == [
            OutlineEntry(title: "Chapter 1", level: 0, pageIndex: 0),
            OutlineEntry(title: "1.1 Tools", level: 1, pageIndex: 1),
            OutlineEntry(title: "Chapter 2", level: 0, pageIndex: 3),
        ])
    }

    @Test func outlineIsEmptyWhenThePDFHasNone() throws {
        let source = try PDFDocumentSource(url: FixturePDF.make(pages: [[FixtureLine("One", y: 700)]]))
        #expect(source.outline.isEmpty)
    }

    @Test func linesComeInReadingOrder() throws {
        let url = try FixturePDF.make(pages: [FixturePDF.paragraph(["First line", "Second line", "Third line"], top: 700)])
        let lines = try PDFDocumentSource(url: url).lines(onPage: 0)
        #expect(lines.map(\.text) == ["First line", "Second line", "Third line"])
        #expect(lines[0].rect.minY > lines[1].rect.minY)
    }

    @Test func imageOnlyPageHasNoLines() throws {
        let source = try PDFDocumentSource(url: FixturePDF.makeImageOnly())
        #expect(source.lines(onPage: 0).isEmpty)
    }

    @Test func pageOutOfRangeHasNoLines() throws {
        let source = try PDFDocumentSource(url: FixturePDF.make(pages: [[FixtureLine("One", y: 700)]]))
        #expect(source.lines(onPage: 5).isEmpty)
    }

    @Test func corruptFileThrowsCannotOpen() throws {
        let url = try FixturePDF.makeCorrupt()
        #expect(throws: DocumentError.cannotOpen(url)) { try PDFDocumentSource(url: url) }
    }

    @Test func lockedFileThrowsLocked() throws {
        let url = try FixturePDF.makeLocked()
        #expect(throws: DocumentError.locked(url)) { try PDFDocumentSource(url: url) }
    }

    @Test func errorsHaveUserMessages() {
        let url = URL(fileURLWithPath: "/tmp/a.pdf")
        #expect(DocumentError.locked(url).errorDescription == "This PDF has a password. Reader cannot open it.")
        #expect(DocumentError.cannotOpen(url).errorDescription == "This file is not a valid PDF, or it is damaged.")
    }
}
```

`Tests/DocumentKitTests/StructuralPathTests.swift`:

```swift
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
```

- [ ] **Step 4: Run the tests and make sure that they fail**

Run: `swift test --filter "PDFDocumentSourceTests|StructuralPathTests"`
Expected: the build fails with `cannot find 'PDFDocumentSource' in scope`.

- [ ] **Step 5: Write the implementation**

`Sources/DocumentKit/DocumentModels.swift`:

```swift
import CoreGraphics
import Foundation

public enum DocumentKind: String, Sendable {
    case pdf
}

public struct DocumentMetadata: Equatable, Sendable {
    public let title: String
    public let author: String?
    public let pageCount: Int

    public init(title: String, author: String?, pageCount: Int) {
        self.title = title
        self.author = author
        self.pageCount = pageCount
    }
}

public struct OutlineEntry: Equatable, Sendable {
    public let title: String
    /// 0 for a top-level entry (a chapter), 1 for its children, and so on.
    public let level: Int
    public let pageIndex: Int

    public init(title: String, level: Int, pageIndex: Int) {
        self.title = title
        self.level = level
        self.pageIndex = pageIndex
    }
}

/// One line of text on a page. `rect` is in page coordinates, with the origin at the bottom left.
public struct TextLine: Equatable, Sendable {
    public let text: String
    public let rect: CGRect

    public init(text: String, rect: CGRect) {
        self.text = text
        self.rect = rect
    }
}

public struct Paragraph: Equatable, Sendable {
    public let pageIndex: Int
    /// Position of the paragraph on its page, from 0.
    public let index: Int
    public let text: String
    public let rect: CGRect

    public init(pageIndex: Int, index: Int, text: String, rect: CGRect) {
        self.pageIndex = pageIndex
        self.index = index
        self.text = text
        self.rect = rect
    }
}

public enum DocumentError: Error, Equatable, LocalizedError {
    case cannotOpen(URL)
    case locked(URL)

    public var errorDescription: String? {
        switch self {
        case .cannotOpen: "This file is not a valid PDF, or it is damaged."
        case .locked: "This PDF has a password. Reader cannot open it."
        }
    }
}
```

`Sources/DocumentKit/DocumentSource.swift`:

```swift
/// A document that the app can show and read text from. Later milestones add Markdown and code sources.
public protocol DocumentSource {
    var kind: DocumentKind { get }
    var metadata: DocumentMetadata { get }
    var outline: [OutlineEntry] { get }
    func paragraphs(onPage pageIndex: Int) -> [Paragraph]
}
```

`Sources/DocumentKit/PDFDocumentSource.swift`:

```swift
import Foundation
import PDFKit

public final class PDFDocumentSource {
    public let url: URL
    public let pdf: PDFDocument

    public init(url: URL) throws {
        guard let pdf = PDFDocument(url: url) else { throw DocumentError.cannotOpen(url) }
        if pdf.isLocked { throw DocumentError.locked(url) }
        self.url = url
        self.pdf = pdf
    }

    public var kind: DocumentKind { .pdf }

    public var metadata: DocumentMetadata {
        let attributes = pdf.documentAttributes ?? [:]
        let title = (attributes[PDFDocumentAttribute.titleAttribute] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let author = (attributes[PDFDocumentAttribute.authorAttribute] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return DocumentMetadata(
            title: title?.isEmpty == false ? title! : url.deletingPathExtension().lastPathComponent,
            author: author?.isEmpty == false ? author : nil,
            pageCount: pdf.pageCount)
    }

    public var outline: [OutlineEntry] {
        guard let root = pdf.outlineRoot else { return [] }
        var entries: [OutlineEntry] = []
        func walk(_ node: PDFOutline, level: Int) {
            for childIndex in 0..<node.numberOfChildren {
                guard let child = node.child(at: childIndex) else { continue }
                let destination = child.destination ?? (child.action as? PDFActionGoTo)?.destination
                if let label = child.label, let page = destination?.page {
                    entries.append(OutlineEntry(title: label, level: level, pageIndex: pdf.index(for: page)))
                }
                walk(child, level: level + 1)
            }
        }
        walk(root, level: 0)
        return entries
    }

    public func lines(onPage pageIndex: Int) -> [TextLine] {
        guard pageIndex >= 0, pageIndex < pdf.pageCount,
              let page = pdf.page(at: pageIndex),
              let selection = page.selection(for: page.bounds(for: .mediaBox))
        else { return [] }
        return selection.selectionsByLine().compactMap { line in
            guard let text = line.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            return TextLine(text: text, rect: line.bounds(for: page))
        }
    }
}
```

`PDFDocumentSource` gets its `DocumentSource` conformance in Task 3, together with `paragraphs(onPage:)`.

`Sources/DocumentKit/StructuralPath.swift`:

```swift
/// Finds the chapter and section titles that contain a page, for example ["Chapter 4", "4.2 Tool use"].
public enum StructuralPath {
    public static func path(forPage page: Int, in outline: [OutlineEntry]) -> [String] {
        var stack: [OutlineEntry] = []
        for entry in outline where entry.pageIndex <= page {
            while let last = stack.last, last.level >= entry.level { stack.removeLast() }
            stack.append(entry)
        }
        return stack.map(\.title)
    }
}
```

- [ ] **Step 6: Run the tests and make sure that they pass**

Run: `swift test --filter "PDFDocumentSourceTests|StructuralPathTests"`
Expected: 14 tests pass. If `linesComeInReadingOrder` fails because PDFKit trims or splits the text in a different way, print `lines` and correct the fixture. Do not weaken the assertion.

- [ ] **Step 7: Commit**

```bash
git add Package.swift Sources Tests
git commit -m "feat: read PDF metadata, outline and text lines"
```

---

### Task 3: Paragraph detection

**Files:**
- Create: `Sources/DocumentKit/ParagraphGrouper.swift`
- Modify: `Sources/DocumentKit/PDFDocumentSource.swift` (add the `DocumentSource` conformance)
- Test: `Tests/DocumentKitTests/ParagraphGrouperTests.swift`, `Tests/DocumentKitTests/PDFParagraphTests.swift`

**Interfaces:**
- Consumes: `TextLine`, `Paragraph`, `PDFDocumentSource.lines(onPage:)` (Task 2).
- Produces:
  - `public enum ParagraphGrouper { static func group(_ lines: [TextLine]) -> [[TextLine]]; static func joinText(_ lines: [TextLine]) -> String }`
  - `extension PDFDocumentSource: DocumentSource` with `public func paragraphs(onPage: Int) -> [Paragraph]`

The rules in `group`. A line starts a new paragraph if one of these conditions is true:

1. The line is higher on the page than the previous line by more than one line height. This occurs at the next column or region.
2. The vertical space between the line and the previous line is more than 0.8 × the median line height.
3. The line height is different from the previous line height by more than 0.3 × the median. This means that the font size changed, for example at a heading.
4. The line starts more than 0.8 × the median line height to the right of the previous line. This is a first-line indent.
5. The previous line ends with `.`, `:`, `?` or `!`, and that line ends more than 3 × the median line height before the right edge of the current paragraph.

- [ ] **Step 1: Write the failing tests**

`Tests/DocumentKitTests/ParagraphGrouperTests.swift`:

```swift
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
```

`Tests/DocumentKitTests/PDFParagraphTests.swift`:

```swift
import Testing
import TestSupport
@testable import DocumentKit

struct PDFParagraphTests {
    @Test func headingAndIndentedParagraphsAreDetected() throws {
        var page = [FixtureLine("1.2 Tool use", y: 720, size: 18)]
        page += FixturePDF.paragraph(["An agent is a loop that", "calls a model and tools."], top: 690, firstIndent: 18)
        page += FixturePDF.paragraph(["The loop stops when the", "task is complete."], top: 662, firstIndent: 18)
        let source = try PDFDocumentSource(url: FixturePDF.make(pages: [page]))

        let paragraphs = source.paragraphs(onPage: 0)

        #expect(paragraphs.map(\.text) == [
            "1.2 Tool use",
            "An agent is a loop that calls a model and tools.",
            "The loop stops when the task is complete.",
        ])
        #expect(paragraphs.map(\.index) == [0, 1, 2])
        #expect(paragraphs.allSatisfy { $0.pageIndex == 0 && !$0.rect.isEmpty })
    }

    @Test func imageOnlyPageHasNoParagraphs() throws {
        let source = try PDFDocumentSource(url: FixturePDF.makeImageOnly())
        #expect(source.paragraphs(onPage: 0).isEmpty)
    }
}
```

- [ ] **Step 2: Run the tests and make sure that they fail**

Run: `swift test --filter "ParagraphGrouperTests|PDFParagraphTests"`
Expected: the build fails with `cannot find 'ParagraphGrouper' in scope`.

- [ ] **Step 3: Write the implementation**

`Sources/DocumentKit/ParagraphGrouper.swift`:

```swift
import CoreGraphics

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
            } else if result.hasSuffix("-"), let next = line.text.first, next.isLowercase {
                result.removeLast()
                result += line.text
            } else {
                result += " " + line.text
            }
        }
        return result
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
```

Add to the end of `Sources/DocumentKit/PDFDocumentSource.swift`:

```swift
extension PDFDocumentSource: DocumentSource {
    public func paragraphs(onPage pageIndex: Int) -> [Paragraph] {
        ParagraphGrouper.group(lines(onPage: pageIndex)).enumerated().map { index, group in
            Paragraph(
                pageIndex: pageIndex,
                index: index,
                text: ParagraphGrouper.joinText(group),
                rect: group.reduce(CGRect.null) { $0.union($1.rect) })
        }
    }
}
```

- [ ] **Step 4: Run the tests and make sure that they pass**

Run: `swift test --filter "ParagraphGrouperTests|PDFParagraphTests"`
Expected: 12 tests pass. If `headingAndIndentedParagraphsAreDetected` fails, print the line rects from `source.lines(onPage: 0)`. Then change the fixture spacing, not the rule thresholds, unless the real line heights show that a threshold is wrong for normal text.

- [ ] **Step 5: Commit**

```bash
git add Sources Tests
git commit -m "feat: detect paragraphs from PDF line layout"
```

---

### Task 4: Chapter splitter for the text files

**Files:**
- Create: `Sources/DocumentKit/ChapterSplitter.swift`
- Test: `Tests/DocumentKitTests/ChapterSplitterTests.swift`

**Interfaces:**
- Consumes: `OutlineEntry` (Task 2).
- Produces:
  - `public struct TextChunk: Equatable, Sendable { fileName: String; title: String; pages: Range<Int> }`
  - `public enum ChapterSplitter { static func chunks(outline: [OutlineEntry], pageCount: Int, pagesPerChunk: Int = 20) -> [TextChunk]; static func slug(_ text: String) -> String }`

The rules:

- Each top-level outline entry (level 0) starts a chunk. The chunk ends where the next top-level entry starts.
- If the first chapter does not start at page 0, a "Front matter" chunk comes first.
- If the outline has no top-level entries, the chunks are fixed blocks of 20 pages, with the title "Pages A–B".
- The file name is `NN-<slug>.md`, where NN is the chunk number, starting at 01.

- [ ] **Step 1: Write the failing tests**

`Tests/DocumentKitTests/ChapterSplitterTests.swift`:

```swift
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
```

- [ ] **Step 2: Run the tests and make sure that they fail**

Run: `swift test --filter ChapterSplitterTests`
Expected: the build fails with `cannot find 'ChapterSplitter' in scope`.

- [ ] **Step 3: Write the implementation**

`Sources/DocumentKit/ChapterSplitter.swift`:

```swift
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
    public static func chunks(outline: [OutlineEntry], pageCount: Int, pagesPerChunk: Int = 20) -> [TextChunk] {
        guard pageCount > 0 else { return [] }
        var starts: [(title: String, page: Int)] = []
        let topLevel = outline
            .filter { $0.level == 0 && $0.pageIndex >= 0 && $0.pageIndex < pageCount }
            .enumerated()
            .sorted { ($0.element.pageIndex, $0.offset) < ($1.element.pageIndex, $1.offset) }
            .map(\.element)
        for entry in topLevel where starts.last?.page != entry.pageIndex {
            starts.append((entry.title, entry.pageIndex))
        }
        if starts.isEmpty {
            starts = stride(from: 0, to: pageCount, by: pagesPerChunk).map { start in
                ("Pages \(start + 1)–\(min(start + pagesPerChunk, pageCount))", start)
            }
        } else if let first = starts.first, first.page > 0 {
            starts.insert(("Front matter", 0), at: 0)
        }
        return starts.enumerated().map { number, start in
            let end = number + 1 < starts.count ? starts[number + 1].page : pageCount
            let fileName = String(format: "%02d-%@.md", number + 1, slug(start.title))
            return TextChunk(fileName: fileName, title: start.title, pages: start.page..<end)
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
```

- [ ] **Step 4: Run the tests and make sure that they pass**

Run: `swift test --filter ChapterSplitterTests`
Expected: 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources Tests
git commit -m "feat: split documents into chapter text chunks"
```

---

### Task 5: Workspace database with document record and FTS5 text

**Files:**
- Modify: `Package.swift` (add GRDB, `WorkspaceStore`, `WorkspaceStoreTests`)
- Create: `Sources/WorkspaceStore/AppPaths.swift`, `Sources/WorkspaceStore/DocumentRecord.swift`, `Sources/WorkspaceStore/WorkspaceDatabase.swift`, `Sources/WorkspaceStore/WorkspaceDatabase+Text.swift`, `Sources/WorkspaceStore/FTSQuery.swift`
- Test: `Tests/WorkspaceStoreTests/WorkspaceDatabaseTests.swift`, `Tests/WorkspaceStoreTests/FTSQueryTests.swift`

**Interfaces:**
- Consumes: `Paragraph` (Task 2).
- Produces:
  - `public struct AppPaths: Sendable { init(root: URL); static func standard() throws -> AppPaths; var root: URL; var globalIndexFile: URL; func workspaceFolder(id: String) -> URL }`
  - `public struct DocumentRecord: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord` with `id, kind, contentHash, lastPath, title, author, pageCount, lastPage, indexedPages, textExported`
  - `public final class WorkspaceDatabase: Sendable` with `init(path: URL) throws`, `static func inMemory() throws -> WorkspaceDatabase`, `insertDocument(_:)`, `document(id:)`, `document(contentHash:)`, `updateLastPath(_:documentID:)`, `setLastPage(_:documentID:)`, `setTextExported(documentID:)`
  - Text: `storeParagraphs(_ paragraphs: [Paragraph], page: Int, documentID: String)`, `paragraphs(documentID: String, pages: Range<Int>) -> [StoredParagraph]`, `searchText(_ query: String, limit: Int = 10) -> [TextHit]`
  - `public struct StoredParagraph: Equatable, Sendable { pageIndex: Int; paragraphIndex: Int; text: String }`
  - `public struct TextHit: Equatable, Sendable { documentID: String; pageIndex: Int; paragraphIndex: Int; text: String }`
  - `public enum FTSQuery { static func anyTerm(_ text: String) -> String? }`

- [ ] **Step 1: Add the targets**

Replace `Package.swift` with:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Reader",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(name: "DocumentKit"),
        .target(name: "WorkspaceStore", dependencies: [
            "DocumentKit",
            .product(name: "GRDB", package: "GRDB.swift"),
        ]),
        .target(name: "TestSupport", path: "Tests/TestSupport"),
        .testTarget(name: "DocumentKitTests", dependencies: ["DocumentKit", "TestSupport"]),
        .testTarget(name: "WorkspaceStoreTests", dependencies: ["WorkspaceStore", "DocumentKit", "TestSupport"]),
    ]
)
```

Run: `swift package resolve`
Expected: GRDB.swift resolves to a 7.x version.

- [ ] **Step 2: Write the failing tests**

`Tests/WorkspaceStoreTests/FTSQueryTests.swift`:

```swift
import Testing
@testable import WorkspaceStore

struct FTSQueryTests {
    @Test func quotesEachWordAndJoinsWithOr() {
        #expect(FTSQuery.anyTerm("multi-agent \"tool\" (use)") == "\"multi\" OR \"agent\" OR \"tool\" OR \"use\"")
    }

    @Test func operatorsBecomePlainWords() {
        #expect(FTSQuery.anyTerm("AND NOT*") == "\"AND\" OR \"NOT\"")
    }

    @Test func noWordsGiveNil() {
        #expect(FTSQuery.anyTerm("--- () \"\"") == nil)
    }
}
```

`Tests/WorkspaceStoreTests/WorkspaceDatabaseTests.swift`:

```swift
import CoreGraphics
import Foundation
import Testing
import DocumentKit
@testable import WorkspaceStore

func makeDocument(id: String = "doc-1", hash: String = "hash-1", pageCount: Int = 3) -> DocumentRecord {
    DocumentRecord(id: id, kind: "pdf", contentHash: hash, lastPath: "/tmp/book.pdf", title: "Book",
                   author: nil, pageCount: pageCount, lastPage: 0, indexedPages: 0, textExported: false)
}

func paragraph(_ page: Int, _ index: Int, _ text: String) -> Paragraph {
    Paragraph(pageIndex: page, index: index, text: text, rect: CGRect(x: 0, y: 0, width: 10, height: 10))
}

struct WorkspaceDatabaseTests {
    @Test func insertsAndFindsDocumentByIDAndHash() throws {
        let database = try WorkspaceDatabase.inMemory()
        try database.insertDocument(makeDocument())
        #expect(try database.document(id: "doc-1") == makeDocument())
        #expect(try database.document(contentHash: "hash-1")?.id == "doc-1")
        #expect(try database.document(contentHash: "other") == nil)
    }

    @Test func updatesLastPageLastPathAndTextExported() throws {
        let database = try WorkspaceDatabase.inMemory()
        try database.insertDocument(makeDocument())
        try database.setLastPage(2, documentID: "doc-1")
        try database.updateLastPath("/new/book.pdf", documentID: "doc-1")
        try database.setTextExported(documentID: "doc-1")
        let stored = try #require(try database.document(id: "doc-1"))
        #expect(stored.lastPage == 2)
        #expect(stored.lastPath == "/new/book.pdf")
        #expect(stored.textExported)
    }

    @Test func storingAPageAgainReplacesItsParagraphs() throws {
        let database = try WorkspaceDatabase.inMemory()
        try database.insertDocument(makeDocument())
        try database.storeParagraphs([paragraph(0, 0, "old text")], page: 0, documentID: "doc-1")
        try database.storeParagraphs([paragraph(0, 0, "new text"), paragraph(0, 1, "second")], page: 0, documentID: "doc-1")
        #expect(try database.paragraphs(documentID: "doc-1", pages: 0..<1).map(\.text) == ["new text", "second"])
        #expect(try database.document(id: "doc-1")?.indexedPages == 1)
    }

    @Test func paragraphsComeInPageOrder() throws {
        let database = try WorkspaceDatabase.inMemory()
        try database.insertDocument(makeDocument())
        try database.storeParagraphs([paragraph(1, 0, "page two")], page: 1, documentID: "doc-1")
        try database.storeParagraphs([paragraph(0, 1, "b"), paragraph(0, 0, "a")], page: 0, documentID: "doc-1")
        #expect(try database.paragraphs(documentID: "doc-1", pages: 0..<2).map(\.text) == ["a", "b", "page two"])
        #expect(try database.paragraphs(documentID: "doc-1", pages: 1..<2) == [StoredParagraph(pageIndex: 1, paragraphIndex: 0, text: "page two")])
    }

    @Test func searchFindsStemmedWordsWithPages() throws {
        let database = try WorkspaceDatabase.inMemory()
        try database.insertDocument(makeDocument())
        try database.storeParagraphs([paragraph(0, 0, "Agents call tools in a loop.")], page: 0, documentID: "doc-1")
        try database.storeParagraphs([paragraph(2, 0, "Planning is hard.")], page: 2, documentID: "doc-1")
        let hits = try database.searchText("agent loops")
        #expect(hits == [TextHit(documentID: "doc-1", pageIndex: 0, paragraphIndex: 0, text: "Agents call tools in a loop.")])
    }

    @Test func searchWithFTSSyntaxCharactersDoesNotThrow() throws {
        let database = try WorkspaceDatabase.inMemory()
        try database.insertDocument(makeDocument())
        try database.storeParagraphs([paragraph(0, 0, "A multi-agent system.")], page: 0, documentID: "doc-1")
        #expect(try database.searchText("\"multi-agent\" AND (system*").count == 1)
        #expect(try database.searchText("---").isEmpty)
    }

    @Test func fileDatabaseKeepsDataAfterReopen() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        try WorkspaceDatabase(path: path).insertDocument(makeDocument())
        #expect(try WorkspaceDatabase(path: path).document(id: "doc-1") != nil)
    }

    @Test func appPathsArePlacedUnderRoot() {
        let paths = AppPaths(root: URL(fileURLWithPath: "/tmp/ReaderTest"))
        #expect(paths.globalIndexFile.path == "/tmp/ReaderTest/index.sqlite")
        #expect(paths.workspaceFolder(id: "abc").path == "/tmp/ReaderTest/workspaces/abc")
    }
}
```

- [ ] **Step 3: Run the tests and make sure that they fail**

Run: `swift test --filter "WorkspaceDatabaseTests|FTSQueryTests"`
Expected: the build fails with `cannot find 'WorkspaceDatabase' in scope`.

- [ ] **Step 4: Write the implementation**

`Sources/WorkspaceStore/AppPaths.swift`:

```swift
import Foundation

/// File locations of the app. Tests pass a temporary root.
public struct AppPaths: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public static func standard() throws -> AppPaths {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return AppPaths(root: base.appendingPathComponent("Reader", isDirectory: true))
    }

    public var globalIndexFile: URL { root.appendingPathComponent("index.sqlite") }

    public func workspaceFolder(id: String) -> URL {
        root.appendingPathComponent("workspaces", isDirectory: true).appendingPathComponent(id, isDirectory: true)
    }
}
```

`Sources/WorkspaceStore/DocumentRecord.swift`:

```swift
import GRDB

public struct DocumentRecord: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "document"
    public static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy { .convertFromSnakeCase }
    public static var databaseColumnEncodingStrategy: DatabaseColumnEncodingStrategy { .convertToSnakeCase }

    public var id: String
    public var kind: String
    public var contentHash: String
    public var lastPath: String
    public var title: String
    public var author: String?
    public var pageCount: Int
    public var lastPage: Int
    /// Pages 0..<indexedPages are in the full-text index.
    public var indexedPages: Int
    /// True when the `text/` files are written.
    public var textExported: Bool

    public init(id: String, kind: String, contentHash: String, lastPath: String, title: String, author: String?,
                pageCount: Int, lastPage: Int, indexedPages: Int, textExported: Bool) {
        self.id = id
        self.kind = kind
        self.contentHash = contentHash
        self.lastPath = lastPath
        self.title = title
        self.author = author
        self.pageCount = pageCount
        self.lastPage = lastPage
        self.indexedPages = indexedPages
        self.textExported = textExported
    }
}
```

`Sources/WorkspaceStore/WorkspaceDatabase.swift`:

```swift
import Foundation
import GRDB

/// The SQLite database of one workspace.
public final class WorkspaceDatabase: Sendable {
    let queue: DatabaseQueue

    public convenience init(path: URL) throws {
        try self.init(queue: DatabaseQueue(path: path.path))
    }

    public static func inMemory() throws -> WorkspaceDatabase {
        try WorkspaceDatabase(queue: DatabaseQueue())
    }

    private init(queue: DatabaseQueue) throws {
        self.queue = queue
        try Self.migrator.migrate(queue)
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1-document") { db in
            try db.execute(sql: """
                CREATE TABLE document (
                    id TEXT PRIMARY KEY,
                    kind TEXT NOT NULL,
                    content_hash TEXT NOT NULL UNIQUE,
                    last_path TEXT NOT NULL,
                    title TEXT NOT NULL,
                    author TEXT,
                    page_count INTEGER NOT NULL,
                    last_page INTEGER NOT NULL DEFAULT 0,
                    indexed_pages INTEGER NOT NULL DEFAULT 0,
                    text_exported INTEGER NOT NULL DEFAULT 0
                );
                CREATE VIRTUAL TABLE document_text USING fts5(
                    document_id UNINDEXED,
                    page_index UNINDEXED,
                    paragraph_index UNINDEXED,
                    text,
                    tokenize = 'porter unicode61'
                );
                """)
        }
        return migrator
    }

    public func insertDocument(_ document: DocumentRecord) throws {
        try queue.write { try document.insert($0) }
    }

    public func document(id: String) throws -> DocumentRecord? {
        try queue.read { try DocumentRecord.fetchOne($0, key: id) }
    }

    public func document(contentHash: String) throws -> DocumentRecord? {
        try queue.read { try DocumentRecord.filter(Column("content_hash") == contentHash).fetchOne($0) }
    }

    public func updateLastPath(_ path: String, documentID: String) throws {
        try queue.write { try $0.execute(sql: "UPDATE document SET last_path = ? WHERE id = ?", arguments: [path, documentID]) }
    }

    public func setLastPage(_ page: Int, documentID: String) throws {
        try queue.write { try $0.execute(sql: "UPDATE document SET last_page = ? WHERE id = ?", arguments: [page, documentID]) }
    }

    public func setTextExported(documentID: String) throws {
        try queue.write { try $0.execute(sql: "UPDATE document SET text_exported = 1 WHERE id = ?", arguments: [documentID]) }
    }
}
```

`Sources/WorkspaceStore/FTSQuery.swift`:

```swift
import Foundation

/// Makes FTS5 MATCH expressions from free text. Each word is quoted, so FTS5 syntax in the input cannot cause an error.
public enum FTSQuery {
    public static func anyTerm(_ text: String) -> String? {
        let words = text.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        guard !words.isEmpty else { return nil }
        return words.map { "\"\($0)\"" }.joined(separator: " OR ")
    }
}
```

`Sources/WorkspaceStore/WorkspaceDatabase+Text.swift`:

```swift
import DocumentKit
import GRDB

public struct StoredParagraph: Equatable, Sendable {
    public let pageIndex: Int
    public let paragraphIndex: Int
    public let text: String

    public init(pageIndex: Int, paragraphIndex: Int, text: String) {
        self.pageIndex = pageIndex
        self.paragraphIndex = paragraphIndex
        self.text = text
    }
}

public struct TextHit: Equatable, Sendable {
    public let documentID: String
    public let pageIndex: Int
    public let paragraphIndex: Int
    public let text: String

    public init(documentID: String, pageIndex: Int, paragraphIndex: Int, text: String) {
        self.documentID = documentID
        self.pageIndex = pageIndex
        self.paragraphIndex = paragraphIndex
        self.text = text
    }
}

extension WorkspaceDatabase {
    /// Replaces the paragraphs of one page and marks the pages up to it as indexed, in one transaction.
    public func storeParagraphs(_ paragraphs: [Paragraph], page: Int, documentID: String) throws {
        try queue.write { db in
            try db.execute(sql: "DELETE FROM document_text WHERE document_id = ? AND page_index = ?",
                           arguments: [documentID, page])
            for paragraph in paragraphs {
                try db.execute(
                    sql: "INSERT INTO document_text (document_id, page_index, paragraph_index, text) VALUES (?, ?, ?, ?)",
                    arguments: [documentID, page, paragraph.index, paragraph.text])
            }
            try db.execute(sql: "UPDATE document SET indexed_pages = MAX(indexed_pages, ?) WHERE id = ?",
                           arguments: [page + 1, documentID])
        }
    }

    public func paragraphs(documentID: String, pages: Range<Int>) throws -> [StoredParagraph] {
        try queue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT page_index, paragraph_index, text FROM document_text
                WHERE document_id = ? AND page_index >= ? AND page_index < ?
                ORDER BY page_index, paragraph_index
                """, arguments: [documentID, pages.lowerBound, pages.upperBound])
            .map { StoredParagraph(pageIndex: $0["page_index"], paragraphIndex: $0["paragraph_index"], text: $0["text"]) }
        }
    }

    /// Finds paragraphs that contain any word of the query, best match first.
    public func searchText(_ query: String, limit: Int = 10) throws -> [TextHit] {
        guard let match = FTSQuery.anyTerm(query) else { return [] }
        return try queue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT document_id, page_index, paragraph_index, text FROM document_text
                WHERE document_text MATCH ? ORDER BY bm25(document_text) LIMIT ?
                """, arguments: [match, limit])
            .map {
                TextHit(documentID: $0["document_id"], pageIndex: $0["page_index"],
                        paragraphIndex: $0["paragraph_index"], text: $0["text"])
            }
        }
    }
}
```

- [ ] **Step 5: Run the tests and make sure that they pass**

Run: `swift test --filter "WorkspaceDatabaseTests|FTSQueryTests"`
Expected: 11 tests pass.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Package.resolved Sources Tests
git commit -m "feat: add workspace database with full-text paragraphs"
```

---

### Task 6: Global index and WorkspaceManager

**Files:**
- Create: `Sources/WorkspaceStore/GlobalIndex.swift`, `Sources/WorkspaceStore/WorkspaceManager.swift`
- Test: `Tests/WorkspaceStoreTests/GlobalIndexTests.swift`, `Tests/WorkspaceStoreTests/WorkspaceManagerTests.swift`

**Interfaces:**
- Consumes: `ContentHash`, `PDFDocumentSource`, `DocumentKind` (Tasks 1 and 2). `AppPaths`, `WorkspaceDatabase`, `DocumentRecord` (Task 5).
- Produces:
  - `public struct RecentDocument: Equatable, Sendable { contentHash; workspaceID; title; lastPath; lastOpenedAt: Date }`
  - `public final class GlobalIndex: Sendable { init(path: URL) throws; workspaceID(contentHash:) throws -> String?; recordOpen(contentHash:workspaceID:title:path:at:) throws; recents(limit:) throws -> [RecentDocument] }`
  - `public struct OpenedWorkspace: Sendable { id: String; folder: URL; textFolder: URL; database: WorkspaceDatabase; document: DocumentRecord }`
  - `public final class WorkspaceManager: Sendable { init(paths: AppPaths) throws; open(pdfAt: URL) throws -> OpenedWorkspace; recents() throws -> [RecentDocument] }`

- [ ] **Step 1: Write the failing tests**

`Tests/WorkspaceStoreTests/GlobalIndexTests.swift`:

```swift
import Foundation
import Testing
@testable import WorkspaceStore

struct GlobalIndexTests {
    private func makeIndex() throws -> GlobalIndex {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return try GlobalIndex(path: folder.appendingPathComponent("index.sqlite"))
    }

    @Test func recordsAndFindsWorkspaceByHash() throws {
        let index = try makeIndex()
        try index.recordOpen(contentHash: "h1", workspaceID: "w1", title: "Book", path: "/a.pdf")
        #expect(try index.workspaceID(contentHash: "h1") == "w1")
        #expect(try index.workspaceID(contentHash: "h2") == nil)
    }

    @Test func recentsAreNewestFirstAndUpdatedOnReopen() throws {
        let index = try makeIndex()
        try index.recordOpen(contentHash: "h1", workspaceID: "w1", title: "One", path: "/1.pdf", at: Date(timeIntervalSince1970: 100))
        try index.recordOpen(contentHash: "h2", workspaceID: "w2", title: "Two", path: "/2.pdf", at: Date(timeIntervalSince1970: 200))
        try index.recordOpen(contentHash: "h1", workspaceID: "w1", title: "One", path: "/moved/1.pdf", at: Date(timeIntervalSince1970: 300))
        let recents = try index.recents()
        #expect(recents.map(\.contentHash) == ["h1", "h2"])
        #expect(recents[0].lastPath == "/moved/1.pdf")
    }
}
```

`Tests/WorkspaceStoreTests/WorkspaceManagerTests.swift`:

```swift
import Foundation
import Testing
import DocumentKit
import TestSupport
@testable import WorkspaceStore

struct WorkspaceManagerTests {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    private func makeManager() throws -> WorkspaceManager {
        try WorkspaceManager(paths: AppPaths(root: root))
    }

    private func samplePDF() throws -> URL {
        try FixturePDF.make(pages: [[FixtureLine("Hello", y: 700)], [FixtureLine("World", y: 700)]], title: "Sample")
    }

    @Test func firstOpenMakesWorkspaceFolderDatabaseAndRecord() throws {
        let manager = try makeManager()
        let workspace = try manager.open(pdfAt: samplePDF())
        #expect(FileManager.default.fileExists(atPath: workspace.folder.appendingPathComponent("workspace.sqlite").path))
        #expect(FileManager.default.fileExists(atPath: workspace.textFolder.path))
        #expect(workspace.document.title == "Sample")
        #expect(workspace.document.pageCount == 2)
        #expect(workspace.document.kind == DocumentKind.pdf.rawValue)
        #expect(try manager.recents().map(\.workspaceID) == [workspace.id])
    }

    @Test func reopenGivesSameWorkspaceAndDatabase() throws {
        let manager = try makeManager()
        let url = try samplePDF()
        let first = try manager.open(pdfAt: url)
        let second = try manager.open(pdfAt: url)
        #expect(first.id == second.id)
        #expect(first.document.id == second.document.id)
        #expect(first.database === second.database)
    }

    @Test func movedCopyOpensSameWorkspaceAndUpdatesPath() throws {
        let manager = try makeManager()
        let url = try samplePDF()
        let first = try manager.open(pdfAt: url)
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        try FileManager.default.copyItem(at: url, to: copy)
        let second = try manager.open(pdfAt: copy)
        #expect(second.id == first.id)
        #expect(second.document.lastPath == copy.path)
        #expect(try second.database.document(id: second.document.id)?.lastPath == copy.path)
    }

    @Test func newManagerFindsExistingWorkspace() throws {
        let url = try samplePDF()
        let first = try makeManager().open(pdfAt: url)
        let second = try makeManager().open(pdfAt: url)
        #expect(first.id == second.id)
    }

    @Test func corruptFileThrowsAndMakesNoWorkspace() throws {
        let manager = try makeManager()
        let url = try FixturePDF.makeCorrupt()
        #expect(throws: DocumentError.cannotOpen(url)) { try manager.open(pdfAt: url) }
        let workspaces = root.appendingPathComponent("workspaces")
        #expect((try? FileManager.default.contentsOfDirectory(atPath: workspaces.path))?.isEmpty ?? true)
    }

    @Test func lockedFileThrowsLocked() throws {
        let url = try FixturePDF.makeLocked()
        #expect(throws: DocumentError.locked(url)) { try makeManager().open(pdfAt: url) }
    }
}
```

- [ ] **Step 2: Run the tests and make sure that they fail**

Run: `swift test --filter "GlobalIndexTests|WorkspaceManagerTests"`
Expected: the build fails with `cannot find 'GlobalIndex' in scope`.

- [ ] **Step 3: Write the implementation**

`Sources/WorkspaceStore/GlobalIndex.swift`:

```swift
import Foundation
import GRDB

public struct RecentDocument: Equatable, Sendable {
    public let contentHash: String
    public let workspaceID: String
    public let title: String
    public let lastPath: String
    public let lastOpenedAt: Date
}

/// Maps each document hash to its workspace, and keeps the recent documents list.
public final class GlobalIndex: Sendable {
    private let queue: DatabaseQueue

    public init(path: URL) throws {
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        queue = try DatabaseQueue(path: path.path)
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1-index") { db in
            try db.execute(sql: """
                CREATE TABLE workspace_index (
                    content_hash TEXT PRIMARY KEY,
                    workspace_id TEXT NOT NULL,
                    title TEXT NOT NULL,
                    last_path TEXT NOT NULL,
                    last_opened_at DATETIME NOT NULL
                );
                """)
        }
        try migrator.migrate(queue)
    }

    public func workspaceID(contentHash: String) throws -> String? {
        try queue.read {
            try String.fetchOne($0, sql: "SELECT workspace_id FROM workspace_index WHERE content_hash = ?", arguments: [contentHash])
        }
    }

    public func recordOpen(contentHash: String, workspaceID: String, title: String, path: String, at date: Date = Date()) throws {
        try queue.write {
            try $0.execute(sql: """
                INSERT INTO workspace_index (content_hash, workspace_id, title, last_path, last_opened_at)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(content_hash) DO UPDATE SET
                    title = excluded.title, last_path = excluded.last_path, last_opened_at = excluded.last_opened_at
                """, arguments: [contentHash, workspaceID, title, path, date])
        }
    }

    public func recents(limit: Int = 20) throws -> [RecentDocument] {
        try queue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM workspace_index ORDER BY last_opened_at DESC LIMIT ?", arguments: [limit])
                .map {
                    RecentDocument(contentHash: $0["content_hash"], workspaceID: $0["workspace_id"], title: $0["title"],
                                   lastPath: $0["last_path"], lastOpenedAt: $0["last_opened_at"])
                }
        }
    }
}
```

`Sources/WorkspaceStore/WorkspaceManager.swift`:

```swift
import DocumentKit
import Foundation
import Synchronization

public struct OpenedWorkspace: Sendable {
    public let id: String
    public let folder: URL
    public let database: WorkspaceDatabase
    public let document: DocumentRecord

    public var textFolder: URL { folder.appendingPathComponent("text", isDirectory: true) }
}

/// Opens the workspace of a document, and makes it when it does not exist.
public final class WorkspaceManager: Sendable {
    public let paths: AppPaths
    private let index: GlobalIndex
    /// One database instance for each workspace, so two windows never write through two connections.
    private let databases = Mutex<[String: WorkspaceDatabase]>([:])

    public init(paths: AppPaths) throws {
        self.paths = paths
        try FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
        index = try GlobalIndex(path: paths.globalIndexFile)
    }

    /// Reads the PDF before it writes anything, so a bad file makes no workspace.
    public func open(pdfAt url: URL) throws -> OpenedWorkspace {
        let source = try PDFDocumentSource(url: url)
        let hash = try ContentHash.sha256(of: url)
        let workspaceID = try index.workspaceID(contentHash: hash) ?? UUID().uuidString
        let folder = paths.workspaceFolder(id: workspaceID)
        try FileManager.default.createDirectory(
            at: folder.appendingPathComponent("text", isDirectory: true), withIntermediateDirectories: true)
        let database = try database(workspaceID: workspaceID, folder: folder)

        var document: DocumentRecord
        if let existing = try database.document(contentHash: hash) {
            document = existing
            if existing.lastPath != url.path {
                try database.updateLastPath(url.path, documentID: existing.id)
                document.lastPath = url.path
            }
        } else {
            let metadata = source.metadata
            document = DocumentRecord(
                id: UUID().uuidString, kind: DocumentKind.pdf.rawValue, contentHash: hash, lastPath: url.path,
                title: metadata.title, author: metadata.author, pageCount: metadata.pageCount,
                lastPage: 0, indexedPages: 0, textExported: false)
            try database.insertDocument(document)
        }
        try index.recordOpen(contentHash: hash, workspaceID: workspaceID, title: document.title, path: url.path)
        return OpenedWorkspace(id: workspaceID, folder: folder, database: database, document: document)
    }

    public func recents() throws -> [RecentDocument] {
        try index.recents()
    }

    private func database(workspaceID: String, folder: URL) throws -> WorkspaceDatabase {
        try databases.withLock { cache in
            if let cached = cache[workspaceID] { return cached }
            let database = try WorkspaceDatabase(path: folder.appendingPathComponent("workspace.sqlite"))
            cache[workspaceID] = database
            return database
        }
    }
}
```

- [ ] **Step 4: Run the tests and make sure that they pass**

Run: `swift test --filter "GlobalIndexTests|WorkspaceManagerTests"`
Expected: 8 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources Tests
git commit -m "feat: open or make a workspace for each PDF"
```

---

### Task 7: Document indexer with resume and text export

**Files:**
- Create: `Sources/WorkspaceStore/DocumentIndexer.swift`
- Test: `Tests/WorkspaceStoreTests/DocumentIndexerTests.swift`

**Interfaces:**
- Consumes: `PDFDocumentSource.paragraphs(onPage:)`, `.outline` (Tasks 2 and 3). `ChapterSplitter.chunks` (Task 4). `WorkspaceDatabase.storeParagraphs`, `.paragraphs`, `.setTextExported`, `.document(id:)` (Task 5). `OpenedWorkspace` (Task 6).
- Produces:
  - `public struct IndexProgress: Equatable, Sendable { indexedPages: Int; pageCount: Int; var isComplete: Bool }`
  - `public enum DocumentIndexer { static func run(workspace: OpenedWorkspace, pdfURL: URL, progress: @Sendable (IndexProgress) -> Void = { _ in }) throws }`. It throws `CancellationError` when the current task is cancelled.

Text file format (one file for each `TextChunk`):

```
# <chunk title>

[p. 3]

<paragraph>

<paragraph>

[p. 4]

<paragraph>
```

A page with no paragraphs gets no `[p. N]` marker.

- [ ] **Step 1: Write the failing tests**

`Tests/WorkspaceStoreTests/DocumentIndexerTests.swift`:

```swift
import Foundation
import Synchronization
import Testing
import TestSupport
@testable import WorkspaceStore

struct DocumentIndexerTests {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    private func threePagePDF() throws -> URL {
        try FixturePDF.make(pages: [
            FixturePDF.paragraph(["Agents use tools."], top: 700),
            FixturePDF.paragraph(["Planning needs memory."], top: 700),
            FixturePDF.paragraph(["Reflection improves answers."], top: 700),
        ], outline: [FixtureOutline("Basics", page: 0), FixtureOutline("Advanced", page: 2)])
    }

    @Test func indexesAllPagesAndReportsProgress() throws {
        let url = try threePagePDF()
        let workspace = try WorkspaceManager(paths: AppPaths(root: root)).open(pdfAt: url)
        let reports = Mutex<[IndexProgress]>([])
        try DocumentIndexer.run(workspace: workspace, pdfURL: url) { progress in reports.withLock { $0.append(progress) } }

        let document = try #require(try workspace.database.document(id: workspace.document.id))
        #expect(document.indexedPages == 3)
        #expect(document.textExported)
        #expect(reports.withLock { $0.last } == IndexProgress(indexedPages: 3, pageCount: 3))
        #expect(try workspace.database.searchText("memory").map(\.pageIndex) == [1])
    }

    @Test func writesOneTextFileForEachChapter() throws {
        let url = try threePagePDF()
        let workspace = try WorkspaceManager(paths: AppPaths(root: root)).open(pdfAt: url)
        try DocumentIndexer.run(workspace: workspace, pdfURL: url)

        let files = try FileManager.default.contentsOfDirectory(atPath: workspace.textFolder.path).sorted()
        #expect(files == ["01-basics.md", "02-advanced.md"])
        let basics = try String(contentsOf: workspace.textFolder.appendingPathComponent("01-basics.md"), encoding: .utf8)
        #expect(basics == "# Basics\n\n[p. 1]\n\nAgents use tools.\n\n[p. 2]\n\nPlanning needs memory.\n")
    }

    @Test func interruptedRunContinuesWithoutDuplicates() async throws {
        let url = try threePagePDF()
        let workspace = try WorkspaceManager(paths: AppPaths(root: root)).open(pdfAt: url)
        let task = Task {
            try DocumentIndexer.run(workspace: workspace, pdfURL: url) { progress in
                if progress.indexedPages == 1 { withUnsafeCurrentTask { $0?.cancel() } }
            }
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try workspace.database.document(id: workspace.document.id)?.indexedPages == 1)

        try DocumentIndexer.run(workspace: workspace, pdfURL: url)

        #expect(try workspace.database.document(id: workspace.document.id)?.indexedPages == 3)
        #expect(try workspace.database.paragraphs(documentID: workspace.document.id, pages: 0..<3).count == 3)
    }

    @Test func secondRunAfterCompletionChangesNothing() throws {
        let url = try threePagePDF()
        let workspace = try WorkspaceManager(paths: AppPaths(root: root)).open(pdfAt: url)
        try DocumentIndexer.run(workspace: workspace, pdfURL: url)
        try DocumentIndexer.run(workspace: workspace, pdfURL: url)
        #expect(try workspace.database.paragraphs(documentID: workspace.document.id, pages: 0..<3).count == 3)
    }

    @Test func imageOnlyPDFCompletesWithNoParagraphs() throws {
        let url = try FixturePDF.makeImageOnly()
        let workspace = try WorkspaceManager(paths: AppPaths(root: root)).open(pdfAt: url)
        try DocumentIndexer.run(workspace: workspace, pdfURL: url)
        let document = try #require(try workspace.database.document(id: workspace.document.id))
        #expect(document.indexedPages == 1)
        #expect(document.textExported)
        let file = try String(contentsOf: workspace.textFolder.appendingPathComponent("01-pages-1-1.md"), encoding: .utf8)
        #expect(file == "# Pages 1–1\n")
    }
}
```

- [ ] **Step 2: Run the tests and make sure that they fail**

Run: `swift test --filter DocumentIndexerTests`
Expected: the build fails with `cannot find 'DocumentIndexer' in scope`.

- [ ] **Step 3: Write the implementation**

`Sources/WorkspaceStore/DocumentIndexer.swift`:

```swift
import DocumentKit
import Foundation

public struct IndexProgress: Equatable, Sendable {
    public let indexedPages: Int
    public let pageCount: Int

    public init(indexedPages: Int, pageCount: Int) {
        self.indexedPages = indexedPages
        self.pageCount = pageCount
    }

    public var isComplete: Bool { indexedPages >= pageCount }
}

/// Puts the document text into the full-text index and writes the `text/` files.
/// It continues from the last indexed page, so it is safe to run again after an interruption.
public enum DocumentIndexer {
    public static func run(
        workspace: OpenedWorkspace, pdfURL: URL, progress: @Sendable (IndexProgress) -> Void = { _ in }
    ) throws {
        let database = workspace.database
        guard let document = try database.document(id: workspace.document.id) else { return }
        if document.indexedPages >= document.pageCount && document.textExported {
            progress(IndexProgress(indexedPages: document.pageCount, pageCount: document.pageCount))
            return
        }
        let source = try PDFDocumentSource(url: pdfURL)
        for page in document.indexedPages..<max(document.indexedPages, document.pageCount) {
            try Task.checkCancellation()
            try database.storeParagraphs(source.paragraphs(onPage: page), page: page, documentID: document.id)
            progress(IndexProgress(indexedPages: page + 1, pageCount: document.pageCount))
        }
        try Task.checkCancellation()
        try exportText(source: source, database: database, documentID: document.id,
                       pageCount: document.pageCount, folder: workspace.textFolder)
        try database.setTextExported(documentID: document.id)
    }

    static func exportText(source: PDFDocumentSource, database: WorkspaceDatabase, documentID: String,
                           pageCount: Int, folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for old in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        where old.pathExtension == "md" {
            try FileManager.default.removeItem(at: old)
        }
        for chunk in ChapterSplitter.chunks(outline: source.outline, pageCount: pageCount) {
            let byPage = Dictionary(grouping: try database.paragraphs(documentID: documentID, pages: chunk.pages), by: \.pageIndex)
            var body = "# \(chunk.title)\n"
            for page in chunk.pages {
                guard let paragraphs = byPage[page], !paragraphs.isEmpty else { continue }
                body += "\n[p. \(page + 1)]\n\n" + paragraphs.map(\.text).joined(separator: "\n\n") + "\n"
            }
            try body.write(to: folder.appendingPathComponent(chunk.fileName), atomically: true, encoding: .utf8)
        }
    }
}
```

- [ ] **Step 4: Run the tests and make sure that they pass**

Run: `swift test --filter DocumentIndexerTests`
Expected: 5 tests pass.

- [ ] **Step 5: Run all tests**

Run: `swift test`
Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources Tests
git commit -m "feat: index document pages and export chapter text files"
```

---

### Task 8: ReaderUI models and views

**Files:**
- Modify: `Package.swift` (add `ReaderUI`, `ReaderUITests`)
- Create: `Sources/ReaderUI/ReaderModel.swift`, `Sources/ReaderUI/Library.swift`, `Sources/ReaderUI/PDFKitView.swift`, `Sources/ReaderUI/ReaderView.swift`
- Test: `Tests/ReaderUITests/ReaderModelTests.swift`, `Tests/ReaderUITests/LibraryTests.swift`

**Interfaces:**
- Consumes: `PDFDocumentSource`, `OutlineEntry`, `StructuralPath` (DocumentKit). `OpenedWorkspace`, `WorkspaceManager`, `AppPaths`, `RecentDocument`, `DocumentIndexer`, `IndexProgress` (WorkspaceStore).
- Produces:
  - `@MainActor @Observable public final class ReaderModel` with `init(workspace: OpenedWorkspace, pdfURL: URL) throws`, `pdf: PDFDocument`, `outline: [OutlineEntry]`, `currentPage: Int`, `structuralPath: [String]`, `indexProgress: IndexProgress`, `searchResults: [SearchResult]`, `navigationRequest: NavigationRequest?`, `lastError: String?`, `pageDidChange(to:)`, `go(toPage:)`, `search(_:)`, `show(_:)`, `startIndexing()`, `stopIndexing()`
  - `public struct SearchResult: Identifiable { id: UUID; pageIndex: Int; snippet: String; selection: PDFSelection }`
  - `public struct NavigationRequest: Equatable { id: UUID; pageIndex: Int; selection: PDFSelection? }`
  - `@MainActor @Observable public final class Library` with `init(paths: AppPaths? = nil)`, `recents: [RecentDocument]`, `startupError: String?`, `refreshRecents()`, `openModel(for: URL) async throws -> ReaderModel`
  - `public struct ReaderView: View { init(model: ReaderModel) }`

- [ ] **Step 1: Add the targets**

In `Package.swift`, add these to `targets`:

```swift
        .target(name: "ReaderUI", dependencies: ["DocumentKit", "WorkspaceStore"]),
        .testTarget(name: "ReaderUITests", dependencies: ["ReaderUI", "WorkspaceStore", "DocumentKit", "TestSupport"]),
```

- [ ] **Step 2: Write the failing tests**

`Tests/ReaderUITests/ReaderModelTests.swift`:

```swift
import Foundation
import Testing
import TestSupport
import WorkspaceStore
@testable import ReaderUI

@MainActor
struct ReaderModelTests {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    private func book() throws -> URL {
        try FixturePDF.make(pages: [
            [FixtureLine("Introduction text", y: 700)],
            [FixtureLine("The orchestrator assigns work", y: 700)],
            [FixtureLine("Summary", y: 700)],
        ], outline: [FixtureOutline("Part One", page: 0, children: [FixtureOutline("Orchestration", page: 1)])])
    }

    private func openModel(_ url: URL) throws -> ReaderModel {
        let workspace = try WorkspaceManager(paths: AppPaths(root: root)).open(pdfAt: url)
        return try ReaderModel(workspace: workspace, pdfURL: url)
    }

    @Test func newDocumentStartsAtFirstPage() throws {
        let model = try openModel(book())
        #expect(model.currentPage == 0)
        #expect(model.navigationRequest?.pageIndex == 0)
    }

    @Test func pageChangeIsSavedAndRestoredOnReopen() throws {
        let url = try book()
        let model = try openModel(url)
        model.pageDidChange(to: 2)
        #expect(model.currentPage == 2)

        let reopened = try openModel(url)
        #expect(reopened.currentPage == 2)
        #expect(reopened.navigationRequest?.pageIndex == 2)
    }

    @Test func structuralPathFollowsCurrentPage() throws {
        let model = try openModel(book())
        model.pageDidChange(to: 1)
        #expect(model.structuralPath == ["Part One", "Orchestration"])
    }

    @Test func goToPageMakesNewNavigationRequest() throws {
        let model = try openModel(book())
        let before = model.navigationRequest
        model.go(toPage: 2)
        #expect(model.navigationRequest?.pageIndex == 2)
        #expect(model.navigationRequest != before)
    }

    @Test func searchFindsPagesAndShowNavigates() throws {
        let model = try openModel(book())
        model.search("orchestrator")
        #expect(model.searchResults.map(\.pageIndex) == [1])
        #expect(model.searchResults[0].snippet.contains("orchestrator"))
        model.show(model.searchResults[0])
        #expect(model.navigationRequest?.pageIndex == 1)
        #expect(model.navigationRequest?.selection != nil)
    }

    @Test func shortOrEmptySearchClearsResults() throws {
        let model = try openModel(book())
        model.search("orchestrator")
        model.search(" o ")
        #expect(model.searchResults.isEmpty)
    }

    @Test func indexingCompletesAndUpdatesProgress() async throws {
        let model = try openModel(book())
        model.startIndexing()
        for _ in 0..<200 where !model.indexProgress.isComplete {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(model.indexProgress == IndexProgress(indexedPages: 3, pageCount: 3))
        #expect(model.lastError == nil)
    }
}
```

`Tests/ReaderUITests/LibraryTests.swift`:

```swift
import DocumentKit
import Foundation
import Testing
import TestSupport
import WorkspaceStore
@testable import ReaderUI

@MainActor
struct LibraryTests {
    let paths = AppPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))

    @Test func openingADocumentAddsItToRecents() async throws {
        let library = Library(paths: paths)
        #expect(library.startupError == nil)
        #expect(library.recents.isEmpty)
        let url = try FixturePDF.make(pages: [[FixtureLine("Text", y: 700)]], title: "Recent Book")
        let model = try await library.openModel(for: url)
        #expect(model.pdf.pageCount == 1)
        #expect(library.recents.map(\.title) == ["Recent Book"])
    }

    @Test func openingADamagedFileThrows() async throws {
        let library = Library(paths: paths)
        let url = try FixturePDF.makeCorrupt()
        await #expect(throws: DocumentError.cannotOpen(url)) { try await library.openModel(for: url) }
    }
}
```

- [ ] **Step 3: Run the tests and make sure that they fail**

Run: `swift test --filter "ReaderModelTests|LibraryTests"`
Expected: the build fails with `cannot find 'ReaderModel' in scope`.

- [ ] **Step 4: Write the models**

`Sources/ReaderUI/ReaderModel.swift`:

```swift
import DocumentKit
import Foundation
import Observation
import PDFKit
import WorkspaceStore

public struct SearchResult: Identifiable {
    public let id = UUID()
    public let pageIndex: Int
    public let snippet: String
    public let selection: PDFSelection
}

/// A request to move the PDF view. Each request has a new ID, so the same page can be requested again.
public struct NavigationRequest: Equatable {
    public let id = UUID()
    public let pageIndex: Int
    public let selection: PDFSelection?

    public static func == (lhs: NavigationRequest, rhs: NavigationRequest) -> Bool { lhs.id == rhs.id }
}

/// State and actions of one reader window.
@MainActor
@Observable
public final class ReaderModel {
    public let workspace: OpenedWorkspace
    public let pdfURL: URL
    public let pdf: PDFDocument
    public let outline: [OutlineEntry]
    public private(set) var currentPage: Int
    public private(set) var indexProgress: IndexProgress
    public private(set) var searchResults: [SearchResult] = []
    public private(set) var navigationRequest: NavigationRequest?
    public private(set) var lastError: String?
    @ObservationIgnored private var indexTask: Task<Void, Never>?

    public init(workspace: OpenedWorkspace, pdfURL: URL) throws {
        let source = try PDFDocumentSource(url: pdfURL)
        let stored = try workspace.database.document(id: workspace.document.id) ?? workspace.document
        let lastPage = min(max(stored.lastPage, 0), max(source.pdf.pageCount - 1, 0))
        self.workspace = workspace
        self.pdfURL = pdfURL
        self.pdf = source.pdf
        self.outline = source.outline
        self.currentPage = lastPage
        self.indexProgress = IndexProgress(indexedPages: stored.indexedPages, pageCount: stored.pageCount)
        self.navigationRequest = NavigationRequest(pageIndex: lastPage, selection: nil)
    }

    public var structuralPath: [String] { StructuralPath.path(forPage: currentPage, in: outline) }

    public func pageDidChange(to pageIndex: Int) {
        guard pageIndex != currentPage else { return }
        currentPage = pageIndex
        do {
            try workspace.database.setLastPage(pageIndex, documentID: workspace.document.id)
        } catch {
            lastError = "Reader cannot save the current page: \(error.localizedDescription)"
        }
    }

    public func go(toPage pageIndex: Int) {
        navigationRequest = NavigationRequest(pageIndex: pageIndex, selection: nil)
    }

    public func search(_ text: String) {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            searchResults = []
            return
        }
        searchResults = pdf.findString(query, withOptions: .caseInsensitive).prefix(200).compactMap { selection in
            guard let page = selection.pages.first, let context = selection.copy() as? PDFSelection else { return nil }
            context.extend(atStart: 40)
            context.extend(atEnd: 40)
            let snippet = (context.string ?? query).replacingOccurrences(of: "\n", with: " ")
            return SearchResult(pageIndex: pdf.index(for: page), snippet: snippet, selection: selection)
        }
    }

    public func show(_ result: SearchResult) {
        navigationRequest = NavigationRequest(pageIndex: result.pageIndex, selection: result.selection)
    }

    public func startIndexing() {
        guard indexTask == nil else { return }
        let workspace = self.workspace
        let pdfURL = self.pdfURL
        let pageCount = workspace.document.pageCount
        indexTask = Task.detached(priority: .utility) { [weak self] in
            do {
                try DocumentIndexer.run(workspace: workspace, pdfURL: pdfURL) { [weak self] progress in
                    Task { @MainActor [weak self] in self?.indexProgress = progress }
                }
                // Progress tasks can arrive in a different order, so the final state is set last.
                await MainActor.run { [weak self] in
                    self?.indexProgress = IndexProgress(indexedPages: pageCount, pageCount: pageCount)
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run { [weak self] in
                    self?.lastError = "Reader cannot index this document: \(error.localizedDescription)"
                }
            }
        }
    }

    public func stopIndexing() {
        indexTask?.cancel()
        indexTask = nil
    }
}
```

`Sources/ReaderUI/Library.swift`:

```swift
import Foundation
import Observation
import WorkspaceStore

/// Opens workspaces for the windows and keeps the recent documents list.
@MainActor
@Observable
public final class Library {
    public private(set) var recents: [RecentDocument] = []
    public private(set) var startupError: String?
    @ObservationIgnored private let manager: WorkspaceManager?

    public init(paths: AppPaths? = nil) {
        var manager: WorkspaceManager?
        var startupError: String?
        do {
            manager = try WorkspaceManager(paths: paths ?? AppPaths.standard())
        } catch {
            startupError = "Reader cannot open its data folder: \(error.localizedDescription)"
        }
        self.manager = manager
        self.startupError = startupError
        refreshRecents()
    }

    public func refreshRecents() {
        recents = (try? manager?.recents()) ?? []
    }

    public func openModel(for url: URL) async throws -> ReaderModel {
        guard let manager else { throw CocoaError(.fileReadUnknown) }
        let workspace = try await Task.detached(priority: .userInitiated) { try manager.open(pdfAt: url) }.value
        refreshRecents()
        return try ReaderModel(workspace: workspace, pdfURL: url)
    }
}
```

- [ ] **Step 5: Run the tests and make sure that they pass**

Run: `swift test --filter "ReaderModelTests|LibraryTests"`
Expected: 9 tests pass.

- [ ] **Step 6: Write the views**

These views have no unit tests. Task 9 checks them manually.

`Sources/ReaderUI/PDFKitView.swift`:

```swift
import PDFKit
import SwiftUI

/// Shows the PDF, reports page changes to the model, and follows its navigation requests.
struct PDFKitView: NSViewRepresentable {
    let model: ReaderModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displaysPageBreaks = true
        view.document = model.pdf
        context.coordinator.observe(view)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        context.coordinator.apply(model.navigationRequest, to: view)
    }

    @MainActor
    final class Coordinator: NSObject {
        let model: ReaderModel
        private var handledRequestID: UUID?

        init(model: ReaderModel) {
            self.model = model
        }

        func observe(_ view: PDFView) {
            NotificationCenter.default.addObserver(
                self, selector: #selector(pageChanged(_:)), name: .PDFViewPageChanged, object: view)
        }

        @objc private func pageChanged(_ notification: Notification) {
            guard let view = notification.object as? PDFView,
                  let page = view.currentPage, let document = view.document else { return }
            model.pageDidChange(to: document.index(for: page))
        }

        func apply(_ request: NavigationRequest?, to view: PDFView) {
            guard let request, request.id != handledRequestID,
                  let page = view.document?.page(at: request.pageIndex) else { return }
            handledRequestID = request.id
            view.layoutDocumentView()
            if let selection = request.selection {
                view.setCurrentSelection(selection, animate: true)
                view.go(to: selection)
            } else {
                view.go(to: page)
            }
        }
    }
}
```

`Sources/ReaderUI/ReaderView.swift`:

```swift
import SwiftUI
import WorkspaceStore

/// The reader window: outline and search results on the left, the PDF on the right.
public struct ReaderView: View {
    let model: ReaderModel
    @State private var query = ""

    public init(model: ReaderModel) {
        self.model = model
    }

    public var body: some View {
        NavigationSplitView {
            ReaderSidebar(model: model)
                .navigationSplitViewColumnWidth(min: 200, ideal: 260)
        } detail: {
            PDFKitView(model: model)
                .navigationTitle(model.workspace.document.title)
                .navigationSubtitle(model.structuralPath.joined(separator: " › "))
        }
        .searchable(text: $query, placement: .sidebar, prompt: "Search in document")
        .onSubmit(of: .search) { model.search(query) }
        .onChange(of: query) { if query.isEmpty { model.search("") } }
        .toolbar {
            ToolbarItem { IndexStatusView(progress: model.indexProgress, error: model.lastError) }
        }
        .task { model.startIndexing() }
        .onDisappear { model.stopIndexing() }
    }
}

struct ReaderSidebar: View {
    let model: ReaderModel

    var body: some View {
        List {
            if !model.searchResults.isEmpty {
                Section("Results (\(model.searchResults.count))") {
                    ForEach(model.searchResults) { result in
                        Button { model.show(result) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.snippet).lineLimit(2)
                                Text("Page \(result.pageIndex + 1)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Section("Contents") {
                if model.outline.isEmpty {
                    Text("This document has no outline.").foregroundStyle(.secondary)
                }
                ForEach(Array(model.outline.enumerated()), id: \.offset) { _, entry in
                    Button(entry.title) { model.go(toPage: entry.pageIndex) }
                        .buttonStyle(.plain)
                        .padding(.leading, CGFloat(entry.level) * 12)
                        .lineLimit(1)
                }
            }
        }
    }
}

struct IndexStatusView: View {
    let progress: IndexProgress
    let error: String?

    var body: some View {
        if let error {
            Label(error, systemImage: "exclamationmark.triangle").labelStyle(.iconOnly).help(error)
        } else if !progress.isComplete {
            HStack(spacing: 6) {
                ProgressView(value: Double(progress.indexedPages), total: Double(max(progress.pageCount, 1)))
                    .frame(width: 80)
                Text("Indexing \(progress.indexedPages)/\(progress.pageCount)").font(.caption).monospacedDigit()
            }
        }
    }
}
```

- [ ] **Step 7: Build and run all tests**

Run: `swift build && swift test`
Expected: the build succeeds and all tests pass.

- [ ] **Step 8: Commit**

```bash
git add Package.swift Sources Tests
git commit -m "feat: add reader model, library and reader views"
```

---

### Task 9: App entry, app bundle script and manual check

**Files:**
- Modify: `Package.swift` (add the `Reader` executable product and the `ReaderApp` target)
- Create: `Sources/ReaderApp/ReaderApp.swift`, `Sources/ReaderApp/LibraryView.swift`, `Sources/ReaderApp/ReaderWindow.swift`, `scripts/make-app.sh`

**Interfaces:**
- Consumes: `Library`, `ReaderModel`, `ReaderView` (Task 8). `RecentDocument` (Task 6). `DocumentError.errorDescription` (Task 2).
- Produces: the `Reader` executable and `build/Reader.app`.

- [ ] **Step 1: Add the product and the target**

In `Package.swift`, add after `platforms:`:

```swift
    products: [
        .executable(name: "Reader", targets: ["ReaderApp"]),
    ],
```

Add to `targets`:

```swift
        .executableTarget(name: "ReaderApp", dependencies: ["ReaderUI", "WorkspaceStore"]),
```

- [ ] **Step 2: Write the app files**

`Sources/ReaderApp/ReaderApp.swift`:

```swift
import AppKit
import ReaderUI
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when the binary runs outside an .app bundle (`swift run`).
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }
}

@main
struct ReaderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var library = Library()

    var body: some Scene {
        Window("Reader", id: "library") {
            LibraryView(library: library)
        }
        .commands {
            CommandGroup(replacing: .newItem) { OpenPDFCommand() }
        }

        WindowGroup(id: "reader", for: URL.self) { $url in
            if let url {
                ReaderWindow(url: url, library: library)
            }
        }
    }
}

/// Shows the system open panel for one PDF.
@MainActor
func choosePDF() -> URL? {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.pdf]
    panel.allowsMultipleSelection = false
    return panel.runModal() == .OK ? panel.url : nil
}

struct OpenPDFCommand: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open PDF…") {
            if let url = choosePDF() { openWindow(id: "reader", value: url) }
        }
        .keyboardShortcut("o")
    }
}
```

`Sources/ReaderApp/LibraryView.swift`:

```swift
import ReaderUI
import SwiftUI

/// The start window: an open button and the recent documents.
struct LibraryView: View {
    let library: Library
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let error = library.startupError {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
            }
            Button("Open PDF…") {
                if let url = choosePDF() { openWindow(id: "reader", value: url) }
            }
            .buttonStyle(.borderedProminent)
            Text("Recent").font(.headline)
            if library.recents.isEmpty {
                Text("No documents yet.").foregroundStyle(.secondary)
            }
            List(library.recents, id: \.contentHash) { recent in
                Button {
                    openWindow(id: "reader", value: URL(fileURLWithPath: recent.lastPath))
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(recent.title)
                        Text(recent.lastPath).font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 360)
        .onAppear { library.refreshRecents() }
    }
}
```

`Sources/ReaderApp/ReaderWindow.swift`:

```swift
import ReaderUI
import SwiftUI

/// Opens the workspace for a URL, then shows the reader.
struct ReaderWindow: View {
    let url: URL
    let library: Library
    @State private var model: ReaderModel?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let model {
                ReaderView(model: model)
            } else if let errorMessage {
                ContentUnavailableView("Reader cannot open this file", systemImage: "exclamationmark.triangle",
                                       description: Text(errorMessage))
            } else {
                ProgressView("Opening…")
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .task(id: url) {
            do {
                model = try await library.openModel(for: url)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
```

- [ ] **Step 3: Write the bundle script**

`scripts/make-app.sh`:

```bash
#!/usr/bin/env bash
# Builds build/Reader.app from the release binary, with an ad-hoc signature.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product Reader
BIN="$(swift build -c release --show-bin-path)/Reader"
APP="build/Reader.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Reader"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Reader</string>
    <key>CFBundleIdentifier</key><string>io.github.reader.Reader</string>
    <key>CFBundleName</key><string>Reader</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP"
```

Run: `chmod +x scripts/make-app.sh`

- [ ] **Step 4: Build and run all tests**

Run: `swift build && swift test`
Expected: the build succeeds and all tests pass.

- [ ] **Step 5: Build the app bundle**

Run: `scripts/make-app.sh`
Expected: the last line is `Built build/Reader.app`.

- [ ] **Step 6: Do the manual check with the real book**

Run: `open build/Reader.app`. Then do these checks with `/Users/hc/Documents/books/2606.24937v2.pdf` (636 pages), and write down the result of each check:

1. Click **Open PDF…** and select the book. The first page shows in less than 2 seconds.
2. The sidebar shows the outline. Click a chapter. The PDF goes to that chapter, and the window subtitle shows the chapter path.
3. The toolbar shows "Indexing N/636", and N increases. You can scroll and read while N increases.
4. Search for `agentic`. The results show page numbers. Click a result. The PDF goes to that result and selects it.
5. Go to page 50 and quit the app (⌘Q) before indexing is complete. Open the app and the book again. The PDF opens at page 50, and indexing continues from the page where it stopped.
6. Run `ls ~/Library/Application\ Support/Reader/workspaces/*/text/`. There is one `.md` file for each chapter. Open one file and make sure that it contains `[p. N]` markers and readable paragraphs.
7. Copy the book to `/tmp/book-copy.pdf` and open the copy. It opens at the same page, which proves that it uses the same workspace.
8. Open a damaged file. For example, run `echo hi > /tmp/bad.pdf` and open `/tmp/bad.pdf`. The window shows "This file is not a valid PDF, or it is damaged."
9. Optional: open a two-column arXiv paper and look at its `text/` files. If the paragraphs from the two columns are mixed, record this as a known problem for M2 (paragraph selection).

If a check fails, use superpowers:systematic-debugging, fix the problem, and add a test in the task that owns the code.

- [ ] **Step 7: Commit**

```bash
git add Package.swift Sources scripts
git commit -m "feat: add Reader app entry, windows and app bundle script"
```
