---
status: not-started
blocked-by: []
date: 2026-10-31
---

# 0063 — fcheck: calls paired on one receiver, closed on every path

`leak-on-exit` follows a handle that an acquiring call returns. Frameworks also pair two calls on one receiver, and
the second is owed on every path out, including the one a `try` takes. maintastic (develop, 2026-10-31) has
`beginConfiguration`/`commitConfiguration` 10 times, `lockForConfiguration`/`unlockForConfiguration` 6,
`CVPixelBufferLockBaseAddress`/`Unlock` 6, `lock()`/`unlock()` 6 and `startAccessingSecurityScopedResource` 12. One
use is wrong: `CaptureActor.configureSessionIfNeeded()` (QR scanner) calls `session.beginConfiguration()`, then three
`try` calls, and only then `commitConfiguration()`, outside a `defer`. A throw leaves the session in configuration, and
the retry opens another, nested `beginConfiguration()`. The other four capture-session sites use `defer`.

Shape: a resource whose handle is the receiver (`x.begin()` … `x.end()`), or the first argument
(`CVPixelBufferLockBaseAddress(b, …)` … `CVPixelBufferUnlockBaseAddress(b, …)`). Passing the receiver to a call does
not hand it on, which is what hides the case above if the current rule's hand-on is reused: `addVideoInput(session:
session, …)`. A `try` on the opening call that throws holds nothing. Built in: the capture-session and capture-device
pairs, pixel-buffer locks, `NSLock`-style `lock()`/`unlock()`; configurable as `resources` with `"holds": "receiver"`
or `"firstArgument"`.

Out of scope at first: `startAccessingSecurityScopedResource()`, whose `Bool` decides whether a release is owed (the
correlation needs a path-sensitive pairing with the `if`), and `DispatchGroup.enter`/`leave`, whose `leave` is usually
in a callback.

Acceptance: a red test per shape and for the hand-on above; maintastic reports `CaptureActor` and nothing for the sites
that use `defer`; fcheck stays clean on the family's repositories.
