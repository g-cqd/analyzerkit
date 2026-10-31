---
status: done
blocked-by: []
date: 2026-10-31
---

# 0065 — modeler: a stored continuation overwritten before it is resumed

maintastic's `Camera.getCurrentFrameInHD()` stores its `CheckedContinuation` in `photoOutputContinuation` and returns;
the photo delegate resumes it and sets it to nil. Five callers can ask for a frame (`CallViewModel` twice, `HDFreeze`,
`LocalVideoProvider`, the workflow's photo step). When two overlap, the second assignment drops the first continuation:
the first photo resumes the second caller, the second callback finds nil, and the first caller never resumes (Swift
logs that the continuation leaked).

Rule `continuation-overwrite`: a write to a member whose type is `CheckedContinuation`, `UnsafeContinuation` or an
optional of one, of a value that is not nil, where no path from the method's entry checks that the member is nil or
resumes it first. The write is usually in the `with…Continuation` closure, which modeler leaves out of the other
rules (closure depth 1); this rule reads it there. Continuations kept in a dictionary under a fresh key, as
`JSONRPCMessageHandler` does, are not this shape.

Acceptance: red tests for the overwrite, a `guard member == nil`, a resume of the old value first, and a dictionary
keyed by request; maintastic reports `Camera.getCurrentFrameInHD()` and nothing else among its 22 continuations.

## Done

In arcleak, not modeler: a dropped continuation is a leaked caller, the lifetime arcleak's rules are about, and
maintastic's Danger already runs arcleak. modeler had it at `6c6f31c` and removed it before releasing (`5447f4a`). arcleak
keeps no false positives, so the rule is narrower than this entry's first shape: arcleak red `9e7c194`, green `cd9a131`
report only a top-level `member = continuation` in a `with…Continuation` closure called from the method's own body,
with no condition before the store in the closure or the method and no mention of the member before it, the member a
stored property. A `guard` on another member, which may be how the code keeps a second call out, stays silent; so do a
key, a collection, a branch and a computed member (ten clean fixtures). A warning: the leak needs two calls that overlap.
On maintastic: `Camera.getCurrentFrameInHD()` and nothing else among its 22 continuations; the family's 20 repositories
are unchanged apart from arcleak's own fixtures. Released in arcleak 0.15.0 (`403e421`).
