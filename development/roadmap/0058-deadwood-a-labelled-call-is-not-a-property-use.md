---
status: not-started
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
