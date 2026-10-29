---
status: not-started
blocked-by: []
date: 2026-10-29
---

# 0002 — Dependency refresh

Scope: swift-collections 1.7.5 (resolved) in analyzerkit and the five tools, and in aemi and AemiJSON (from 1.7.3);
swift-syntax 604.0.0 in aemi's resolution (from 603.0.2). swift-argument-parser 1.8.2, swift-system 1.8.1, indexstore-db
and swift-lmdb at `release/6.4.x` are current; `main` of indexstore-db is the next toolchain and is not followed. Order:
aemi → AemiRegex → AemiJSON → AemiProtobuf → analyzerkit → tools, each `swift test` green before the next, then the
revision pins of analyzerkit in the tools.

Red: none (no behaviour). Acceptance: every suite green; `Package.resolved` diffs only in these entries.
