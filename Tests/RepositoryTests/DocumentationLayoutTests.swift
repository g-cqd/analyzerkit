import Foundation
import Testing

struct DocumentationLayoutTests {
    private static func record(_ name: String, _ front: String, body: String = "# x\n") -> (name: String, text: String)
    {
        (name, "---\n\(front)\n---\n\n\(body)")
    }

    @Test func `the architecture records are sound`() {
        let records = DocumentationLayout.documents(in: "adr")
        #expect(records.count >= 1)
        #expect(DocumentationLayout.adrProblems(in: records).isEmpty, "\(DocumentationLayout.adrProblems(in: records))")
    }

    @Test func `a record has a number, a date and a status, and a superseded one names a successor that names it back`()
    {
        let good = [
            Self.record("0001-a.md", "status: superseded\ndate: 2026-10-29\nsuperseded-by: ADR-0002"),
            Self.record("0002-b.md", "status: accepted\ndate: 2026-10-30\nsupersedes: ADR-0001"),
        ]
        #expect(DocumentationLayout.adrProblems(in: good).isEmpty)

        let oneWay = [
            Self.record("0001-a.md", "status: superseded\ndate: 2026-10-29\nsuperseded-by: ADR-0002"),
            Self.record("0002-b.md", "status: accepted\ndate: 2026-10-30"),
        ]
        #expect(DocumentationLayout.adrProblems(in: oneWay).count == 1)
    }
}
