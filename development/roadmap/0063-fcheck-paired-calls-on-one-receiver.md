---
status: done
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

## Done

fcheck red `3802166`, green `c3d6b3e`. A resource's `holds` is `result` (as before), `receiver` or `firstArgument`;
the capture-session configuration, the capture-device configuration lock and the pixel-buffer base-address lock are
built in. A pair is ended only by its release. It is followed only when its opening call is a statement of its own,
since code that checks a `CVReturn` handles a failure the rule cannot tie to the release, and only when the receiver is
a simple name (`self.` dropped). Two shapes from maintastic were false positives in a first version and are tests
now: a checked `let status = CVPixelBufferLockBaseAddress(…)`, and a force-unwrapped argument (`pixelBuffer!`) that was
not matched at its unlock. On maintastic: `CaptureActor.configureSessionIfNeeded()` and nothing else new (16 such
sites); the family's repositories are unchanged. Released in fcheck 0.4.0. `lock()`/`unlock()` is not built in: a lock
taken in one method and released in another is sometimes intended; `resources` can add it.
