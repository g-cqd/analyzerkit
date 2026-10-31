---
status: not-started
blocked-by: []
date: 2026-10-31
---

# 0061 — swift-search on `SymbolFacts` (P1)

ADR-0027, after roadmap 0055. swift-search's `SymbolExtractor` gives way to `SymbolFacts`, with its output
byte-equal. The research's three differences are in `SymbolFacts` now. Reading swift-search's output field by field,
against deadwood's on the fixture of 0055, finds eleven more. Each is either a `SymbolFacts` addition or a
projection in swift-search:

1. Tuple-pattern bindings (`let (a, b) = …`): deadwood skips a binding that is not an `IdentifierPattern`.
2. Whether a declaration in an accessor body is local: there is no accessor scope. Range containment gives it.
3. The text of a member access's base: not recorded.
4. The write role of an `inout` argument and of a compound assignment: deadwood records `unknown`.
5. Range ends: `SymbolFacts` includes trailing trivia. swift-search ends at `endPositionBeforeTrailingTrivia`.
6. A memberwise initializer's label, recorded as a write at the argument: deadwood has it and swift-search does not,
   and the two cannot be told apart from the facts.
7. A type annotation's text: `trimmedDescription` against `description.trimmedHorizontalWhitespace`.
8. Signatures: the variadic `...` suffix, and whether `throws` and `rethrows` are told apart.
9. `self`, `Self`, `super` and `Any`: swift-search leaves them out.
10. An extension's name: its path split into components, against the type's text.
11. `arguments`: `[]` against nil when there are none.

Red: for each, a test on the fixture with the value swift-search answers today. Then swift-search's search and
symbol commands report byte-equal on a pinned g-cqd package and on maintastic, and its extraction time stays within 5%.
