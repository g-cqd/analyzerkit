---
status: not-started
blocked-by: []
date: 2026-11-01
---

# 0068 — Facts coding shared by arcleak, deadwood and dolly

Step 5 of 0067, first part. The three tools write their per-file facts to the cache with similar `Codable` code (the
research note puts it near 3,000 tokens). Changing a facts type changes the cache payload, so every runner pays a cold run and
each tool bumps its cache `version`; that is why it was kept out of the first four steps.

Red: for each tool, a facts value encoded by the current code decodes through the shared code to an equal value, and the other
way round, on the fixtures; then the cache bytes of a fixture run are compared and the difference, if any, is listed.

Acceptance: the shared coding is in analyzerkit with its own tests; the tools' reports are byte-equal; the release note's
Cache section says whether the payload changed and what to delete on a runner.

Not started; nothing was prototyped.
