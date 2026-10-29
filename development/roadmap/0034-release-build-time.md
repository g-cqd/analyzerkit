---
status: not-started
blocked-by: []
date: 2026-10-29
---

# 0034 — Release build time

Scope: each tool's release build compiles AemiJSONCore whole-module on its own (about 4 min, 1.6 GB under load; 250–435 s
per tool). Probe first: where the time goes (`-Xfrontend -debug-time-function-bodies`, `-driver-time-compilation`), whether
the tools need AemiJSONCore at all after 0017 (caches leave AemiJSON), and whether CI caches the build products between tools.

Red: none until measured. Acceptance: the measurement in the diary and an entry per remedy.
