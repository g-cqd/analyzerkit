/// The version of the JSON report contract shared by arcleak, dolly and deadwood.
///
/// Each tool writes it as the top-level `schemaVersion` field of `--format json`.
/// It changes only when a field of the 1.x contract is removed, renamed or changes
/// meaning; adding a field does not change it, so a consumer must ignore fields it
/// does not know.
public enum ReportSchema {
    /// The current contract version.
    public static let version = 1
}
