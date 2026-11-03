# CI

Run `swift-ci validate`, `swift-ci plan`, or `swift-ci run quality` locally; CI
calls the same pinned tooling. `.ci/action.json` controls the matrix and cadence.
Linux debug/release/ASan and macOS debug run per change. The remaining sanitizer
and macOS release checks run nightly (when a commit landed) or by dispatch.

`baselines/dolly.json` accepts 150 existing clone fingerprints (48 warnings,
102 notes at adoption), not new findings and not a claim that these are false
positives. This is a recorded adoption backlog boundary, not a code fix;
reduce it as duplication is removed. No deadwood/arcleak baseline was needed.
