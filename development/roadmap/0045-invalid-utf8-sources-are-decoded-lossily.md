---
status: not-started
blocked-by: []
date: 2026-10-29
---

# 0045 — fcheck and modeler decode a file that is not UTF-8

Found by the exit-code probe of 0013 (diary 2026-10-29-16): given only a file that is not valid UTF-8, arcleak, deadwood
and dolly skip it as degraded and exit 70; fcheck and modeler decode it with replacement characters and analyse that.
Analysing text that is not the file can report a position that is not where the bytes are, and can hide that the input was
damaged.

Scope: fcheck and modeler read sources through the same validated decode as the others (a degraded file, reason
"not valid UTF-8"), or the family decides otherwise in an ADR; either way, one behaviour.

Red: a corpus of one invalid file and one valid one; each tool lists the invalid one as degraded and analyses the other.

Acceptance: the five tools agree on that corpus.
