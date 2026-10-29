---
status: not-started
blocked-by: [0030]
date: 2026-10-29
---

# 0032 — maintastic: the update, file by file

Repository: maintastic `ios` (worktrees under `~/Developer/maintastic/ios`). Contract in use today: research
`2026-10-29-consumers-and-ci-contract.md` §1–2.

## Wave 1 (same findings)

1. `ShareXcodePlugins/Package.swift`: the three `.binaryTarget(url:checksum:)` entries → new versions; checksums from the
   release notes (verify with `swift package compute-checksum` on the downloaded bundles).
2. `DangerPlugins/Sources/DangerXCResultParser/Analysis/Analyzer+StaticAnalysis.swift`:
   - deadwood: replace `["--no-cache"]` by `["--cache-path", $0.cachePath + "/facts"]` (its cache now fits); remove the
     64 MiB sentence from the doc comment;
   - arcleak, dolly: unchanged (`--cache-path …/facts` becomes a directory, which the tools create);
   - `failureStatuses: [64, 70, 74, 78]`: unchanged (now true of every tool).
3. `…/Analysis/StaticAnalysisReport.swift`: unchanged to keep working. Optional: decode `notes` and `skippedFiles` and show
   "N not checked: <first paths>" in the Danger comment; add one fixture with the new keys to
   `DangerPlugins/Tests/DangerXCResultParserTests/AnalyzerFixtures.swift` and keep the old one.
4. `…/Analysis/Analysis.swift` `indexStorePath(environment:)`: unchanged to keep working. Optional: pass
   `DERIVED_DATA_PATH` directly, since the tools now accept a DerivedData root and match `WorkspacePath`.
5. Runner hygiene (self-hosted `mobile`): delete `~/Desktop/analyzer-cache/*/facts` once (v1 files; the tools would replace
   them anyway) and `~/Library/Caches/{arcleak,deadwood,dolly}` legacy files (the tools trim them on first run).
6. Configuration: `.arcleak.json`, `.deadwood.json`, `.dolly.json` unchanged. Optional: replace them by one
   `.swift-analyzers.json` (shared `exclude`, `dolly.duplication`), update the three file references in
   `Oculavis Share IOS.xcodeproj` and the mentions in `CONTRIBUTING.md`, `AGENTS.md`, `DangerPlugins/README.md`.
7. Verify on a branch: `pr-run-checks.yml` green; the Danger comment lists the same findings as on `develop`.

## Wave 2 (better findings)

1. Pins and checksums as in wave 1.
2. Before merging, run the three tools on `develop` with the new versions locally: arcleak gates, so each new arcleak
   warning is fixed or suppressed (`@al:`) in the same pull request; dolly and deadwood only warn.
3. `.arcleak.json`: the excludes added only to keep the index usable (`Danger/`, `ShareXcodePlugins/`, `ShareMacros/Tests/`,
   `scripts/`, `Dangerfile.hooks.swift`) can be removed; keep those that are not app code by choice.
4. Expect the notes "index active for N of M files; K not in the index, J changed since the build"; `CONTRIBUTING.md`
   describes the index store accordingly.
5. Optional: add fcheck and modeler (`.binaryTarget`s, `Analyzer.fcheck`, `Analyzer.modeler` in DangerPlugins, both
   warn-only at first).

## Wave 3 (cleanup)

Pins only: maintastic uses none of the removed spellings or keys (checked 2026-10-29: no `--include`, `--exclude`,
`--include-tests`, embedding flags, `contextNote`, `cacheNote`, deadwood `notes`). Re-check before the wave.

Red: none in maintastic before a wave; each wave's branch must show the tests of `DangerPlugins` green with the new
fixtures, and the PR checks green.

Acceptance: maintastic on each wave within a week of its release, with the Danger comment's finding count explained by the
release notes.
