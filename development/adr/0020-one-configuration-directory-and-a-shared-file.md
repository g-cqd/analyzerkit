---
status: superseded
superseded-by: ADR-0021
date: 2026-10-29
supersedes: ADR-0007
---

# 0020 — One configuration directory, a shared file, and no silently ignored key

## Context

ADR-0007 chose `.swift-analyzers.json` with a section per tool. Probed before building it (roadmap 0014, diary
2026-10-29-17), three of its premises did not hold:

- "An unknown key fails the run as today": no tool rejects an unknown key. `{"exlude": [...]}` or `{"bogus": 1}` runs and
  exits 0 in arcleak, deadwood, dolly and fcheck; the exclusion the user meant never happens. Only unknown rule ids fail.
- Where files are found: every tool reads its own file from the current directory only. Run from `Sources/`, a broken
  `.arcleak.json` at the repository root is not read at all. ADR-0007 found the shared file by walking up to the project
  root but left the tool files where they were, so one run could read two directories, and `exclude` globs, which are
  relative to their file (ADR-0008), would have two roots.
- `indexStore` and `cache` as shared keys: no tool reads such keys yet.

The configurations in use hold only known keys (maintastic's three files: `exclude`, and dolly's `duplication`; the g-cqd
packages' `.deadwood.json`: `production`, `rules`).

## Decision

1. **One configuration directory per run.** Without `--config`, it is the current directory if it holds
   `.swift-analyzers.json` or the tool's own file, else the project root of the analyzed paths (`ProjectLayout`). Only
   that directory's files are read, so every `exclude` entry is relative to the same root. `--config <file>` replaces the
   lookup: a file named `.swift-analyzers.json` is read in the shared format, any other file as the tool's own.
2. **The shared file.** Top-level keys shared by the tools: `exclude`, `includeRegions`, `excludeRegions`, `defines`,
   `platforms`. A section per tool (`arcleak`, `deadwood`, `dolly`, `fcheck`, `modeler`) holds that tool's own keys and may
   repeat a shared one. A shared key a tool has no use for is ignored by that tool and named as such by `--verbose`. Keys
   for the index store and the cache join when a tool reads them.
3. **Precedence**, lowest to highest: built-in defaults, the shared top level, the tool's section, the tool's own file,
   command-line flags. Objects merge key by key (RFC 7396), other values replace, except `exclude`, whose lists are
   concatenated in that order.
4. **No silently ignored key.** An unknown key at the top level of the shared file, in the tool's own section, or at the
   top level of the tool's own file fails the run with 78, naming the file and the key. Another tool's section is not
   checked by this tool, so tools of different versions can share one file. A shared key of the wrong type is 78 too.
5. `--verbose` prints the files read and, for each key more than one source set, which one won.
6. fcheck reads `includeRegions`/`excludeRegions` through its test-and-generated switch: code is included when the regions
   included (and not excluded) contain `test` or `generated`, as `--include-tests` means both (ADR-0019).

## Consequences

- A per-tool file keeps working unchanged when it is in the current directory, and is now also found at the project root
  when the tool runs from a subdirectory.
- A configuration with a misspelt or stale key, accepted silently until now, fails with 78 and says which key: a
  release-notes item for the four tools. None of the configurations in use is affected.
- modeler has no configuration today; it reads its section with its migration (roadmap 0022).
