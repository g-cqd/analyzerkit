internal import AemiProcess
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
/// toolchain probes, index-store builds and test runs (ADR-0004, ADR-0030; roadmap 0010), on swift-subprocess.
///
/// The child starts a session of its own, with the signal dispositions reset (swift-subprocess sets
/// `POSIX_SPAWN_SETSIGDEF`) and no inherited descriptor beyond the three standard ones (`CLOEXEC_DEFAULT`). It and every
/// process it starts share one process group. A deadline, a cancelled task, a monitor or the memory limit signals that
/// group: SIGTERM, then SIGKILL after ``terminationGrace``, so a build that is stopped leaves no compiler behind, even one
/// that ignores SIGTERM (a disposition the child sets is inherited by what it `exec`s; `xcodebuild` does this).
///
/// A process can leave the group and still belong to the session: `swift test` starts its testing helper in a new
/// group, and a timed-out mutant's helper ran on for 2.5 hours (Litmus, 2026-11-02). So when the child has ended, by
/// any path, every process left in its session is terminated too, and so is every process carrying
/// ``Options/environmentToken`` (a simulator's test host, which no session of ours holds). See ``Options/reapsSession``.
///
/// swiftlang/swift-subprocess#371 (open) reports a child stopped by SIGSTOP read as exited on macOS 26 and 27; a probe
/// here (macOS 27.0.1) saw the deadline end it instead. Should it happen, the session cleanup above still ends the
/// stopped process. Waiting on swift-subprocess for the fix.
///
/// Only a session is asked of swift-subprocess: combined with a process group, a user or a group id, it forks and
/// `exec`s instead of spawning, and that path leaks every descriptor into the child when `/dev/fd` cannot be opened
/// (swiftlang/swift-subprocess#382). A test holds the descriptors a child sees.
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
        /// The signal that ended the child, when one did; ``exitStatus`` is then 128 plus it. Tells a crash from a
        /// program that exits 134 itself.
        public var terminationSignal: Int32? = nil
        /// The child's process id, which is also its session's id.
        public var processIdentifier: Int32 = 0
        /// Why the child was stopped by the run's monitor or memory limit; nil when it ended on its own.
        public var stopReason: String? = nil
        /// Processes left in the child's session, or carrying its environment token, that were killed after it ended.
        public var reaped: [Int32] = []
        /// The usage of the child's session, sampled while it ran; nil when ``Options/sampling`` is off.
        public var usage: SampledUsage? = nil

        public var succeeded: Bool { exitStatus == 0 }
        public var standardOutputText: String { String(decoding: standardOutput, as: UTF8.self) }
        public var standardErrorText: String { String(decoding: standardError, as: UTF8.self) }
    }

    /// What the processes of a child's session used, sampled while it ran.
    ///
    /// Sampled, not exact: the CPU of the last interval before a process ends is not seen, nor a process that lived
    /// less than one interval. The exact usage of the direct child comes from the call that reaps it, which
    /// swift-subprocess makes; swiftlang/swift-subprocess#226 (open) adds `ExecutionResult.resourceUsage`, and this
    /// sampling stays the measure of the whole session, which a reaped child's usage does not cover.
    public struct SampledUsage: Sendable, Equatable {
        /// User and system CPU of every process seen in the session, at its last sample.
        public var cpuNanoseconds: UInt64
        /// The largest footprint of the session at one sample (the sum over its processes).
        public var peakFootprintBytes: UInt64
        public var samples: Int

        public init(cpuNanoseconds: UInt64, peakFootprintBytes: UInt64, samples: Int) {
            self.cpuNanoseconds = cpuNanoseconds
            self.peakFootprintBytes = peakFootprintBytes
            self.samples = samples
        }
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

    /// The clock a deadline is measured on.
    public enum DeadlineClock: Sendable, Hashable {
        /// Running time: a machine asleep does not run the child, and its sleep does not count (the default).
        case suspending
        /// Wall time, sleep included: a laptop closed during a run times out every child on waking.
        case continuous
    }

    /// One piece of a child's output, as it arrives.
    public struct OutputChunk: Sendable {
        public enum Stream: Sendable, Hashable {
            case standardOutput
            case standardError
        }

        public let stream: Stream
        public let bytes: [UInt8]
    }

    /// How a run supervises its child beyond the deadline.
    public struct Options: Sendable {
        /// Terminate, once the child has ended, the processes it left in its session. On by default: a child's
        /// descendant that left the process group still belongs to the session.
        public var reapsSession = true
        /// An environment entry, `NAME=value`, set in the child's environment, whose holders are terminated once the
        /// child has ended, wherever they are: a process started outside the session (a simulator's test host) when the
        /// entry was passed on to it. Unique per run. Apple platform binaries hide their environment; the session
        /// finds those.
        public var environmentToken: String? = nil
        public var deadlineClock = DeadlineClock.suspending
        /// Sample the session's usage at this interval; nil does not sample (``Result/usage`` is nil).
        public var sampling: Duration? = nil
        /// Stop the child when its session's footprint passes this many bytes (sampled at ``sampling``, or every
        /// 100 ms when that is nil). ``Result/stopReason`` then says so.
        public var memoryLimitBytes: UInt64? = nil
        /// Called with each piece of output as it arrives, from the task reading it.
        public var outputObserver: (@Sendable (OutputChunk) -> Void)? = nil
        /// The scheduling class of the child and what it starts.
        public var priority = Priority.inherited

        public init() {}
    }

    /// How the system schedules a child. Darwin maps these to quality-of-service classes, which also choose between
    /// performance and efficiency cores; elsewhere every value runs as ``inherited``.
    public enum Priority: Sendable, Hashable {
        /// The caller's own class (the default).
        case inherited
        /// Long-running work the user is not waiting on: still progresses under load.
        case utility
        /// Work that yields to everything else: a run on a machine someone is using. Slower, and its timings vary.
        case background
    }

    /// The child, as the run's monitor sees it.
    public struct ProcessControl: Sendable {
        /// The child's process id, which is also its session's id.
        public let processIdentifier: Int32
        fileprivate let requests: AsyncStream<String>.Continuation

        /// Stops the child (its group: SIGTERM, then SIGKILL after the grace) and records `reason` in
        /// ``Result/stopReason``. The first reason is kept; later calls do nothing.
        public func stop(reason: String) {
            requests.yield(reason)
        }
    }

    /// Which variables a child inherits.
    public enum EnvironmentPolicy: Sendable, Hashable {
        /// ``allowedEnvironmentKeys`` only.
        case scrubbed
        /// Those, and what selects a toolchain and an SDK: `DEVELOPER_DIR`, `TOOLCHAINS`, `SDKROOT`.
        case toolchain
        /// ``allowedEnvironmentKeys`` and these.
        case scrubbedAdding(Set<String>)

        /// The variables kept from the source environment.
        public var keys: Set<String> {
            switch self {
            case .scrubbed: allowedEnvironmentKeys
            case .toolchain: allowedEnvironmentKeys.union(["DEVELOPER_DIR", "TOOLCHAINS", "SDKROOT"])
            case .scrubbedAdding(let extra): allowedEnvironmentKeys.union(extra)
            }
        }
    }

    /// Variables a child inherits; everything else is dropped, `DYLD_*`, `LD_*`, `DEVELOPER_DIR`, `SHELL` and `BASH_ENV`
    /// included.
    public static let allowedEnvironmentKeys: Set<String> = [
        "PATH", "HOME", "USER", "LOGNAME", "LANG", "LC_ALL", "LC_CTYPE", "LC_MESSAGES", "TMPDIR", "TERM",
    ]

    /// The allowed variables of `source`, then `overrides`.
    public static func scrubbedEnvironment(
        overrides: [String: String] = [:],
        source: [String: String]
    ) -> [String: String] {
        environment(.scrubbed, overrides: overrides, source: source)
    }

    /// The variables of `source` that `policy` keeps, then `overrides`.
    ///
    /// A `DYLD_*` override reaches the child only when the child is not protected by System Integrity Protection: dyld
    /// drops those variables when it loads a protected executable (`/bin/sh`, `/usr/bin/env`), and that executable
    /// does not pass them on to what it runs (measured on macOS 27).
    public static func environment(
        _ policy: EnvironmentPolicy,
        overrides: [String: String] = [:],
        source: [String: String]
    ) -> [String: String] {
        let keys = policy.keys
        var environment = source.filter { keys.contains($0.key) }
        for (key, value) in overrides { environment[key] = value }
        return environment
    }

    /// Runs `executable` until it exits, the deadline passes, the task is cancelled, or the monitor or the memory limit
    /// stops it. Each of standard output and standard error keeps at most `outputLimit` bytes; the rest is read and
    /// dropped, so a child that writes a lot never blocks on a full pipe.
    ///
    /// - Parameter monitor: Runs beside the child from its start and can stop it through ``ProcessControl/stop(reason:)``.
    ///   It is cancelled when the child has ended, and must then return: the run waits for it.
    public static func run(
        _ executable: String,
        _ arguments: [String],
        directory: String? = nil,
        environment: [String: String],
        timeout: Duration = .seconds(120),
        outputLimit: Int = 1 << 20,
        options: Options = Options(),
        monitor: (@Sendable (ProcessControl) async -> Void)? = nil
    ) async throws(Failure) -> Result {
        guard executable.hasPrefix("/") else { throw .notAbsolute(executable) }
        guard !Task.isCancelled else { throw .cancelled(executable: executable) }
        var platform = PlatformOptions()
        platform.createSession = true
        #if canImport(Darwin)
            switch options.priority {
            case .inherited: break
            case .utility: platform.qualityOfService = .utility
            case .background: platform.qualityOfService = .background
            }
        #endif
        platform.teardownSequence = [
            .gracefulShutDown(toProcessGroup: true, allowedDurationToNextStep: terminationGrace)
        ]
        var variables: [Environment.Key: String] = [:]
        for (key, value) in environment { variables[Environment.Key(stringLiteral: key)] = value }
        if let token = options.environmentToken, let equals = token.firstIndex(of: "=") {
            variables[Environment.Key(stringLiteral: String(token[..<equals]))] = String(
                token[token.index(after: equals)...]
            )
        }
        let configuration = Configuration(
            executable: .path(FilePath(executable)),
            arguments: Arguments(arguments),
            environment: .custom(variables),
            workingDirectory: directory.map { FilePath($0) },
            platformOptions: platform
        )
        // Processes started from a second before the launch on: the start times are whole microseconds on Darwin,
        // clock ticks on Linux.
        let since = microsecondsSince1970() - 1_000_000
        let launched = Mutex<Int32?>(nil)
        let outcome: ExecutionResult<Collected, SequenceOutput, SequenceOutput>
        do {
            outcome = try await Subprocess.run(configuration, input: .none, output: .sequence, error: .sequence) {
                execution in
                launched.withLock { $0 = execution.processIdentifier.value }
                return try await collect(
                    execution,
                    timeout: timeout,
                    limit: outputLimit,
                    options: options,
                    monitor: monitor
                )
            }
        } catch let stopped as Stopped {
            await cleanUp(launched.withLock { $0 }, since: since, options: options)
            throw stopped.failure(executable: executable, timeout: timeout)
        } catch is CancellationError {
            await cleanUp(launched.withLock { $0 }, since: since, options: options)
            throw .cancelled(executable: executable)
        } catch {
            await cleanUp(launched.withLock { $0 }, since: since, options: options)
            throw .launchFailed(executable: executable, reason: "\(error)")
        }
        let pid = outcome.processIdentifier.value
        let reaped = await cleanUp(pid, since: since, options: options)
        // Subprocess tears a cancelled task's child down itself; its outputs then end as if it had finished.
        guard !Task.isCancelled else { throw .cancelled(executable: executable) }
        let (status, signal): (Int32, Int32?) =
            switch outcome.terminationStatus {
            case .exited(let code): (Int32(code), nil)
            case .signaled(let signal): (128 + Int32(signal), Int32(signal))
            }
        var result = Result(
            exitStatus: status,
            standardOutput: outcome.closureResult.output,
            standardError: outcome.closureResult.error,
            outputTruncated: outcome.closureResult.truncated
        )
        result.terminationSignal = signal
        result.processIdentifier = pid
        result.stopReason = outcome.closureResult.stopReason
        result.reaped = reaped
        result.usage = options.sampling == nil ? nil : outcome.closureResult.usage
        return result
    }

    /// Both outputs, as far as the limit, and what the supervision saw.
    private struct Collected: Sendable {
        var output: [UInt8] = []
        var error: [UInt8] = []
        var truncated = false
        var stopReason: String?
        var usage: SampledUsage?
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
        case stopped(String)
        case usage(SampledUsage)
        /// A helper task ended without anything to report (the monitor returned).
        case idle
    }

    /// Reads both outputs until they end, racing the deadline, the monitor and the sampler. On the deadline, a stop
    /// request, or when the task is cancelled, the child's group is stopped here, while the child is not yet reaped and
    /// its process-group id cannot be reused.
    private static func collect(
        _ execution: Execution<NoInput, SequenceOutput, SequenceOutput>,
        timeout: Duration,
        limit: Int,
        options: Options,
        monitor: (@Sendable (ProcessControl) async -> Void)?
    ) async throws -> Collected {
        let group = execution.processIdentifier.value
        let finished = Finished()
        let (requests, requester) = AsyncStream<String>.makeStream()
        let control = ProcessControl(processIdentifier: group, requests: requester)
        do {
            return try await withThrowingTaskGroup(of: Event.self) { tasks in
                tasks.addTask {
                    defer { finished.count.add(1, ordering: .relaxed) }
                    let (bytes, truncated) = try await drain(
                        execution.standardOutput,
                        limit: limit,
                        stream: .standardOutput,
                        observer: options.outputObserver
                    )
                    return .output(bytes, truncated: truncated)
                }
                tasks.addTask {
                    defer { finished.count.add(1, ordering: .relaxed) }
                    let (bytes, truncated) = try await drain(
                        execution.standardError,
                        limit: limit,
                        stream: .standardError,
                        observer: options.outputObserver
                    )
                    return .error(bytes, truncated: truncated)
                }
                tasks.addTask {
                    switch options.deadlineClock {
                    case .suspending: try await Task.sleep(for: timeout, clock: .suspending)
                    case .continuous: try await Task.sleep(for: timeout, clock: .continuous)
                    }
                    return .deadline
                }
                tasks.addTask {
                    for await reason in requests { return .stopped(reason) }
                    return .idle
                }
                if let monitor {
                    tasks.addTask {
                        await monitor(control)
                        return .idle
                    }
                }
                if options.sampling != nil || options.memoryLimitBytes != nil {
                    tasks.addTask {
                        .usage(await sample(session: group, options: options, control: control))
                    }
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
                    case .stopped(let reason):
                        if collected.stopReason == nil {
                            collected.stopReason = reason
                            await stop(group: group, finished: finished)
                        }
                    case .usage(let usage):
                        collected.usage = usage
                    case .idle:
                        break
                    }
                    if outputs == 2 {
                        requester.finish()
                        tasks.cancelAll()
                        // The sampler returns what it saw when cancelled; the other helpers report nothing more.
                        while true {
                            do {
                                guard let event = try await tasks.next() else { break }
                                if case .usage(let usage) = event { collected.usage = usage }
                            } catch {
                                continue  // the deadline's sleep, cancelled
                            }
                        }
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

    /// Samples the session until cancelled, stopping the child through `control` past the memory limit.
    private static func sample(session: Int32, options: Options, control: ProcessControl) async -> SampledUsage {
        let interval = options.sampling ?? .milliseconds(100)
        var cpu: [ProcessKey: UInt64] = [:]
        var usage = SampledUsage(cpuNanoseconds: 0, peakFootprintBytes: 0, samples: 0)
        while !Task.isCancelled {
            var footprint: UInt64 = 0
            for process in ProcessTable.members(ofSession: session) {
                guard let live = ProcessTable.usage(of: process.pid) else { continue }
                cpu[ProcessKey(pid: process.pid, started: process.started)] = live.cpuNanoseconds
                footprint &+= live.footprintBytes
            }
            usage.samples += 1
            usage.peakFootprintBytes = max(usage.peakFootprintBytes, footprint)
            usage.cpuNanoseconds = cpu.values.reduce(0, &+)
            if let limit = options.memoryLimitBytes, footprint > limit {
                control.stop(reason: "memory limit: the session's footprint reached \(footprint) bytes, over \(limit)")
            }
            try? await Task.sleep(for: interval)
        }
        return usage
    }

    /// One process over its life: a pid can be reused.
    private struct ProcessKey: Hashable {
        let pid: Int32
        let started: Int64
    }

    /// Terminates what the child left: the processes of its session, and those carrying its environment token, started
    /// since `since`. SIGTERM, then SIGKILL to the survivors after the grace (at once when the task is cancelled).
    /// Returns the processes signalled.
    @discardableResult
    private static func cleanUp(_ session: Int32?, since: Int64, options: Options) async -> [Int32] {
        let me = getpid()
        let mySession = getsid(0)
        func leftovers() -> [ProcessTable.Process] {
            ProcessTable.list().filter { process in
                guard process.pid != me, process.pid > 1, process.started >= since else { return false }
                if options.reapsSession, let session, session > 1, session != mySession, process.session == session {
                    return true
                }
                if let token = options.environmentToken {
                    return ProcessTable.environment(of: process.pid, contains: token)
                }
                return false
            }
        }
        guard options.reapsSession || options.environmentToken != nil else { return [] }
        var signalled: [Int32] = []
        // New processes can appear while the first ones are stopped (a shell's last act); a few rounds catch them.
        for _ in 0..<4 {
            let found = leftovers()
            if found.isEmpty { break }
            for process in found where ProcessTable.send(SIGTERM, to: process.pid) { signalled.append(process.pid) }
            let deadline = ContinuousClock.now + terminationGrace
            var alive = found
            while !alive.isEmpty, ContinuousClock.now < deadline, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(20))
                let current = Set(ProcessTable.list().map { ProcessKey(pid: $0.pid, started: $0.started) })
                alive = alive.filter { current.contains(ProcessKey(pid: $0.pid, started: $0.started)) }
            }
            for process in alive { ProcessTable.send(SIGKILL, to: process.pid) }
        }
        return Array(Set(signalled)).sorted()
    }

    private static func microsecondsSince1970() -> Int64 {
        var now = timeval()
        _ = unsafe gettimeofday(&now, nil)
        return Int64(now.tv_sec) * 1_000_000 + Int64(now.tv_usec)
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

    private static func drain(
        _ sequence: SubprocessOutputSequence,
        limit: Int,
        stream: OutputChunk.Stream,
        observer: (@Sendable (OutputChunk) -> Void)?
    ) async throws -> ([UInt8], Bool) {
        var bytes: [UInt8] = []
        var truncated = false
        for try await buffer in sequence {
            unsafe buffer.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                if let observer { observer(OutputChunk(stream: stream, bytes: unsafe Array(raw))) }
                let room = max(0, limit - bytes.count)
                if raw.count > room { truncated = true }
                unsafe bytes.append(contentsOf: raw.prefix(room))
            }
        }
        return (bytes, truncated)
    }
}
