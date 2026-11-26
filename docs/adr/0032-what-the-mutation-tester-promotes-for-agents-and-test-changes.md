---
status: accepted
date: 2026-11-27
---

# 0032 — Acceptances, excerpts, agent guides, test declarations and scheme synthesis live in analyzerkit

## Context

Litmus 0.5 adds an inner loop for coding agents and developers (out-of-source acceptance of equivalent mutants, an
agent-readable report, an installable agent guide), mutation of the code a test edit affects, and a scheme that tests
every unit-test target of an Xcode workspace. Each needs a component that is not about mutation:

| Need | What it is | Who else needs it |
| --- | --- | --- |
| A reviewed list of findings not to act on, each with its reason, kept out of the source | a sibling of the baseline: one decision per entry, matched by stable id, then by an anchor that survives edits | every analyzer's false positives (deadwood's dynamic uses, dolly's intended clones, arcleak's reviewed cycles) |
| The numbered lines around a finding | an excerpt over `LineIndex` | every report a coding agent reads |
| Install a tool's guide for coding agents | a skill file per harness and a marked `AGENTS.md` section, idempotent, link-refusing | every tool with a workflow an agent follows |
| Which tests a file declares, and where | `@Test` functions and `XCTestCase` methods with suite, signature and lines | deadwood (test entry points are roots), swift-search (find tests), litmus (lines → tests) |
| Which targets a project has, and a scheme that tests them | pbxproj target ids and product types; scheme XML | any tool that builds an index store or runs tests of a workspace whose schemes are incomplete |

Litmus also kept a copy of `Fingerprint.normalized`, the whitespace collapsing of the anchored identity, because it
was internal.

## Decision

1. `ReportSupport.AcceptanceFile`: `schemaVersion` 1, the tool, sorted entries (`id`, `path`, `declaration`, `rule`,
   `text`, `replacement`, `reason`, `addedAt`). A reason needs 10 non-space characters; a file of another version or
   tool, or with a repeated id, is refused whole. `match` accepts a finding by id, then by an anchor matching exactly
   one finding (ids first, so an anchor never takes a finding an id names), and returns the stale entries.
2. `Fingerprint.normalized` is public.
3. `SourceCorpus.LineIndex.excerpt(lines:radius:maxLineBytes:)` and `content(ofLine:)`.
4. `AnalyzerCLI.AgentGuide`: `.agents/skills/<tool>/SKILL.md`, `.claude/skills/<tool>/SKILL.md`, and a section
   between `<!-- <tool>:agent-guide -->` markers in `AGENTS.md`; nothing is written through a symbolic link.
5. `ProjectModel.TestDeclarationScanner` (syntactic, as `TestConventions`); `XcodeNativeTargets` and
   `XcodeSchemeWriter`.

Litmus keeps what is about mutation: the selector of `--only-id`, which mutants a test change reaches, the quarantine
of failing test targets, the agent report's fields.

## Alternatives considered

- **Reasons in the baseline file.** A baseline is written wholesale by `--write-baseline` and keyed by a fingerprint
  that moves with the line; mixing reviewed decisions into it would let a regenerated baseline drop them silently.
- **An `agent` case of `ReportOutputFormat`.** Adding a case to the shared enum breaks every tool's exhaustive
  `switch` at once, and each tool's agent record differs (a mutant has a replacement and reaching tests, a dead
  declaration has neither). The shared parts (excerpt, guide installation) are promoted; the format stays per tool
  until a second tool ships one.
- **Narrowing test-change scopes by the symbols a test references (`SymbolFacts`).** A weakened assertion changes the
  verdict of code the test reaches through helpers it does not name; narrowing by names would plan too little.
  Litmus narrows by per-test reach when it has it, by covering targets otherwise.

## Consequences

- Additive: no existing API changes behaviour; the analyzers build unchanged. Linux builds and tests pass
  (FoundationEssentials has neither `replacingOccurrences` nor `range(of:)`, so the new code uses the standard
  library's string search).
- Follow-ups for the siblings, each its own change in its repository: an `accept` command and acceptance file in
  deadwood, dolly and arcleak; an `agent-guide` command in each tool; deadwood's test-entry detection on
  `TestDeclarationScanner`.
