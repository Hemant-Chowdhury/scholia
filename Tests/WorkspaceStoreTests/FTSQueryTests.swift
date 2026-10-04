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

struct FTSQueryLimitTests {
    @Test func longTextGivesAtMostThirtyTermsWithoutStopWords() throws {
        let words = (0..<500).map { "word\($0)" } + Array(repeating: "the", count: 50)
        let query = try #require(FTSQuery.anyTerm(words.joined(separator: " ")))
        let terms = query.components(separatedBy: " OR ")
        #expect(terms.count == 30)
        #expect(!terms.contains("\"the\""))
    }

    @Test func repeatedWordsAreUsedOnce() {
        #expect(FTSQuery.anyTerm("loop loop Loop agent") == "\"loop\" OR \"agent\"")
    }
}
