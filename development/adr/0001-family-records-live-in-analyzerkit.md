---
status: accepted
date: 2026-10-29
---

# 0001 — The family's records live in analyzerkit, under `development/`

## Context

The review of 2026-10-29 (research `2026-10-29-index-store-reports-reviewed.md`) found the same defects in several tools at
once, and the fixes share components. A plan that spans six repositories needs one place for its decisions, its roadmap and
its probe history. ask, TerminalKit and AemiProtobuf keep ADRs, a roadmap, a diary and research notes; ask moved them out of
`docs/` into `development/` so that user documentation and development records cannot be confused (ask's `development/adr/0128-user-documentation-in-docs-development-records-in-development.md`).

## Decision

1. Records for work that spans the family live in analyzerkit: `development/adr`, `development/roadmap`,
   `development/diary`, `development/research` and `development/WHITE-PAPER.md`.
2. The layout is ask's (the same ask record): `development/` for records, `README.md` and `docs/` for users. The analyzers are tools
   with users, so the split applies to them more than to a library.
3. A decision about one tool alone lives in that tool's repository, in the same layout (roadmap 0001 adds it to each tool).

## Consequences

- TerminalKit and AemiProtobuf keep `docs/` for records; the difference is the root folder only, and the file format is
  the same. Converging them is their owners' call.
- Roadmap entries here may name work in other repositories; such an entry says which repository and is closed by a link.
