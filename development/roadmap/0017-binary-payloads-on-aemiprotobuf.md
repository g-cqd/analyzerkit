---
status: done
blocked-by: []
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

## Done

`CorpusScanner.scan` has a protobuf overload for facts with AemiProtobuf's fast path (`0af0310`, red `2236d7e`); the
JSON path stays. The codec is part of the salt, so a payload one codec wrote is never decoded by the other.
`WireWriter.field(_:_:)` and `WireReader.forEachField`, `readInt`, `readBool`, `readEnum` and `readMessage` follow
proto3's implicit presence. String-raw enumerations go as their raw values; an unknown one fails the decode, so the
file is a miss. The tools write their conformances by hand with these helpers. `@ProtoMessage` would have needed
`var`s with defaults and integer enumerations in every model.

Measured first, in release on maintastic: payload decoding was at most 230 ms of deadwood's 2.08 s warm run, and
detection 1.7 s. The conversion was expected to save little time and half the size, and it did. Each red test has
two parts: every payload type round-trips byte-stable, and a 3,000-file synthetic corpus stays within its budget.

| tool | 3,000-file corpus, JSON → protobuf | budget | cache on maintastic | warm run, same load | commit |
|---|---|---|---|---|---|
| deadwood | 54.3 → 15.1 MB | under a third of JSON, under 16 MiB | 97 → 35 MB | scan 193 → 169 ms; run 1.59 → 1.54 s | `7f478a9` |
| dolly | 11.5 → 3.5 MB | under 40% of JSON | 26 → 8.1 MB | scan ~203 → ~193 ms (reads every file's text) | `e54fa10` |
| arcleak | 8.5 → 2.0 MB | under a third of JSON | 4.3 → 2.0 MB | 0.53 s either way; cold 1.21 → 0.97 s | `6f879c5` |

How each tool shrinks its payload:

- **deadwood** leaves a location's file out when it is the file's own.
- **dolly** writes its 16-byte token records as packed varint lanes (lines as zigzag deltas) instead of base64.
- **arcleak** writes each enumeration with associated values as a message of its case's name and payload.

Findings of warm runs equal uncached runs' on maintastic for all three. The acceptance "deadwood writes a cache on
maintastic and its warm run is faster than its cold run" was met by 0019's container already: 1.55 s warm against
2.08 s cold.
