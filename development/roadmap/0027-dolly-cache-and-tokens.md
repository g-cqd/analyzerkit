---
status: done
blocked-by: []
date: 2026-10-29
---

# 0027 — dolly: binary token cache and the shared interner

Repository: g-cqd/dolly. Scope: token streams cached as packed lanes (0017); `CorpusAssembler` on `AemiInterner`'s parallel
merge (0015), keeping symbol order deterministic so suffix arrays and findings do not change; per-file tables become
`Interner`s filled from token bytes (`TokenSyntax.rawText` where swift-syntax exposes it, else the token's UTF-8), so
no `String` is made per token (0047). The probe measured 37.5 against 14.7 ms on the reference app's token stream, 7.7 merged.

Red: a size budget for the cache on a 3,000-file corpus (27 MB on the reference app today); findings byte-identical on the golden
corpora.

Acceptance: warm run faster than cold on the reference app (today 1.00 s against 1.24 s).

## Done

- **Packed lanes and the size budget** came with 0017 (dolly `eaef64f`): on the 3,000-file corpus JSON wrote 11.5 MB
  and protobuf 3.5 MB, against a budget of 40% of JSON. The cache on the reference app went from 26 to 8.1 MB.
- **Acceptance** was met there too: warm 0.52 s against cold 0.74 s on the reference app (release).
- **The interner** was built and measured, then not adopted (dolly red `5748a1e`, reverted with the numbers in
  `1134483`). Each file filled an `AemiInterner`, the cache kept its serialized table, and the corpus was their
  parallel merge. Suffix arrays and the 244 findings were identical, but nothing got faster: release, the reference app,
  three rounds at one load:

  | | dictionary (kept) | `AemiInterner` merge |
  |---|---|---|
  | assembly | 13.8 ms | 15.9 ms |
  | warm run | 0.50 s | 0.52 s |
  | cold run | equal | equal |
  | cache | 8.1 MB | 7.9 MB |

  aemi's probe merged large tables. the reference app's 2,981 per-file tables average a few dozen texts, so the merge's
  per-input cost dominates. The assembly is 3% of a warm run either way.
