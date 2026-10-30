---
status: not-started
blocked-by: [0017]
date: 2026-10-29
---

# 0027 — dolly: binary token cache and the shared interner

Repository: g-cqd/dolly. Scope: token streams cached as packed lanes (0017); `CorpusAssembler` on `AemiInterner`'s parallel
merge (0015), keeping symbol order deterministic so suffix arrays and findings do not change; per-file tables become
`Interner`s filled from token bytes (`TokenSyntax.rawText` where swift-syntax exposes it, else the token's UTF-8), so
no `String` is made per token (0047). The probe measured 37.5 against 14.7 ms on maintastic's token stream, 7.7 merged.

Red: a size budget for the cache on a 3,000-file corpus (27 MB on maintastic today); findings byte-identical on the golden
corpora.

Acceptance: warm run faster than cold on maintastic (today 1.00 s against 1.24 s).
