---
status: not-started
blocked-by: []
date: 2026-10-29
---

# 0015 — `AemiInterner`

Repository: aemi. Scope (ADR-0012): probe first, then build.

Probes, in aemi's diary: (1) intern and lookup of maintastic's 73,319 USRs and of dolly's token texts, against
`[String: UInt32]`; (2) hash choice (XXH64 against a short-key hash); (3) per-task tables merged by hash shard against a
lock-striped concurrent table, 1–8 workers; (4) memory per symbol.

Build: chunked byte arena, open addressing with stored hashes, `UInt32` symbols, interning from UTF-8 buffers and
`SyntaxText` without `String`, `Interner` / `FrozenInterner` / parallel merge with deterministic symbols, serialisation.

Red: determinism (same input order, same symbols, any worker count); no `String` allocation on the intern path (allocation
counter); round trip through serialisation.

Acceptance: the probes' numbers; tests; a benchmark with thresholds. Consumers move in 0024 (deadwood), 0027 (dolly),
0023 (arcleak).
