import AnalyzerCLI
import Foundation
import Testing

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

/// A signal cancels the run instead of killing the process (ADR-0030). Serialized: the tests signal this process.
@Suite(.serialized) struct TerminationSignalsTests {
    @Test func `a signal cancels the operation, which ends as interrupted`() async throws {
        await #expect(throws: TerminationSignals.Interrupted(signal: SIGHUP)) {
            try await TerminationSignals.run(cancellingOn: [SIGHUP]) {
                Task {
                    try? await Task.sleep(for: .milliseconds(100))
                    kill(getpid(), SIGHUP)
                }
                try await Task.sleep(for: .seconds(30))
                return 0
            }
        }
    }

    @Test func `an operation that finishes after the signal keeps its result`() async throws {
        let value = try await TerminationSignals.run(cancellingOn: [SIGHUP]) {
            kill(getpid(), SIGHUP)
            // Finishing regardless: a run that writes its partial report when cancelled.
            try? await Task.sleep(for: .milliseconds(200))
            return 42
        }
        #expect(value == 42)
    }

    @Test func `an operation's own error passes through when no signal came`() async {
        struct Own: Error, Equatable {}
        await #expect(throws: Own()) {
            try await TerminationSignals.run(cancellingOn: [SIGHUP]) { () async throws -> Int in throw Own() }
        }
    }

    /// The disposition is restored: a later SIGHUP to a child that inherits it is not ignored.
    @Test func `the signal's disposition is restored afterwards`() async throws {
        _ = try await TerminationSignals.run(cancellingOn: [SIGHUP]) { 1 }
        #if canImport(Darwin)
            let current = signal(SIGHUP, SIG_DFL)
            #expect(unsafe unsafeBitCast(current, to: Int.self) == unsafeBitCast(SIG_DFL, to: Int.self))
        #endif
        #expect(TerminationSignals.Interrupted(signal: SIGINT).exitStatus == 130)
    }
}
