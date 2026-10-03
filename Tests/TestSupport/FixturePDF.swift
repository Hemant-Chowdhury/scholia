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
