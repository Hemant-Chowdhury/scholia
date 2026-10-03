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
    case notFound(URL)
    case cannotOpen(URL)
    case locked(URL)

    public var errorDescription: String? {
        switch self {
        case .notFound(let url):
            "Reader cannot find this file at \(url.path). If you moved it, open it again from its new location."
        case .cannotOpen: "This file is not a valid PDF, or it is damaged."
        case .locked: "This PDF has a password. Reader cannot open it."
        }
    }
}
