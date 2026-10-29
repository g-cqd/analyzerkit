import ReportSupport
import Testing

@Suite struct XcodeDiagnosticTests {
    @Test func `a diagnostic line names its place, severity, rule and message`() {
        #expect(
            XcodeDiagnostic.line(
                path: "Sources/A.swift", line: 3, column: 9, severity: "warning", rule: "leak", message: "m — n")
                == "Sources/A.swift:3:9: warning: [leak] m — n")
        #expect(
            XcodeDiagnostic.line(
                path: "/a b/B.swift", line: 1, column: 1, severity: "note", rule: nil, message: "try x()")
                == "/a b/B.swift:1:1: note: try x()")
    }
}
