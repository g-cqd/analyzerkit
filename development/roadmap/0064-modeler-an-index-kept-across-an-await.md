---
status: done
blocked-by: []
date: 2026-10-31
---

# 0064 — modeler: an index into a member kept across an `await`

`ChatMessageListViewModel.refreshMessage(with:)` in maintastic takes `messages.firstIndex(where:)`, awaits the server,
then calls `messages.replaceSubrange(index..<index + 1, …)`. A message that the socket inserts at 0 in the meantime moves
the replacement onto a neighbour; `refresh()` setting `messages = []` makes the range invalid, which traps. modeler 0.3.0
reports it as a `reentrancy` on `messages`, because the index came from a `guard let`, which is a check. Bound with
`let index = messages.firstIndex(…)!` it would not be reported at all.

Rule `stale-index`: a local bound from `firstIndex`, `lastIndex`, `index(of:)`, `indices`, `startIndex` or `endIndex` of a
member collection, or from arithmetic on one, used after an `await` to subscript that member or to pass to
`remove(at:)`, `insert(_:at:)`, `replaceSubrange`, `swapAt`, with no rebinding in between, on one path. Severity
error: it can crash. The message says to look the index up again by identity after the `await`.

Acceptance: red tests for the guard-let and the force-unwrap forms, a rebinding that clears it, a use of the index on
another collection that does not; maintastic reports `refreshMessage(with:)` under the new rule, and the `reentrancy`
finding on that line is not reported twice.

## Done

modeler red `3c3982b`, green `6c6f31c`. Effects `bindIndex` and `useIndex`; an error by default. On maintastic,
`ChatMessageListViewModel.refreshMessage(with:)` moves from `reentrancy` to `stale-index`, and nothing else changes; the
family's repositories are unchanged. Released in modeler 0.4.0.
