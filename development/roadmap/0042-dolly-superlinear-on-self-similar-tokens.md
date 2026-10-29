---
status: not-started
blocked-by: []
date: 2026-10-29
---

# 0042 — dolly: superlinear time on self-similar token runs

Found by 0041's red test (diary 2026-10-29-09). Two files, each one chain of identical calls (`view.m(1).m(1)…`), take
0.14 s at 1,000 links, 0.63 s at 2,000 and 1.62 s at 3,000 in release (one finding, the right one); 137 s at 3,000 in
a debug test. A file that repeats one short token pattern, generated code most of all, makes the clone engine grow
faster than its length: every window matches every other.

Scope: find which stage grows (prefix index, candidate pairs, verification) with a profile at two sizes, then bound it
for repeated windows without changing a finding. Related: 0027 (dolly's tokens).

Red: a scaling test, the 4,000-link pair against the 1,000-link pair, within a factor the profile justifies (linear
or near it), plus the findings of the corpora in research `2026-10-29-performance-on-maintastic.md` unchanged.

Acceptance: the red test green; release timings before and after recorded; findings identical on maintastic, ask and
the tools themselves.
