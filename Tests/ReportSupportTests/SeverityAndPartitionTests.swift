import ProjectModel
import Testing

@Suite struct SeverityAndPartitionTests {
    @Test func `severities order note below warning below error and the maximum decides`() {
        #expect(Severity.note < .warning && Severity.warning < .error)
        #expect([Severity.warning, .error, .note].max() == .error)
        #expect(Severity(rawValue: "warning") == .warning)
    }

    @Test func `partitioned keeps order in both halves and puts the non-matching half first`() {
        let (rest, matching) = [1, 2, 3, 4, 5].partitioned { $0.isMultiple(of: 2) }
        #expect(rest == [1, 3, 5] && matching == [2, 4])
        let (none, all) = [Int]().partitioned { _ in true }
        #expect(none.isEmpty && all.isEmpty)
    }
}
