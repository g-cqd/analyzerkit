import ProjectModel
import Testing

@Suite struct ReportSchemaTests {
    @Test func `the report contract version is 1`() {
        #expect(ReportSchema.version == 1)
    }
}
