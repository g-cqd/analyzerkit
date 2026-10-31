---
status: not-started
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
