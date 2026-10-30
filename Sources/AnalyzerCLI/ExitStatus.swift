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

extension ExitStatus {
    /// A search ran and matched nothing (ADR-0026): status 1, as `grep` exits.
    ///
    /// The value of ``findings`` under the name a search command means; not a case of its own, so ``allCases`` stays
    /// the sysexits list every consumer reads.
    public static var noMatch: ExitStatus { .findings }
}

/// How a search command that finished ends (ADR-0026): it prints matches, never findings, so `--strict` does not apply.
public enum SearchOutcome {
    /// 70 when it read none of the files it found, else 0 when something matched, else ``ExitStatus/noMatch``.
    ///
    /// Matches from an index store count with no file read, so the file counts only decide when nothing matched.
    public static func status(matchCount: Int, analyzedFileCount: Int = 0, skippedFileCount: Int = 0) -> ExitStatus {
        if matchCount > 0 { return .success }
        if analyzedFileCount == 0, skippedFileCount > 0 { return .internalFailure }
        return .noMatch
    }
}
