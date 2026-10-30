---
status: done
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

## Done

`SourceCorpus.LineIndex(_ bytes:)`: one pass records each line's start, content end and whether it holds a byte outside
ASCII; `lineCount`, `length(ofLine:)`, `line(containingByte:)` (binary search), `utf16Offset(line:utf8Column:)` and
`utf8Column(line:utf16Offset:)`, 1-based lines, nil for a line that does not exist. ASCII lines convert by arithmetic;
others transcode the line's bytes in place (`transcode` from an `ArraySlice` iterator, no `String`), so invalid UTF-8
counts exactly as `String(decoding:as:)` does; an offset inside a surrogate pair gives its scalar's start. Safe code
only: array indexing, which the release probe shows is fast enough. 8 tests, red at `a397131`.

Release probe (`/tmp/liprobe`, 10,000 lines, 472 KB, every tenth line non-ASCII, a third CRLF; best of 200 and 50,
three runs, loaded machine), against swift-search's `TextPositions` in the same binary:

| | `LineIndex` | `TextPositions` |
| --- | ---: | ---: |
| index the file | 0.35 ms (1.36 GB/s) | 11.1 ms |
| 1,000 column → offset, non-ASCII lines | 51–58 µs | 126–141 µs |
| 1,000 offset → column, non-ASCII lines | 73–83 µs | 625–633 µs |
| 1,000 column → offset, ASCII lines | 3–5 µs | — |

The bar (under 1 ms for 10,000 lines) is met. Not measured: allocations per conversion (the code allocates none on
either path; not checked with a counter).
