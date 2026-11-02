---
status: accepted
date: 2026-11-02
---

# 0030 — Supervision beyond the process group, signals as cancellation, checked reports, and which tests reach a file

## Context

Litmus, the family's mutation tester, runs thousands of builds and test suites through `BoundedProcess` and reads
projects through `ProjectModel`. It recorded what it had to build around analyzerkit (Litmus
`docs/upstream-recommendations.md`, AK-1 to AK-15), and some of it was measured the hard way on 2026-11-02:

- `swift test` starts its testing helper in a new process group. A timed-out mutant's endless loop survived the group
  kill and kept two cores busy for 2.5 hours. A simulator's test host is not a descendant at all.
- Killed by SIGTERM, Litmus ran no teardown; `xcodebuild`, which ignores SIGTERM, ran on.
- A run cannot stop its child on what it sees (Swift Testing's first failure), a crash is indistinguishable from an
  exit status of 134, per-child CPU and memory are unknown, and a mutant that allocates without bound has no limit.
- Deadlines ran on the continuous clock: a laptop closed during a run times out every child on waking.
- A `litmus` section in `.swift-analyzers.json` made every other tool reject the file.
- A report that fails to encode was written as `{}`, an empty and clean report.
- Fingerprints hash the line and column, so an edit above a finding renews it.
- Which test targets reach a file, which a scheme runs, and whether `#if canImport(…)` is active were unknown without a
  build; under `--define` every `canImport` clause counted as inactive (the static configuration throws for it).
- A bounded, link-refusing copy with a content manifest, and the byte extent of a preview, lived only in Litmus.

## Decision

1. **`BoundedProcess` cleans up after its child** (on by default, `Options.reapsSession`): every process left in the
   child's session, started since the launch, gets SIGTERM, then SIGKILL after the grace; and every process carrying
   `Options.environmentToken`, wherever it is (aemi's `ProcessTable`, aemi ADR 0028). `Result.reaped` lists them.
2. **Supervision options**, all additive: a monitor (`run(…, monitor:)`, a `ProcessControl` with the pid and
   `stop(reason:)`, recorded in `Result.stopReason`); `Result.terminationSignal`; sampled usage of the session
   (`Options.sampling`, `Result.usage`) and a memory limit (`Options.memoryLimitBytes`); an output observer; deadlines on
   the suspending clock by default (`Options.deadlineClock`); `EnvironmentPolicy` (`scrubbed`, `toolchain`,
   `scrubbedAdding`).
3. **Waiting on swift-subprocess**: exact per-child usage is swiftlang/swift-subprocess#226 (open), which reports
   what the reaping call returns; until then usage is sampled (it misses the last interval), and the sampling stays the
   measure of the whole session afterwards. #371 (open, a stopped child read as exited on macOS 26/27) did not reproduce
   here; the session cleanup ends such a child regardless. #382 (open) leaks descriptors on the fork fallback, which a
   session alone never takes; a test holds the descriptors a child sees.
4. **`TerminationSignals.run(cancellingOn:_:)`** in AnalyzerCLI: the first SIGINT, SIGTERM or SIGHUP cancels the
   operation; a second exits with 128 plus the signal. Built natively on Dispatch after swift-service-lifecycle's
   `UnixSignals` (ignore on Darwin so kqueue delivers, wait for registration), restoring the dispositions afterwards,
   which `UnixSignals` does not; no package added.
5. **The shared configuration** knows `litmus`, accepts the section of a tool it does not know (listed with
   `--verbose`, `Resolved.otherSections`), and still rejects a name within two edits of a known tool's.
6. **`ToolReportFormat.formatChecked`** throws `ReportEncodingFailure`; `format` keeps its `{}` and says why to prefer
   the checked one. Not deprecated: the tools build with warnings as errors.
7. **`Fingerprint.anchored`**: rule, path, enclosing declaration, whitespace-collapsed text, ordinal; written beside the
   first fingerprint in SARIF (`<tool>/anchored/v1`) when a finding gives one. Baselines keep the first until a version
   reads both.
8. **Project facts**: `ProjectClassification.testTargets(covering:)` from manifest and `PBXTargetDependency`
   dependencies (conservative when not literal); `XcodeSchemeReader` for schemes and test plans;
   `ModuleAwareBuildConfiguration` answering `canImport` from `CompilationConditions.sdkModules(at:)` and the project's
   modules; `CompilerConfiguration.read` for the compiler's own `-print-static-build-config`; `TreeSnapshot` (copy by
   clone, SHA-256 manifest, verification); `RegionSpan.bytes` and `region(atByte:line:in:)`, spans comparing as before.

## Consequences

The one change of behaviour for existing callers is the cleanup: a tool whose child leaves a daemon in its session (a
build service started by `xcodebuild`) now sees it ended with the run, which is the isolation the executor promised.
Deadlines no longer count a machine's sleep. Everything else is additive; the five analyzers build unchanged.

Not covered: per-child usage that is exact (#226); a `canImport` with a version (the module list has none); schemes Xcode
generates without writing them; a host application a test bundle is not declared to depend on.
