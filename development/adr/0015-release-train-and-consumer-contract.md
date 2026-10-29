---
status: accepted
date: 2026-10-29
---

# 0015 — Releases ship in three waves, against a written consumer contract

## Context

The tools are pinned in many places (research `2026-10-29-consumers-and-ci-contract.md`): maintastic's
`ShareXcodePlugins/Package.swift` (artifact bundles by URL and checksum), its DangerPlugins (flags, exit codes, report
keys), aemi's reusable `swift-quality.yml`, four copies of `Scripts/analyzers.sh` (AemiJSON, AemiMarkdown, AemiRegex, ask)
at three different version sets, AemiProtobuf's `tools.lock`, Atelier's `helpers.lock`, and committed
`.dolly-baseline.json` files. A release that changes the surface, the findings and the cache at once cannot be adopted
cleanly by any of them.

## Decision

1. **The contract** — what a consumer may depend on, changed only as below: release archive names
   (`<tool>-<version>-macos-arm64.tar.gz`, `…-linux-x86_64.tar.gz`, `<tool>-<version>.artifactbundle.zip`, each with a
   `.sha256`), the executable's name and path in the bundle, subcommands and flags, exit codes (ADR-0006), report keys
   (ADR-0017), SARIF shape, baseline format and fingerprints, suppression syntax (`@al:`/`@arcleak:`, `@dw:`/`@deadwood:`,
   `@dl:`/`@dolly:`, `@fc:`/`@fcheck:`), configuration files and keys.
2. **Three waves**, each a minor release of every tool, in the order arcleak, deadwood, dolly, fcheck, modeler, after an
   analyzerkit revision is pinned:
   - **Wave 1, same findings.** Shared foundations, new surface with aliases, cache v2, speed. Reports equal to the
     previous release on every golden corpus apart from added keys. A consumer bumps pins and checksums and changes
     nothing else.
   - **Wave 2, better findings.** Correctness fixes (index per definition, fcheck and modeler rules, CFG). Findings
     appear and disappear; the release notes list each change by rule with its probe. A consumer re-runs and re-baselines.
   - **Wave 3, cleanup.** Aliases and the old note keys removed, announced in waves 1 and 2.
3. **Every release note has the same sections**, filled or marked "none": archives and checksums; flags added, renamed,
   removed; exit codes; report keys; configuration; cache (location, format, what to delete); findings that may appear;
   findings that may disappear; consumer steps for maintastic and for the g-cqd scripts and workflows.
4. **Patch releases** (wave 0, and between waves) are allowed only for a defect that makes a gate wrong (a false error or
   warning in a gating tool, a refused toolchain, a write outside the cache): smallest fix, red test first, same note
   sections, no surface change.
5. A release is not tagged until its notes' consumer steps were run on a branch of maintastic and of one g-cqd package
   and both were green.

## Consequences

- Version numbers per wave: arcleak 0.13 / 0.14 / 0.15, deadwood 0.12 / 0.13 / 0.14, dolly 0.12 / 0.13 / 0.14, fcheck
  0.2 / 0.3 / 0.4, modeler 0.2 / 0.3 / 0.4.
- The four copies of `analyzers.sh` become one script published by aemi (roadmap 0031), so a wave changes one pin set.
