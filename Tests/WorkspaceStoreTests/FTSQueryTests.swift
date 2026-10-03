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
