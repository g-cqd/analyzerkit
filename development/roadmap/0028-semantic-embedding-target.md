---
status: not-started
blocked-by: []
date: 2026-10-29
---

# 0028 — `SemanticEmbedding` beside `WordPiece`

Scope (ADR-0016): the NL contextual, Hugging Face Core ML and deterministic providers (41–80 % similar in three tools) move
into one target; `--experimental-embeddings <rank|confidence|semantic>` and `--embedding-bundle` in `AnalyzerCLI`.

Red: each tool's embedding tests run against the shared target; the deterministic provider gives the same vectors as each
tool's copy today.

Acceptance: identical experimental output on the fixture corpora; the three copies deleted.
