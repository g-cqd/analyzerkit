---
status: not-started
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
