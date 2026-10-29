public import SwiftSyntax

/// How the test frameworks find their entry points. Neither calls a test
/// by name from source, so every tool needs the same rules to know what the
/// frameworks instantiate.
public enum TestConventions {
    /// Swift Testing marks a test function with `@Test`.
    public static let testAttribute = "Test"

    /// Swift Testing marks a suite with `@Suite`. A type holding `@Test`
    /// functions is a suite even without it.
    public static let suiteAttribute = "Suite"

    /// XCTest runs every `test…` method of an `XCTestCase` subclass.
    public static let xcTestCaseClass = "XCTestCase"

    /// Modules only test code imports.
    public static let testModules: Set<String> = ["XCTest", "Testing"]

    /// Whether the file at `path` is test code: it imports a test framework,
    /// or it lives in a `Tests` or `UITests` directory, or its name ends in
    /// `Tests.swift` or `Test.swift`.
    /// - Complexity: O(i) in the number of file-scope items.
    public static func isTestFile(path: String, tree: SourceFileSyntax) -> Bool {
        if isTestPath(path) {
            return true
        }
        return tree.statements.contains { item in
            guard let importDecl = item.item.as(ImportDeclSyntax.self),
                let module = importDecl.path.first?.name.text
            else { return false }
            return testModules.contains(module)
        }
    }

    /// Whether the file imports a test framework: code only tests can link.
    public static func importsTestFramework(_ tree: SourceFileSyntax) -> Bool {
        tree.statements.contains { item in
            guard let importDecl = item.item.as(ImportDeclSyntax.self), let module = importDecl.path.first?.name.text
            else { return false }
            return testModules.contains(module)
        }
    }

    /// Whether the path alone marks test code.
    public static func isTestPath(_ path: String) -> Bool {
        let components = path.split(separator: "/")
        if components.contains(where: { $0 == "Tests" || $0.hasSuffix("Tests") && !$0.contains(".") }) {
            return true
        }
        return path.hasSuffix("Tests.swift") || path.hasSuffix("Test.swift")
    }
}
