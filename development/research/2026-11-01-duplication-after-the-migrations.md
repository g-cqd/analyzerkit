# 2026-11-01 — what the tools still copy from each other, after the migrations

The migrations of 0018 to 0022 are done and the shared foundations are in use, yet dolly finds a lot of code that exists
in several tools. This note measures what is left, says why it is left, and orders what could move. It extends
`2026-10-29-surface-and-duplication.md` (ADR-0016's evidence), which measured before the migrations.

## Method

- **Clones:** dolly (debug build of `main`) over the `Sources` of arcleak, deadwood, dolly, fcheck, modeler and
  swift-search together, default thresholds, `--no-cache`. 363 findings, of which 237 have copies in two or more tools.
  Tokens below add up the regions dolly reports per file; a region copied into three files is reported more than once,
  so the sum (about 21,900) is an upper bound, not a count of distinct lines.
- **Line similarity:** two files of the same name, after replacing each tool's name with `TOOL`, compared line by line
  (`difflib`, no junk heuristic). It is low for files that share long regions and differ elsewhere, so it is read with the
  clone tokens, not instead of them.
- Within a repository (not across tools) the largest clones are 60 to 130 tokens: `Package.swift` target lists,
  `switch` tables in analyzerkit's `ScopeTracker` and `CorpusScanner`, modeler's `DeclarationExtractor`. None is a
  candidate for promotion.
- `Scripts/` and `Package.swift` copies are left out of the plan: SwiftPM manifests cannot share code.

## Where ADR-0016 stands

| ADR-0016 row | Roadmap | Status |
| --- | --- | --- |
| `IndexStoreSupport`, `ProjectModel`, `SourceCorpus`, `ReportSupport`, `Suppression`, `AnalyzerCLI`, shared configuration, cache v2, binary payloads | 0005 to 0017 | done |
| the five migrations | 0018 to 0022 | done |
| `SemanticEmbedding` beside `WordPiece` | 0028 | **not started** |
| AemiInterner in every consumer | 0047 | **not started** (no tool imports it) |

So most of what dolly finds is not code that was missed. It is the layer that stayed in each tool *on top of* the shared
code, plus the one row nobody started.

## What is left

| Group | Files | Clone tokens | Copies | Line similarity | Why it is still copied |
| --- | --- | ---: | --- | ---: | --- |
| Embedding providers | `HFSemanticEmbeddingProvider`, `NLContextual…`, `Deterministic…`, `SemanticEmbeddingProvider`, `EmbeddingRank`, `EmbeddingProviderSelection` | 3,175 + 687 + 410 + 282 + 242 + 147 | arcleak, deadwood, dolly (swift-search for the protocol) | arcleak and deadwood 41 to 75 %; dolly's 6 to 14 % | 0028 not started |
| Report layer | `Finding`, `ReportFormatter`, `AnalysisReport`, `RuleID` | 1,218 + 2,349 + 457 + 535 | arcleak, deadwood, dolly (fcheck, modeler have own shapes) | `Finding` and `ReportFormatter` 81 %, `AnalysisReport` 65 % (arcleak against deadwood); `RuleID` 4 to 11 % (the rule lists differ) | types are per tool: each has its own `RuleID`, and arcleak adds a witness, deadwood a confidence, dolly related regions |
| Wire mirrors of shared types | `SuppressionDirective`, `Baseline`, `PathPresentation` | 565 + 557 + 500 | arcleak, deadwood, dolly | 83 to 93 % | the shared `Suppression.Directive<Rule>` is not `Codable`, so each tool keeps a `@JSONCodable` mirror and a mirrored `Kind` enum ("keep wire/cache models local") |
| Facts and cache coding | `FactsProtobufCoding`, `FactsExtraction`, `APICallFact` | 1,021 + 449 + 217 | arcleak, deadwood, dolly, modeler, swift-search | `FactsProtobufCoding` 6 to 17 % whole-file; the other two not measured by line | each tool has its own facts types; only deadwood imports `SymbolFacts` |
| Command line | `ArcLeakCommand`, `DeadwoodCommand`, `DollyCommand`, `Analyze` (fcheck, modeler) | 2,254 + 1,201 + 274 + 431 | all five | file-level low, regions of 130 to 600 tokens identical | option groups are shared; the run skeleton (config, discover, analyze, baseline, format, exit) and `Rules`, `validate()` are not |
| Configuration | `Configuration` | 1,814 | all six | arcleak and deadwood 67 %, others 10 to 23 % | `SharedConfiguration` owns the common keys; each tool decodes its own |
| deadwood and dolly engine | `AtomicBitmap`, `CollectionShims`, `ConcurrencyConfiguration`, `DirectionOptimizingBFS`, `ParallelFrontierExpansion` | about 800 | deadwood, dolly | 15 to 24 % | ADR-0016: two consumers, tuned apart |
| Index reading | `IndexStoreReader` | 296 | arcleak, deadwood | 48 % | what `IndexStoreSupport` did not take |

## What running deadwood on the family added

Run on each tool's `Sources` without an index store (deadwood 0.14.2):

- **dolly** has code that production code never reaches. Only its tests use `MinHashGenerator`, `exactJaccardSimilarity`
  (with `MinHashSignature` and the helpers under them), `generateCharacterShingles` and `DeterministicEmbeddingProvider`.
  Nothing at all calls `computePairwiseSimilarities`, `shouldSwitchToTopDown`, `TokenCorpus.lineCount`,
  `ConcurrencyConfiguration.serial`, `CoreMLSemanticEmbeddingProvider` and `UnconfiguredSemanticEmbeddingProvider`. Moving
  these to analyzerkit would move dead code, so they are deleted first, or the owner says which are kept on purpose (the
  MinHash code may be a deliberate library surface).
- **analyzerkit:** `FactsStore.cachedPaths(at:identity:salt:)` is used only by a test.
- Both `shouldSwitchToTopDown` and `serial` are in the files that deadwood and dolly share (the engine row above), which
  is the strongest argument for not promoting that row as it stands.

## What would move, and how

**1. Delete what is dead** (dolly, then the tools' own findings). No dependency on anything.

**2. Wire mirrors** (about 1,600 tokens, three tools). One of two ways, both ending with one copy:

- make `Suppression.Directive<Rule>` and `DirectiveKind` `Codable` in the shared target, and delete the mirror and the
  `Kind` conversion in each tool. Whether AemiJSON's `@JSONCodable` accepts a generic struct is **not checked here**; a
  hand-written `Codable` in the shared target is still one copy instead of three.
- `Baseline` generic over a protocol that gives rule, path, line, column and message, with the fingerprint hash left
  where it is (ADR-0017: fingerprints must not change). arcleak hashes inline and deadwood through `FNV1a`; whether they
  give identical values is **not checked here** and is the first test to write.
- `PathPresentation` becomes a thin use of `PathPresenter`.

The check for each: the tool's goldens and a reference app report stay byte-equal.

**3. The embedding target (0028)** (about 4,900 tokens, three tools). Platform code stays behind `#if canImport`
(`CoreML`, `NaturalLanguage`), as the tools have it now, so the Linux build keeps compiling a stub. The deterministic
provider is the test oracle (same vectors as each copy today). dolly's provider set is the smallest after step 1 (its Core ML and unconfigured providers have no callers).

**4. The report layer** (about 4,500 tokens, three tools). The largest and the riskiest: a protocol for the fields every
finding has and a generic `ReportFormatter` over it, with each tool's extra (arcleak's witness, deadwood's confidence,
dolly's related regions) written by a closure or an associated type. Baselines and SARIF goldens must not change.
`ScopedFinding`, which arcleak's, deadwood's and dolly's `Finding` already conform to, is the seed of the protocol.

**5. Facts, commands, configuration.** Smaller per tool and tied to each tool's format: changing facts types changes the
cache payload, which costs every runner a cold run and a `version` bump. The commands' run skeleton is worth one
roadmap entry once step 4 has fixed the finding protocol; configuration last.

**Not planned:** the deadwood and dolly engine row (above), `Package.swift`, `ToolInfo`, each tool's rules.

## Order, and what each step costs

| Step | Tokens removed (upper bound) | Tools touched | Release needed |
| --- | ---: | --- | --- |
| 1 dead code | n/a | dolly, others | dolly patch |
| 2 wire mirrors | 1,600 | arcleak, deadwood, dolly | analyzerkit, then three patches |
| 3 embeddings (0028) | 4,900 | arcleak, deadwood, dolly | analyzerkit, then three minors (flags move into `AnalyzerCLI`) |
| 4 report layer | 4,500 | arcleak, deadwood, dolly | analyzerkit, then three minors |
| 5 facts, commands, configuration | 8,000 | all | per tool |

Each step is the same train as 0030: land the shared piece with its own tests, migrate the tools with byte-equal
reports, run each suite, then tag.

## What happened to the plan

Steps 1 to 4 were carried out the same day (roadmap 0067 has the commits). Two parts were decided to stay per tool after
reading the code: `PathPresentation` (the shared rule was already `PathPresenter`; the per-field choices differ on purpose) and
`AnalysisReport` (its extra fields differ; `ToolReport` is the surface the renderers need). The byte-equal check was run on the
fixtures and on the other tools' `Sources` for the embeddings and the report layer, not on the reference app. Step 5 is split into 0068
(facts coding), 0069 (run skeleton) and 0070 (configuration).

## Not verified

- The clone tokens are dolly's, from a debug build; no second tool confirmed them.
- No candidate was prototyped, so every "byte-equal" above is a requirement, not a result.
- The embedding providers were compared by lines, not run: their vectors were not compared.
- Whether the three copies of a file differ in behaviour, not only in text, was read for `Baseline`, `Finding` and
  `SuppressionDirective` only.
