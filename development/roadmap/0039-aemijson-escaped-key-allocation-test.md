---
status: not-started
blocked-by: []
date: 2026-10-29
---

# 0039 — AemiJSON: `escapedKeysDoNotAllocatePerKey` fails

Repository: AemiJSON. Found during 0002 (diary 2026-10-29-04): `DuplicateKeyEscapeTests.escapedKeysDoNotAllocatePerKey`
fails locally on `5542d37` with 2,010 allocations for 500 plain keys against 4,011 for 500 escaped keys (budget: plain + 8),
identically with swift-collections 1.7.3 and 1.7.5, so not caused by the dependency refresh. AemiJSON's CI has not run since
the aemi rewrite (0037), so it has not reported it; it will on the next push.

Scope: find which allocation is made per escaped key (about four each), in debug and in release with `AEMIJSON_DEV=1`, and
whether it is a regression (bisect from the last green run, `95c43e8`) or a debug-only effect the test should account for.
This is AemiJSON's work; the entry is here because the analyzer family found it.

Acceptance: the test passes in both configurations, or a recorded decision in AemiJSON changes its budget.
