---
status: done
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

## Done

Diary 2026-10-29-20; aemi's diary 2026-10-29-03 and ADR 0019 hold the numbers and the design. aemi `74cafb1` (probe, ADR
0019), `1bee6b5` red, `c3d6a93` green: `AemiKernel.WyHash` and the `AemiInterner` product.

Probes, on maintastic's own streams (661,234 USR occurrences, 120,256 distinct, 120 bytes; 1,123,010 tokens, 30,209
distinct): the arena interner against `[String: UInt32]` with a `String` per key, 17.2 against 102 ms for USRs and 14.7
against 37.5 ms for tokens; wyhash the fastest hash on both (XXH64 next, SipHash last); per-worker tables merged by shard
8.6 and 7.7 ms on four workers, with symbols equal to sequential interning, against 18.8 and 31.6 ms for a lock-striped
table that is not deterministic; memory per distinct key 171 against 244 bytes and 72 against 107.

Red seen failing for every test and vector. Built: `Interner` (one owner), `FrozenInterner` (`Sendable`), `Interner.merge`
(deterministic on any worker count), LEB128 serialisation with damaged input refused, no allocation for a known key or a
new one within the reserved capacity. Package benchmark `interner/*` on the same streams: 107 to 20 ms (USRs) and 37 to
19 ms (tokens) on one thread, 8.1 and 7.3 ms merged on four.

Not done here: consumers (0023 arcleak, 0024 deadwood, 0027 dolly); whether `intern` should be `@inlinable` (a call into
another module costs 15 to 20% in the micro-benchmark) is for those migrations to measure. The Linux build waits for CI.
