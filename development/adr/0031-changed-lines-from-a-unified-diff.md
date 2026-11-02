# ADR-0031 — Changed lines from a unified diff

Status: accepted
Date: 2026-11-02

## Context

The family's pull-request mode is file-scoped: `--only` lists the changed files and `--report-new-since` promotes
findings a change created elsewhere (ADR-0019, ADR-0028). Litmus, the family's mutation tester, needs the lines: an
the reference app pull request changes a median of 4 Swift files but creates a median of 1 mutant on its changed lines, against 8
in the files (litmus docs/research/2026-11-02-pr-profile.md). Analyzers could later report only on changed lines too.

## Decision

`ProjectModel.ChangedLines` reads a unified diff (`git diff`, `diff -u`, any context size) into the new-side changed
lines per file, as sorted disjoint ranges, plus the deleted files. Renames, binaries and mode changes are changed files
without lines; a hunk that only removes lines changes no line. Paths are decoded (git's C quoting), git's `a/`/`b/`
prefixes detected or stripped as `patch -p`, and refused when absolute or leaving the root. The diff is refused whole
on a malformed or short hunk, or beyond its limits (256 MiB, 100,000 files): a diff read halfway would scope a run to
part of a change. `rebased(onto:)` views a repository diff from a package subdirectory.

## Consequences

- Litmus's `--diff`/`--diff-base` use it; analyzers can add a line scope on the same reader.
- The tool decides what a change "touches" from lines; whether a removal changes the code around it is the caller's
  policy (Litmus: no).
