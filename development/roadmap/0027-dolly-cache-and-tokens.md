---
status: not-started
blocked-by: [0015, 0016, 0017, 0020]
date: 2026-10-29
---

# 0027 — dolly: binary token cache and the shared interner

Repository: g-cqd/dolly. Scope: token streams cached as packed lanes (0017); `CorpusAssembler` on `AemiInterner`'s parallel
merge (0015), keeping symbol order deterministic so suffix arrays and findings do not change.

Red: a size budget for the cache on a 3,000-file corpus (27 MB on maintastic today); findings byte-identical on the golden
corpora.

Acceptance: warm run faster than cold on maintastic (today 1.00 s against 1.24 s).
