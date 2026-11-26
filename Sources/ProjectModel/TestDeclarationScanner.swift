public import SwiftSyntax

/// One test a framework would run, as the source declares it.
public struct TestDeclaration: Sendable, Hashable {
    public enum Framework: String, Sendable, Hashable {
        case swiftTesting
        case xcTest
    }

    /// The function's base name (`boundary`).
    public let name: String
    /// The name with its argument labels (`boundary(value:)`), as Swift Testing identifies it.
    public let signature: String
    /// The enclosing types, outermost first, joined by dots (`Outer.Inner`); nil at file scope.
    public let suite: String?
    public let framework: Framework
    /// The 1-based lines from the first attribute to the closing brace.
    public let lines: ClosedRange<Int>
}

/// Finds the tests a file declares, syntactically (``TestConventions``): functions marked `@Test`, at any depth, and
/// the parameterless instance methods named `test…` of a class that inherits `XCTestCase` in its own declaration.
/// A subclass of another `XCTestCase` subclass is not followed: the base is in another file.
public enum TestDeclarationScanner {
    /// - Complexity: O(*n*) in the syntax nodes.
    public static func scan(_ tree: SourceFileSyntax, converter: SourceLocationConverter) -> [TestDeclaration] {
        let collector = Collector { converter.location(for: $0).line }
        collector.walk(tree)
        return collector.found
    }

    /// Walks declarations in source order, keeping the stack of enclosing types.
    private final class Collector: SyntaxVisitor {
        /// The 1-based line of a position.
        let lineOf: (AbsolutePosition) -> Int
        var found: [TestDeclaration] = []
        /// The enclosing types, and whether each is an `XCTestCase` subclass.
        var types: [(name: String, isTestCase: Bool)] = []

        init(lineOf: @escaping (AbsolutePosition) -> Int) {
            self.lineOf = lineOf
            super.init(viewMode: .sourceAccurate)
        }

        override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
            let inherits =
                node.inheritanceClause?.inheritedTypes.contains {
                    $0.type.trimmedDescription == TestConventions.xcTestCaseClass
                        || $0.type.trimmedDescription == "XCTest." + TestConventions.xcTestCaseClass
                } ?? false
            types.append((node.name.text, inherits))
            return .visitChildren
        }
        override func visitPost(_ node: ClassDeclSyntax) { types.removeLast() }

        override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
            types.append((node.name.text, false))
            return .visitChildren
        }
        override func visitPost(_ node: StructDeclSyntax) { types.removeLast() }

        override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
            types.append((node.name.text, false))
            return .visitChildren
        }
        override func visitPost(_ node: EnumDeclSyntax) { types.removeLast() }

        override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
            types.append((node.name.text, false))
            return .visitChildren
        }
        override func visitPost(_ node: ActorDeclSyntax) { types.removeLast() }

        override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
            types.append((node.extendedType.trimmedDescription, false))
            return .visitChildren
        }
        override func visitPost(_ node: ExtensionDeclSyntax) { types.removeLast() }

        override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
            let name = node.name.text
            let isSwiftTesting = node.attributes.contains { element in
                guard case .attribute(let attribute) = element else { return false }
                return attribute.attributeName.trimmedDescription == TestConventions.testAttribute
                    || attribute.attributeName.trimmedDescription == "Testing." + TestConventions.testAttribute
            }
            let isStatic = node.modifiers.contains { $0.name.text == "static" || $0.name.text == "class" }
            let isXCTest =
                !isSwiftTesting && types.last?.isTestCase == true && name.hasPrefix("test") && !isStatic
                && node.signature.parameterClause.parameters.isEmpty
            if isSwiftTesting || isXCTest {
                let labels = node.signature.parameterClause.parameters.map { $0.firstName.text + ":" }.joined()
                let start = lineOf(node.positionAfterSkippingLeadingTrivia)
                let end = lineOf(node.endPositionBeforeTrailingTrivia)
                found.append(
                    TestDeclaration(
                        name: name,
                        signature: name + "(" + labels + ")",
                        suite: types.isEmpty ? nil : types.map(\.name).joined(separator: "."),
                        framework: isSwiftTesting ? .swiftTesting : .xcTest,
                        lines: start...end
                    )
                )
            }
            // Local functions inside a test are not tests.
            return .skipChildren
        }
    }
}
