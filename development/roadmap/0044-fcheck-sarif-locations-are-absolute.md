---
status: done
blocked-by: []
date: 2026-10-29
---

# 0044 — fcheck's SARIF locations are absolute under `--relative-to`

Found while recording the report goldens of 0011 (diary 2026-10-29-14). With `--relative-to`, fcheck's SARIF declares
`SRCROOT` but writes every location, the primary one and each code-flow step, as an absolute `file://` uri of the machine
that ran it: `ArtifactURI.location` takes the path as the report spells it, already relativized, and fcheck passed the
absolute one. The other three analyzers relativize first. Uploaded to GitHub code scanning from a CI runner, an fcheck
result then names `/home/runner/…`, which no repository file matches.

Red: a leak in `Sources/T.swift`, rendered as SARIF relative to the corpus root: every artifact location, primary and
code-flow, is `Sources/T.swift` with `uriBaseId` `SRCROOT` (fails today: all absolute).

Acceptance: the test green; fcheck's SARIF golden (0011) recorded after the fix.

## Done

fcheck `fd065b2` red, `853fe5a` green: each location path is relativized to the SARIF root before `ArtifactURI` and
`SarifColumns` see it. Paths outside the root or needing escapes stay absolute `file://` uris, as `ArtifactURI` decides.
Full fcheck suite green apart from the 0011 golden tests then in progress. A user-visible fix for the release notes of
fcheck's next patch release: SARIF uploads from CI link to repository files.
