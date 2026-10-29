---
status: done
blocked-by: []
date: 2026-10-29
---

# 0037 — Restore CI after aemi's history rewrite

Found during 0002 (diary 2026-10-29-04). Since aemi's authorship rewrite on 2026-10-28, the commits its callers pinned for
the shared workflows (`afc1be3`, `4f270e0`) are on no branch, and GitHub refuses them: "error parsing called workflow
… swift-tool.yml@afc1be3…: workflow was not found". Every run of AemiJSON, AemiRegex, analyzerkit, arcleak, deadwood,
dolly, fcheck, modeler and Atelier since that evening failed with no job started.

Scope: the ten `uses:` lines in those nine repositories point at `f6da05c` (aemi `main`), whose `swift-tool.yml` and
`swift-quality.yml` are byte-identical to the old pins'.

## Done

One commit per repository ("ci: call aemi's shared workflow at f6da05c, which is on main"); `actionlint` clean before and
after. Not yet pushed, so not yet seen green on GitHub; the next push of each repository is the proof.

Left open, as their own entries: a pinned workflow commit must stay on a branch of aemi (0038); AemiJSON's suite has one
failing test that the broken CI hid (0039); AemiProtobuf's CI has never run on Swift 6.4 (0040).
