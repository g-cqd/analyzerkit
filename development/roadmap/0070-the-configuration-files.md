---
status: not-started
blocked-by: [0069]
date: 2026-11-01
---

# 0070 — `.swift-analyzers.json` in the tools

Step 5 of 0067, last part. Each tool reads its section of `.swift-analyzers.json` with its own decoding and merge with the
command line. The loading and the precedence (file, then flags) are the same; the keys are not.

Red: a configuration with an unknown key, a wrong type and a missing file gives the same message and exit code in the three
tools before and after; the keys each tool accepts stay as they are.

Acceptance: loading, precedence and the error texts are in analyzerkit; each tool declares its keys only. No key is added or
renamed, so no consumer step.

Last in the order because it touches the most user-visible text.
