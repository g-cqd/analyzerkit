---
status: not-started
blocked-by: [0040]
date: 2026-10-29
---

# 0017 — Cache payloads on AemiProtobuf

Scope (ADR-0010): measure first, on maintastic, the facts of each tool encoded by AemiJSON's macro path and by
AemiProtobuf's `@ProtoMessage` path (size, encode, decode, allocations); then give the facts types `@ProtoMessage`
conformances (repeated entry messages for dictionaries until AemiProtobuf's macro supports maps, its roadmap 0005);
consider packed `UInt32` lanes for dolly's token streams.

Red: a size budget per tool on a 3,000-file synthetic corpus (deadwood's JSON exceeds 64 MiB on maintastic today; the
budget is set from the measurement); round-trip equality of every facts type.

Acceptance: the measurement in the diary; deadwood writes a cache on maintastic and its warm run is faster than its cold run.

From 0016: on a warm run the shards cost 2 ms and decoding every payload (JSON) 26–29 ms of 46 on maintastic; that
decode is this item's target. The container takes payload bytes, so the codec changes in `CorpusScanner` alone.
