import Foundation
import ProjectModel
import ReportSupport
import Testing

/// The renderers arcleak, deadwood and dolly each wrote (roadmap 0067, step 4), on a made-up tool, so the shared skeleton is
/// pinned apart from any one tool's goldens.
@Suite struct ToolReportFormatTests {
    private struct Finding: ReportedFinding {
        var path = "/repo/A.swift"
        var line = 3
        var column = 5
        var severityName = "warning"
        var ruleName = "rule-a"
        var displayMessage = "something is off"
        var fingerprint = "fp1"
        var relatedLocations: [ReportedLocation] = []
        var sarifProperties: [String: Sarif.Property]?
    }

    private struct Degraded: ReportedDegradedFile {
        var path: String
        var displayText: String
    }

    private struct Report: ToolReport, Encodable {
        var findings: [Finding] = []
        var degradedFiles: [Degraded] = []
        var suppressedCount = 0
        var analyzedFileCount = 4
        var wasCancelled = false
        var classificationIssues: [ClassificationIssue] = []
        var timings: [String: Double] = [:]
        var leadingRunNotes: [RunNote] = []
        var trailingRunNotes: [RunNote] = []
        var uncoveredFiles: [SkippedFile] = []
        var sarifWarnings: [String] = []

        private enum CodingKeys: String, CodingKey { case analyzedFileCount }
    }

    private enum Format: ToolReportFormat {
        typealias Report = ToolReportFormatTests.Report
        static let toolName = "fake"
        static let toolVersion = "1.2.3"
        static let informationURI = "https://example.test/fake"
        static let sarifRules = [Sarif.Rule(id: "rule-a", shortDescription: Sarif.Text("a"), help: Sarif.Text("why"))]
        static let byteOrderMark = SarifColumns.ByteOrderMark.dropped
        static let readCap = 1 << 20
    }

    private static func object(_ text: String) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    // MARK: xcode

    @Test func `xcode prints each finding then a warning per degraded file, rule named after the tool`() {
        var report = Report()
        report.findings = [Finding(), Finding(path: "/repo/B.swift", line: 1, column: 1, severityName: "error")]
        report.degradedFiles = [Degraded(path: "/repo/C.swift", displayText: "file skipped: not UTF-8")]
        #expect(
            Format.format(report, as: .xcode) == """
                /repo/A.swift:3:5: warning: [rule-a] something is off
                /repo/B.swift:1:1: error: [rule-a] something is off
                /repo/C.swift:1:1: warning: [fake] file skipped: not UTF-8
                """
        )
    }

    // MARK: summary

    @Test func `the summary counts severities, then suppressed and degraded files`() {
        var report = Report()
        report.findings = [Finding(severityName: "error"), Finding(), Finding(severityName: "note")]
        report.suppressedCount = 2
        report.degradedFiles = [
            Degraded(path: "/repo/C.swift", displayText: "x"), Degraded(path: "/repo/C.swift", displayText: "y"),
        ]
        #expect(
            Format.summary(report)
                == "fake: 3 finding(s) (1 error(s), 1 warning(s), 1 note(s)) in 4 file(s) (1 not checked)"
                + "; 2 suppressed; 1 file(s) degraded"
        )
        #expect(Format.summary(Report()) == "fake: 0 finding(s) (0 error(s), 0 warning(s)) in 4 file(s)")
    }

    // MARK: json

    @Test func `json has the report's keys and the envelope's; notes run leading, classification, trailing, passed`()
        throws
    {
        var report = Report()
        report.leadingRunNotes = [RunNote(code: "lead", severity: "note", message: "l")]
        report.trailingRunNotes = [RunNote(code: "trail", severity: "note", message: "t")]
        report.classificationIssues = [
            ClassificationIssue(code: "c", message: "m", paths: ["/repo/x/1.swift", "/elsewhere/2.swift"])
        ]
        let json = try Self.object(
            Format.format(
                report,
                as: .json,
                relativeTo: "/repo",
                runNotes: [RunNote(code: "passed", severity: "note", message: "p")]
            )
        )
        #expect(json["analyzedFileCount"] as? Int == 4)
        #expect(json["tool"] as? String == "fake" && json["version"] as? String == "1.2.3")
        let notes = try #require(json["runNotes"] as? [[String: Any]])
        #expect(notes.map { $0["code"] as? String } == ["lead", "c", "trail", "passed"])
        #expect(notes[1]["paths"] as? [String] == ["x/1.swift", "/elsewhere/2.swift"])
        #expect(json["timings"] == nil)
    }

    @Test func `skipped files are the degraded, the uncovered and the passed, each path once`() throws {
        var report = Report()
        report.degradedFiles = [
            Degraded(path: "/repo/D.swift", displayText: "x"), Degraded(path: "/repo/D.swift", displayText: "y"),
        ]
        report.uncoveredFiles = [
            SkippedFile(path: "/repo/D.swift", reason: .notIndexed),
            SkippedFile(path: "/repo/U.swift", reason: .notIndexed),
        ]
        let json = try Self.object(
            Format.format(
                report,
                as: .json,
                skippedFiles: [
                    SkippedFile(path: "/repo/U.swift", reason: .unreadable),
                    SkippedFile(path: "/repo/P.swift", reason: .unreadable),
                ]
            )
        )
        let skipped = try #require(json["skippedFiles"] as? [[String: String]])
        #expect(
            skipped == [
                ["path": "/repo/D.swift", "reason": "degraded"], ["path": "/repo/U.swift", "reason": "notIndexed"],
                ["path": "/repo/P.swift", "reason": "unreadable"],
            ]
        )
    }

    @Test func `timings are in the JSON when asked for`() throws {
        var report = Report()
        report.timings = ["parse": 0.5]
        #expect(try Self.object(Format.format(report, as: .json))["timings"] == nil)
        let timed = try #require(
            Self.object(Format.format(report, as: .json, timings: true))["timings"] as? [String: Double]
        )
        #expect(timed == ["parse": 0.5])
    }

    // MARK: sarif

    @Test func `sarif has the findings, a note per degraded file, the driver and a clean invocation`() throws {
        var report = Report()
        report.findings = [Finding()]
        report.degradedFiles = [Degraded(path: "/repo/C.swift", displayText: "file skipped: bad")]
        let log = try Self.object(Format.format(report, as: .sarif, relativeTo: "/repo"))
        let run = try #require((log["runs"] as? [[String: Any]])?.first)
        let driver = try #require((run["tool"] as? [String: Any])?["driver"] as? [String: Any])
        #expect(driver["name"] as? String == "fake" && driver["version"] as? String == "1.2.3")
        #expect(driver["informationUri"] as? String == "https://example.test/fake")
        #expect((driver["rules"] as? [[String: Any]])?.first?["id"] as? String == "rule-a")
        let results = try #require(run["results"] as? [[String: Any]])
        #expect(results.map { $0["ruleId"] as? String } == ["rule-a", "fake/degraded-file"])
        #expect(results.map { $0["level"] as? String } == ["warning", "note"])
        #expect((results[0]["partialFingerprints"] as? [String: String]) == ["fake/v1": "fp1"])
        #expect((results[1]["partialFingerprints"] as? [String: String]) == [:])
        #expect((results[1]["message"] as? [String: String]) == ["text": "file skipped: bad"])
        #expect(results[0]["relatedLocations"] == nil)
        let invocation = try #require((run["invocations"] as? [[String: Any]])?.first)
        #expect(invocation["executionSuccessful"] as? Bool == true)
    }

    @Test func `related locations, properties and warnings reach the log`() throws {
        var finding = Finding()
        finding.relatedLocations = [
            ReportedLocation(path: "/repo/B.swift", line: 9, column: 2, message: "duplicate region")
        ]
        finding.sarifProperties = ["confidence": .string("high")]
        var report = Report()
        report.findings = [finding]
        report.sarifWarnings = ["fake: warning: index missing"]
        let log = try Self.object(Format.format(report, as: .sarif))
        let run = try #require((log["runs"] as? [[String: Any]])?.first)
        let result = try #require((run["results"] as? [[String: Any]])?.first)
        let related = try #require((result["relatedLocations"] as? [[String: Any]])?.first)
        #expect((related["message"] as? [String: String]) == ["text": "duplicate region"])
        #expect((result["properties"] as? [String: String]) == ["confidence": "high"])
        let invocation = try #require((run["invocations"] as? [[String: Any]])?.first)
        #expect(invocation["executionSuccessful"] as? Bool == true)
        #expect((invocation["toolExecutionNotifications"] as? [[String: Any]])?.count == 1)
    }

    @Test func `a cancelled run and a run that analyzed nothing fail the invocation`() throws {
        var cancelled = Report()
        cancelled.wasCancelled = true
        var nothing = Report()
        nothing.analyzedFileCount = 1
        nothing.degradedFiles = [Degraded(path: "/repo/C.swift", displayText: "x")]
        #expect(nothing.everyFileSkipped)
        for report in [cancelled, nothing] {
            let log = try Self.object(Format.format(report, as: .sarif))
            let run = try #require((log["runs"] as? [[String: Any]])?.first)
            let invocation = try #require((run["invocations"] as? [[String: Any]])?.first)
            #expect(invocation["executionSuccessful"] as? Bool == false)
        }
    }

    @Test func `the output format names are the CLI's`() {
        #expect(ReportOutputFormat.allCases.map(\.rawValue) == ["xcode", "json", "sarif"])
    }
}
