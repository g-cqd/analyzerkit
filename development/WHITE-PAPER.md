# analyzerkit and the analyzer family — White Paper

The rules the analyzer family runs on: analyzerkit and the five tools that build on it, arcleak (ARC safety), deadwood
(unused code), dolly (duplication), fcheck (obligations on every path) and modeler (models and interleavings). Principles
live here, never a log: the log is the diary. Records for work that spans the family live in this repository; a decision
that concerns one tool alone lives in that tool's repository.

## What the family promises

The same project gives the same answer whichever tool reads it. Concretely, for every tool:

- **One project model.** SwiftPM packages, Xcode projects and workspaces, nested local packages and git worktrees are
  recognised the same way, by `ProjectLayout`; every feature (index store, regions, tests, caches) works on all of them.
- **One surface.** The same flags spell the same thing, the same configuration file is read, the same paths are analysed,
  the same exit codes mean the same failure, and the report has one shape (ADR-0006, ADR-0007, ADR-0008, ADR-0009).
- **One contract with the CIs that run it.** What a consumer depends on (release archives, flags, exit codes, report keys,
  baseline fingerprints, suppression syntax) changes only through the release train (ADR-0015), never as a side effect.

## The evidence rule

Every claim is named, given a probe that could fail, run, and recorded in the diary before it is acted on.

- **A probe that cannot fail is not a probe.** A fixture that only exercises the happy path proves nothing about the bug.
- **Unprobed claims are open questions, never facts.** A record says "to be measured" until a probe says otherwise, and a
  retracted claim is written down as retracted (diary 2026-10-29-01 retracts two).
- **Real corpora decide.** Synthetic fixtures find mechanisms; a real project (maintastic, the g-cqd packages) decides
  whether a mechanism matters and how much.

## Red first

No production change without a failing test committed before it, failing for the reason stated (ADR-0002).

- Correctness: the probe that showed the bug becomes the test, minimal and deterministic.
- Index work: fixtures are real stores built by `swiftc -index-store-path`; a test that cannot run on a host is disabled
  with `.enabled(if:)` and says why, never `return`s and passes.
- Speed: operation counts through seams, scaling ratios, size budgets and benchmarks with thresholds. Wall-clock time
  alone never gates a test.
- Surface: golden tests of `--help`, the JSON envelope and the exit codes, shared from analyzerkit so one test proves
  the five tools agree.

## Correctness, then safety, then speed

- **Fail open, and say so.** An analysis that cannot use a capability (index, cache, toolchain) degrades to the precise
  thing it can still do, names the files it did not check and why, and never guesses from stale data.
- **Never write where you were not asked to.** A tool writes only into its cache directory and the paths its flags name.
- **Input is attacker input.** Configuration, caches, index stores and sources are bounded and validated; a malformed
  one is a typed error or a cache miss, never a trap.
- **Speed is a number.** A performance change is measured before and after, release build, same corpus, median and
  spread. Debug builds measure a program nobody ships.

## Where code lives

A component lives in the lowest package where a second consumer is plausible:

| Package | Holds |
| --- | --- |
| Aemi (`aemi`, `AemiJSON`, `AemiProtobuf`, `AemiRegex`) | general mechanisms: byte kernels, I/O, the directory walker (ADR-0013), the interner (ADR-0012), codecs |
| analyzerkit | what every analyzer needs and no other program does: project model, corpus scan and caches, index-store support, CLI surface, report, suppression, control flow |
| a tool | its rules, its facts, its findings |

Moving a component up or down is an ADR with the consumers named.

## Documentation law

| Path | Rule |
| --- | --- |
| `development/WHITE-PAPER.md` | Principles, never a log. Capped at 200 lines. |
| `development/adr/NNNN-title.md` | One decision per file, `accepted` or `superseded`. New evidence makes a new ADR that supersedes the old. |
| `development/roadmap/NNNN-title.md` | One claimable unit of work per file with `status:` (`not-started`, `in-progress`, `done`) and `blocked-by:`. |
| `development/diary/YYYY-MM-DD-NN.md` | The working log and the probe history. 256 lines; roll over. |
| `development/research/` | Dated notes, and the probe sources under `research/probes/`. |
| `README.md`, `docs/` | For users of the library and the tools only. |

A test enforces this table (roadmap 0001).

## Process

Test first and see it fail for the right reason. Atomic commits that say why. A pre-existing problem found on the way is a
roadmap entry, not a silent repair. Dependencies move in one order: aemi → AemiRegex → AemiJSON → AemiProtobuf →
analyzerkit → the tools → their consumers, each step green before the next.
