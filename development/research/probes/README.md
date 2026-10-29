# Probes of 2026-10-29

Sources of the probes behind research `2026-10-29-index-store-reports-reviewed.md` and
`2026-10-29-performance-on-maintastic.md`. Each is the seed of a red test (ADR-0002); the roadmap entry that fixes the
defect turns it into a test in the repository that owns the code.

| File | Probes | How to run |
| --- | --- | --- |
| `index-fixtures.sh` | A1, A3, A4, A6, D1, D2 | `ARCLEAK=… DEADWOOD=… ./index-fixtures.sh` (binaries of the version under test) |
| `fcheck-probes.sh` | F1–F6, K1, K2 | `FCHECK=… ./fcheck-probes.sh` |
| `ArcleakFakeIndexProbe.swift` | A2 | copy into `arcleak/Tests/ArcLeakCoreTests/`, `swift test --filter ZZProbeTests` |
| `ControlFlowProbes.swift` | K1–K3 | copy into `analyzerkit/Tests/ControlFlowTests/` |
| `ModelerProbes.swift` | M1–M3 | copy into `modeler/Tests/ModelerCoreTests/` |
| `TrustProbe.swift` | D4 | copy into arcleak's and deadwood's test targets (replace `MODULE`) |
| `perf/` | timings and profiles | see `perf/README.md` |

Fixtures are built with `swiftc -index-store-path … -emit-module` from the toolchain whose `libIndexStore.dylib` the tools
load. `-typecheck` does not record per-file units and makes every file look stale.
