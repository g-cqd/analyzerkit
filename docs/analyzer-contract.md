# How the analyzers behave

arcleak, deadwood, dolly, fcheck and modeler share one command-line surface, one configuration file, one report format and one
set of exit codes. This page describes what they have in common, so each tool's own guide can stick to its rules. Everything here
is implemented by analyzerkit.

- [Configuration](#configuration)
- [Scoping a report to some files](#scoping-a-report-to-some-files)
- [Baselines and fingerprints](#baselines-and-fingerprints)
- [Exit codes](#exit-codes)
- [The JSON report](#the-json-report)
- [SARIF](#sarif)
- [The facts cache](#the-facts-cache)
- [Using an analyzer as a pull-request gate](#using-an-analyzer-as-a-pull-request-gate)

## Configuration

A run reads configuration from one directory: the current one if it holds `.swift-analyzers.json` or the tool's own file
(`.arcleak.json`, `.deadwood.json`, `.dolly.json`, `.fcheck.json`, `.modeler.json`), otherwise the nearest directory above it that
does, up to the repository root. `--config FILE` reads that one file instead (in the shared format when it is named
`.swift-analyzers.json`).

`.swift-analyzers.json` is shared by all the tools. Its top level holds the settings every tool understands: `exclude`,
`includeRegions`, `excludeRegions`, `defines` and `platforms`. A section named after a tool (`"arcleak"`, `"dolly"`, …) holds
that tool's own keys. The top level, the section and the tool's own file apply in that order: `exclude` lists add up, objects merge
key by key, other values replace. An unknown key, or a key given twice, is an error (exit `78`) that names the file and the key.
`--verbose` prints which files were read and which one set each value.

A sample file is [`.swift-analyzers.json`](.swift-analyzers.json).

### Regions

A file's region says what kind of code it is: production, test, preview, debug-only, mock, generated or script. It comes from the
package or Xcode project first (a test target is test code wherever it lives), then from the file's content (a test-framework
import, a generator's header), then from path conventions. A file inside a project that no target compiles is named in a note.
`--include-regions` and `--exclude-regions` (or the configuration keys) take `preview`, `debug`, `test`, `mock`, `generated`,
`script` or `all`: included regions are analyzed as ordinary code, excluded ones are left out of the report.

## Scoping a report to some files

`--only PATH` (repeatable) and `--only-from FILE` (one path per line, `-` for standard input) narrow the **report**, not the
analysis. These analyses look at the whole program: a declaration is unused because nothing else in the corpus uses it, a
clone is a clone because a match exists elsewhere, and a cycle can cross files. Handing an analyzer only the changed files
therefore gives a different and wrong answer.

- A finding is kept when any of its locations is in scope. Only kept findings decide the exit code.
- Findings outside the scope are not printed. The JSON report lists them under `outOfScope`, and the summary counts them, so a
  scoped run cannot be mistaken for a clean one.
- An empty scope keeps nothing: an empty report and exit `0`. A scope that matches no analyzed file prints a warning on stderr.
- `--relative-to` changes how paths print, never which findings are kept.
- `--report-new-since BASELINE` adds the findings outside the scope that the base branch's baseline does not hold, which is how a
  change that leaves code dead in an untouched file is found.

`git diff --name-only` prints paths relative to the repository root, so run from there (or use `git diff --relative`). Non-ASCII
names come out octal-escaped unless `git config core.quotepath false` is set in the CI checkout. Lines tolerate CRLF endings.

## Baselines and fingerprints

A baseline lets a team adopt a rule on code that already breaks it: `--write-baseline FILE` records the current findings and
exits `0`, and `--baseline FILE` then drops what the file holds, so only new findings fail the gate.

- A finding's `fingerprint` hashes its rule, path, line, column and message. The path is relative to the repository root (found by
  walking up to `.git`), so a committed baseline matches on any machine and wherever the checkout lives. Outside a repository the
  absolute path is hashed.
- Line and column are hashed, so an edit above a baselined finding brings it back. Regenerate the baseline after large moves
  rather than loosen the match.
- `--relative-to DIR` changes the paths that print. At the repository root it changes nothing else. For any other directory, the
  printed `fingerprint` and `fingerprintPath` (and SARIF's `partialFingerprints`) are anchored there, so give the same value to the
  run that writes a baseline and to every run that reads it.
- A baseline is JSON with sorted `fingerprints`, the `tool` and a `version` (`1`). A baseline of another `version`, or one over
  1 MiB, is refused with exit `78`. `--write-baseline` needs an unscoped run (exit `64` with `--only`).

To report only the findings a change introduces, write a baseline from the base branch and read it on the pull request:

```sh
# on the base branch
TOOL analyze . --write-baseline base.json
# on the pull request
git diff --name-only origin/main... -- '*.swift' > changed.txt
TOOL analyze . --baseline base.json --only-from changed.txt --strict
```

## Exit codes

| Code | Meaning |
| --- | --- |
| `0` | The gate passed: no error-severity finding (or, with `--strict`, no warning or error). Notes never fail a run. Also after `--write-baseline`. |
| `1` | The gate failed on findings, and nothing else. A step that reacts to `1` is not triggered by a typo in the configuration. |
| `64` | Usage error: a bad argument, a path that does not exist, no Swift file under the paths, an unreadable `--only-from` file. |
| `70` | Nothing was analyzed. If every file was skipped (unreadable, not UTF-8, over 10 MiB), the report is still printed, with a note per file, and standard output is not empty. If the run itself failed or was cancelled, standard output is empty. |
| `74` | An output file could not be written (a baseline, or a `--fix` result). |
| `78` | Invalid configuration (including an unknown or repeated key), or a missing or malformed baseline. |

A cancelled run reports no findings and exits `70` rather than looking clean: an analysis of a partial corpus does not report
less, it reports wrongly. Severities are `error`, `warning` and `note`; each tool says which rules default to which.

## The JSON report

`--format json` prints one object on standard output; standard error is free text, so do not merge the two. Optional keys are left
out when they have no value, never written as `null`. Every analyzer's report carries these keys, besides its own:

| Key | Meaning |
| --- | --- |
| `schemaVersion` | The version of the report contract, `1`. |
| `tool`, `version` | Which analyzer wrote it, and its version. |
| `findings` | What to act on: in scope, not suppressed, not in the baseline. |
| `outOfScope` | Findings outside `--only`. |
| `suppressed` | Findings silenced by a comment directive, each with its `reason` when the author gave one. |
| `degradedFiles` | Files skipped or only partly analyzed, with the reason. |
| `runNotes` | Notes about the run (what was left out, why a cache was not used), each with a code, a severity and the paths it concerns. |
| `skippedFiles` | Files the run did not check, with the reason. |
| `timings` | Seconds per phase, with `--timings`. |

A finding has `rule`, `severity`, `path`, `line`, `column` (1-based, in UTF-8 bytes, as compilers print), `message`, an optional
`note`, and the `fingerprint`.

`schemaVersion` changes only when a field is removed, renamed, retyped, made required or optional, or changes meaning, or the
closed set of severities changes. Adding a field does not change it, and rule ids are an open set. A consumer should ignore
fields it does not know, handle rule ids it does not know, and reject a higher `schemaVersion` than it was written for.

## SARIF

`--format sarif` prints SARIF 2.1.0, for GitHub code scanning and other consumers. Every location is an RFC 3986 URI reference:

- **Relative**, when `--relative-to DIR` is given and the file lies inside `DIR`, and its path is made only of unreserved
  characters: the URI is the path (`Sources/App/Box.swift`) with `"uriBaseId": "SRCROOT"`, and the run's
  `originalUriBaseIds.SRCROOT.uri` is `DIR` as a `file://` URI.
- **Absolute** otherwise: `file://` and the path, with every other byte percent-encoded. A path with a space, a `#` or a
  non-ASCII letter is always written this way, because a relative URI is never percent-encoded.

Pass `--relative-to` at the repository root when uploading to code scanning so the results link to files. Paths are canonical
(absolute, symlinks resolved, no `/private` prefix on macOS) whichever spelling the command line used.

SARIF columns count UTF-16 code units, and the run says so (`"columnKind": "utf16CodeUnits"`); a byte-order mark does not count.
The `xcode` and `json` formats keep the UTF-8 byte columns that compilers print and fingerprints hash.

A file that could not be read appears as a note-level result named `<tool>/degraded-file`. A run that analyzed nothing, or was
cancelled, records `"executionSuccessful": false` on its invocation. Warnings about a feature that was asked for and did not run
are `warning` notifications and never fail the run.

## The facts cache

Parsing is the expensive part of a run, so each analyzer caches what it extracted from every file. The cache is on by default
and lives in the user cache directory (`~/Library/Caches/<tool>` on macOS, `$XDG_CACHE_HOME/<tool>` or `~/.cache/<tool>`
elsewhere), one directory per workspace. `--cache-path DIR` moves the root and `--no-cache` turns it off.

- An entry is keyed by the file's content (and by the configuration, where the facts depend on it) and is only read by the build
  of the tool that wrote it, so a rebuilt or updated tool starts cold instead of trusting another build's facts.
- Rules always run again, so findings never go stale against the rules or the configuration.
- The cache fails open: an entry that cannot be read or decoded counts as a miss, is reported once on standard error, and is
  rebuilt. Writes are atomic, and entries of deleted files are pruned within a size budget.
- Parallel jobs can share the default root; concurrent runs over the same files never serve wrong facts. Give a CI job its own
  `--cache-path` outside the repository, so the cache does not show up in `git status`.

## Using an analyzer as a pull-request gate

1. Run from the repository root, over the whole corpus (`TOOL analyze .`), not over the changed files.
2. Scope the report with `--only-from changed.txt`, and filter accepted debt with `--baseline`.
3. Add `--strict` if warnings should fail the gate, and `--format sarif --relative-to .` to upload results to code scanning.
4. Treat exit `1` as "findings"; the other non-zero codes mean the gate itself broke.
