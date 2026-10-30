---
status: not-started
blocked-by: []
date: 2026-10-30
---

# 0051 — Columns in UTF-8 and UTF-16 (P4)

ADR-0027. A line index over a file's bytes (`SourceCorpus.LineIndex`): line starts found once with `memchr` on LF and a
CR scan (all three line ends, never `Character`, which makes CRLF one), and conversions between a 1-based UTF-8 column
and a 0-based UTF-16 offset on one line, computed from that line's bytes only: ASCII lines answer in O(1) after an ASCII
check, others by walking the line's scalars. swift-search's `TextPositions` decodes whole lines into `String` per call
and splits the file into `Substring`s up front (its H10).

Red: CRLF, CR and LF endings; a line with a 4-byte scalar (one column of 4 bytes, two UTF-16 units); a column past the
end of the line is clamped; invalid UTF-8 counts each invalid byte as one replacement (one UTF-16 unit), as
`String(decoding:)` does; the round trip column → offset → column on every boundary of a mixed line.

Bar: a 10,000-line file indexed in under 1 ms (release); a conversion on an ASCII line without allocating.
Consumers: swift-search (LSP positions), arcleak's LSP server, SARIF `columnKind: utf16CodeUnits` if a writer ever
emits it.
