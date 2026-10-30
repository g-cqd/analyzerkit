import AnalyzerCLI
import Testing

/// ADR-0026: a search command exits 0 when it matched, 1 when it ran and matched nothing, and keeps ADR-0018's other
/// statuses (roadmap 0056).
@Suite struct SearchOutcomeTests {
    @Test func `no match is status 1, the value a finding has, under its own name`() {
        #expect(ExitStatus.noMatch.rawValue == 1)
        #expect(ExitStatus.noMatch == .findings)
        // Not a case of its own: the sysexits list every consumer reads is unchanged.
        #expect(ExitStatus.allCases.map(\.rawValue) == [0, 1, 64, 70, 74, 78])
    }

    @Test func `a search that matched succeeds and one that matched nothing does not`() {
        #expect(SearchOutcome.status(matchCount: 3) == .success)
        #expect(SearchOutcome.status(matchCount: 0) == .noMatch)
    }

    @Test func `a search that could read none of the files it found is an internal failure`() {
        #expect(SearchOutcome.status(matchCount: 0, analyzedFileCount: 0, skippedFileCount: 2) == .internalFailure)
        #expect(SearchOutcome.status(matchCount: 0, analyzedFileCount: 1, skippedFileCount: 2) == .noMatch)
        // Matches from the index store with no file read are matches.
        #expect(SearchOutcome.status(matchCount: 4, analyzedFileCount: 0, skippedFileCount: 0) == .success)
    }
}
