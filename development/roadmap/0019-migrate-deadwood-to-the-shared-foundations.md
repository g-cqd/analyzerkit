---
status: not-started
blocked-by: [0005, 0007, 0010, 0011, 0012, 0013, 0014, 0016]
date: 2026-10-29
---

# 0019 — Migrate deadwood to the shared foundations (wave 1)

Repository: g-cqd/deadwood. Scope: replace the tool's own discovery, path filter, report formatter, baseline, path
presentation, suppression, command-line options and facts cache with analyzerkit's (ADR-0016); read
`.swift-analyzers.json`; keep the old flag spellings as aliases. Its `IndexStore/` directory moves onto `IndexStoreSupport`, keeping today's behaviour; its `GlobMatcher`, `SafeRegex` and `RegexCache` are deleted (ADR-0008). Its cache now fits (0016, 0017), so maintastic can drop `--no-cache`.

Red: golden reports (xcode, JSON, SARIF, baseline) recorded from the current release on the tool's fixture corpus and on a
pinned snapshot of a g-cqd package; the migrated tool must match them byte for byte apart from added keys. The shared
`--help` and exit-code goldens of 0013 fail until the migration lands.

Acceptance: goldens green; the tool's suite green; its own copies of the replaced files deleted; timings on maintastic before
and after in the tool's diary.
