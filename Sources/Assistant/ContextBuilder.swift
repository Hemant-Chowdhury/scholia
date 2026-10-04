import DocumentKit
import Foundation

public enum ReadingAction: String, Sendable, CaseIterable {
    case explain, simplify, define, ask, followup

    public var title: String {
        switch self {
        case .explain: "Explain"
        case .simplify: "Simplify"
        case .define: "Define"
        case .ask: "Ask"
        case .followup: "Follow-up"
        }
    }
}

public enum QuickFollowUp: String, Sendable, CaseIterable {
    case simpler, example, why, connect

    public var title: String {
        switch self {
        case .simpler: "Simpler"
        case .example: "Give an example"
        case .why: "Why does this matter?"
        case .connect: "Connect to earlier"
        }
    }

    public var prompt: String {
        switch self {
        case .simpler: "Explain that again in simpler words, with an everyday example."
        case .example: "Give me one more concrete example."
        case .why: "Why does this matter in this book? Connect it to the main topic of the chapter."
        case .connect: "Connect this to earlier parts of the book. Cite the pages."
        }
    }
}

public struct BookInfo: Sendable, Equatable {
    public let title: String
    public let author: String?

    public init(title: String, author: String?) {
        self.title = title
        self.author = author
    }
}

public struct RelatedThread: Sendable, Equatable {
    public let question: String
    public let answerStart: String
    /// Page index (from 0).
    public let page: Int

    public init(question: String, answerStart: String, page: Int) {
        self.question = question
        self.answerStart = answerStart
        self.page = page
    }
}

public struct RelatedPassage: Sendable, Equatable {
    /// Page index (from 0).
    public let page: Int
    public let text: String

    public init(page: Int, text: String) {
        self.page = page
        self.text = text
    }
}

public struct PromptInput: Sendable {
    public let book: BookInfo
    public let aboutMe: String
    public let selection: SelectionContext
    public let action: ReadingAction
    public let question: String?
    public let relatedThreads: [RelatedThread]
    public let relatedPassages: [RelatedPassage]
    public let templates: PromptTemplates

    public init(book: BookInfo, aboutMe: String, selection: SelectionContext, action: ReadingAction, question: String?,
                relatedThreads: [RelatedThread], relatedPassages: [RelatedPassage], templates: PromptTemplates = .standard) {
        self.templates = templates
        self.book = book
        self.aboutMe = aboutMe
        self.selection = selection
        self.action = action
        self.question = question
        self.relatedThreads = relatedThreads
        self.relatedPassages = relatedPassages
    }
}

/// Makes the prompt that the agent receives (spec 5.2). Each part has a size limit in characters.
public enum ContextBuilder {
    static let aboutMeLimit = 2000
    static let selectionLimit = 6000
    static let paragraphLimit = 1200
    static let passageLimit = 600
    static let maxPassages = 4
    static let maxThreads = 3

    public static func firstPrompt(_ input: PromptInput) -> String {
        (context(input) + ["Task: " + instruction(input.action, question: input.question, templates: input.templates)])
            .joined(separator: "\n\n")
    }

    /// For a new session in an existing thread (after a restart, or after a change of agent or model).
    public static func resumePrompt(_ input: PromptInput, transcript: [(role: String, content: String)]) -> String {
        let lines = transcript.suffix(8).map { ($0.role == "user" ? "Reader: " : "Tutor: ") + clip($0.content, 1500) }
        return (context(input) + [
            "This continues an earlier conversation about the selected text:",
            lines.joined(separator: "\n\n"),
            "Now answer this: " + (input.question ?? ""),
        ]).joined(separator: "\n\n")
    }

    public static func instruction(_ action: ReadingAction, question: String?, templates: PromptTemplates = .standard) -> String {
        switch action {
        case .explain: templates.resolved(\.explain)
        case .simplify: templates.resolved(\.simplify)
        case .define: templates.resolved(\.define)
        case .ask, .followup: templates.resolved(\.ask) + " " + (question ?? "")
        }
    }

    private static func context(_ input: PromptInput) -> [String] {
        let selection = input.selection
        var parts = [input.templates.resolved(\.rules)]
        let author = input.book.author.map { " by \($0)" } ?? ""
        let path = selection.structuralPath.isEmpty ? "" : selection.structuralPath.joined(separator: " › ") + " "
        parts.append("Book: \"\(input.book.title)\"\(author)\nLocation: \(path)(page \(selection.pageIndex + 1))")
        let about = input.aboutMe.trimmingCharacters(in: .whitespacesAndNewlines)
        if !about.isEmpty { parts.append("About the reader:\n" + clip(about, aboutMeLimit)) }
        parts.append("The full text of the book is in the folder `text/` in your working directory (one Markdown file for each chapter, with [p. N] page markers). Read it when you need more context.")
        let threads = input.relatedThreads.prefix(maxThreads)
        if !threads.isEmpty {
            parts.append("Earlier questions about this book:\n" + threads.map {
                "- (p. \($0.page + 1)) Q: \(clip($0.question, 300)) A: \(clip($0.answerStart, 400))"
            }.joined(separator: "\n"))
        }
        let passages = input.relatedPassages.prefix(maxPassages)
        if !passages.isEmpty {
            parts.append("Related passages from the book:\n" + passages.map { "[p. \($0.page + 1)] \(clip($0.text, passageLimit))" }
                .joined(separator: "\n"))
        }
        if !selection.before.isEmpty {
            parts.append("Text before the selection:\n" + selection.before.map { clip($0, paragraphLimit) }.joined(separator: "\n\n"))
        }
        if let containing = selection.containing {
            parts.append("Paragraph with the selection:\n" + clip(containing, paragraphLimit))
        }
        parts.append("Selected text (page \(selection.pageIndex + 1)):\n\"\"\"\n\(clip(selection.text, selectionLimit))\n\"\"\"")
        if !selection.after.isEmpty {
            parts.append("Text after the selection:\n" + selection.after.map { clip($0, paragraphLimit) }.joined(separator: "\n\n"))
        }
        return parts
    }

    static func clip(_ text: String, _ limit: Int) -> String {
        text.count <= limit ? text : String(text.prefix(limit)) + "…"
    }
}
