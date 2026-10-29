internal import Foundation

/// Filesystem policy for libraries loaded into the analyzer process (ADR-0014).
public enum BinaryTrustChecker {
    public struct Assessment: Sendable, Equatable {
        public let path: String
        public let rejection: String?
        public var isTrusted: Bool { rejection == nil }
    }
    public static func assess(_ path: String) -> Assessment {
        Assessment(path: path, rejection: "not implemented")
    }
    public static func isTrusted(at path: String) -> Bool { assess(path).isTrusted }
}

/// One ordered resolution policy. The command seam runs only fixed system probes, never project code.
public enum ToolchainResolution {
    public struct Outcome: Sendable, Equatable {
        public let libraryPath: String?
        public let diagnostics: [String]
    }
    public static func resolve(
        environment: [String: String]? = nil,
        home: String? = nil,
        commandLineTools: String = "/Library/Developer/CommandLineTools",
        command: (_ executable: String, _ arguments: [String], _ environment: [String: String]) -> String? = systemProbe
    ) -> Outcome {
        Outcome(libraryPath: nil, diagnostics: [])
    }
    public static func systemProbe(_ executable: String, _ arguments: [String], _ environment: [String: String])
        -> String?
    {
        nil
    }
}
