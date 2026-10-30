---
status: not-started
blocked-by: []
date: 2026-10-30
---

# 0049 — Check that every package spells indexstore-db the same

ADR-0025. A script, `Scripts/family-pins.sh`, given the directory holding the checkouts, prints each package's
requirement on indexstore-db, aemi, AemiRegex, AemiJSON, AemiProtobuf and analyzerkit as written in its `Package.swift`,
and exits 1 when two packages write one identity differently. It reads manifests as text; it resolves nothing.

Red: a fixture directory of three manifests, one with `branch: "release/6.4.x"` against two revisions, makes it exit 1
and name the package; the same fixture with identical revisions exits 0.

Today it would report: indexstore-db `0390867` (analyzerkit, swift-search) against `64aa0b2` (arcleak, deadwood); aemi
`2fbe4e4` (AemiRegex, MacFS) against `04e49d1` (AemiJSON). Neither conflicts yet, because no package depends on both
sides; the script is there for the day one does. Not a CI job until the CI work resumes.
