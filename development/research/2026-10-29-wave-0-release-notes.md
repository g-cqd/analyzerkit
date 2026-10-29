# 2026-10-29 — Wave 0 release notes (drafts)

Patch releases for the defects that made a gate wrong (ADR-0015 item 4, roadmap 0035), in ADR-0015's fixed sections. They
become the GitHub release text when the owner tags them; the checksums are filled from the release workflow's `.sha256`
files, and the consumer steps are run on a maintastic branch first (ADR-0015 item 5).

## fcheck 0.1.2 (from 0.1.1)

| Section | |
| --- | --- |
| Archives | `fcheck-0.1.2-macos-arm64.tar.gz`, `fcheck-0.1.2-linux-x86_64.tar.gz`, `fcheck-0.1.2.artifactbundle.zip`, each with `.sha256` (to fill) |
| Flags | none |
| Exit codes | none |
| Report | none |
| Configuration | none |
| Cache | none to do: the build identity changes, so a 0.1.1 cache is discarded and rewritten |
| Findings that may appear | `leak-on-exit` for a handle open across `for try await` (the loop's head throws) |
| Findings that may disappear | `leak-on-exit` "when the function throws at line 0" after a `do`/`catch let error` (or `catch _`, `catch var e`) that catches everything |
| Speed | the callee of a call is read from its tokens: an 800-link chain 4.21 s → 0.01 s; maintastic cold 1.31 → 0.57 s wall, 6.42 → 1.27 s CPU |
| Measured | findings identical on maintastic, AemiProtobuf, aemi, ask, AemiJSON (none of the two shapes occurs there) |
| Consumer steps | AemiProtobuf `Scripts/tools.lock`: `FCHECK_COMMIT` → the 0.1.2 archives by version and SHA-256 (0.1.1 already publishes archives; its roadmap 0015 is stale) |

## arcleak 0.12.1 (from 0.12.0)

| Section | |
| --- | --- |
| Archives | `arcleak-0.12.1-*` as above (to fill) |
| Flags | none |
| Exit codes | none |
| Report | none |
| Configuration | none |
| Cache | none to do (build identity) |
| Findings that may appear | none |
| Findings that may disappear | with `--index-store*` only: a cycle through a type the corpus declares (a same-named class of another module was used); a `stored-closure-strong-self` in an extension of a struct declared in another file; anything inferred from a type that has left its declaring file since the build |
| Messages | `--index-store-path` naming a directory without index records (`<DerivedData>`, `…/Index.noindex`): "… is not an index store …; pass the store directory itself, e.g. `<DerivedData>/Index.noindex/DataStore`", instead of "stale for N file(s)"; nothing is created in that directory any more |
| Measured | without an index, findings identical on maintastic (3), ask, AemiJSON |
| Consumer steps | maintastic `ShareXcodePlugins/Package.swift`: arcleak URL and checksum; `DangerPlugins` unchanged. g-cqd: the lock (four `analyzers.sh`, AemiProtobuf `tools.lock`, aemi `swift-quality.yml` defaults) |

## deadwood 0.11.2 (from 0.11.1)

| Section | |
| --- | --- |
| Archives | `deadwood-0.11.2-*` as above (to fill) |
| Flags | none |
| Exit codes | none |
| Report | none |
| Configuration | none |
| Cache | none to do |
| Findings that may appear | none |
| Findings that may disappear | none |
| Behaviour | `libIndexStore.dylib` owned by the current user is trusted (an `Xcode.app` installed outside the App Store, swiftly toolchains): the index is read with Xcode's own library instead of Command Line Tools' |
| Messages | a directory without index records given to `--index-store-path`: "warning: … is not an index store …" instead of "does not cover the analyzed files (0 declarations resolved)"; nothing is created in it |
| Consumer steps | maintastic `ShareXcodePlugins/Package.swift`: deadwood URL and checksum (keep `--no-cache` until wave 1, D7). g-cqd: the lock |
