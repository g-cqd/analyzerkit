---
status: done
blocked-by: []
date: 2026-10-30
---

# 0052 — The toolchain's `sourcekit-lsp` (P5)

ADR-0027. `ToolchainResolution` already finds the trusted `libIndexStore` (ADR-0014): from an explicit path, the
`TOOLCHAINS`/`DEVELOPER_DIR` environment, `xcrun`, then the default toolchain. `sourcekit-lsp` is found the same way and
next to the same library, so the server and the reader always come from one toolchain; an explicit `--sourcekit-lsp`
wins and must be an absolute, executable, regular file.

Red: a fake toolchain directory with both files resolves both from it; a toolchain without `sourcekit-lsp` reports which
file is missing; an explicit relative path is refused; resolution runs `xcrun` at most once for both.
Consumer: swift-search, which resolves it itself today.

## Done

`ToolchainResolution.Outcome.sourceKitLSPPath`: once a library is selected, the server is looked for at `usr/bin` beside
its `usr/lib`, so it always comes from the library's toolchain and costs no command (xcrun is still asked only
`--find swift`). It must be a regular executable file that passes `BinaryTrustChecker`; the outcome's diagnostics say
which server was selected, or that there is none, or why one was refused. `explicitSourceKitLSP(_:)` checks a path given
on the command line: absolute, executable, trusted, returned canonical. 5 tests, red at `14c6744`. Xcode's toolchain and
the user toolchains on this machine (6.3.3, 6.4.0) have the same layout. swift-search's `SourceKitLSP.locate` goes in
its 0006.
