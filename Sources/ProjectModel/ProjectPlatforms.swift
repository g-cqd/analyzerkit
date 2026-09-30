/// Which platforms a project builds for, read from its project files, as
/// the names `#if os(...)` tests: `iOS`, `macOS`, `tvOS`, `watchOS`,
/// `visionOS`. A tool evaluating `#if` for the host platform instead skips
/// every iOS-only branch of an iOS app.
public enum ProjectPlatforms {
    /// `SDKROOT` values in an Xcode project and their `os()` names.
    static let sdkRoots: [String: String] = [
        "iphoneos": "iOS",
        "macosx": "macOS",
        "appletvos": "tvOS",
        "watchos": "watchOS",
        "xros": "visionOS",
    ]

    /// `.platforms` entries in a package manifest and their `os()` names.
    static let packagePlatforms: [String: String] = [
        ".iOS(": "iOS",
        ".macOS(": "macOS",
        ".tvOS(": "tvOS",
        ".watchOS(": "watchOS",
        ".visionOS(": "visionOS",
        ".macCatalyst(": "iOS",
    ]

    /// Whether `path` is a file this reader understands.
    public static func isPlatformSource(_ path: String) -> Bool {
        path.hasSuffix(".pbxproj") || path.hasSuffix("/Package.swift") || path == "Package.swift"
    }

    /// The platforms one project file names; empty when it names none.
    /// - Complexity: O(n) in the length of `contents` per platform name.
    public static func platforms(path: String, contents: String) -> Set<String> {
        var found: Set<String> = []
        if path.hasSuffix(".pbxproj") {
            for (sdk, name) in sdkRoots where contents.contains("SDKROOT = \(sdk);") {
                found.insert(name)
            }
        } else if isPlatformSource(path) {
            for (entry, name) in packagePlatforms where contents.contains(entry) {
                found.insert(name)
            }
        }
        return found
    }
}
