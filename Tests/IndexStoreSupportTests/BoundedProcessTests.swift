import Foundation
import IndexStoreSupport
import Testing

/// The executor every index-store build and toolchain probe goes through (ADR-0004): a deadline, a cap on what it keeps,
/// a scrubbed environment.
@Suite struct BoundedProcessTests {
    private let environment = BoundedProcess.scrubbedEnvironment(source: ProcessInfo.processInfo.environment)

    @Test func `a child's exit status and both outputs are returned`() throws {
        let result = try BoundedProcess.runBlocking(
            "/bin/sh", ["-c", "echo out; echo err >&2; exit 3"], environment: environment)
        #expect(result.exitStatus == 3)
        #expect(!result.succeeded)
        #expect(result.standardOutputText == "out\n")
        #expect(result.standardErrorText == "err\n")
        #expect(!result.outputTruncated)
    }

    @Test func `a child past its deadline is terminated and the run says so`() {
        let start = ContinuousClock.now
        #expect(throws: BoundedProcess.Failure.timedOut(executable: "/bin/sleep", after: .milliseconds(300))) {
            try BoundedProcess.runBlocking("/bin/sleep", ["30"], environment: environment, timeout: .milliseconds(300))
        }
        #expect(ContinuousClock.now - start < .seconds(5))
    }

    @Test func `a child that ignores the termination signal is killed`() {
        let start = ContinuousClock.now
        #expect(throws: BoundedProcess.Failure.timedOut(executable: "/bin/sh", after: .milliseconds(300))) {
            try BoundedProcess.runBlocking(
                "/bin/sh", ["-c", "trap '' TERM; sleep 30"], environment: environment, timeout: .milliseconds(300))
        }
        #expect(ContinuousClock.now - start < .seconds(10))
    }

    /// A megabyte through a pipe whose reader keeps only 4 KiB: the child must still finish, not block on a full pipe.
    @Test func `output past the limit is read and dropped, and the child still finishes`() throws {
        let result = try BoundedProcess.runBlocking(
            "/bin/sh", ["-c", "head -c 1048576 /dev/zero; head -c 1048576 /dev/zero >&2"], environment: environment,
            timeout: .seconds(20), outputLimit: 4096)
        #expect(result.succeeded)
        #expect(result.standardOutput.count == 4096)
        #expect(result.standardError.count == 4096)
        #expect(result.outputTruncated)
    }

    @Test func `the environment keeps the allowed variables and the overrides, nothing else`() throws {
        let source = [
            "PATH": "/usr/bin:/bin", "HOME": "/Users/x", "DYLD_INSERT_LIBRARIES": "/tmp/evil.dylib",
            "SHELL": "/bin/zsh",
            "DEVELOPER_DIR": "/Applications/Xcode.app", "LANG": "C",
        ]
        let scrubbed = BoundedProcess.scrubbedEnvironment(
            overrides: ["DEVELOPER_DIR": "/Xcode-beta.app"], source: source)
        #expect(
            scrubbed == ["PATH": "/usr/bin:/bin", "HOME": "/Users/x", "LANG": "C", "DEVELOPER_DIR": "/Xcode-beta.app"])
        let result = try BoundedProcess.runBlocking("/usr/bin/env", [], environment: scrubbed)
        let lines = Set(result.standardOutputText.split(separator: "\n").map(String.init))
        #expect(lines == ["PATH=/usr/bin:/bin", "HOME=/Users/x", "LANG=C", "DEVELOPER_DIR=/Xcode-beta.app"])
    }

    @Test func `only an absolute executable is run`() {
        #expect(throws: BoundedProcess.Failure.notAbsolute("sh")) {
            try BoundedProcess.runBlocking("sh", ["-c", "true"], environment: environment)
        }
    }

    @Test func `cancelling the task terminates the child`() async {
        let environment = self.environment
        let task = Task {
            try await BoundedProcess.run("/bin/sleep", ["30"], environment: environment, timeout: .seconds(60))
        }
        try? await Task.sleep(for: .milliseconds(200))
        let start = ContinuousClock.now
        task.cancel()
        let outcome = await task.result
        #expect(ContinuousClock.now - start < .seconds(5))
        guard case .failure(let error) = outcome else {
            Issue.record("the child ran to completion")
            return
        }
        #expect(error as? BoundedProcess.Failure == .cancelled(executable: "/bin/sleep"))
    }
}
