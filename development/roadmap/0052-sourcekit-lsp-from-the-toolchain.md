---
status: not-started
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
