---
status: not-started
blocked-by: []
date: 2026-10-30
---

# 0057 — swift-search's four defects, probed in deadwood and arcleak

ADR-0027. swift-search found four defects in code deadwood and arcleak share by lineage (swift-search diary
2026-10-29-01, probes 2, 3, 4, 6). Each gets a probe in both tools before any fix:

1. Index paths `/private/var/…` against corpus paths `/var/…`: a fixture package under `/var` (a temporary directory)
   with an index store; does the tool match its findings to files, or drop or duplicate them?
2. A function looked up by its exact name: IndexStoreDB names it `fetch(id:)`; does a lookup by `fetch` miss it?
3. CRLF: a file with CRLF endings; are line numbers after the first line right? (`"\r\n"` is one `Character`.)
4. A property never read: does deadwood report swift-search's removed `SourcePosition.location` shape (a public
   property with a function-typed neighbour of the same name)?

Each probe that reproduces becomes a red test in the tool and a fix in its migration (0018, 0019) or on its own if it
changes a report; each that does not is recorded here with why.
