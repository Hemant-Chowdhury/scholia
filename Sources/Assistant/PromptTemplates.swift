import Foundation

/// The texts of the prompt that the reader can change in Settings. An empty field uses the default text.
public struct PromptTemplates: Sendable, Equatable, Codable {
    public static let defaultsKey = "promptTemplates"

    /// The role and rules at the start of each first prompt.
    public var rules: String
    public var explain: String
    public var simplify: String
    public var define: String
    /// Comes before the reader's own question.
    public var ask: String
    public var simpler: String
    public var example: String
    public var why: String
    public var connect: String

    public static let standard = PromptTemplates(
        rules: """
            You are a reading tutor in the Reader app. You help the reader understand a book, one passage at a time.

            Rules:
            - Explain in the context of this book and of the reader's background.
            - Be clear and concrete. Use short paragraphs, examples and analogies. Use Markdown.
            - When you use content from the book, cite the page as [p. N].
            - If the passage depends on an earlier part of the book, say which part.
            - Do not change files and do not run commands.
            """,
        explain: "Explain the selected text so that I understand it fully. Start with a one-sentence summary. Then explain it step by step, define each technical term, and give an example.",
        simplify: "Explain the selected text in the simplest words, for a smart beginner. Use one concrete everyday example. Keep it short.",
        define: "List each technical term in the selected text. For each term, give a short definition in the context of this book, one line each.",
        ask: "Answer my question about the selected text:",
        simpler: QuickFollowUp.simpler.prompt,
        example: QuickFollowUp.example.prompt,
        why: QuickFollowUp.why.prompt,
        connect: QuickFollowUp.connect.prompt)

    public init(rules: String, explain: String, simplify: String, define: String, ask: String,
                simpler: String, example: String, why: String, connect: String) {
        self.rules = rules
        self.explain = explain
        self.simplify = simplify
        self.define = define
        self.ask = ask
        self.simpler = simpler
        self.example = example
        self.why = why
        self.connect = connect
    }

    /// Fields that are missing in saved data get the default text.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let standard = Self.standard
        func value(_ key: CodingKeys, _ fallback: String) -> String {
            (try? container.decodeIfPresent(String.self, forKey: key)) ?? fallback
        }
        self.init(rules: value(.rules, standard.rules), explain: value(.explain, standard.explain),
                  simplify: value(.simplify, standard.simplify), define: value(.define, standard.define),
                  ask: value(.ask, standard.ask), simpler: value(.simpler, standard.simpler),
                  example: value(.example, standard.example), why: value(.why, standard.why),
                  connect: value(.connect, standard.connect))
    }

    public static func load(from defaults: UserDefaults) -> PromptTemplates {
        guard let data = defaults.data(forKey: defaultsKey),
              let templates = try? JSONDecoder().decode(PromptTemplates.self, from: data) else { return .standard }
        return templates
    }

    public func save(to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.defaultsKey) }
    }

    /// A field, or its default when the field is empty.
    func resolved(_ keyPath: KeyPath<PromptTemplates, String>) -> String {
        let text = self[keyPath: keyPath].trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? Self.standard[keyPath: keyPath] : text
    }

    public func text(for followUp: QuickFollowUp) -> String {
        switch followUp {
        case .simpler: resolved(\.simpler)
        case .example: resolved(\.example)
        case .why: resolved(\.why)
        case .connect: resolved(\.connect)
        }
    }
}
