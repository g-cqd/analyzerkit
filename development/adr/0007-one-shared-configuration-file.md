---
status: accepted
date: 2026-10-29
---

# 0007 — `.swift-analyzers.json`: one shared configuration, a section per tool

## Context

maintastic keeps `.arcleak.json`, `.deadwood.json` and `.dolly.json` with nearly the same `exclude` list, which also repeats
what discovery already skips (`.build/`, `DerivedData/`, `.swiftpm/`). The keys that mean the same thing (`exclude`,
`includeRegions`, `excludeRegions`, platforms, defines) are parsed by five copies of the same code. The owner left the name
to this decision.

## Decision

1. The shared file is `.swift-analyzers.json` at the project root (`ProjectLayout`), found by walking up from the analyzed
   paths to the repository root. The name says what reads it and for what language, and does not name a library the user
   never installs.
2. Its top level holds the shared keys: `exclude`, `includeRegions`, `excludeRegions`, `defines`, `platforms`,
   `indexStore` (`path`, `build`), `cache` (`path`, `maximumBytes`).
3. Each tool has a section named after it (`"arcleak": { … }`, `"deadwood": { … }`, …) holding its own keys, and may
   repeat a shared key to override it.
4. Precedence, lowest to highest: built-in defaults, the shared top level, the tool's section, the tool's own file
   (`.arcleak.json`, …, still read, unchanged), command-line flags. `exclude` lists are concatenated, other keys replace.
5. An unknown key, at the top level or in a section, fails the run as today (exit 78), naming the file and the key.

## Consequences

- Existing per-tool files keep working with no change; a consumer migrates by moving keys, when it wants.
- `--verbose` prints which files were read and which value won for each key that more than one source set.
