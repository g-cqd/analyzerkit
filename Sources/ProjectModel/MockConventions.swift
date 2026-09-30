/// How a test double names itself: no compiler attribute marks one, so
/// spotting a mock is a naming convention, not a language feature.
public enum MockConventions {
    /// Type-name suffixes a test double conventionally carries.
    public static let typeNameSuffixes = ["Mock", "Spy", "Stub", "Fake"]

    /// Path components that mark a directory of test doubles.
    public static let pathComponents = ["Mocks", "Mock", "Spies", "Stubs", "Fakes"]

    /// Whether a type or file named `name` reads as a test double.
    public static func isMockName(_ name: String) -> Bool {
        typeNameSuffixes.contains { name.hasSuffix($0) }
    }

    /// Whether `path` sits under a directory test doubles conventionally
    /// live in, or is itself named like one.
    public static func isMockPath(_ path: String) -> Bool {
        let components = path.split(separator: "/").map(String.init)
        if components.contains(where: { pathComponents.contains($0) }) {
            return true
        }
        guard let fileName = components.last else { return false }
        let base = fileName.hasSuffix(".swift") ? String(fileName.dropLast(6)) : fileName
        return isMockName(base)
    }
}
