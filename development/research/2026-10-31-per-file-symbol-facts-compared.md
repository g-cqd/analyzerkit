# 2026-10-31 — swift-search's and deadwood's symbol extraction, compared (roadmap 0055)

swift-search's `SymbolExtractor` and deadwood's `DeclarationCollector` plus `ReferenceCollector` (through
`StaticAnalyzer.collectFacts`) share a lineage and have diverged. Both ran over the same files: deadwood's own
`Sources` at `c2b1229` (84 files) and maintastic (`parts-MAIN-24752-stock-handling`, 2,981 files). The probes are in
`probes/symbol-facts/`, copied into each tool's tests for the run and not committed there.

- **Declarations** were matched by file, line and name. Columns differ by design: swift-search places a declaration at
  its name, deadwood at its first token.
- **References** were matched by file, line, column and name.

## Declarations

| | deadwood `Sources` | maintastic |
| --- | ---: | ---: |
| swift-search | 1,831 | 43,199 |
| deadwood | 3,755 | 64,920 |
| same file, line and name | 1,800 | 39,756 |
| at the same place, of a different kind | 0 | 0 |

Only deadwood records:

- **Parameters** (1,057 and 12,679) and **function-local constants and variables** (859 and 8,846). deadwood's
  unused-parameter and unused-local rules need them; swift-search leaves locals out on purpose.
- **`topLevelCode` nodes** (125 on maintastic), one per run of file-scope code, so its reachability can root them.

Recorded by both, on different lines: a declaration with an attribute on the line before (`@MainActor`, `@inlinable`,
`@JSONCodable`). deadwood's location is the attribute's line, swift-search's the name's: 2,309 methods, 435 structs,
259 protocols, 231 classes and 128 extensions on maintastic.

Only swift-search records **macro declarations** (6 on maintastic); deadwood has no such kind.

## References

| | deadwood `Sources` | maintastic |
| --- | ---: | ---: |
| swift-search | 16,898 | 247,786 |
| deadwood | 18,397 | 291,136 |
| at the same place | 16,871 | 245,756 |

- **Roles.** swift-search's are coarse (`read`, `write`, `call`, `type`) and deadwood's finer (`memberAccessBase`,
  `memberAccessMember`, `typeAnnotation`, `attribute`, `unknown`, …). Every pair maps one way: deadwood's context
  determines swift-search's role. The exception is `unknown`, which swift-search splits into `read` (28,913) and
  `write` (3,475).
- **Only deadwood** (45,380 on maintastic): argument labels recorded as `write` (21,356), `self` and `Self` as member
  bases (5,403), a call's callee again as `call` (5,387), and type annotations inside closures and patterns (2,432).
  These are the facts its liveness rules read; the labels are the shape behind the 0058 fix.
- **Only swift-search** (2,030 on maintastic): the later components of a member type (`Outer.Inner`'s `Inner`), as
  `type`.

## Time and memory

Debug builds, one thread, parsing included, each tool's test process:

| | deadwood `Sources` | maintastic | peak |
| --- | ---: | ---: | ---: |
| swift-search | 3.23 s | 55.5 s | 212 MB |
| deadwood | 3.18 s | 54.4 s | 307 MB |

Parsing dominates both, so the time is the same. deadwood's extra facts cost about 45% more memory at peak.

## Reading

One extraction can serve both. deadwood's is a superset of swift-search's, apart from three things:

- the name's position beside the declaration's first token;
- the later components of a member type;
- macro declarations.

swift-search would project what it reads: drop parameters and locals, and map deadwood's contexts to its roles,
`unknown` decided as swift-search decides it today. Moved to analyzerkit with those three additions, deadwood's
reports stay byte-equal, since it gains facts it does not read, and swift-search's become a projection to check
byte-equal in its switching entry.
