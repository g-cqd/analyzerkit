internal import Dispatch
internal import Foundation

#if canImport(Darwin)
    internal import Darwin
#elseif canImport(Glibc)
    internal import Glibc
#endif

/// Runs a subprocess with a deadline, a cap on the output kept, and a scrubbed environment: the one executor for
/// toolchain probes and index-store builds (ADR-0004; roadmap 0010).
public enum BoundedProcess {
    /// How long a child that was asked to stop has before it is killed.
    static let terminationGrace: DispatchTimeInterval = .seconds(2)
    /// How long the output readers get, once the child is gone, to see the end of its pipes: a grandchild that kept
    /// them open does not hold the run.
    static let drainGrace: DispatchTimeInterval = .seconds(2)

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
    public static func scrubbedEnvironment(
        overrides: [String: String] = [:], source: [String: String]
    ) -> [String: String] {
        var environment = source.filter { allowedEnvironmentKeys.contains($0.key) }
        for (key, value) in overrides { environment[key] = value }
        return environment
    }

    /// Runs `executable` and blocks the calling thread until it exits, the deadline passes, or nothing more can be read.
    /// Each of standard output and standard error keeps at most `outputLimit` bytes; the rest is read and dropped, so a
    /// child that writes a lot never blocks on a full pipe.
    public static func runBlocking(
        _ executable: String, _ arguments: [String], directory: String? = nil, environment: [String: String],
        timeout: Duration = .seconds(120), outputLimit: Int = 1 << 20
    ) throws(Failure) -> Result {
        try execute(
            executable, arguments, directory: directory, environment: environment, timeout: timeout,
            outputLimit: outputLimit, isCancelled: { false })
    }

    /// ``runBlocking(_:_:directory:environment:timeout:outputLimit:)`` off the cooperative pool; cancelling the task
    /// terminates the child.
    public static func run(
        _ executable: String, _ arguments: [String], directory: String? = nil, environment: [String: String],
        timeout: Duration = .seconds(120), outputLimit: Int = 1 << 20
    ) async throws(Failure) -> Result {
        let cancelled = Flag()
        let outcome: Swift.Result<Result, Failure> = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                DispatchQueue.global().async {
                    continuation.resume(
                        returning: Swift.Result { () throws(Failure) -> Result in
                            try execute(
                                executable, arguments, directory: directory, environment: environment,
                                timeout: timeout, outputLimit: outputLimit, isCancelled: { cancelled.isSet })
                        })
                }
            }
        } onCancel: {
            cancelled.set()
        }
        return try outcome.get()
    }

    private static func execute(
        _ executable: String, _ arguments: [String], directory: String?, environment: [String: String],
        timeout: Duration, outputLimit: Int, isCancelled: () -> Bool
    ) throws(Failure) -> Result {
        guard executable.hasPrefix("/") else { throw .notAbsolute(executable) }
        guard !isCancelled() else { throw .cancelled(executable: executable) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        if let directory { process.currentDirectoryURL = URL(fileURLWithPath: directory) }
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        process.standardInput = FileHandle.nullDevice
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do {
            try process.run()
        } catch {
            throw .launchFailed(executable: executable, reason: "\(error)")
        }
        let drained = DispatchGroup()
        let standardOutput = Drain(output.fileHandleForReading, limit: outputLimit, group: drained)
        let standardError = Drain(errors.fileHandleForReading, limit: outputLimit, group: drained)

        let deadline = DispatchTime.now() + interval(timeout)
        var stopped: Failure?
        while exited.wait(timeout: min(DispatchTime.now() + .milliseconds(20), deadline)) == .timedOut {
            if isCancelled() {
                stopped = .cancelled(executable: executable)
            } else if DispatchTime.now() >= deadline {
                stopped = .timedOut(executable: executable, after: timeout)
            }
            if stopped != nil { break }
        }
        if let stopped {
            process.terminate()
            if exited.wait(timeout: .now() + terminationGrace) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                exited.wait()
            }
            _ = drained.wait(timeout: .now() + drainGrace)
            throw stopped
        }
        _ = drained.wait(timeout: .now() + drainGrace)
        let out = standardOutput.snapshot()
        let err = standardError.snapshot()
        return Result(
            exitStatus: process.terminationStatus, standardOutput: out.bytes, standardError: err.bytes,
            outputTruncated: out.truncated || err.truncated)
    }

    private static func interval(_ duration: Duration) -> DispatchTimeInterval {
        let (seconds, attoseconds) = duration.components
        let total = seconds.multipliedReportingOverflow(by: 1_000_000_000)
        guard !total.overflow, seconds >= 0 else { return .never }
        return .nanoseconds(Int(clamping: total.partialValue + attoseconds / 1_000_000_000))
    }

    /// Reads one pipe to its end on a thread of its own, keeping the first `limit` bytes.
    private final class Drain: @unchecked Sendable {
        private let lock = NSLock()
        private var bytes: [UInt8] = []
        private var truncated = false

        init(_ handle: FileHandle, limit: Int, group: DispatchGroup) {
            group.enter()
            DispatchQueue.global().async { [self] in
                defer { group.leave() }
                while true {
                    let chunk = handle.availableData
                    if chunk.isEmpty { return }
                    lock.lock()
                    let room = max(0, limit - bytes.count)
                    if chunk.count > room { truncated = true }
                    bytes += chunk.prefix(room)
                    lock.unlock()
                }
            }
        }

        func snapshot() -> (bytes: [UInt8], truncated: Bool) {
            lock.lock()
            defer { lock.unlock() }
            return (bytes, truncated)
        }
    }

    /// Set once, from any thread.
    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false

        var isSet: Bool {
            lock.lock()
            defer { lock.unlock() }
            return value
        }

        func set() {
            lock.lock()
            value = true
            lock.unlock()
        }
    }
}
