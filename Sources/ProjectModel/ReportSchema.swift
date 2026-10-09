/// The version of the JSON report contract shared by arcleak, dolly and deadwood.
///
/// Each tool writes it as the top-level `schemaVersion` field of `--format json`.
/// It changes only when a change can break a consumer that ignores unknown fields:
/// a field is removed, renamed, retyped, made required or optional, or changes
/// meaning, or the closed set of severities changes. Rule ids are an open set: a new
/// rule can appear without a version bump, so a consumer must handle a rule id it does
/// not know. Adding a field does not change the version either, so a consumer must ignore
/// fields it does not know, and must reject a `schemaVersion` above the one it was
/// written for.
public enum ReportSchema {
    /// The current contract version.
    public static let version = 1
}
