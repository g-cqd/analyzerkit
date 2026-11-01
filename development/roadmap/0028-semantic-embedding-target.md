---
status: done
blocked-by: []
date: 2026-10-29
---

# 0028 — `SemanticEmbedding` beside `WordPiece`

Scope (ADR-0016): the NL contextual, Hugging Face Core ML and deterministic providers (41–80 % similar in three tools) move
into one target; `--experimental-embeddings <rank|confidence|semantic>` and `--embedding-bundle` in `AnalyzerCLI`.

Red: each tool's embedding tests run against the shared target; the deterministic provider gives the same vectors as each
tool's copy today.

Acceptance: identical experimental output on the fixture corpora; the three copies deleted.

## Done

2026-11-01, as step 3 of 0067. Red `e5d3550`, green `a82ff6a`: target `SemanticEmbedding` on `WordPiece`. It has
`SemanticEmbeddingProvider`, `DeterministicEmbeddingProvider`, `EmbeddingBundleLocator`, `NLContextualSemanticEmbeddingProvider`,
`HFSemanticEmbeddingProvider` and `SemanticEmbeddingProviders.onDeviceOrFallback()`; Core ML and NaturalLanguage stay behind
`#if canImport`. arcleak, deadwood and dolly deleted their copies; the experimental output matched byte for byte. The flags
are still each tool's own (`AnalyzerCLI` has no embedding options yet), and arcleak's `resolveProvider` and deadwood's
`EmbeddingProviderSelection.resolve` are still two near-identical bundle, then NL, then deterministic resolvers that could be
one.
