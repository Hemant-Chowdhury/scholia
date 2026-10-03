import Foundation

/// Makes FTS5 MATCH expressions from free text. Each word is quoted, so FTS5 syntax in the input cannot cause an error.
public enum FTSQuery {
    public static func anyTerm(_ text: String) -> String? {
        let words = text.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        guard !words.isEmpty else { return nil }
        return words.map { "\"\($0)\"" }.joined(separator: " OR ")
    }
}
