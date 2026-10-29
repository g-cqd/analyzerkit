public import ProjectModel

/// The exit status of every analyzer's analysing command (ADR-0018).
public enum ExitStatus: Int32, Sendable, CaseIterable {
    /// The run finished and nothing failed it.
    case success = 0
    /// A finding failed the run: an error, or with `--strict` a warning.
    case findings = 1
    /// Usage: an unknown option, a path that does not exist, no Swift file under the paths given.
    case usage = 64
    /// The run was cancelled, or every file found was skipped.
    case internalFailure = 70
    /// An output the run was asked to write could not be written.
    case outputFailure = 74
    /// A configuration or baseline file that cannot be read or is invalid.
    case badConfiguration = 78
}

/// How a run that finished ends (ADR-0018).
public enum RunOutcome {
    /// Whether findings of these severities fail the run: an error does; with `strict`, a warning too; a note never.
    public static func fails(_ severities: some Sequence<Severity>, strict: Bool) -> Bool {
        severities.contains { strict ? $0 > .note : $0 == .error }
    }

    /// The status of a finished run: 70 when it analyzed nothing although files were found, else 1 when a finding
    /// fails it, else 0.
    public static func status(
        severities: some Sequence<Severity>, strict: Bool, analyzedFileCount: Int, skippedFileCount: Int
    ) -> ExitStatus {
        if analyzedFileCount == 0, skippedFileCount > 0 { return .internalFailure }
        return fails(severities, strict: strict) ? .findings : .success
    }
}
