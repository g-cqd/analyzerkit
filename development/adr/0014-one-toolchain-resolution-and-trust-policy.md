---
status: accepted
date: 2026-10-29
---

# 0014 — One toolchain resolution and one trust policy

## Context

deadwood requires `libIndexStore.dylib` to be owned by root. An `Xcode.app` installed outside the App Store (xcodes, a
downloaded `.xip`) is owned by the user, so deadwood refuses Xcode's own dylib and falls back silently to the Command Line
Tools copy; that works on the owner's machine only because both are Swift 6.4 (probe D4). arcleak accepts root or the
current user. Both hard-code `/Applications/Xcode.app` and ignore `xcode-select` and `DEVELOPER_DIR`.

## Decision

1. Resolution order: `DEVELOPER_DIR`, then `xcode-select -p`, then `xcrun --find swift`, then the user's
   `~/Library/Developer/Toolchains`, then `/Library/Developer/CommandLineTools`. The first candidate whose dylib passes the
   policy wins, and `--verbose` says which one and why the others lost.
2. Trust policy: after resolving links, a regular file, not group- or world-writable, owned by root or by the current user,
   in a directory that is not group- or world-writable.
3. A dylib whose toolchain differs from the one that built the store is reported as a note when the store's unit
   metadata says so.

## Consequences

- Xcode-beta and xcodes-named installations work; a machine without Command Line Tools works.

## Implementation boundary (2026-10-29)

Roadmap 0009 supplies one ordered resolver and trust policy in IndexStoreSupport, adopted by both tools. The parent
check means the immediate resolved containing directory, not every ancestor. The policy is defense in depth for a
developer CLI, not a sandbox or a race-free dlopen authorization mechanism. Explicit library overrides use it too.
Verbose diagnostics describe selection, not a successful load or index coverage. Store-unit compiler identity notes
(item 3) and the bounded process executor are integrated with the reader in roadmap 0010.
