---
status: in-progress
blocked-by: []
date: 2026-10-29
---

# 0030 — The release train: three waves, one note format

Scope (ADR-0015). For each wave, in order:

1. Tag analyzerkit (`analyzerkit-wave-N` annotated tag on the pinned revision) and pin that revision in the five tools.
2. Release arcleak, deadwood, dolly, fcheck, modeler in that order (wave 1: 0.13.0, 0.12.0, 0.12.0, 0.2.0, 0.2.0; wave 2:
   0.14.0, 0.13.0, 0.13.0, 0.3.0, 0.3.0; wave 3: 0.15.0, 0.14.0, 0.14.0, 0.4.0, 0.4.0) through aemi's `swift-tool.yml`, which
   publishes the two archives, the artifact bundle and their `.sha256`.
3. Write each tool's release note with the fixed sections, every one filled or "none":
   - **Archives**: names, SHA-256 of each archive and of the bundle, bundle checksum as SwiftPM prints it.
   - **Flags**: added, renamed (old spelling still accepted until wave 3), removed.
   - **Exit codes**: changes.
   - **Report**: keys added, deprecated, removed; `schemaVersion` (stays 1).
   - **Configuration**: keys and files added or changed; `.swift-analyzers.json`.
   - **Cache**: location, format, what to delete on a runner, budget.
   - **Findings that may appear** and **findings that may disappear**: by rule, each with its probe and an example.
   - **Consumer steps**: maintastic (from 0032) and the g-cqd scripts and workflows (from 0031), as commands and file edits.
4. Before tagging: run the consumer steps on a branch of maintastic and of AemiJSON; both green, and the finding deltas
   match the note's two findings sections. Record the run in this repository's diary.
5. After tagging: open the consumer pull requests (0031, 0032) the same day.

Red: a release-note lint (sections present, each filled or "none", checksums match the published `.sha256`) run in the
tools' release workflow; it fails on today's free-form notes.

Acceptance: three waves shipped; every consumer on wave 3.

## Progress

Wave 1, 2026-10-31:

- **The release-note lint.** aemi red `44dcac2`, green `79e32de`, in `swift-tool.yml`'s publish job. It reads
  `release-notes/<tag>.md` from the tool's repository, requires the nine sections, each filled or "none", checks any
  checksum written against the published `.sha256` files, fills Archives from them, and publishes the result instead
  of generated notes. aemi's CI runs it on fixtures.
- **Notes** are written for arcleak 0.13.0, deadwood 0.12.0, dolly 0.12.0, fcheck 0.2.0 and modeler 0.2.0, and the
  versions are bumped. maintastic is not touched (the owner's call).
- **Linux had been broken across the family**, unseen while CI went unread:
  - aemi's directory walker named Darwin's `DIR` (`bf77673`, `8e054b9`), and AemiTestKit imported Testing publicly
    where nothing used it (`a20fb18`). aemi's CI had no Linux build; it has one now (`da29260`, `d2bd5e0`), limited to
    the products the tools take.
  - analyzerkit used `NSString`, `ObjCBool` and `subpaths(atPath:)`, which FoundationEssentials lacks, and Glibc's
    `pthread_getattr_np` in two tests (`cccc537`, `d00cb83`). A test of unreadable directories cannot run as root.
  - The tools' tests called `createFile` without using its result, which Linux does not discard.
- **Pins** for the wave: aemi `a20fb18`, AemiRegex `dcf5e3a`, AemiJSON `0869500`, AemiProtobuf `4947dd1`, analyzerkit
  `d00cb83`.
- **Shipped.** The tag `analyzerkit-wave-1` is at `d00cb83`. Every tag's CI passed and published both archives, the
  artifact bundle and their `.sha256` files. The lint filled each note's Archives section. fcheck's SwiftPM checksum,
  recomputed from the downloaded bundle, matches its note.

  | tool | tag | commit | macOS arm64 SHA-256 | Linux x86_64 SHA-256 |
  |---|---|---|---|---|
  | arcleak | v0.13.0 | `71efb6f` | `766f69e4…` | `8d9c2447…` |
  | deadwood | v0.12.0 | `ad6db61` | `5b962437…` | `780b56a1…` |
  | dolly | v0.12.0 | `88371dc` | `07700f9e…` | `fa08f218…` |
  | fcheck | v0.2.0 | `d2b4e47` | `95392d58…` | `2c5c3055…` |
  | modeler | v0.2.0 | `a046124` | `1afc4d85…` | `4d012b06…` |

  The full hashes are in aemi's `Scripts/analyzers.lock`. The consumers are on this set (0031). There were no pull
  requests: the owner asked for direct commits to `main`.
- **Wave 2 shipped.** The tag `analyzerkit-wave-2` is at `0a13bbf`: IndexQueries' name scan (0054) and SymbolFacts
  (0055). arcleak and deadwood read the index through `IndexQueries`, and deadwood collects with `SymbolFacts`, byte-equal
  on maintastic. dolly, fcheck and modeler only move to the shared revision (ADR-0025). Each tool's suite passed
  locally before its tag. CI was not awaited, at the owner's request. Every tag's run then passed and published.

  | tool | tag | commit | macOS arm64 SHA-256 | Linux x86_64 SHA-256 |
  |---|---|---|---|---|
  | arcleak | v0.14.0 | `dac733f` | `ae10f9a2…` | `8322167a…` |
  | deadwood | v0.13.0 | `ece2a67` | `93aaf921…` | `e964ef5e…` |
  | dolly | v0.13.0 | `a37d45a` | `16ba43c5…` | `70943a58…` |
  | fcheck | v0.3.0 | `dc96dc8` | `000884a7…` | `c212eb33…` |
  | modeler | v0.3.0 | `7993d95` | `d3076ae5…` | `6355e848…` |

  The full hashes are in aemi's `Scripts/analyzers.lock` (`1580771`). Wave 3 drops the old flag spellings.
- **After wave 2, on analyzerkit `0a13bbf`:** rules found by running fcheck and modeler on maintastic (roadmap 0062 to
  0066). Each suite passed locally before its tag, and each tag's run passed and published.

  | tool | tag | commit | macOS arm64 SHA-256 | Linux x86_64 SHA-256 |
  |---|---|---|---|---|
  | arcleak | v0.15.0 | `403e421` | `1b7186d9…` | `9680abe8…` |
  | fcheck | v0.4.0 | `03acac1` | `ce39ff6b…` | `17b40071…` |
  | modeler | v0.4.0 | `1b3993e` | `f59cadb9…` | `458d66a4…` |
