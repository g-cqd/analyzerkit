# 2026-10-29 — The index-store reports, reviewed and probed

Input: three reports from wiring `--index-store-path` into maintastic's CI (arcleak 0.12.0, deadwood 0.11.1, dolly 0.11.0),
and a second review of analyzerkit, fcheck and modeler. Every claim below was probed; the probe sources are in
`probes/`, and each probe becomes the red test of its roadmap entry.

## Method

- **Synthetic index fixtures** (`probes/index-fixtures.sh`): modules compiled with
  `swiftc -index-store-path … -emit-module` by the toolchain whose `libIndexStore.dylib` the tools load. `-typecheck` is
  not enough: it records no per-file units and makes every file look stale (this produced one wrong claim, retracted).
- **Fake indexes** through `IndexReading` for arcleak's graph logic; `@testable` probes for internal policies.
- **CLI probes** of the debug and release binaries on small sources (`probes/fcheck-probes.sh`).
- **Control-flow probes** printing successors of the graph's nodes (`probes/ControlFlowProbes.swift`).
- **Real project**: maintastic `parts-MAIN-24752-stock-handling` (Xcode project, 17 local packages), its DerivedData
  index copied to `/tmp` with timestamps preserved so that nothing was written into the owner's DerivedData.

## Verdicts

| ID | Claim | Verdict |
| --- | --- | --- |
| A1 | arcleak drops the index for the run when one file has no unit | Confirmed; maintastic: 62 of 2,830 files, index never used |
| A1′ | The database import is paid before the index is discarded | Confirmed: 9.4 s and 128 MB first run, 2.4 s after |
| A2 | Corpus value types are looked up by name | Confirmed: phantom `mutualStrongProperties` through a corpus `struct` |
| A3 | Same-named types in two modules: arbitrary pick | Confirmed: an unrelated `struct Coordinator` hides a real cycle |
| A3b | An `extension` occurrence makes the lookup fail | Refuted |
| A4 | Declaring-file freshness not checked; class-ness guessed | Confirmed, error severity, while "index store active" |
| A5 | Discovery by folder name and first file | Confirmed on maintastic (fresh index not found; nested package taken as root) |
| A6 | Wrong layouts not normalised | Confirmed; `v5/` and `IndexDatabase/` created inside the wrong directory |
| A7 | Concurrent use corrupts the shared database | Refuted (3 concurrent runs, identical results); the location problem remains |
| A8 | No notes in JSON, no `--verbose` | Confirmed |
| A9 | Skipped backend test passes | Confirmed by inspection |
| — | `/tmp` symlinks make stores stale | Retracted (fixture artifact) |
| D1 | deadwood layout and message problems | Confirmed, same side effect as A6 |
| D2 | References from unindexed files invisible | Confirmed on a fixture; no measurable impact on maintastic |
| D4 | Trust policies differ | Confirmed, worse: user-owned `Xcode.app` refused, silent fallback to Command Line Tools |
| D5 | Summary-only pass | Confirmed: ≈ 2,640 samples, nearly all of `computeReachability` |
| D6 | Discovery | Confirmed on maintastic |
| D7 | Facts cache never written (> 64 MiB) | Confirmed; every run cold |
| D8 | Caches never evicted | Confirmed: 226 MB, 140 MB, 62 MB |
| F1, F1b | Helper-of-helper; implicit-return helpers not acquirers | Confirmed both |
| F2 | Reassigned handle loses the leak | Confirmed |
| F3 | `log…` prefix matches `login` | Confirmed |
| F4 | `door.open()` is an acquisition | Confirmed |
| F5 | Untyped flushes | Confirmed (`flushLogs()`, file `fsync` after `rename`) |
| F6 | "throws at line 0" | Confirmed |
| F7 | Quadratic `CallSite.callee` | Confirmed by sampling (see the performance note) |
| M1 | Claim-before-await reported | Confirmed; refined: a hazard only when another method writes the member |
| M2 | Loop-carried stale write missed | Confirmed |
| M3 | Branch pairing | Confirmed (documented limit) |
| M4 | README overstates CorpusScan sharing | Confirmed |
| K1 | `catch let error` not catch-all | Confirmed, user-visible in fcheck |
| K2 | `for try await` without throw edge | Confirmed, user-visible in fcheck |
| K3 | `fallthrough`; labelled `break` out of `do`/`if` | Confirmed both (no successor: the path vanishes) |

## What the reports got wrong

- arcleak's report proposed deciding per *analyzed* file. The index answers questions about types the corpus does not
  declare, so the file whose freshness matters is the *declaring* file of the answer (ADR-0005).
- deadwood's report covered findings in stale files, not references from them (D2).
- Both reports took "stale" at face value; most of maintastic's "stale" files are files no scheme builds.
