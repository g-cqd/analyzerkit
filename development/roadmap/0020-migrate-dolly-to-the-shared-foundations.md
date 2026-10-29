---
status: not-started
blocked-by: [0007, 0016, 0043]
date: 2026-10-29
---

# 0020 — Migrate dolly to the shared foundations (wave 1)

Repository: g-cqd/dolly. Scope: replace (or, where the tool has none, adopt) the tool's own discovery, path filter, report formatter, baseline, path
presentation, suppression, command-line options and facts cache with analyzerkit's (ADR-0016); read
`.swift-analyzers.json`; keep the old flag spellings as aliases. `contextNote` stays beside `notes` until wave 3.

Red: golden reports (xcode, JSON, SARIF, baseline) recorded from the current release on the tool's fixture corpus and on a
pinned snapshot of a g-cqd package; the migrated tool must match them byte for byte apart from added keys. The shared
`--help` and exit-code goldens of 0013 fail until the migration lands.

Acceptance: goldens green; the tool's suite green; its own copies of the replaced files deleted; timings on maintastic before
and after in the tool's diary.

Also (from 0014): with the shared output options, `--verbose` prints `SharedConfiguration.Resolved.verboseLines`;
dolly discards them until then.
