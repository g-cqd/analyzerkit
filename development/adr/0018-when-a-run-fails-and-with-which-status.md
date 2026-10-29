---
status: accepted
date: 2026-10-29
---

# 0018 — When a run fails, and with which status

## Context

ADR-0006 lists the exit codes but not which findings fail a run, nor where "no input" ends and "nothing analyzed" begins.
Probed with the same scenarios on all five tools (`research/probes/exit-codes.py`, diary 2026-10-29-16):

| Scenario | arcleak | deadwood | dolly | fcheck | modeler |
| --- | --- | --- | --- | --- | --- |
| an error finding, no `--strict` | 1 | 1 | 1 | **0** | (no errors) |
| a warning finding, `--strict` / without | 1 / 0 | 1 / 0 | 1 / 0 | 1 / 0 | 1 / 0 |
| a note finding, `--strict` | 0 | 0 | 0 | 0 | — |
| configuration or baseline unreadable or invalid | 78 | 78 | 78 | **64** | (none) |
| `--write-baseline` cannot be written | **78** | **78** | **78** | **1** | (none) |
| unknown flag | 64 | 64 | 64 | 64 | 64 |
| a path that does not exist, or no Swift file under it | 64 | 64 | 64 | 64 | **0** |
| every file unreadable | 70 | 70 | 70 | **0** | **0** |

Three tools agree on the severity rule; fcheck passes a run with error findings. fcheck and modeler exit 0 when they read no
file at all, which a CI gate takes for a clean result.

## Decision

Every analysing command, every tool (`AnalyzerCLI.ExitStatus` and `RunOutcome`):

| Status | When |
| --- | --- |
| 0 | the run finished and nothing failed it |
| 1 | a finding of severity `error`; with `--strict`, also `warning`. A `note` never fails a run |
| 64 | usage: an unknown option, a path that does not exist, no Swift file under the paths given |
| 70 | internal failure: the run was cancelled, or every file found was skipped (unreadable, invalid, over the cap) |
| 74 | an output the run was asked to write could not be written: `--write-baseline`, `--stamp`, `--fix` |
| 78 | a configuration or baseline file that cannot be read or is invalid |

The report is printed for 1 and for 70 when every file was skipped (so the skipped files are visible), never for a
cancelled run.

## Consequences

- fcheck: error findings fail without `--strict`; 78 for configuration and baseline; 74 for `--write-baseline`; 70 when it
  read nothing. modeler: 64 for a missing path or no Swift file, 70 when it read nothing. arcleak, deadwood, dolly: 74
  instead of 78 when `--write-baseline` cannot be written. Each is a release-notes item.
- maintastic treats 64, 70, 74 and 78 alike as "did not run", so none of the changes moves its gate except the two that
  were bugs: fcheck and modeler no longer pass on nothing read, and fcheck no longer passes on error findings.
- Whether fcheck and modeler should, like the others, skip a file that is not valid UTF-8 rather than decode it lossily
  is a separate question (roadmap 0045).
