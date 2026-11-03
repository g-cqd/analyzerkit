---
status: done
blocked-by: []
date: 2026-10-31
---

# 0062 — modeler and fcheck on the reference app: four re-checks modeler did not see, a local lock, a README example fcheck rejected

First runs of fcheck 0.3.0 and modeler 0.3.0 on the reference app (its development branch, the excludes of its `.deadwood.json`,
2,530 files, about a second each). fcheck reported 1 finding, which is a real bug (a translator cuts a translated
name at 100 UTF-8 bytes). modeler reported 29; each one was read in the code. Five were already handled there:

- a dialog model's compatibility check: after the `await`, `guard isStillCurrent(for:)`
  re-checks `ticketData` through a method of the type. modeler saw only direct reads.
- `ImageLoader.loadThumbnail()` (2 findings): a generation token. The method bumps `loadSequence` before the
  `await` and compares it after; the only other writer of `loadingState`, `refreshThumbnail(using:)`, bumps it too.
- `ConnectionManager.performStartUserSession()`: `try Task.checkCancellation()` after the `await`; the only other writer
  of `currentState`, `logoutUser()`, cancels the session task. `cancel()` was not even an effect.
- `FormatConverter.retrieveConverter(for:to:)` (`lock-gap`): the class's only `withLock` is on a local, the
  converter callback's state, so no member is shared. The class is not `Sendable` either.

While trying a resource in fcheck's configuration, the README's own `.fcheck.json` example exited 78: a resource without
`negativeIsInvalid` did not decode, although the initializer defaults it to false.

## Done

- modeler red `fb803a7`, green `f6a0c73`. After the `await`, a member is checked again by a condition that calls a
  method of the type that reads it, provided the call is not itself awaited. It is also checked again by a check of a token
  this method wrote before, when every other writer of the member writes the token, and by `Task.isCancelled` or
  `try Task.checkCancellation()`, when another method writes the member and each one cancels a task a member holds.
  `cancel()` on a member is a new effect kind. A `withLock` on a local or a parameter no longer makes the type one
  that takes locks. 11 tests; the 99 pass with TLC, and the goldens are unchanged. On the reference app, 29 findings went to 24:
  the five above, and nothing new. A first version counted an awaited call in a condition as a check
  (`if let url = try await downloadFile(url:)`), which made one new finding in `DownloadingFilePreviewViewModel`; that case
  has its own test. AemiProtobuf, ask, analyzerkit, modeler, fcheck, AemiJSON and TerminalKit: unchanged (no findings).
- fcheck red `749ba78`, green `a1b2f2d`. The test reads the README's example itself. 119 tests pass.

Neither is released. Still reported on purpose: a session list view model's `editSession(_:)`, where the
`isEditing` claim blocks a second `editSession` but not `deleteCurrentSession()`, which writes `editableSession` too.

The TLA+ gap, done after: modeler red `9600160`, green `0618f01` (an enum records its Boolean computed properties
over its cases; a guard on `member.isX` resolves to those cases once every file is read, and narrows nothing when it
does not resolve); red `6df1ad8`, green `baf507d` (a `switch` whose other cases leave narrows the member after it; a
`break` leaves only the switch); red `9628746`, green `05eae7c` (a claimed finding's monitor starts from the value the
claim wrote). TLC on `SessionCoordinator` went from traces that start where the code refuses to a real one:
`start()` claims `.preparing`, `handleMediaServicesReset()` sets `.idle`, `start()` overwrites it.

Released in modeler 0.4.0 (`f5b44d4`) and fcheck 0.4.0 (`49bb882`).
