import Foundation
import Testing

/// The documentation law holds for this repository's records, and each rule fires when it is broken.
struct DocumentationLayoutTests {
    private static func record(_ name: String, _ front: String, body: String = "# x\n") -> (name: String, text: String)
    {
        (name, "---\n\(front)\n---\n\n\(body)")
    }

    private static func numbers(in directory: String) -> Set<String> {
        Set(DocumentationLayout.documents(in: directory).map { String($0.name.prefix(4)) })
    }

    // MARK: This repository

    @Test func `the white paper exists and stays within its line cap`() throws {
        let url = DocumentationLayout.repositoryRoot.appending(path: "development/WHITE-PAPER.md")
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(DocumentationLayout.whitePaperProblems(text).isEmpty, "\(DocumentationLayout.whitePaperProblems(text))")
    }

    @Test func `the architecture records are sound`() {
        let records = DocumentationLayout.documents(in: "adr")
        #expect(records.count >= 1)
        #expect(DocumentationLayout.adrProblems(in: records).isEmpty, "\(DocumentationLayout.adrProblems(in: records))")
    }

    @Test func `the roadmap is sound`() {
        let entries = DocumentationLayout.documents(in: "roadmap")
        #expect(entries.count >= 1)
        let problems = DocumentationLayout.roadmapProblems(in: entries)
        #expect(problems.isEmpty, "\(problems)")
    }

    @Test func `the diary is named and sized as the law says`() {
        let files = DocumentationLayout.documents(in: "diary")
        #expect(files.count >= 1)
        #expect(DocumentationLayout.diaryProblems(in: files).isEmpty, "\(DocumentationLayout.diaryProblems(in: files))")
    }

    @Test func `every local reference between records resolves`() {
        let documents = ["adr", "roadmap", "diary", "research"].flatMap { DocumentationLayout.documents(in: $0) }
        let research = Set(DocumentationLayout.documents(in: "research").map(\.name))
        let problems = DocumentationLayout.referenceProblems(
            in: documents, adrs: Self.numbers(in: "adr"), roadmap: Self.numbers(in: "roadmap"), research: research)
        #expect(problems.isEmpty, "\(problems)")
    }

    // MARK: The rules themselves

    @Test func `the white paper must be short enough to read and long enough to say something`() {
        let atCap = String(repeating: "x\n", count: DocumentationLayout.maximumWhitePaperLines)
        #expect(DocumentationLayout.whitePaperProblems(atCap).isEmpty)
        #expect(DocumentationLayout.whitePaperProblems(atCap + "x\n").count == 1)
        #expect(DocumentationLayout.whitePaperProblems("# Title\n").count == 1)
    }

    @Test func `a record has a number, a date and a status, and a superseded one names a successor that names it back`()
    {
        let good = [
            Self.record("0001-a.md", "status: superseded\nsuperseded-by: ADR-0002\ndate: 2026-10-29"),
            Self.record("0002-b.md", "status: accepted\nsupersedes: ADR-0001\ndate: 2026-10-29"),
        ]
        #expect(DocumentationLayout.adrProblems(in: good).isEmpty)
        let oneWay = [
            Self.record("0001-a.md", "status: superseded\nsuperseded-by: ADR-0002\ndate: 2026-10-29"),
            Self.record("0002-b.md", "status: accepted\ndate: 2026-10-29"),
        ]
        #expect(DocumentationLayout.adrProblems(in: oneWay).count == 1)
        #expect(
            DocumentationLayout.adrProblems(in: [Self.record("0001-a.md", "status: superseded\ndate: 2026-10-29")])
                .count == 1)
        #expect(
            DocumentationLayout.adrProblems(in: [Self.record("0001-a.md", "status: draft\ndate: 2026-10-29")]).count
                == 1)
        #expect(DocumentationLayout.adrProblems(in: [Self.record("0001-a.md", "status: accepted")]).count == 1)
        #expect(
            DocumentationLayout.adrProblems(in: [Self.record("0001-a.md", "status: accepted\ndate: 29.10.2026")]).count
                == 1)
        #expect(
            DocumentationLayout.adrProblems(in: [Self.record("a.md", "status: accepted\ndate: 2026-10-29")]).count == 1)
        #expect(
            DocumentationLayout.adrProblems(in: [
                Self.record("0001-a.md", "status: accepted\ndate: 2026-10-29"),
                Self.record("0001-b.md", "status: accepted\ndate: 2026-10-29"),
            ])
            .count == 1)
    }

    @Test func `a roadmap entry needs a date, a known status, and blockers that exist and are not done`() {
        func entry(_ number: String, _ status: String, _ blockedBy: String = "[]", date: String = "2026-10-29")
            -> (name: String, text: String)
        {
            Self.record("\(number)-work.md", "status: \(status)\nblocked-by: \(blockedBy)\ndate: \(date)")
        }
        #expect(
            DocumentationLayout.roadmapProblems(in: [
                entry("0001", "in-progress"), entry("0002", "not-started", "[0001]"),
            ])
            .isEmpty)
        #expect(DocumentationLayout.roadmapProblems(in: [entry("0001", "finished")]).count == 1)
        #expect(DocumentationLayout.roadmapProblems(in: [entry("0001", "not-started", "[0009]")]).count == 1)
        #expect(
            DocumentationLayout.roadmapProblems(in: [entry("0001", "done"), entry("0002", "not-started", "[0001]")])
                .count == 1)
        #expect(
            DocumentationLayout.roadmapProblems(in: [entry("0001", "in-progress"), entry("0002", "done", "[0001]")])
                .isEmpty)
        #expect(DocumentationLayout.roadmapProblems(in: [entry("0001", "done", date: "")]).count == 1)
        #expect(
            DocumentationLayout.roadmapProblems(in: [entry("0001", "done"), entry("0001", "done")]).count == 1)
    }

    @Test func `a diary file must be named by date and stay within the budget, inclusive`() {
        let atBudget = String(repeating: "x\n", count: DocumentationLayout.maximumDiaryLines)
        #expect(DocumentationLayout.diaryProblems(in: [("2026-10-29-01.md", atBudget)]).isEmpty)
        #expect(DocumentationLayout.diaryProblems(in: [("2026-10-29-01.md", atBudget + "x\n")]).count == 1)
        #expect(DocumentationLayout.diaryProblems(in: [("notes.md", "x\n")]).count == 1)
        #expect(DocumentationLayout.diaryProblems(in: [("2026-10-29-1.md", "x\n")]).count == 1)
    }

    @Test
    func `a local reference must name a record that exists, and a reference into another repository is not checked`() {
        func problems(_ body: String) -> [String] {
            DocumentationLayout.referenceProblems(
                in: [("note.md", body)], adrs: ["0001"], roadmap: ["0002"], research: ["2026-10-29-x.md"])
        }
        #expect(problems("ADR-0001, roadmap 0002, research `2026-10-29-x.md`, Roadmap 0002.").isEmpty)
        #expect(problems("See ADR-0009.").count == 1)
        #expect(problems("See roadmap 0009.").count == 1)
        #expect(problems("See research `2026-10-29-missing.md`.").count == 1)
        #expect(problems("its roadmap 0018; AemiProtobuf's roadmap 0015; ask's ADR-0128").isEmpty)
        #expect(problems("A reference looks like research `<file>.md`.").isEmpty, "a placeholder is not a reference")
    }
}
