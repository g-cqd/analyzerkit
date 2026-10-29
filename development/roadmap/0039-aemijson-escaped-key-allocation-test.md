---
status: done
blocked-by: []
date: 2026-10-29
---

# 0039 — AemiJSON: `escapedKeysDoNotAllocatePerKey` fails

Repository: AemiJSON. Found during 0002 (diary 2026-10-29-04): `DuplicateKeyEscapeTests.escapedKeysDoNotAllocatePerKey`
fails locally on `5542d37` with 2,010 allocations for 500 plain keys against 4,011 for 500 escaped keys (budget: plain + 8),
identically with swift-collections 1.7.3 and 1.7.5, so not caused by the dependency refresh. AemiJSON's CI runs on Linux only,
where allocation counting is unavailable and the test records nothing, so CI never measured it.

Scope: find which allocation is made per escaped key (about four each), in debug and in release with `AEMIJSON_DEV=1`, and
whether it is a regression (bisect from the last green run, `95c43e8`) or a debug-only effect the test should account for.
This is AemiJSON's work; the entry is here because the analyzer family found it.

Acceptance: the test passes in both configurations, or a recorded decision in AemiJSON changes its budget.

## Done

Diary 2026-10-29-05. Measured by elimination: duplicate detection costs one allocation for escaped keys, as designed
(`\n` keys 2,011 against 2,010 plain); the extra four per key come from scanning any `\uXXXX`, in every string, during
`TapeBuilder.build()`; `JSONString.hex4` alone adds four allocations per call against an empty baseline loop, `Hex.value`
none. Debug only: in release everything measured zero and the test passed. The cause is `hex4`'s `for k in 0 ..< 4` loop in
a debug build of AemiJSONCore (why the compiler allocates there was not investigated). AemiJSON `f339174` (red:
`UnicodeEscapeScanAllocationTests`, 403 against 3) and `8b34bff` (fix: four explicit digit reads); 429 tests green in debug;
pushed.

Not done here: AemiJSON's CI cannot catch an allocation regression without a macOS leg, and other `for … in 0 ..< n` loops
in AemiJSONCore may allocate in debug the same way. Both are AemiJSON's to decide.
