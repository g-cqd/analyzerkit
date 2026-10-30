---
status: done
blocked-by: []
date: 2026-10-30
---

# 0057 — swift-search's four defects, probed in deadwood and arcleak

ADR-0027. swift-search found four defects in code deadwood and arcleak share by lineage (swift-search diary
2026-10-29-01, probes 2, 3, 4, 6). Each gets a probe in both tools before any fix:

1. Index paths `/private/var/…` against corpus paths `/var/…`: a fixture package under `/var` (a temporary directory)
   with an index store; does the tool match its findings to files, or drop or duplicate them?
2. A function looked up by its exact name: IndexStoreDB names it `fetch(id:)`; does a lookup by `fetch` miss it?
3. CRLF: a file with CRLF endings; are line numbers after the first line right? (`"\r\n"` is one `Character`.)
4. A property never read: does deadwood report swift-search's removed `SourcePosition.location` shape (a public
   property with a function-typed neighbour of the same name)?

Each probe that reproduces becomes a red test in the tool and a fix in its migration (0018, 0019) or on its own if it
changes a report; each that does not is recorded here with why.

## Done

`research/probes/swift-search-defects.sh` (fixtures under `$TMPDIR`, which macOS spells `/var/folders/…` while the
compiler records `/private/var/…`), run on deadwood `4fbb624` and arcleak `32c15ea` debug builds:

| | Defect | deadwood | arcleak |
| --- | --- | --- | --- |
| 1 | `/var` against `/private/var` | not reproduced: the index is used, `neverCalled()` found (both sides go through `resolvingSymlinksInPath`) | not reproduced: "index store active", the cycle found |
| 2 | exact name misses `name(label:)` | not applicable: no lookup by name | not applicable: it looks up type names only, which carry no labels |
| 3 | CRLF split as one `Character` | line numbers right (SwiftSyntax). **`--only-from` with a CRLF or CR file scoped every finding out, exit 0**: fixed, `fcbb3f7` (red `2c11c61`) | the same, fixed, `78626fb` (red `419fb44`) |
| 4 | an unread property beside a called function of the same base name | **reproduced by name**: `Position.location` unreported, because `Converter().location(for:)` counts as its use; found with the index | not applicable |

The `--only-from` fix splits on `Character.isNewline`. The comment above the old split claimed it handled CRLF by
trimming `\r`, but the trim never ran, because the split never cut the text. Both tools' full suites pass (deadwood 388,
arcleak 230 tests).

Also found, and left: arcleak's and deadwood's embedding-rank snippets (`ArcLeakCommand.snippets(for:)`, deadwood
`Analyzer.snippet`) split source text on `"\n"`. On a CRLF file they pick the wrong text. That only reorders findings under
the experimental embedding ranking, so it waits for the migrations (0018, 0019), which read lines through analyzerkit.

Defect 4 changes deadwood's report (it adds findings), so it is its own entry: 0058.
