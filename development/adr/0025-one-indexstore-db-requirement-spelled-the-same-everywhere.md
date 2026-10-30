---
status: accepted
date: 2026-10-30
---

# 0025 — One indexstore-db requirement, spelled the same in every package

## Context

analyzerkit requires indexstore-db at `revision: "0390867…"` (upstream `main`, roadmap 0010). arcleak and deadwood require
`revision: "64aa0b2…"`, which is today the head of `release/6.4.x`. dolly, fcheck and modeler pin analyzerkit `3032271`,
which does not depend on indexstore-db yet, so nothing conflicts today. The conflict comes with the first tool that takes
analyzerkit's head: swift-search's probe of sourcekit-lsp, which requires `release/6.4.x`, failed on exactly that.

SwiftPM probe (`research/probes/pins/requirement-spellings.sh`, 2026-10-30): a root depending on two local packages that require indexstore-db.

| Case | Requirements | Result |
| --- | --- | --- |
| C1 | revision `0390867` and branch `release/6.4.x` | fails: "two different revision-based requirements" |
| C2 | revision `64aa0b2` and branch `release/6.4.x`, **the same commit** | fails, same message |
| C3 | branch `release/6.4.x` twice | resolves |
| C4 | revision `64aa0b2` twice | resolves |
| C5 | branch `main` and branch `release/6.4.x` | fails |

SwiftPM compares the requirements as written, not the commits they name: every package must spell the requirement in the
same way. swift-lmdb comes only through indexstore-db and follows it.

Which spelling: `release/6.4.x` has none of `main`'s 28 commits since they split, among them "Read symbol records
concurrently when collecting occurrences" (`c2cc524`). Measured with a probe built twice (`research/probes/pins/IndexStoreDBRevisionProbe.swift`, built against each), on maintastic's Xcode store (8,774 units, 263,332 symbol names), Xcode's `libIndexStore`, runs
interleaved, load average 40–144, best of 4:

| Operation | `main` `0390867` | `release/6.4.x` `64aa0b2` |
| --- | ---: | ---: |
| Import into a new database | 4.92 s | 4.79 s |
| `canonicalOccurrences(ofName:)` × 2,011 | 0.82 s | 0.84 s |
| References of 500 sparse symbols | 0.19 s | 0.23 s |
| Every occurrence of 121 common symbols (106,301 occurrences) | **1.14 s** | **2.24 s** |

The counts are identical. The last row is what deadwood and arcleak do when they read references, and `main` halves it.
The 6.4 toolchain's `libIndexStore` reads the store through `main`'s IndexStoreDB with the same results.

## Decision

1. The family requires indexstore-db with **one revision, written identically** in every package that names it:
   analyzerkit, arcleak, deadwood, swift-search, and any other that adds it. No `branch:` requirement, which would conflict
   with every revision (C1, C2) and moves under the consumers.
2. analyzerkit's revision is the one. A tool moves its revision in the same commit as the analyzerkit bump that changes
   it, as it already does for aemi (one revision per package identity).
3. The revision stays on upstream `main` while it carries what the tools measure (row 4). A move to a release branch's
   head is a new measurement and an amendment, not a default.
4. sourcekit-lsp is not linked into a family package (swift-search ADR-0001: it runs out of process). Linking it would
   require its own indexstore-db requirement and is out of scope until that ADR changes.

## Consequences

- arcleak and deadwood go from `64aa0b2` to `0390867` in their migrations (0018, 0019), which already say so.
- A bump of indexstore-db is a train: analyzerkit first, then every tool, the same day; roadmap 0049 adds a script that
  lists every package's requirement so a mismatch is found before resolution fails.
- swift-search's option O1 ("`branch: release/6.4.x` everywhere") is refused: it costs row 4 and is no easier to keep.
- `main` is the next toolchain's branch: a commit there may need a newer `libIndexStore` than the toolchain in use. The
  family pins a revision measured against the toolchain in `.swift-version`, never `main`'s moving head.
