internal import Dispatch
internal import Synchronization

#if canImport(Darwin)
    internal import Darwin
#elseif canImport(Glibc)
    internal import Glibc
#endif

/// Turns SIGINT, SIGTERM and SIGHUP into the cancellation of a run, so its supervised children are torn down and its
/// journals closed instead of left behind (ADR-0030).
///
/// A process killed by a signal it does not handle runs no `defer` and cancels no task: Litmus, interrupted, left
/// `xcodebuild` running (2026-11-02). Under ``run(cancellingOn:_:)`` the first signal cancels the operation, which
/// every `BoundedProcess` under it answers by stopping its child and cleaning up its session; a second signal exits at
/// once with 128 plus the signal, for a run that does not stop.
///
/// The design follows swift-service-lifecycle's `UnixSignals` (2.13): on Darwin the signal is ignored so that kqueue,
/// which Dispatch's signal source uses and which ranks below a disposition, delivers it, and the operation starts only
/// once every source is registered, so an early signal is not lost. Unlike `UnixSignals`, the dispositions are restored
/// when the operation ends. A child started by swift-subprocess resets its dispositions (`POSIX_SPAWN_SETSIGDEF`), so
/// the ignored signals do not reach it; one started otherwise inherits them across `exec`.
public enum TerminationSignals {
    /// The signals ``run(cancellingOn:_:)`` handles by default.
    public static let defaultSignals: [Int32] = [SIGINT, SIGTERM, SIGHUP]

    /// The operation was cancelled by a signal.
    public struct Interrupted: Error, Equatable, Sendable {
        public let signal: Int32

        public init(signal: Int32) { self.signal = signal }
        /// The conventional exit status of a process ended by `signal`.
        public var exitStatus: Int32 { 128 + signal }
    }

    /// Runs `operation`, cancelling it on the first of `signals` and exiting the process on the second.
    /// - Returns: What the operation returned, even after a signal, when it finished its work regardless.
    /// - Throws: ``Interrupted`` when a signal arrived and the operation then threw; the operation's error otherwise.
    public static func run<T: Sendable>(
        cancellingOn signals: [Int32] = defaultSignals,
        _ operation: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        let received = Mutex<Int32?>(nil)
        let queue = DispatchQueue(label: "analyzerkit.termination-signals")
        let started = Mutex<Task<T, any Error>?>(nil)
        var sources: [any DispatchSourceSignal] = []
        #if canImport(Darwin)
            var previous: [(Int32, sig_t?)] = []
        #endif
        for number in signals {
            #if canImport(Darwin)
                previous.append((number, signal(number, SIG_IGN)))
            #endif
            let source = DispatchSource.makeSignalSource(signal: number, queue: queue)
            source.setEventHandler {
                let first = received.withLock { value -> Bool in
                    guard value == nil else { return false }
                    value = number
                    return true
                }
                if first {
                    started.withLock { $0 }?.cancel()
                } else {
                    _exit(128 + number)
                }
            }
            await withCheckedContinuation { (registered: CheckedContinuation<Void, Never>) in
                source.setRegistrationHandler { registered.resume() }
                source.resume()
            }
            sources.append(source)
        }
        defer {
            for source in sources { source.cancel() }
            #if canImport(Darwin)
                for (number, handler) in previous { _ = signal(number, handler) }
            #endif
        }
        let task = Task { try await operation() }
        started.withLock { $0 = task }
        // A signal between the registration and the task's creation cancelled nothing yet.
        if received.withLock({ $0 }) != nil { task.cancel() }
        return try await withTaskCancellationHandler {
            do {
                return try await task.value
            } catch {
                if let number = received.withLock({ $0 }) { throw Interrupted(signal: number) }
                throw error
            }
        } onCancel: {
            task.cancel()
        }
    }
}
