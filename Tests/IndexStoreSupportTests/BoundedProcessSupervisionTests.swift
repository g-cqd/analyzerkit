import Foundation
import Synchronization
import Testing

@testable import IndexStoreSupport

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

/// What a run leaves behind and how it is supervised (ADR-0030): a child's descendants that left its group, a process
/// holding its token, the signal that ended it, a monitor, sampled usage and a memory limit.
@Suite struct BoundedProcessSupervisionTests {
    private let environment = BoundedProcess.scrubbedEnvironment(source: ProcessInfo.processInfo.environment)
    private static let perl = "/usr/bin/perl"

    /// Whether `pid` stopped executing; a container without a reaping init can keep its zombie forever.
    private func gone(_ pid: Int32) async throws -> Bool {
        for _ in 0..<100 {
            if BoundedProcess.hasTerminated(pid) { return true }
            try await Task.sleep(for: .milliseconds(20))
        }
        return false
    }

    private func marker() -> String {
        FileManager.default.temporaryDirectory.appending(path: "bounded-\(UUID().uuidString)").path
    }

    private func pid(in path: String) throws -> Int32 {
        try #require(
            Int32(String(contentsOfFile: path, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))
        )
    }

    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: perl)))
    func `a descendant that left the group is terminated once the child has exited`() async throws {
        let path = marker()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let result = try await BoundedProcess.run(
            Self.perl,
            [
                "-e",
                "if (fork() == 0) { setpgrp(0,0); open(F, '>', '\(path)'); print F $$; close F; sleep 60; exit 0 } sleep 1; exit 0",
            ],
            environment: environment
        )
        #expect(result.exitStatus == 0)
        let escaped = try pid(in: path)
        #expect(result.reaped.contains(escaped))
        #expect(try await gone(escaped))
    }

    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: perl)))
    func `a descendant that left the group is terminated when the child times out`() async throws {
        let path = marker()
        defer { try? FileManager.default.removeItem(atPath: path) }
        await #expect(throws: BoundedProcess.Failure.self) {
            try await BoundedProcess.run(
                Self.perl,
                [
                    "-e",
                    "if (fork() == 0) { setpgrp(0,0); open(F, '>', '\(path)'); print F $$; close F; sleep 60; exit 0 } sleep 60",
                ],
                environment: environment,
                timeout: .milliseconds(800)
            )
        }
        #expect(try await gone(try pid(in: path)))
    }

    @Test func `nothing is reaped when the session is left alone`() async throws {
        var options = BoundedProcess.Options()
        options.reapsSession = false
        let result = try await BoundedProcess.run(
            "/bin/sh",
            ["-c", "exit 0"],
            environment: environment,
            options: options
        )
        #expect(result.reaped.isEmpty)
        #expect(result.processIdentifier > 1)
    }

    /// A process outside the child's session (it called `setsid`) that holds the token. Apple platform binaries hide
    /// their environment, so on macOS the holder must be another executable: Xcode's Python.
    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: tokenHolder)))
    func `a process that left the session is found by the token it carries`() async throws {
        let path = marker()
        defer { try? FileManager.default.removeItem(atPath: path) }
        var options = BoundedProcess.Options()
        options.environmentToken = "ANALYZERKIT_TEST_TOKEN=\(UUID().uuidString)"
        let script = """
            import os, time
            if os.fork() == 0:
                os.setsid()
                with open('\(path)', 'w') as f: f.write(str(os.getpid()))
                time.sleep(60)
            time.sleep(0.5)
            """
        let result = try await BoundedProcess.run(
            Self.tokenHolder,
            ["-c", script],
            environment: environment,
            options: options
        )
        let holder = try pid(in: path)
        #expect(result.reaped.contains(holder))
        #expect(try await gone(holder))
    }

    private static var tokenHolder: String {
        #if os(macOS)
            "/Applications/Xcode.app/Contents/Developer/usr/bin/python3"
        #else
            "/usr/bin/python3"
        #endif
    }

    @Test func `the signal that ended the child is reported`() async throws {
        let result = try await BoundedProcess.run("/bin/sh", ["-c", "kill -SEGV $$"], environment: environment)
        #expect(result.terminationSignal == SIGSEGV)
        #expect(result.exitStatus == 128 + SIGSEGV)
        let exited = try await BoundedProcess.run("/bin/sh", ["-c", "exit 139"], environment: environment)
        #expect(exited.terminationSignal == nil)
        #expect(exited.exitStatus == 139)
    }

    @Test func `a monitor stops the child and the reason is kept`() async throws {
        let start = ContinuousClock.now
        let result = try await BoundedProcess.run(
            "/bin/sleep",
            ["30"],
            environment: environment,
            timeout: .seconds(20)
        ) { control in
            #expect(control.processIdentifier > 1)
            try? await Task.sleep(for: .milliseconds(200))
            control.stop(reason: "seen enough")
            control.stop(reason: "a second reason is ignored")
        }
        #expect(result.stopReason == "seen enough")
        #expect(result.terminationSignal == SIGTERM)
        #expect(ContinuousClock.now - start < .seconds(5))
    }

    @Test func `a monitor that never stops the child does not change the run`() async throws {
        let result = try await BoundedProcess.run("/bin/sh", ["-c", "echo done"], environment: environment) { _ in
            try? await Task.sleep(for: .seconds(60))
        }
        #expect(result.stopReason == nil)
        #expect(result.standardOutputText == "done\n")
    }

    @Test func `the session's usage is sampled while the child runs`() async throws {
        var options = BoundedProcess.Options()
        options.sampling = .milliseconds(20)
        let result = try await BoundedProcess.run(
            "/bin/sh",
            ["-c", "i=0; while [ $i -lt 80000 ]; do i=$((i+1)); done"],
            environment: environment,
            options: options
        )
        let usage = try #require(result.usage)
        #expect(usage.samples > 1)
        #expect(usage.cpuNanoseconds > 0)
        #expect(usage.peakFootprintBytes > 0)
    }

    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: perl)))
    func `a child past the memory limit is stopped`() async throws {
        var options = BoundedProcess.Options()
        options.memoryLimitBytes = 64 << 20
        options.sampling = .milliseconds(25)
        let result = try await BoundedProcess.run(
            Self.perl,
            ["-e", "my $x = 'a' x 400_000_000; sleep 30"],
            environment: environment,
            timeout: .seconds(20),
            options: options
        )
        #expect(result.stopReason?.hasPrefix("memory limit") == true)
        #expect((result.usage?.peakFootprintBytes ?? 0) > 64 << 20)
    }

    @Test func `the continuous clock is a deadline too`() async {
        var options = BoundedProcess.Options()
        options.deadlineClock = .continuous
        await #expect(throws: BoundedProcess.Failure.timedOut(executable: "/bin/sleep", after: .milliseconds(300))) {
            try await BoundedProcess.run(
                "/bin/sleep",
                ["30"],
                environment: environment,
                timeout: .milliseconds(300),
                options: options
            )
        }
    }

    /// Only the three standard descriptors reach the child, even one this process opened without close-on-exec.
    @Test func `no descriptor of this process reaches the child`() async throws {
        let path = marker()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let descriptor = unsafe open(path, O_CREAT | O_RDWR, 0o600)
        try #require(descriptor > 2)
        defer { close(descriptor) }
        #if os(Linux)
            let listing = "ls /proc/self/fd"
        #else
            let listing = "ls /dev/fd"
        #endif
        let result = try await BoundedProcess.run("/bin/sh", ["-c", listing], environment: environment)
        let open = Set(result.standardOutputText.split(whereSeparator: \.isWhitespace).compactMap { Int32($0) })
        #expect(!open.contains(descriptor))
        #expect(open.isSuperset(of: [0, 1, 2]))
    }

    @Test func `every piece of output reaches the observer`() async throws {
        let seen = Mutex<[UInt8]>([])
        var options = BoundedProcess.Options()
        options.outputObserver = { chunk in
            if chunk.stream == .standardOutput { seen.withLock { $0 += chunk.bytes } }
        }
        let result = try await BoundedProcess.run(
            "/bin/sh",
            ["-c", "echo one; sleep 0.1; echo two"],
            environment: environment,
            options: options
        )
        #expect(seen.withLock { $0 } == result.standardOutput)
    }

    @Test func `the toolchain policy keeps what selects a toolchain`() {
        let source = ["PATH": "/bin", "DEVELOPER_DIR": "/X", "SDKROOT": "/S", "TOOLCHAINS": "t", "SECRET": "s"]
        #expect(
            BoundedProcess.environment(.toolchain, source: source) == [
                "PATH": "/bin", "DEVELOPER_DIR": "/X", "SDKROOT": "/S", "TOOLCHAINS": "t",
            ]
        )
        #expect(
            BoundedProcess.environment(.scrubbed, overrides: ["A": "1"], source: source) == ["PATH": "/bin", "A": "1"]
        )
        #expect(
            BoundedProcess.environment(.scrubbedAdding(["SECRET"]), source: source) == ["PATH": "/bin", "SECRET": "s"]
        )
    }

    @Test func `a child runs at a lower priority when asked`() async throws {
        for priority in [BoundedProcess.Priority.utility, .background] {
            var options = BoundedProcess.Options()
            options.priority = priority
            let result = try await BoundedProcess.run(
                "/bin/sh",
                ["-c", "echo ok"],
                environment: environment,
                options: options
            )
            #expect(result.standardOutputText == "ok\n")
        }
    }
}

extension BoundedProcessSupervisionTests {
    @Test func `the termination check distinguishes a live process from a missing one`() {
        #expect(!BoundedProcess.hasTerminated(getpid()))
        #expect(BoundedProcess.hasTerminated(Int32.max))
    }
}
