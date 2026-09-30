# analyzerkit

The model of a Swift project that static analyzers share: which code the
system, the test frameworks or a script runner starts without any Swift call
site, and which code only debug builds, previews or generators produce.

deadwood (unused code), arcleak (retain cycles and leaks) and dolly (code
clones) each need the same answers. Kept here, a rule learned by one tool
reaches the others.

## Library: `ProjectModel`

| API | Answers |
| --- | --- |
| `CodeRegion` | the kind of code: production, `debugOnly`, `preview`, `test`, `mock`, `generated`, `script` (an option set; a preview in `#if DEBUG` is both) |
| `CodeRegionScanner` | the line spans of a file that only debug builds (`#if DEBUG`) or previews (`#Preview`, `PreviewProvider`) compile |
| `TopLevelCodeScanner` | code at file scope that no declaration names: `#Preview` bodies, other freestanding macros, script statements |
| `ConditionalCompilation` | whether an `#if` clause compiles only in debug builds |
| `SystemEntryPoints` | the classes project files tell the system to create: Info.plist principal, extension and scene-delegate classes, their `INFOPLIST_KEY_` build settings, storyboard and xib `customClass` |
| `GeneratedCode` | whether a generator wrote a file, from its header or its path |
| `TestConventions` | the attributes and base class the test frameworks look for, and whether a file is test code (its imports or its path) |
| `ProjectPlatforms` | the platforms a project builds for, from an Xcode project's `SDKROOT` or a manifest's `platforms`, as `#if os(...)` names |

Everything is syntactic or textual: no build, no index, no Foundation
dependency in the library. Each scanner states its complexity; all are linear
in their input.

## Use

```swift
.package(url: "https://github.com/g-cqd/analyzerkit.git", revision: "<commit>")
```

```swift
.product(name: "ProjectModel", package: "analyzerkit")
```

The analyzers pin a revision, as they pin their other private dependencies.

## Develop

```sh
swift build --build-tests
swift test --skip-build
```

Swift 6.4 (`.swift-version`), formatted with `swift format` (`.swift-format`).

## License

MIT, see `LICENSE`.
