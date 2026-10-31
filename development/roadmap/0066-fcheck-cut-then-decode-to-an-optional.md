---
status: done
blocked-by: []
date: 2026-10-31
---

# 0066 — fcheck: bytes cut and decoded to an optional

`cut-then-decode` reads `String(decoding:as:)`, which turns a split character into U+FFFD. `String(data:encoding:
.utf8)` and `String(bytes:encoding: .utf8)` of the same cut return nil instead, which drops the whole text, usually
behind a `?? ""`. And `s.utf16.prefix(n)` decoded back splits a surrogate pair. maintastic has none of these today
(its one cut is `TicketTranslator`'s, already reported); the rule is general coverage, not a finding there.

Acceptance: red tests for the two optional initializers and the UTF-16 cut, each with its witness line; the family's
repositories stay clean.

## Done

fcheck red `76fe318`, green `ffc462d`: `String(data:encoding: .utf8)`, `String(bytes:encoding: .utf8)` and
`String(<cut utf8 or utf16 view>)`, with a message saying the whole text is lost. maintastic and the family's
repositories: unchanged. Released in fcheck 0.4.0.
