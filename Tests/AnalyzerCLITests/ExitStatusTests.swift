import AnalyzerCLI
import ProjectModel
import Testing

@Suite struct ExitStatusTests {
    @Test func `the statuses are the sysexits values every consumer reads`() {
        #expect(ExitStatus.allCases.map(\.rawValue) == [0, 1, 64, 70, 74, 78])
    }

    @Test func `an error fails a run; a warning only with strict; a note never`() {
        #expect(!RunOutcome.fails([], strict: true))
        #expect(RunOutcome.fails([.error], strict: false))
        #expect(RunOutcome.fails([.note, .error], strict: false))
        #expect(!RunOutcome.fails([.warning, .note], strict: false))
        #expect(RunOutcome.fails([.warning], strict: true))
        #expect(!RunOutcome.fails([.note, .note], strict: true))
    }

    @Test func `a run that skipped every file it found is an internal failure, findings or not`() {
        #expect(
            RunOutcome.status(severities: [], strict: false, analyzedFileCount: 0, skippedFileCount: 2)
                == .internalFailure)
        #expect(
            RunOutcome.status(severities: [.error], strict: false, analyzedFileCount: 0, skippedFileCount: 1)
                == .internalFailure)
        #expect(
            RunOutcome.status(severities: [.error], strict: false, analyzedFileCount: 1, skippedFileCount: 1)
                == .findings)
        #expect(
            RunOutcome.status(severities: [.warning], strict: false, analyzedFileCount: 3, skippedFileCount: 0)
                == .success)
        #expect(
            RunOutcome.status(severities: [.warning], strict: true, analyzedFileCount: 3, skippedFileCount: 0)
                == .findings)
        #expect(RunOutcome.status(severities: [], strict: true, analyzedFileCount: 0, skippedFileCount: 0) == .success)
    }
}
