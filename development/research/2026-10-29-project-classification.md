# 2026-10-29 — What project classification has to read (roadmap 0043 probe)

maintastic (`parts-MAIN-24752-stock-handling`), read-only.

## Xcode

One project, `Oculavis Share IOS.xcodeproj`, 3,506 lines, 556 objects. Five native targets: an application, two app
extensions, a unit-test bundle, a UI-test bundle. Objects by kind: 264 build configurations, 131 file references, 39 build
files, 19 groups, 16 `PBXFileSystemSynchronizedRootGroup`, 6 `PBXFileSystemSynchronizedBuildFileExceptionSet`, 5 sources
phases (all empty), 2 shell-script phases, 3 variant groups.

- **Every target's sources come from synchronized folders.** The classic path (sources phase → build file → file
  reference → group chain) is still needed for older projects, but here it lists nothing.
- **An exception flips membership.** The `NotificationExtension` folder belongs to no target; an exception set for the
  extension adds `NotificationService.swift` to it. The app's `app` folder carries an exception for the UI-test target
  adding `AppStoreScreenshotScreens/AppStoreScreenshotScreen.swift`: a source shared by the app and its UI tests. Info.plist
  exceptions for owning targets remove the file. Reading exceptions as removals only would lose the extension entirely.
- **Script phases.** "Clean Localizable" runs `swift ./scripts/clean_localizable_full.swift` and lists that file as an
  *output*, to make Xcode rerun it. Listed outputs are not enough to call a file generated: a file the script text runs is
  a script. The other phase writes JSON outside the tree.
- `PropertyListSerialization` parses the project in 556 ms (release, first call) and is Foundation-only; a reader of the
  OpenStep grammar (dictionaries, arrays, quoted and bare strings, comments, data) is a few hundred lines.

## SwiftPM

17 manifests. 16 are one library, one test target and one plugin dependency, with `path:` in most; ShareMacros has four
test targets; ShareXcodePlugins has 45 targets (three binary, twelve plugins, executables). Every `targets:` array is a
literal list of calls; the one top-level `let` is `swiftSettings`. No manifest needs evaluation; a dynamic one must still be
recognised and reported, not guessed.
