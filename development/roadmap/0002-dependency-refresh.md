---
status: done
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

## Done

Diary 2026-10-29-04. aemi resolves swift-syntax 604.0.0 and swift-collections 1.7.5; analyzerkit and the five tools 1.7.5;
the benchmark packages of arcleak, deadwood and dolly afresh (they had drifted below their manifests) and build. AemiRegex,
AemiJSON and AemiProtobuf do not track `Package.resolved`: refreshed locally, suites run, nothing to commit. Consumers
resolve their own graph, so no pin moved downstream. Every suite green on macOS except one pre-existing AemiJSON failure
(0039). Found on the way: every shared-workflow caller's CI dead since aemi's rewrite (0037, repaired), AemiProtobuf's CI
never on Swift 6.4 (0040).
