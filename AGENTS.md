# Working in `analyzerkit`

Shared project model, corpus scanner, caching, reporting, and toolchain library for the `g-cqd` Swift analyzers.

## Engineering principles

- **Verify claims with executable checks.** Write a failing test or measurement before changing behaviour; never state unmeasured performance or unverified behaviour as fact.
- **Strictness.** Swift 6 language mode, strict concurrency, strict memory safety where configured, and warnings as errors. No force-unwraps or force-casts in production paths.
- **Bounded work and safety.** Bound untrusted inputs, recursion depth, and memory before allocation; handle errors explicitly without crashing on hostile input.
- **Factual documentation.** Keep `README.md`, user docs, and `Package.swift` aligned with the current codebase—no roadmaps, speculative plans, or diary logs in public docs.

All tools depending on `analyzerkit` share one CLI/configuration/exit-code contract (`docs/analyzer-contract.md`). Never execute user project manifests (`Package.swift` is parsed via `swift-syntax` only), and validate all external toolchain binaries/libraries through `BinaryTrustChecker`.

## Commands

```sh
swift test
swift format lint --strict --recursive Sources Tests Package.swift
```

## Architecture records

Accepted architectural decisions live in `docs/adr/` (when present). Only add a new ADR for durable architectural choices; mark superseded records clearly.
