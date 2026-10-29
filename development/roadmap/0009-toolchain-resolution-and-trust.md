---
status: not-started
blocked-by: []
date: 2026-10-29
---

# 0009 — One toolchain resolution and one trust policy

Scope (ADR-0014): `DEVELOPER_DIR`, `xcode-select -p`, `xcrun`, user toolchains, Command Line Tools, in that order; trust =
regular file, not group- or world-writable, owner root or the current user, parent directory not writable by others;
`--verbose` names the chosen dylib and why others lost.

Red: `research/probes/TrustProbe.swift` as assertions (deadwood refuses a user-owned `Xcode.app` today); a fixture with a
group-writable dylib is refused; a `DEVELOPER_DIR` pointing at another Xcode wins.

Acceptance: both tools load Xcode's dylib on the owner's machine; the CLT fallback is used only when nothing earlier passes.
