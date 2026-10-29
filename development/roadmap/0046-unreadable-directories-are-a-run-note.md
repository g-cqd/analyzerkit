---
status: not-started
blocked-by: []
date: 2026-10-29
---

# 0046 — An unreadable directory is a run note in every tool

Found while closing 0007 (diary 2026-10-29-19): `SourceDiscovery.discover(under:isExcluded:)` now says which directories it
could not list, and every tool still calls `swiftFiles`, so a directory without read permission drops its files from the
analysis without a word, in all five tools.

Scope: each tool calls `discover` and turns `unreadableDirectories` into one `RunNote` (ADR-0017), code
`unreadable-directory`, severity `warning`, paths listed under the usual cap; the files it hid are not `skippedFiles`, since
nobody knows them. Every file found skipped and no file analyzed still exits 70 (ADR-0018); an unreadable directory alone
does not change the exit status.

Red: per tool, a fixture with a directory at mode 000 beside a readable one: the report carries the note with that path
(fails today: no note).

Acceptance: the five tools' report goldens unchanged when every directory is readable.
