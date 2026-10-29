/// Runs a subprocess with a deadline, a cap on the output kept, and a scrubbed environment: the one executor for
/// toolchain probes and index-store builds (ADR-0004; roadmap 0010). Red stub.
public enum BoundedProcess {
    /// What a finished child left.
    public struct Result: Sendable, Equatable {
        public let exitStatus: Int32
        public let standardOutput: [UInt8]
        public let standardError: [UInt8]
        /// Whether output past the limit was read and dropped.
        public let outputTruncated: Bool

        public var succeeded: Bool { exitStatus == 0 }
        public var standardOutputText: String { String(decoding: standardOutput, as: UTF8.self) }
        public var standardErrorText: String { String(decoding: standardError, as: UTF8.self) }
    }

    /// Why a child gave no result.
    public enum Failure: Error, Equatable, Sendable {
        /// Only an absolute path is run; nothing is looked up on `PATH`.
        case notAbsolute(String)
        case launchFailed(executable: String, reason: String)
        /// The deadline passed; the child was terminated, then killed if it lingered.
        case timedOut(executable: String, after: Duration)
        /// The calling task was cancelled; the child was terminated.
        case cancelled(executable: String)
    }

    /// Variables a child inherits; everything else is dropped, `DYLD_*`, `LD_*`, `DEVELOPER_DIR`, `SHELL` and `BASH_ENV`
    /// included.
    public static let allowedEnvironmentKeys: Set<String> = [
        "PATH", "HOME", "USER", "LOGNAME", "LANG", "LC_ALL", "LC_CTYPE", "LC_MESSAGES", "TMPDIR", "TERM",
    ]

    /// The allowed variables of `source`, then `overrides`.
    public static func scrubbedEnvironment(overrides: [String: String] = [:], source: [String: String]) -> [String:
        String]
    {
        [:]
    }

    /// Runs `executable` and blocks the calling thread until it exits, the deadline passes, or nothing more can be read.
    /// Each of standard output and standard error keeps at most `outputLimit` bytes; the rest is read and dropped, so a
    /// child that writes a lot never blocks on a full pipe.
    public static func runBlocking(
        _ executable: String, _ arguments: [String], directory: String? = nil, environment: [String: String],
        timeout: Duration = .seconds(120), outputLimit: Int = 1 << 20
    ) throws(Failure) -> Result {
        throw .launchFailed(executable: executable, reason: "not implemented")
    }

    /// ``runBlocking(_:_:directory:environment:timeout:outputLimit:)`` off the cooperative pool; cancelling the task
    /// terminates the child.
    public static func run(
        _ executable: String, _ arguments: [String], directory: String? = nil, environment: [String: String],
        timeout: Duration = .seconds(120), outputLimit: Int = 1 << 20
    ) async throws(Failure) -> Result {
        throw .launchFailed(executable: executable, reason: "not implemented")
    }
}
