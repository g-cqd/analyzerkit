---
status: accepted
date: 2026-10-29
---

# 0012 — A real interner, in Aemi

## Context

Aemi's `InternedStrings` is compile-time string obfuscation (`@Interned`, `SI.v`), not an interner, and does not fit any
analyzer. The analyzers key their hot tables by `String`: deadwood's index graph by USR (64,675 declarations, 73,319
symbols on maintastic; `mapDeclarationsToUSRs` alone is ≈ 512 samples of the index run), arcleak's ownership graph by type
name, dolly by token text through its own two-level interner (per-file `[String]` tables merged serially through a
`[String: UInt32]`). A second consumer outside the analyzers is plausible: AemiJSON object keys, AemiProtobuf descriptor
names.

## Decision

1. A new Aemi product, `AemiInterner`, depending on `AemiKernel` only.
2. Storage: an append-only byte arena in fixed-size chunks (stable addresses, no reallocation of stored bytes) and an
   open-addressing table of `(hash, symbol)` with the hash stored to skip most byte comparisons. A symbol is a `UInt32`
   newtype. Interning takes UTF-8 bytes (a buffer, a `Substring`'s UTF-8 view, swift-syntax `SyntaxText`) and never makes a
   `String`; resolving returns a borrowed UTF-8 view, and a `String` only when asked.
3. Three forms, one format:
   - `Interner`: single-owner, mutable, the fastest; one per task.
   - `FrozenInterner`: immutable and `Sendable`, lock-free reads, for the analysis phase.
   - a parallel merge: per-task interners merged into one frozen table by sharding on the hash's top bits, one shard per
     worker, with deterministic symbols (assigned in input order, so the same corpus gives the same symbols on every run).
4. Serialisable as arena plus offsets, so a cache stores per-file tables and the merge rebuilds the corpus table.

## Consequences

- dolly's `CorpusAssembler`, deadwood's USR tables and arcleak's name tables move onto it (roadmap 0015, 0024, 0027).
- Nothing in the analyzers depends on `InternedStrings`.

## Open questions

- Gain over `[String: UInt32]` for USR-like keys (60–200 bytes) and for short tokens; hash choice (XXH64 is in AemiKernel;
  a faster short-key hash may pay); merge cost against a lock-striped concurrent table. Roadmap 0015 measures all three
  before the API is fixed.

Answered by measurement in roadmap 0015 (aemi's ADR 0019 and diary 2026-10-29-03): five times the dictionary on USRs and
2.5 times on tokens; wyhash; the per-worker merge, not a lock-striped table.
