public import ProjectModel
internal import SourceCorpus

#if canImport(FoundationEssentials)
    import FoundationEssentials
#else
    import Foundation
#endif

// The report skeleton arcleak, deadwood and dolly each wrote (roadmap 0067, step 4): `--format xcode|json|sarif`, the
// stderr summary line, the JSON envelope's notes and skipped files, and the SARIF log. A tool says what its findings and
// its report hold; the wording, the order and the keys are fixed here, so a fix to one reaches all.

/// The `--format` values every analyzer shares.
public enum ReportOutputFormat: String, CaseIterable, Sendable {
    /// `path:line:col: warning|error: [rule] message`, parsed by Xcode and SwiftPM build logs into inline diagnostics.
    case xcode
    /// Stable, versioned JSON of the full report.
    case json
    /// SARIF 2.1.0, for GitHub code scanning and other SARIF consumers.
    case sarif
}

/// Where a finding points beside its own location: a clone-group member, a link in a cycle.
public struct ReportedLocation: Sendable, Equatable {
    public let path: String
    public let line: Int
    public let column: Int
    /// What the location is, for SARIF's `relatedLocations`; nil leaves it unsaid.
    public let message: String?

    public init(path: String, line: Int, column: Int, message: String? = nil) {
        self.path = path
        self.line = line
        self.column = column
        self.message = message
    }
}

/// What the shared renderers read from a tool's finding.
public protocol ReportedFinding: Sendable {
    var path: String { get }
    /// 1-based.
    var line: Int { get }
    /// 1-based UTF-8 column, as swift-syntax counts it; SARIF output converts it.
    var column: Int { get }
    /// `error`, `warning` or `note`: SARIF's `level` and Xcode's severity.
    var severityName: String { get }
    /// The rule's id.
    var ruleName: String { get }
    /// The message as printed, a finding's note after it included.
    var displayMessage: String { get }
    /// The stable id baselines and SARIF's `partialFingerprints` carry.
    var fingerprint: String { get }
    /// One SARIF related location each; none by default.
    var relatedLocations: [ReportedLocation] { get }
    /// SARIF's result `properties`; none by default.
    var sarifProperties: [String: Sarif.Property]? { get }
}

extension ReportedFinding {
    public var relatedLocations: [ReportedLocation] { [] }
    public var sarifProperties: [String: Sarif.Property]? { nil }
}

/// A file the run read in part or not at all.
public protocol ReportedDegradedFile: Sendable {
    var path: String { get }
    /// What the report says about it, such as `file skipped: not UTF-8`.
    var displayText: String { get }
    /// Whether the whole file went unanalyzed, rather than part of its analysis; true by default.
    var skippedWhole: Bool { get }
}

extension ReportedDegradedFile {
    public var skippedWhole: Bool { true }
}

/// What the shared renderers read from a tool's whole-run report.
public protocol ToolReport: Sendable {
    associatedtype Finding: ReportedFinding
    associatedtype DegradedFile: ReportedDegradedFile

    var findings: [Finding] { get }
    var degradedFiles: [DegradedFile] { get }
    var suppressedCount: Int { get }
    var analyzedFileCount: Int { get }
    /// A cancelled run carries no findings, and its SARIF invocation fails.
    var wasCancelled: Bool { get }
    var classificationIssues: [ClassificationIssue] { get }
    /// Seconds per phase, written to the JSON when `--timings` is given.
    var timings: [String: Double] { get }
    /// Run notes the tool puts before the classification issues; none by default.
    var leadingRunNotes: [RunNote] { get }
    /// Run notes the tool puts after the classification issues; none by default.
    var trailingRunNotes: [RunNote] { get }
    /// Files the tool did not check for a reason of its own (a file no index store covered); none by default.
    var uncoveredFiles: [SkippedFile] { get }
    /// Notes SARIF carries as warning notifications, which never fail the run; none by default.
    var sarifWarnings: [String] { get }
}

extension ToolReport {
    public var leadingRunNotes: [RunNote] { [] }
    public var trailingRunNotes: [RunNote] { [] }
    public var uncoveredFiles: [SkippedFile] { [] }
    public var sarifWarnings: [String] { [] }

    /// True when every file the run was given was skipped, so it analyzed nothing. Such a report has no findings and must
    /// not pass for a clean one. A file counts once however often it degraded, and not at all when only part of its
    /// analysis was skipped.
    public var everyFileSkipped: Bool {
        analyzedFileCount > 0 && Set(degradedFiles.lazy.filter(\.skippedWhole).map(\.path)).count >= analyzedFileCount
    }
}

/// A tool's identity and the choices its output makes; conforming gives the tool `format` and `summary`.
public protocol ToolReportFormat {
    associatedtype Report: ToolReport & Encodable

    static var toolName: String { get }
    static var toolVersion: String { get }
    static var informationURI: String { get }
    /// The SARIF driver's rules.
    static var sarifRules: [Sarif.Rule] { get }
    /// What the tool's parse did with a byte-order mark, which decides how SARIF columns convert.
    static var byteOrderMark: SarifColumns.ByteOrderMark { get }
    /// The largest file the tool reads, in bytes, which SARIF's column conversion reads under too.
    static var readCap: Int { get }
}

extension ToolReportFormat {
    /// - Parameters:
    ///   - root: the directory `report` was relativized to, if any. SARIF declares it as the base its relative uris
    ///     resolve against.
    ///   - runNotes: notes the command adds (`--report-new-since`), after the report's own.
    ///   - skippedFiles: files the command skipped, after the report's own.
    ///   - verbose: every path of a classification note, not the first few.
    ///   - timings: carry the phases' times in the JSON report.
    public static func format(
        _ report: Report,
        as format: ReportOutputFormat,
        relativeTo root: String? = nil,
        runNotes: [RunNote] = [],
        skippedFiles: [SkippedFile] = [],
        verbose: Bool = false,
        timings: Bool = false
    ) -> String {
        switch format {
        case .xcode:
            return xcode(report)
        case .json:
            return encode(
                envelope(
                    report,
                    root: root.map(SourcePath.canonical),
                    extraNotes: runNotes,
                    extraSkipped: skippedFiles,
                    verbose: verbose,
                    timings: timings
                )
            )
        case .sarif:
            return sarif(report, root: root.map(SourcePath.canonical))
        }
    }

    /// One human summary line (for stderr, so stdout stays machine-parseable).
    public static func summary(_ report: Report) -> String {
        let errors = report.findings.count(where: { $0.severityName == "error" })
        let notes = report.findings.count(where: { $0.severityName == "note" })
        let warnings = report.findings.count - errors - notes
        let degraded = Set(report.degradedFiles.map(\.path)).count
        var line = "\(toolName): \(report.findings.count) finding(s) "
        line += "(\(errors) error(s), \(warnings) warning(s)"
        line += notes > 0 ? ", \(notes) note(s))" : ")"
        line += " in \(report.analyzedFileCount) file(s)"
        line += ReportSummary.notChecked(degraded)
        if report.suppressedCount > 0 {
            line += "; \(report.suppressedCount) suppressed"
        }
        if degraded > 0 {
            line += "; \(degraded) file(s) degraded"
        }
        return line
    }

    private static func xcode(_ report: Report) -> String {
        var lines = report.findings.map {
            XcodeDiagnostic.line(
                path: $0.path,
                line: $0.line,
                column: $0.column,
                severity: $0.severityName,
                rule: $0.ruleName,
                message: $0.displayMessage
            )
        }
        for degraded in report.degradedFiles {
            lines.append(
                XcodeDiagnostic.line(
                    path: degraded.path,
                    line: 1,
                    column: 1,
                    severity: "warning",
                    rule: toolName,
                    message: degraded.displayText
                )
            )
        }
        return lines.joined(separator: "\n")
    }

    /// The JSON report: the tool's own fields and the keys every analyzer's report carries (ADR-0017).
    private static func envelope(
        _ report: Report,
        root: String?,
        extraNotes: [RunNote],
        extraSkipped: [SkippedFile],
        verbose: Bool,
        timings: Bool
    ) -> ReportEnvelope<Report> {
        var seen: Set<String> = []
        let degraded = report.degradedFiles.compactMap { file in
            seen.insert(file.path).inserted ? SkippedFile(path: file.path, reason: .degraded) : nil
        }
        let skipped = degraded + (report.uncoveredFiles + extraSkipped).filter { seen.insert($0.path).inserted }
        func shown(_ path: String) -> String { root.map { RepositoryRoot.relativize(path, to: $0) } ?? path }
        let classification = report.classificationIssues.map { issue in
            RunNote(
                code: issue.code,
                severity: "note",
                message: issue.message,
                paths: issue.paths.map(shown),
                verbose: verbose
            )
        }
        return ReportEnvelope(
            report,
            tool: toolName,
            version: toolVersion,
            runNotes: report.leadingRunNotes + classification + report.trailingRunNotes + extraNotes,
            skippedFiles: skipped,
            timings: timings ? report.timings : nil
        )
    }

    // MARK: SARIF 2.1.0

    /// The SARIF log, on the shared model.
    /// - Parameter root: the canonical directory the report's relative paths hang from, or nil when every path is absolute.
    private static func sarif(_ report: Report, root: String?) -> String {
        var columns = SarifColumns(root: root, byteOrderMark: byteOrderMark, readCap: readCap)
        /// Where a finding or a related location points, its column in UTF-16.
        func location(_ path: String, line: Int, column: Int, message: String? = nil) -> Sarif.Location {
            Sarif.Location(
                physicalLocation: Sarif.PhysicalLocation(
                    artifactLocation: Sarif.ArtifactLocation(path: path, root: root),
                    region: Sarif.Region(startLine: line, startColumn: columns.column(column, line: line, path: path))
                ),
                message: message.map(Sarif.Text.init)
            )
        }
        let results = report.findings.map { finding in
            let related = finding.relatedLocations
            return Sarif.Result(
                ruleId: finding.ruleName,
                level: finding.severityName,
                message: Sarif.Text(finding.displayMessage),
                locations: [location(finding.path, line: finding.line, column: finding.column)],
                // One location per further member, so a consumer can jump to each (omitted when there are none).
                relatedLocations: related.isEmpty
                    ? nil
                    : related.map { location($0.path, line: $0.line, column: $0.column, message: $0.message) },
                partialFingerprints: ["\(toolName)/v1": finding.fingerprint],
                properties: finding.sarifProperties
            )
        }
        // Degraded files were invisible in SARIF, the format code scanning uploads, so unparseable or unreadable code
        // looked analyzed. A note-level result per degraded file keeps them where the findings are.
        let degradedResults = report.degradedFiles.map { file in
            Sarif.Result(
                ruleId: "\(toolName)/degraded-file",
                level: "note",
                message: Sarif.Text(file.displayText),
                locations: [
                    Sarif.Location(
                        physicalLocation: Sarif.PhysicalLocation(
                            artifactLocation: Sarif.ArtifactLocation(path: file.path, root: root),
                            region: Sarif.Region(startLine: 1, startColumn: 1)
                        )
                    )
                ],
                partialFingerprints: [:]
            )
        }
        // A run that analyzed nothing fails: its results are incomplete (SARIF 2.1.0 §3.20.21).
        let failure: String? =
            if report.wasCancelled {
                "the run was cancelled before the corpus was complete; no findings reported"
            } else if report.everyFileSkipped {
                "every file in the corpus was skipped (unreadable, non-UTF8, or over the size cap); "
                    + "nothing was analyzed"
            } else {
                nil
            }
        let log = Sarif.Log(runs: [
            Sarif.Run(
                tool: Sarif.Tool(
                    driver: Sarif.Driver(
                        name: toolName,
                        version: toolVersion,
                        informationUri: informationURI,
                        rules: sarifRules
                    )
                ),
                invocations: [Sarif.Invocation(failure: failure, warnings: report.sarifWarnings)],
                root: root,
                results: results + degradedResults
            )
        ])
        return encode(log)
    }

    /// Deterministic pretty-printed JSON for report payloads; encoding a value the tool built itself cannot reasonably
    /// fail, so the fallback is an empty object rather than a thrown error.
    private static func encode(_ value: some Encodable) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value), let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }
}
