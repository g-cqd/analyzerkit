/// One line of the `xcode` output format, which Xcode and SwiftPM build logs turn into inline diagnostics:
/// `path:line:column: severity: [rule] message`, the `[rule]` omitted when there is none.
public enum XcodeDiagnostic {
    public static func line(
        path: String, line: Int, column: Int, severity: String, rule: String?, message: String
    ) -> String {
        ""
    }
}
