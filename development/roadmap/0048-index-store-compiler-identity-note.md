---
status: not-started
blocked-by: []
date: 2026-10-29
---

# 0048 — A note when the store was built by another compiler

ADR-0014 item 3, left out of 0010: when the store's units say which compiler wrote them and it is not the toolchain whose
`libIndexStore` reads them, the report says so. IndexStoreDB does not expose a unit's provider identifier or version; the
C API of `libIndexStore` does (`indexstore_unit_reader_get_provider_identifier`, `…_get_provider_version`), so this needs
a unit reader of our own over the trusted library, opened by `dlopen` and used only for those two strings, sampled on a
few units rather than all.

Measure first whether it earns its unsafe code: libIndexStore reads every store version it knows regardless of the
compiler, so the note is advice, and the toolchain resolution's `--verbose` already says which library was chosen.

Red: a store written by a fixture whose units claim another provider version (or, failing a way to write one, a unit file
from an older toolchain kept as a fixture) gives the note; a store from the resolved toolchain gives none.
