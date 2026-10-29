import Foundation
import ReportSupport
import Testing

@Suite struct ReportEnvelopeTests {
    private struct ToolReport: Encodable {
        let findings: [String]
        let notes: [String]
    }

    private static func object(_ value: some Encodable) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try #require(try JSONSerialization.jsonObject(with: encoder.encode(value)) as? [String: Any])
    }

    @Test func `the envelope adds its keys and keeps the tool's own, types included`() throws {
        let envelope = ReportEnvelope(
            ToolReport(findings: ["a"], notes: ["deadwood: warning: kept as strings"]), tool: "deadwood",
            version: "0.11.2", runNotes: [RunNote(code: "index", severity: "warning", message: "no store")],
            skippedFiles: [SkippedFile(path: "Bad.swift", reason: .degraded)])
        let json = try Self.object(envelope)
        #expect(json["schemaVersion"] as? Int == 1)
        #expect(json["tool"] as? String == "deadwood")
        #expect(json["version"] as? String == "0.11.2")
        #expect(json["findings"] as? [String] == ["a"])
        #expect(json["notes"] as? [String] == ["deadwood: warning: kept as strings"])
        let note = try #require((json["runNotes"] as? [[String: Any]])?.first)
        #expect(note["code"] as? String == "index" && note["severity"] as? String == "warning")
        #expect(note["message"] as? String == "no store" && note["count"] as? Int == 0)
        #expect(note["paths"] as? [String] == [])
        #expect(json["skippedFiles"] as? [[String: String]] == [["path": "Bad.swift", "reason": "degraded"]])
        #expect(json["timings"] == nil)
    }

    @Test func `empty notes and skipped files are present as empty arrays, timings only when given`() throws {
        let bare = try Self.object(ReportEnvelope(ToolReport(findings: [], notes: []), tool: "t", version: "1"))
        #expect(bare["runNotes"] as? [Any] != nil && (bare["runNotes"] as? [Any])?.isEmpty == true)
        #expect((bare["skippedFiles"] as? [Any])?.isEmpty == true)
        let timed = try Self.object(
            ReportEnvelope(ToolReport(findings: [], notes: []), tool: "t", version: "1", timings: ["scan": 0.5]))
        #expect(timed["timings"] as? [String: Double] == ["scan": 0.5])
    }

    @Test func `a note counts every path and lists ten unless verbose`() {
        let paths = (1...25).map { "File\($0).swift" }
        let capped = RunNote(code: "index", severity: "note", message: "not indexed", paths: paths)
        #expect(capped.count == 25)
        #expect(capped.paths == Array(paths.prefix(10)))
        let full = RunNote(code: "index", severity: "note", message: "not indexed", paths: paths, verbose: true)
        #expect(full.count == 25 && full.paths == paths)
        let few = RunNote(code: "cache", severity: "note", message: "m", paths: ["a"])
        #expect(few.count == 1 && few.paths == ["a"])
    }

    @Test func `skipped-file reasons are the four ADR-0017 names`() {
        #expect(SkippedFile.Reason.allRawValues == ["notIndexed", "changedSinceBuild", "unreadable", "degraded"])
    }

    @Test func `the summary says how many files were not checked, and nothing when none`() {
        #expect(ReportSummary.notChecked(0) == "")
        #expect(ReportSummary.notChecked(1) == " (1 not checked)")
        #expect(ReportSummary.notChecked(12) == " (12 not checked)")
    }
}

extension SkippedFile.Reason {
    fileprivate static var allRawValues: [String] {
        [SkippedFile.Reason.notIndexed, .changedSinceBuild, .unreadable, .degraded].map(\.rawValue)
    }
}
