internal import Subprocess
internal import Synchronization

#if canImport(System)
    internal import System
#else
    internal import SystemPackage
#endif
#if canImport(Darwin)
    internal import Darwin
#elseif canImport(Glibc)
    internal import Glibc
#endif

/// Runs a subprocess with a deadline, a cap on the output kept, and a scrubbed environment: the one executor for
/// toolchain probes and index-store builds (ADR-0004; roadmap 0010), on swift-subprocess.
///
/// The child starts a session of its own, so it and every process it starts share one process group. A deadline or a
/// cancelled task signals that group: SIGTERM, then SIGKILL after ``terminationGrace``, so a build that is stopped leaves
/// no compiler behind, even one that ignores SIGTERM (an ignored signal survives `exec`).
public enum BoundedProcess {
    /// How long a stopped group has between SIGTERM and SIGKILL.
    public static let terminationGrace: Duration = .seconds(2)

    /// What a finished child left.
    public struct Result: Sendable, Equatable {
        /// The exit status; for a child killed by a signal, 128 plus the signal, as shells report it.
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
        /// The deadline passed; the child's process group was terminated, then killed if it lingered.
        case timedOut(executable: String, after: Duration)
        /// The calling task was cancelled; the child's process group was terminated.
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

    /// Runs `executable` until it exits, the deadline passes, or the task is cancelled. Each of standard output and
    /// standard error keeps at most `outputLimit` bytes; the rest is read and dropped, so a child that writes a lot never
    /// blocks on a full pipe.
    public static func run(
        _ executable: String, _ arguments: [String], directory: String? = nil, environment: [String: String],
        timeout: Duration = .seconds(120), outputLimit: Int = 1 << 20
    ) async throws(Failure) -> Result {
        guard executable.hasPrefix("/") else { throw .notAbsolute(executable) }
        guard !Task.isCancelled else { throw .cancelled(executable: executable) }
        var options = PlatformOptions()
        options.createSession = true
        options.teardownSequence = [
            .gracefulShutDown(toProcessGroup: true, allowedDurationToNextStep: terminationGrace)
        ]
        var variables: [Environment.Key: String] = [:]
        for (key, value) in environment { variables[Environment.Key(stringLiteral: key)] = value }
        let configuration = Configuration(
            executable: .path(FilePath(executable)), arguments: Arguments(arguments),
            environment: .custom(variables), workingDirectory: directory.map { FilePath($0) },
            platformOptions: options)
        let outcome: ExecutionResult<Collected, SequenceOutput, SequenceOutput>
        do {
            outcome = try await Subprocess.run(configuration, input: .none, output: .sequence, error: .sequence) {
                execution in
                try await collect(execution, timeout: timeout, limit: outputLimit)
            }
        } catch let stopped as Stopped {
            throw stopped.failure(executable: executable, timeout: timeout)
        } catch is CancellationError {
            throw .cancelled(executable: executable)
        } catch {
            throw .launchFailed(executable: executable, reason: "\(error)")
        }
        // Subprocess tears a cancelled task's child down itself; its outputs then end as if it had finished.
        guard !Task.isCancelled else { throw .cancelled(executable: executable) }
        let status: Int32 =
            switch outcome.terminationStatus {
            case .exited(let code): Int32(code)
            case .signaled(let signal): 128 + Int32(signal)
            }
        return Result(
            exitStatus: status, standardOutput: outcome.closureResult.output,
            standardError: outcome.closureResult.error,
            outputTruncated: outcome.closureResult.truncated)
    }

    /// Both outputs, as far as the limit.
    private struct Collected: Sendable {
        var output: [UInt8] = []
        var error: [UInt8] = []
        var truncated = false
    }

    /// Why the body stopped the child; turned into a ``Failure`` once Subprocess has torn it down.
    private enum Stopped: Error {
        case deadline
        case cancelled

        func failure(executable: String, timeout: Duration) -> Failure {
            switch self {
            case .deadline: .timedOut(executable: executable, after: timeout)
            case .cancelled: .cancelled(executable: executable)
            }
        }
    }

    private enum Event: Sendable {
        case output([UInt8], truncated: Bool)
        case error([UInt8], truncated: Bool)
        case deadline
    }

    /// Reads both outputs until they end, racing the deadline. On the deadline, or when the task is cancelled, the
    /// child's group is stopped here, while the child is not yet reaped and its process-group id cannot be reused.
    private static func collect(
        _ execution: Execution<NoInput, SequenceOutput, SequenceOutput>, timeout: Duration, limit: Int
    ) async throws -> Collected {
        let group = execution.processIdentifier.value
        let finished = Finished()
        do {
            return try await withThrowingTaskGroup(of: Event.self) { tasks in
                tasks.addTask {
                    defer { finished.count.add(1, ordering: .relaxed) }
                    let (bytes, truncated) = try await drain(execution.standardOutput, limit: limit)
                    return .output(bytes, truncated: truncated)
                }
                tasks.addTask {
                    defer { finished.count.add(1, ordering: .relaxed) }
                    let (bytes, truncated) = try await drain(execution.standardError, limit: limit)
                    return .error(bytes, truncated: truncated)
                }
                tasks.addTask {
                    try await Task.sleep(for: timeout)
                    return .deadline
                }
                var collected = Collected()
                var outputs = 0
                while let event = try await tasks.next() {
                    switch event {
                    case .output(let bytes, let truncated):
                        collected.output = bytes
                        collected.truncated = collected.truncated || truncated
                        outputs += 1
                    case .error(let bytes, let truncated):
                        collected.error = bytes
                        collected.truncated = collected.truncated || truncated
                        outputs += 1
                    case .deadline:
                        await stop(group: group, finished: finished)
                        tasks.cancelAll()
                        throw Stopped.deadline
                    }
                    if outputs == 2 {
                        tasks.cancelAll()
                        return collected
                    }
                }
                return collected
            }
        } catch let stopped as Stopped {
            throw stopped
        } catch {
            // Cancellation reached the readers or the deadline's sleep.
            await stop(group: group, finished: finished)
            throw Stopped.cancelled
        }
    }

    /// SIGTERM to the group, then SIGKILL once both outputs have ended or the grace has passed.
    private static func stop(group: pid_t, finished: Finished) async {
        kill(-group, SIGTERM)
        let deadline = ContinuousClock.now + terminationGrace
        while finished.count.load(ordering: .relaxed) < 2 && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        kill(-group, SIGKILL)
    }

    /// How many of the two outputs have ended.
    private final class Finished: Sendable {
        let count = Atomic<Int>(0)
    }

    private static func drain(_ sequence: SubprocessOutputSequence, limit: Int) async throws -> ([UInt8], Bool) {
        var bytes: [UInt8] = []
        var truncated = false
        for try await buffer in sequence {
            unsafe buffer.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                let room = max(0, limit - bytes.count)
                if raw.count > room { truncated = true }
                unsafe bytes.append(contentsOf: raw.prefix(room))
            }
        }
        return (bytes, truncated)
    }
}
