import ProjectModel
import Testing

@Suite struct ReportSchemaTests {
    @Test func `the shared JSON report contract is at version 1`() {
        #expect(ReportSchema.version == 1)
    }
}
