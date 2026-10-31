---
status: in-progress
blocked-by: [0030]
date: 2026-10-29
---

# 0031 — g-cqd consumers: one script, one pin set

Repositories: aemi, AemiJSON, AemiRegex, AemiMarkdown, ask, AemiProtobuf, Atelier. Inventory in research
`2026-10-29-consumers-and-ci-contract.md`.

Before wave 1:
- aemi publishes one `Scripts/analyzers.sh` (install by version and SHA-256 for `macos-arm64` and `linux-x86_64`, run each
  tool with `--strict --no-cache --relative-to .` and the repository's baseline when present) and a `analyzers.lock`
  format; AemiJSON, AemiRegex, AemiMarkdown and ask replace their copies with it (four copies at three version sets
  today; AemiMarkdown is two releases behind).
- aemi's `swift-quality.yml` reads its defaults from the same lock instead of literal versions (0.11.0, 0.10.3, 0.10.2
  today).
- AemiProtobuf's `tools.lock`: fcheck and modeler from release archives (0.1.1 publishes them) instead of commits; close its
  roadmap 0015 as stale with a link to the releases.
- Atelier `Apps/GitDiffViewer/scripts/helpers.lock`: commits → release tags.

Each wave: bump the lock in aemi, then in each consumer (one line each); run; for wave 2 review new findings per the note
and refresh `.dolly-baseline.json` only if dolly's findings changed.

Red: aemi's script refuses an archive whose SHA-256 does not match the lock (test with a tampered archive).

Acceptance: every consumer on the same pin set after each wave, green.

## Progress

Wave 1, 2026-10-31. Every consumer is on the wave-1 set:

- **aemi:** red `f0a80e7`, green `7558abf`.
  - `Scripts/analyzers.sh` reads its tools, corpus, lock, cache and download URL from `ANALYZERS_*`. It runs
    `modeler check` and everything else with `analyze`, and passes each `.<tool>-baseline.json` that exists.
  - `Scripts/analyzers.lock` holds one line per tool: version, macOS hash, Linux hash.
  - `Scripts/tests/analyzers-test.sh` serves fake releases from a `file://` URL. It shows that a tampered archive and
    a tool missing from the lock both exit 2 before anything runs. CI runs it.
  - The defaults of `swift-quality.yml` moved to 0.13.0, 0.12.0 and 0.12.0. They are still literals; reading them from
    the lock is left.
- **AemiJSON (`8c00703`), AemiRegex (`ae59f93`), AemiMarkdown (`3737e8c`), ask (`a4ed168`):**
  - Each `Scripts/analyzers.sh` is now a bootstrap. It pins an aemi commit, keeps its own corpus, fetches the script
    and the lock from `raw.githubusercontent.com` into `~/Library/Caches/g-cqd-analyzers/aemi-<commit>`, and execs it.
  - All four are clean. AemiRegex's gate had been red already, under deadwood 0.11.1 too: `ByteRange` was unused, and
    `296f418` removes it.
  - ask's CI cache path follows the script, and its ADR-0022 is amended (`796b937`).
- **AemiProtobuf (`8f25cf5`):**
  - fcheck 0.2.0 and modeler 0.2.0 now come from release archives; `install_source` is gone, and its roadmap 0015 is
    done.
  - fcheck reports three `cut-then-decode` warnings in `ProtoJSONNumber.split`, the same as under 0.1.2. They appeared
    because the old pin predated the rule learning `dropFirst`. The slices are ASCII digits, so the warnings are
    accepted in place.
  - That is a gap in the rule: a `prefix` whose predicate admits only ASCII cannot straddle a character. It is noted
    for fcheck.
- **Atelier (`71cb60f`, `5956e54`, `28504f8`):**
  - `helpers.lock` pins the release commits, since its format and its decision D15 require commits.
  - The app's command line (`analyze <root> --only-from - --format sarif --relative-to <root>`) gives the same result
    counts under dolly 0.11.0 and 0.12.0.
  - Its old pins (the 0.11.0, 0.10.3 and 0.10.2 release commits) are no longer on the tools' `main`.
- **Wave 2:** aemi `1580771` (the lock and the swift-quality defaults). The bootstraps' `AEMI=` moved: AemiJSON
  `acddaf1`, AemiRegex `bb62f71`, AemiMarkdown `6895a0b` and ask `09a6d5f`. So did AemiProtobuf's `tools.lock`
  (`a5b1208`) and Atelier's `helpers.lock` (`5fdec61`, `348ad3a`, `be14512`). The swift-quality references at aemi `f6da05c` moved to
  `1580771` (AemiJSON, AemiRegex, Atelier `5b9bd6c`): that file differs only in its defaults. Every gate ran locally on
  the new releases and passed with the same baselines. AemiJSON's and AemiProtobuf's CI were already red before either
  wave (a NaN coding path and a Linux release build in AemiJSON, and `setup-swift`'s gpg step on AemiProtobuf's Linux job). Their
  analyzer jobs pass.
- **maintastic on wave 2** (MAIN-24613 on its current branch, local commits `793c0ae3fc`, `571b8dee01` and `f8dc637712`, not
  pushed): `ShareXcodePlugins` pins arcleak 0.14.0, dolly 0.13.0 and deadwood 0.13.0, up from 0.12.0, 0.11.0 and 0.11.1. All three keep their cache
  in `<tool>/cache`, because 0.13 and 0.14 leave alone the `facts` file that the old versions wrote and then run without a cache.
  deadwood gets its cache back: the 64 MiB limit is gone, and it runs in 4 s instead of 10 on an unchanged repository. `.arcleak.json` drops the excludes
  that only kept 0.12.0's index for the whole run, since arcleak now checks the index file by file. Measured on maintastic with its Xcode
  store: arcleak and dolly report the same findings; deadwood reports 36 fewer, all of them false positives under 0.11.1 (e.g.
  `ShareFonts.bodySmall`, which is used); a warm run equals a cold one. DangerPlugins' 153 tests pass.
- analyzerkit **0.4.0** is tagged at `805c89b`, which has wave 2's sources. Its release page needs a token with the `workflow` scope.
- **arcleak 0.15.0, fcheck 0.4.0, modeler 0.4.0:** aemi `d1b496e` (the lock; swift-quality's arcleak default). The
  bootstraps' `AEMI=` and the swift-quality references moved: AemiJSON `eaccfb9`, AemiRegex `5366ebb`, AemiMarkdown
  `dc878fd`, ask `3a684a5`, Atelier `8243cc5`. AemiProtobuf `tools.lock` is at `b508578`, and Atelier's GitDiffViewer helper at
  arcleak `403e421` (`1e4ae04`; that commit was built in release from a clean export). Every gate ran locally on the new
  releases with unchanged results. maintastic: arcleak 0.15.0 on PR #1805 (`07a2e6476e`), whose Danger run reports
  `Camera.getCurrentFrameInHD()` as a new warning.
