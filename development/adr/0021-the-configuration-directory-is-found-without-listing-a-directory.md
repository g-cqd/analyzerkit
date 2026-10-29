---
status: accepted
date: 2026-10-29
supersedes: ADR-0020
---

# 0021 — The configuration directory is found without listing a directory

## Context

ADR-0020 found the configuration directory at the project root of the analyzed paths (`ProjectLayout`) when the current
directory had no file. Adopted by the tools (roadmap 0014, diary 2026-10-29-17), it stalled deadwood's command-line
tests: `ProjectLayout` lists every ancestor directory up to the repository root, or up to `/` outside a repository, and
walks the whole project tree for manifests. Outside a repository the ancestors include the system's temporary directory,
262,000 entries on the owner's machine; each run took more than a minute before analysing anything. A configuration
lookup needs neither the listing nor the manifests: only whether two file names exist.

## Decision

ADR-0020 stands as written there, its item 1 replaced by:

1. **One configuration directory per run, found by `stat` alone.** Without `--config`, it is the current directory if it
   holds `.swift-analyzers.json` or the tool's own file; else the nearest directory holding one, from the analyzed paths'
   common directory up to and including their repository root (`.git`, a directory or a worktree file); outside a
   repository, no directory beyond the current one. Only that directory's files are read, so every `exclude` entry is
   relative to the same root. `--config <file>` replaces the lookup: a file named `.swift-analyzers.json` is read in the
   shared format, any other as the tool's own.

The others (the shared file and its sections, precedence, no silently ignored key including a key given twice,
`--verbose`, fcheck's region switch) are unchanged.

## Consequences

- The lookup costs two `stat` calls per directory between the analyzed paths and the repository root, and no listing.
- The nearest configuration wins: a nested package with its own file, analysed alone from its directory or below, reads
  that file, as `.swift-format` and `.gitignore` are found.
- Outside a repository, a configuration in a parent directory is not read; pass `--config` or run from its directory.
