---
status: not-started
blocked-by: []
date: 2026-10-29
---

# 0040 — AemiProtobuf's CI has never run on Swift 6.4

Repository: AemiProtobuf (its own roadmap 0013, CI). Both of its runs failed (2026-10-26, 2026-10-28): its jobs run on
`macos-26` with the image's Swift 6.3.3 while `Package.swift` and `.swift-version` ask for 6.4 ("package 'aemiprotobuf' is
using Swift tools version 6.4.0 but the installed version is 6.3.3"), and `swift-format` is not on the runner. It does not
use aemi's shared workflow by decision (its ADR-0006), so 0037 does not reach it.

Scope: install the toolchain `.swift-version` names (as aemi's `swift-tool.yml` does with `swift-actions/setup-swift`
pinned by SHA), and `swift-format` from that toolchain. This is AemiProtobuf's work; the entry is here because 0017 depends
on AemiProtobuf being green.

Acceptance: AemiProtobuf's CI green on a push.
