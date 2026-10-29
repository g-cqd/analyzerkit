---
status: done
blocked-by: []
date: 2026-10-29
---

# 0009 — One toolchain resolution and one trust policy

Scope (ADR-0014): `DEVELOPER_DIR`, `xcode-select -p`, `xcrun`, user toolchains, Command Line Tools, in that order; trust =
regular file, not group- or world-writable, owner root or the current user, parent directory not writable by others;
`--verbose` names the chosen dylib and why others lost.

Red: `research/probes/TrustProbe.swift` as assertions (the original probe found deadwood refusing a user-owned
`Xcode.app`; wave 0 repaired ownership, not resolution order or parent permissions); a fixture with a group-writable
dylib is refused; a `DEVELOPER_DIR` pointing at another Xcode wins.

Acceptance: both tools load Xcode's dylib on the owner's machine; the CLT fallback is used only when nothing earlier passes.

## Done

Diary 2026-10-29-12. Introduced the `IndexStoreSupport` product with the index-reader-independent toolchain/trust foundation;
IndexStoreDB opening and process-executor consolidation remain in 0010. Shared red `f2848c8`, green `fe58b7e`.

`ToolchainResolution.resolve` tries DEVELOPER_DIR (developer directory or .app), system xcode-select, xcrun, user
.xctoolchain directories in descending name order, then CLT. Stops on success, returns the checked canonical path and
all preceding rejection reasons. Fixed absolute system probes; no shell, inherited DYLD variables or caller PATH.
xcode-select sees no override; xcrun sees the explicit DEVELOPER_DIR. Library checks resolve links, require a regular
file owned by root/current user, refuse group/world-writable files and immediate parents. This does not claim to check
every ancestor or prevent a concurrent check-to-dlopen replacement race.

Nine shared tests cover ordering, lazy short-circuiting, root/current/foreign ownership, writable files and parents,
links, malformed paths, environment scrubbing, CLT fallback and all-candidates-rejected diagnostics. Full shared suite
passes. Arcleak `cc0a076` red, `b0d7744` green; deadwood `7557f74` red, `1330bba` green, both pin `fe58b7e`.
Their copied permission checks and discovery policies are gone; tiny compatibility surfaces delegate to analyzerkit.
Both also check explicitly supplied dylibs before creating a database or calling dlopen. `--verbose` prints selection
and rejection diagnostics to stderr only when index mode is requested, without altering reports or exit status.
Deadwood's older symlink test now expects the resolved-target policy required by ADR-0014.

Verified full tool suites: arcleak 211 tests, deadwood 369. Throwaway local probes (removed afterward) assert both select
/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/libIndexStore.dylib; each compiles
a temporary fixture with the matching swiftc, opens its own reader through default discovery and reads an indexed unit.
No maintastic files/stores changed. No release builds, Linux execution or CI work in this pass.

The narrow synchronous system probes retain the previous timeout-free synchronous behavior; 0010 must replace them
with the consolidated bounded executor. Compiler/toolchain mismatch notes from store unit metadata (ADR-0014 item 3)
also belong to 0010's reader/coverage integration, not a filesystem-only resolver.
