---
status: done
blocked-by: []
date: 2026-10-31
---

# 0062 — modeler and fcheck on maintastic: four re-checks modeler did not see, a local lock, a README example fcheck rejected

First runs of fcheck 0.3.0 and modeler 0.3.0 on maintastic (app-ios at develop, the excludes of its `.deadwood.json`,
2,530 files, about a second each). fcheck reported 1 finding, which is a real bug (`TicketTranslator` cuts a translated
name at 100 UTF-8 bytes). modeler reported 29; each one was read in the code. Five were already handled there:

- `CreateTicketDialogModel.clearTicketTypeIfNotCompatibleWith(asset:)`: after the `await`, `guard isStillCurrent(for:)`
  re-checks `ticketData` through a method of the type. modeler saw only direct reads.
- `PreviewableImageProvider.loadThumbnail()` (2 findings): a generation token. The method bumps `loadSequence` before the
  `await` and compares it after; the only other writer of `loadingState`, `refreshThumbnail(using:)`, bumps it too.
- `AppCommunication.performStartUserSession()`: `try Task.checkCancellation()` after the `await`; the only other writer
  of `currentState`, `logoutUser()`, cancels the session task. `cancel()` was not even an effect.
- `AudioFormatConverter.retrieveConverter(for:to:)` (`lock-gap`): the class's only `withLock` is on a local, the
  converter callback's state, so no member is shared. The class is not `Sendable` either.

While trying a resource in fcheck's configuration, the README's own `.fcheck.json` example exited 78: a resource without
`negativeIsInvalid` did not decode, although the initializer defaults it to false.

## Done

- modeler red `9ec2d10`, green `1d0e26f`. After the `await`, a member is checked again by a condition that calls a
  method of the type that reads it, provided the call is not itself awaited. It is also checked again by a check of a token
  this method wrote before, when every other writer of the member writes the token, and by `Task.isCancelled` or
  `try Task.checkCancellation()`, when another method writes the member and each one cancels a task a member holds.
  `cancel()` on a member is a new effect kind. A `withLock` on a local or a parameter no longer makes the type one
  that takes locks. 11 tests; the 99 pass with TLC, and the goldens are unchanged. On maintastic, 29 findings went to 24:
  the five above, and nothing new. A first version counted an awaited call in a condition as a check
  (`if let url = try await downloadFile(url:)`), which made one new finding in `DownloadingFilePreviewViewModel`; that case
  has its own test. AemiProtobuf, ask, analyzerkit, modeler, fcheck, AemiJSON and TerminalKit: unchanged (no findings).
- fcheck red `82edd97`, green `45c95e3`. The test reads the README's example itself. 119 tests pass.

Neither is released. Still reported on purpose: `TicketTaskTimeTrackingSessionListViewModel.editSession(_:)`, where the
`isEditing` claim blocks a second `editSession` but not `deleteCurrentSession()`, which writes `editableSession` too.

Not addressed: modeler's TLA+ model has no precondition for a guard on a computed property (`state.isRecording ||
state.isPaused`), so TLC's first trace on `RecordingCoordinator` started `finalize()` from `.idle`, which the code
refuses. Resolving an enum's Boolean computed properties to their cases would remove that.
