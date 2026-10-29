/// What a run says about itself rather than about one finding (ADR-0017).
public struct RunNote: Codable, Sendable, Equatable {
    public let code: String
    public let severity: String
    public let message: String
    public let count: Int
    public let paths: [String]

    public init(code: String, severity: String, message: String, paths: [String] = [], verbose: Bool = false) {
        self.code = code
        self.severity = severity
        self.message = message
        count = 0
        self.paths = []
    }
}

/// A file the run did not check, or did not check in full (ADR-0017).
public struct SkippedFile: Codable, Sendable, Equatable {
    public enum Reason: String, Codable, Sendable {
        case notIndexed, changedSinceBuild, unreadable, degraded
    }

    public let path: String
    public let reason: Reason

    public init(path: String, reason: Reason) {
        self.path = path
        self.reason = reason
    }
}

/// A tool's report with the keys every report carries: `schemaVersion` and ADR-0017's `tool`, `version`, `runNotes`,
/// `skippedFiles` and, when asked for, `timings`. The tool's own keys are written first and keep their names and
/// types; the envelope adds keys only.
public struct ReportEnvelope<Report: Encodable>: Encodable {
    public let report: Report
    public let tool: String
    public let version: String
    public let runNotes: [RunNote]
    public let skippedFiles: [SkippedFile]
    public let timings: [String: Double]?

    public init(
        _ report: Report, tool: String, version: String, runNotes: [RunNote] = [], skippedFiles: [SkippedFile] = [],
        timings: [String: Double]? = nil
    ) {
        self.report = report
        self.tool = tool
        self.version = version
        self.runNotes = runNotes
        self.skippedFiles = skippedFiles
        self.timings = timings
    }

    public func encode(to encoder: any Encoder) throws {
        try report.encode(to: encoder)
    }
}

/// The phrases every tool's one-line stderr summary shares.
public enum ReportSummary {
    /// " (N not checked)" when files were skipped, "" otherwise.
    public static func notChecked(_ count: Int) -> String { "" }
}
