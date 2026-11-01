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
   - **Consumer steps**: the reference app (from 0032) and the g-cqd scripts and workflows (from 0031), as commands and file edits.
4. Before tagging: run the consumer steps on a branch of the reference app and of AemiJSON; both green, and the finding deltas
   match the note's two findings sections. Record the run in this repository's diary.
5. After tagging: open the consumer pull requests (0031, 0032) the same day.

Red: a release-note lint (sections present, each filled or "none", checksums match the published `.sha256`) run in the
tools' release workflow; it fails on today's free-form notes.

Acceptance: three waves shipped; every consumer on wave 3.

## Progress

Wave 1, 2026-10-31:

- **The release-note lint.** aemi red `cbf67b1`, green `9b19354`, in `swift-tool.yml`'s publish job. It reads
  `release-notes/<tag>.md` from the tool's repository, requires the nine sections, each filled or "none", checks any
  checksum written against the published `.sha256` files, fills Archives from them, and publishes the result instead
  of generated notes. aemi's CI runs it on fixtures.
- **Notes** are written for arcleak 0.13.0, deadwood 0.12.0, dolly 0.12.0, fcheck 0.2.0 and modeler 0.2.0, and the
  versions are bumped. the reference app is not touched (the owner's call).
- **Linux had been broken across the family**, unseen while CI went unread:
  - aemi's directory walker named Darwin's `DIR` (`5eeac3f`, `7c14a00`), and AemiTestKit imported Testing publicly
    where nothing used it (`18b02d3`). aemi's CI had no Linux build; it has one now (`7e67739`, `a3ac239`), limited to
    the products the tools take.
  - analyzerkit used `NSString`, `ObjCBool` and `subpaths(atPath:)`, which FoundationEssentials lacks, and Glibc's
    `pthread_getattr_np` in two tests (`59bca29`, `bfceb6f`). A test of unreadable directories cannot run as root.
  - The tools' tests called `createFile` without using its result, which Linux does not discard.
- **Pins** for the wave: aemi `18b02d3`, AemiRegex `c0307ab`, AemiJSON `6495fd1`, AemiProtobuf `a475f6f`, analyzerkit
  `bfceb6f`.
- **Shipped.** The tag `analyzerkit-wave-1` is at `bfceb6f`. Every tag's CI passed and published both archives, the
  artifact bundle and their `.sha256` files. The lint filled each note's Archives section. fcheck's SwiftPM checksum,
  recomputed from the downloaded bundle, matches its note.

  | tool | tag | commit | macOS arm64 SHA-256 | Linux x86_64 SHA-256 |
  |---|---|---|---|---|
  | arcleak | v0.13.0 | `8556878` | `766f69e4…` | `8d9c2447…` |
  | deadwood | v0.12.0 | `67b4095` | `5b962437…` | `780b56a1…` |
  | dolly | v0.12.0 | `f5a2632` | `07700f9e…` | `fa08f218…` |
  | fcheck | v0.2.0 | `310335f` | `95392d58…` | `2c5c3055…` |
  | modeler | v0.2.0 | `073d929` | `1afc4d85…` | `4d012b06…` |

  The full hashes are in aemi's `Scripts/analyzers.lock`. The consumers are on this set (0031). There were no pull
  requests: the owner asked for direct commits to `main`.
- **Wave 2 shipped.** The tag `analyzerkit-wave-2` is at `04d8eba`: IndexQueries' name scan (0054) and SymbolFacts
  (0055). arcleak and deadwood read the index through `IndexQueries`, and deadwood collects with `SymbolFacts`, byte-equal
  on the reference app. dolly, fcheck and modeler only move to the shared revision (ADR-0025). Each tool's suite passed
  locally before its tag. CI was not awaited, at the owner's request. Every tag's run then passed and published.

  | tool | tag | commit | macOS arm64 SHA-256 | Linux x86_64 SHA-256 |
  |---|---|---|---|---|
  | arcleak | v0.14.0 | `9c91ba8` | `ae10f9a2…` | `8322167a…` |
  | deadwood | v0.13.0 | `9f77f9a` | `93aaf921…` | `e964ef5e…` |
  | dolly | v0.13.0 | `2f7f5e3` | `16ba43c5…` | `70943a58…` |
  | fcheck | v0.3.0 | `4c5d1f1` | `000884a7…` | `c212eb33…` |
  | modeler | v0.3.0 | `29c65f7` | `d3076ae5…` | `6355e848…` |

  The full hashes are in aemi's `Scripts/analyzers.lock` (`45a62fd`). Wave 3 drops the old flag spellings.
- **After wave 2, on analyzerkit `04d8eba`:** rules found by running fcheck and modeler on the reference app (roadmap 0062 to
  0066). Each suite passed locally before its tag, and each tag's run passed and published.

  | tool | tag | commit | macOS arm64 SHA-256 | Linux x86_64 SHA-256 |
  |---|---|---|---|---|
  | arcleak | v0.15.0 | `daff058` | `1b7186d9…` | `9680abe8…` |
  | fcheck | v0.4.0 | `49bb882` | `ce39ff6b…` | `17b40071…` |
  | modeler | v0.4.0 | `f5b44d4` | `f59cadb9…` | `458d66a4…` |
- **2026-11-01, a dependency release on analyzerkit `da8888d`.** The family's heads after the parenthesis change (ask's roadmap 0184,
  `lineBreakBeforeEachArgument`): aemi `0ef4279`, AemiRegex `bc59772`, AemiJSON `cbac433`, AemiProtobuf `7393728`. AemiJSON `cbac433` puts the
  element's position or the member's key before an error from its fast-path encodes (AemiJSON's roadmap 0005). The tools' sources
  are only reformatted, so the findings are those of the previous release; each suite and `Scripts/lint-format.sh` passed locally
  before its tag. CI was not awaited, so the archives' hashes and aemi's `Scripts/analyzers.lock` are not updated yet. This is not
  wave 3, which still drops the old flag spellings. swift-search is pinned to the same set locally (its repository is not published).

  | tool | tag | commit |
  |---|---|---|
  | arcleak | v0.15.1 | `c9d047d` |
  | deadwood | v0.13.1 | `b011e55` |
  | dolly | v0.13.1 | `7378056` |
  | fcheck | v0.4.1 | `57f9e00` |
  | modeler | v0.4.1 | `73662f8` |
- **2026-11-01, a second dependency release, on analyzerkit `2e63fd3`.** The family's heads at 17:00: aemi `a4e7edc` (ADR 0024: AemiArgon2,
  CAemiCPU, an Embedded AemiKernel), AemiRegex `b4a058f`, AemiJSON `f03e42f`, AemiProtobuf `9af5a96` (re-pinned to them first). arcleak
  0.16.1, deadwood 0.14.2, dolly 0.13.2, fcheck 0.4.3 and modeler 0.4.2 are pins only, except deadwood: its tags v0.14.0 and v0.14.1
  never published (the Linux build did not compile, a branch of `Analyzer.indexAwareUnused` returned a pair for a triple), so 0.14.2 is
  the first 0.14 and its note is the sum. Built and tested in `swift:6.4.1-noble` before the tags: deadwood, arcleak and fcheck;
  dolly and modeler were not (the container hung). On arm64 Linux, SwiftPM's own test discovery crashes in libIndexStore ("corrupted
  double-linked list"); `--disable-index-store` avoids it. aemi moved again at 17:59 (`8087a01`, AemiArgon2 only) while this ran, so the
  tools are one aemi commit behind; Atelier is on it.

  | tool | tag | commit |
  |---|---|---|
  | arcleak | v0.16.1 | `36a20ef` |
  | deadwood | v0.14.2 | `c2dc872` |
  | dolly | v0.13.2 | `edce425` |
  | fcheck | v0.4.3 | `4211a0e` |
  | modeler | v0.4.2 | `901a3e9` |

  Before this, on the same day: arcleak 0.16.0 (`cac8645`), fcheck 0.4.2 (`c8599aa`), deadwood 0.14.1 (`72a1213`, not published).
