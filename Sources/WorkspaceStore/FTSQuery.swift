import Foundation

/// Makes FTS5 MATCH expressions from free text. Each word is quoted, so FTS5 syntax in the input cannot cause an error.
public enum FTSQuery {
    static let maxTerms = 30
    static let stopWords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "but", "by", "for", "from", "has", "have", "in", "into", "is", "it",
        "its", "not", "of", "on", "or", "that", "the", "their", "then", "there", "these", "they", "this", "to", "was",
        "we", "were", "which", "will", "with", "you", "can", "each", "than", "also", "more", "such", "when", "what",
    ]

    /// Matches any word of the text. A long text (for example, a long selection) keeps only its 30 longest
    /// words that are not stop words, so the search stays fast.
    public static func anyTerm(_ text: String) -> String? {
        var seen = Set<String>()
        var words = text.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
        if words.count > maxTerms {
            words = words.filter { !stopWords.contains($0.lowercased()) }
            let longest = Set(words.enumerated().sorted { ($0.element.count, -$0.offset) > ($1.element.count, -$1.offset) }
                .prefix(maxTerms).map(\.offset))
            words = words.enumerated().filter { longest.contains($0.offset) }.map(\.element)
        }
        guard !words.isEmpty else { return nil }
        return words.map { "\"\($0)\"" }.joined(separator: " OR ")
    }
}
