# 2026-10-29 — Performance of the five tools on maintastic

The question: where does each tool spend its time on a real project, in the hot paths and outside them?

## Method

- Corpus: maintastic `parts-MAIN-24752-stock-handling` at its working tree of 2026-10-29 (Xcode project, 17 local
  packages), each tool with the repository's own `.<tool>.json` where one exists.
- Binaries: release builds of arcleak `ac4f1c1`, deadwood `240bbb3`, dolly `073fd7b`, fcheck `be49f54`, modeler `1b924c6`.
- Machine: arm64, 8 cores (4 performance). Another build was running (load ≈ 6), so absolute times are indications;
  sample shares inside one run are the firm figures.
- Times: `/usr/bin/time -p`, one cold run (`--no-cache`), one run that writes the cache, one warm run.
- Profiles: `sample <pid> 300 1` on the process, summarised by top-of-stack and by inclusive count per function
  (`probes/perf/`).

## Wall time

| Tool | Files | Cold | Write | Warm | Cores used cold / warm | Cache |
| --- | ---: | ---: | ---: | ---: | --- | ---: |
| fcheck | 2,584 | 1.87 s (7.9 s user) | 2.11 s | 0.65 s | 4.5 / 1.2 | 0.65 MB |
| modeler | 2,973 | 0.69 s | 0.75 s | 0.55 s | 2.7 / 1.2 | 10.8 MB |
| dolly | 2,873 | 1.24 s | 1.45 s | 1.00 s | 2.8 / 1.4 | 27 MB (Foundation JSON) |
| arcleak | 2,830 | 1.40 s | 1.45 s | 1.15 s | 2.3 / 1.2 | 4.3 MB |
| deadwood | 2,973 | 3.60 s | 4.10 s | 3.61 s | 2.8 / 2.8 | none: "skipped facts cache larger than 64 MiB" |
| arcleak, index | 2,830 | 9.4 s first, 2.4 s after | | | | + 128 MB database |
| deadwood, index | 2,973 | 23.8 s | | | | |

Under heavier load the first measurements were 1.5–2.5× slower but kept the same order; one of them (modeler, dolly)
showed warm slower than cold.

## Where the time goes

**fcheck, cold.** `ResourceRule.analyze` 798 of 1,112 per-file samples, parsing 110. Inside it `acquiredKind(of:)` (438)
reads `CallSite.last` (368) and `CallSite.callee` (173); the top self symbol is `_swift_stdlib_getBinaryProperties`
(2,028). `callee` is `calledExpression.trimmedDescription.filter { !$0.isWhitespace }`, recomputed on each access, and on a
SwiftUI chain the called expression is the whole view body: quadratic.

**Warm runs (all tools).** About 1.2 cores used: the remaining time is serial. fcheck: cache load 88 of 133 main-thread
samples (AemiJSON generic `Codable`, `DecodeContext.memberValueIndex`), and `__open` the top self symbol (every file reopened
to fingerprint). modeler: cache load 196 of 426. dolly: `discoverSwiftFiles` 494 of 670, of which
`RepositoryRoot.common(of:)` 171 and `SourceDiscovery.files` 201; cache decode 135; `isExcluded` 87.

**arcleak, cold.** Main thread: discovery 255 and `RepositoryRoot.common` 204 of 505. Per file: parse 206,
`FactsExtraction.scanDirectives` 127 of which `SuppressionDirective.parse` 116. Self time dominated by idle threads and I/O
(`read` 370, `__open` 325, `__getattrlist` 154, `lstat` 134).

**deadwood, index.** `indexBackedUnused` 9,509 samples: `IndexStoreAnalyzer.findUnusedSymbols()` 2,638 (it feeds only the
summary line), `buildEdges` 1,060 and `collectDefinitions` 1,013 (each queries `symbolOccurrences(inFilePath:)` for every
file, serially), `mapDeclarationsToUSRs` 512, `canonicalPath` resolving symlinks per occurrence. The store is opened twice
(fallback manager, then bridge).

**analyzerkit.** `RepositoryRoot.common(of:)` walks up from every file with a `fileExists(".git")` per level and no memo,
for arcleak, deadwood, dolly and fcheck (twice). `SourceDiscovery.files` makes a Foundation attribute dictionary per entry.

**Builds.** Each tool's release build compiles AemiJSONCore whole-module on its own (about 4 min, 1.6 GB); release builds
took 250–435 s per tool under load.

## What follows

Correctness of the measurements: absolute numbers moved by up to 2.5× with load, so every roadmap entry that claims a gain
re-measures before and after on a quiet machine, same corpus, median of at least five runs. The targets in the roadmap are
goals until then.
