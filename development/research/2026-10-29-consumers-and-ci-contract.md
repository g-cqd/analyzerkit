# 2026-10-29 — Who runs the analyzers, and what each release wave asks of them

Inventory made from the working trees of 2026-10-29 (g-cqd workspace, maintastic `parts-MAIN-24752-stock-handling`) and the
GitHub releases. It is the input of roadmap 0030–0032 and of every release note (ADR-0015). Re-check it before each wave:
pins move.

## 1. The contract surface in use today

| Surface | Used by | Values in use |
| --- | --- | --- |
| Release archives | g-cqd scripts, aemi workflow | `<tool>-<v>-macos-arm64.tar.gz`, `<tool>-<v>-linux-x86_64.tar.gz`, `.sha256` beside each |
| Artifact bundles | maintastic `ShareXcodePlugins` | `https://github.com/g-cqd/<tool>/releases/download/v<v>/<tool>-<v>.artifactbundle.zip` + checksum |
| Subcommand | all | `analyze` (arcleak, deadwood, dolly, fcheck), `check` (modeler) |
| Flags | maintastic | `analyze . --config .<tool>.json --format json --relative-to .`, `--cache-path <dir>/<tool>/facts` (arcleak, dolly), `--no-cache` (deadwood, workaround for D7), `--index-store-path <store>` (arcleak, deadwood) |
| Flags | g-cqd scripts | `analyze --strict --no-cache --relative-to . [--baseline .dolly-baseline.json] <corpus>`; aemi workflow: arcleak `--strict --no-cache`, dolly `--no-cache --relative-to . [--baseline …]`, deadwood `--format sarif --no-cache --production` |
| Exit codes | maintastic | 0/1 ran; 64, 70, 74, 78 "did not run, whatever it wrote" |
| Report keys | maintastic `StaticAnalysisReport` | `schemaVersion == 1`; `findings[].path, line, message, note, rule, severity, related[].path, related[].line` |
| Baselines | AemiJSON, AemiProtobuf (`.dolly-baseline.json`) | fingerprints are repository-relative |
| Config files | maintastic | `.arcleak.json`, `.deadwood.json`, `.dolly.json` (also referenced in `Oculavis Share IOS.xcodeproj` as files of the navigator) |
| Suppression comments | all code bases | `@al:`, `@dw:`, `@dl:`, `@fc:` and long forms |

## 2. Consumers and their pins

| Consumer | File | Pins | How | Gate |
| --- | --- | --- | --- | --- |
| maintastic | `ShareXcodePlugins/Package.swift` | arcleak 0.12.0, deadwood 0.11.1, dolly 0.11.0 | `.binaryTarget(url:checksum:)` | arcleak red, others warn (Danger) |
| maintastic | `DangerPlugins/Sources/DangerXCResultParser/Analysis/Analyzer+StaticAnalysis.swift` | flags, exit codes | Swift | — |
| maintastic | `…/Analysis/StaticAnalysisReport.swift` | report keys, `supportedSchema = 1` | Swift | — |
| maintastic | `…/Analysis/Analysis.swift` | `ANALYZER_CACHE_PATH` (default `~/Desktop/analyzer-cache`), `INDEX_STORE_PATH` or newest `Index.noindex/DataStore` under `DERIVED_DATA_PATH` | env | — |
| maintastic | `Dangerfile.swift`, `Dangerfile.hooks.swift` | which analyzers run on commit/push/PR | Swift | — |
| maintastic | `DangerPlugins/Tests/…` (`AnalyzerFixtures`, `AnalysisReportTests`, `StaticAnalysisTests`, …) | report fixtures | tests | — |
| maintastic | `.github/workflows/pr-run-checks.yml` | self-hosted `mobile` runner, `DERIVED_DATA_PATH` var; no `actions/cache` for analyzers | YAML | required `run-checks` |
| maintastic | `CONTRIBUTING.md`, `AGENTS.md`, `DangerPlugins/README.md` | describe flags and config files | prose | — |
| aemi | `.github/workflows/swift-quality.yml` (reusable) | defaults arcleak 0.11.0, dolly 0.10.3, deadwood 0.10.2 | release archives | arcleak gates, dolly and deadwood report |
| aemi | `.github/workflows/swift-tool.yml` (reusable) | builds and publishes every tool's archives and bundle | — | — |
| AemiJSON | `Scripts/analyzers.sh`; `ci.yml` uses `swift-quality.yml@4f270e0` | deadwood 0.11.1, dolly 0.11.0, arcleak 0.12.0 | archives + SHA | — |
| AemiRegex | `Scripts/analyzers.sh`; `ci.yml` uses `swift-quality.yml@afc1be3` | same as AemiJSON | archives + SHA | — |
| AemiMarkdown | `Scripts/analyzers.sh` | deadwood 0.10.2, dolly 0.10.3, arcleak 0.11.0 (behind) | archives + SHA | — |
| ask | `Scripts/analyzers.sh`, `Scripts/quality.sh` | deadwood 0.11.1, dolly 0.11.0, arcleak 0.12.0 (macOS SHA only) | archives + SHA | — |
| AemiProtobuf | `Scripts/tools.lock`, `tools.sh`, `quality.sh`, `model.sh` | deadwood 0.11.1, dolly 0.11.0, arcleak 0.12.0; fcheck `f664987`, modeler `2c699c7` built from source | archives; source | all five |
| Atelier | `.github/workflows/ci.yml` (`swift-quality.yml@afc1be3` ×3); `Apps/GitDiffViewer/scripts/helpers.lock` | arcleak `aecf299`, dolly `32876a0`, deadwood `98d9271` | commits | — |
| the tools themselves | `.github/workflows/ci.yml` → `swift-tool.yml@afc1be3`; `action.yml` (GitHub Action, no consumer found in the workspace) | — | — | — |

Findings of the inventory:

- Four copies of `analyzers.sh` at three version sets; aemi's workflow defaults are two releases behind.
- AemiProtobuf roadmap 0015 ("fcheck and modeler publish no release archive") is stale: fcheck 0.1.1 and modeler 0.1.1
  publish both archives and bundles.
- maintastic searches DerivedData for the index store itself because the tools could not (A5, A6).

## 3. What each wave asks of each consumer

### Wave 1 — same findings

Tool changes visible to consumers: new versions and checksums; new flag spellings with the old ones still accepted (a
deprecation line on stderr); the report gains `tool`, `notes`, `skippedFiles` (and `timings` on request); `--cache-path`
becomes a directory (a v1 cache file at that path is replaced); the default cache root and the index database move under
the tools' cache directory, with a size budget; `--index-store-path` accepts a DerivedData root, `Index.noindex` or
`DataStore`, and nothing is written next to the store; exit codes unified (modeler and fcheck gain 70/74/78; deadwood and
dolly gain 74); `.swift-analyzers.json` is read when present.

| Consumer | Steps |
| --- | --- |
| maintastic | 1. `ShareXcodePlugins/Package.swift`: three URLs and checksums (and two more if fcheck/modeler are added). 2. `Analyzer+StaticAnalysis.swift`: drop deadwood's `--no-cache` (D7 fixed), give it `--cache-path` like the others; update the doc comments (64 MiB note). 3. Optional: read `notes`/`skippedFiles` in `StaticAnalysisReport` and show "N not checked" in the Danger comment; add a fixture with the new keys to `AnalyzerFixtures` and keep one without them. 4. Optional: `Analysis.indexStorePath` may pass `DERIVED_DATA_PATH` itself. 5. Clean `~/Desktop/analyzer-cache/*/facts` once on the runner (the tools also do it). 6. No change to `.arcleak.json`, `.deadwood.json`, `.dolly.json`. |
| aemi | Bump `swift-quality.yml` defaults; publish the single shared `analyzers.sh` (roadmap 0031). |
| AemiJSON, AemiRegex, AemiMarkdown, ask | Replace `Scripts/analyzers.sh` by the shared script with one pin set; re-run; `.dolly-baseline.json` must still match (wave 1 keeps fingerprints). |
| AemiProtobuf | `tools.lock`: new versions and SHAs; fcheck and modeler move from source commits to release archives; close its roadmap 0015 with a link. |
| Atelier | `helpers.lock` commits → release tags; workflow pins of `swift-quality.yml`. |

### Wave 2 — better findings

Tool changes: index decided per definition (arcleak uses the index on maintastic where it used none; deadwood adds
references from unindexed files); fcheck rule fixes (F1–F6, K1–K3: some false positives disappear, some leaks appear);
modeler on the control-flow graph (M1 false positives disappear, M2 findings appear).

| Consumer | Steps |
| --- | --- |
| maintastic | 1. Pins. 2. Run the PR analysis on `develop` with the new versions; arcleak gates, so any new arcleak warning blocks: fix or suppress before bumping. 3. `.arcleak.json`: the excludes added only to keep the index (`Danger/`, `ShareXcodePlugins/`, `ShareMacros/Tests/`, `scripts/`, `Dangerfile.hooks.swift`) can go; decide per directory whether it should be analysed at all. 4. Expect the index note "active for N of M files; K not in the index, J changed since the build" instead of "stale". |
| g-cqd packages | Pins; re-run; refresh `.dolly-baseline.json` only if dolly's findings changed (wave 2 does not change dolly's rules; it should not); fix or suppress new fcheck/modeler findings in AemiProtobuf. |

### Wave 3 — cleanup

Tool changes: old flag spellings removed (`--include`/`--exclude` as regions, `--include-tests`, the three embedding
flags); `contextNote`, `cacheNote` removed; deadwood's `notes` becomes the structured array.

| Consumer | Steps |
| --- | --- |
| maintastic | Pins only if no removed flag is used (none today); if DangerPlugins decoded deadwood's old `notes: [String]` (it does not today), update it. |
| g-cqd scripts and aemi workflow | None today: the scripts pass `--strict --no-cache --relative-to . [--baseline …]`, and aemi's workflow passes deadwood `--format sarif --no-cache --production` (checked 2026-10-29). Re-check before wave 3. |
