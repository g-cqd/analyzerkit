---
status: accepted
date: 2026-10-29
---

# 0010 — Internal caches are binary, on AemiProtobuf; what others read stays JSON

## Context

Measured on maintastic (research `2026-10-29-performance-on-maintastic.md`): dolly's facts cache is 27 MB of JSON and its
warm run (1.00 s) is barely faster than its cold run (1.24 s); modeler's is 10.8 MB and decoding it costs about what
parsing does; deadwood's exceeds its 64 MiB cap, is never written, and every run is cold (warm 3.6 s = cold 3.6 s). In
fcheck and modeler the decode runs serially on the main thread through AemiJSON's generic `Codable` path
(`DecodeContext.memberValueIndex`). No program but the tool that wrote it reads a cache. AemiProtobuf writes 46–50 % of the
JSON size for record-shaped data and its macro path decodes 2× faster than AemiJSON's macro path on its benchmark
(AemiProtobuf `docs/research/2026-10-25-aemijson-vs-aemiprotobuf.md`).

## Decision

1. Formats read only by the tool that wrote them (facts caches, the interner tables, index-coverage memos) are binary:
   AemiProtobuf wire format through `@ProtoMessage` types, inside the container of ADR-0011.
2. Formats read by anything else stay JSON and byte-stable: reports, SARIF, baselines, configuration, `modeler facts`.
   They stay on Foundation's encoder, as today, because baselines hash their bytes.
3. AemiProtobuf's generic `Codable` path is not used for caches: it decodes slower than AemiJSON's (11.1 against 6.5 ms on
   AemiProtobuf's own benchmark; its roadmap 0018). Facts types get `@ProtoMessage` conformances.

## Consequences

- Facts types are shaped as messages: dictionaries become repeated entry messages until AemiProtobuf's macro supports maps
  (its roadmap 0005), enums become integer fields with an explicit unknown case.
- A cache written by another build is discarded whole, as today (build identity in the container header), so the wire
  format's schema evolution is a convenience, not a requirement.

## Open questions

- Size and decode time of each tool's facts in AemiProtobuf against AemiJSON's macro path on maintastic (roadmap 0017
  measures before converting all tools).
- Whether dolly's token streams are better stored as raw packed arrays (`[UInt32]` lanes) than as protobuf packed fields.
