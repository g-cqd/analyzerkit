---
status: done
blocked-by: []
date: 2026-10-30
---

# 0058 — deadwood: a call with argument labels is not a use of a property

0057, defect 4. Without an index store, deadwood resolves references by name. The call `Converter().location(for: n)`
counts as a use of every declaration named `location`, so an unread property `Position.location` is never reported.
swift-search had the same shape (its diary 2026-10-29-01, probe 6). Its fix: a reference spelled as a call with
arguments, or with argument labels, cannot name a property whose type is not a function type.

Red: the probe's fixture (an internal `Position.location`, a called `Converter.location(for:)`) reports the property by
name, as it already does with the index. A property of function type called with arguments (`handler(x)`) stays used. A
property read without a call (`p.location`) stays used.

Acceptance: deadwood's goldens updated only where a finding appears, each one checked by hand; maintastic's report before
and after in deadwood's diary (new findings listed, none disappearing).

## Done

deadwood red `d361bd0`, green `b7fc0ab`. A reference that is the callee of a call with arguments records their labels
(`Reference.callLabels`, `_` for an unlabeled one). Labels are cached under `"a"`, and the cache header moved to
`facts 3`. When the corpus has a function whose parameters fit those labels (in order, defaulted or variadic ones
optional), the by-name match drops variables and constants with a written non-function type. When no function fits,
every match stays, because the call may be `callAsFunction` on the property's type. A property of function type, or with
no written type, is always kept. 5 tests; deadwood's 393 pass with its goldens unchanged.

maintastic (`parts-MAIN-24752-stock-handling`, its `.deadwood.json`, debug builds of `fcbb3f7` and `b7fc0ab`): 57 findings
before, 58 after, none gone. The new one, `TicketOverviewViewModel.ticketTypeDescription`, was checked by hand. It is
never read; the name's only other uses are labelled calls to two private functions `ticketTypeDescription(ticketType:)`
and `ticketTypeDescription(for:)`. The analyzed count moved from 2,977 to 2,981 between the runs: the working tree changed
under them (it is someone's live checkout).
