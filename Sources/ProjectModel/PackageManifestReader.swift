internal import SwiftParser
internal import SwiftSyntax

/// A target as a manifest declares it, before its directories are resolved.
struct DeclaredPackageTarget: Sendable, Equatable {
    var name: String
    /// `target`, `executableTarget`, `testTarget`, `macro`, `plugin`, `systemLibrary` or `binaryTarget`.
    var kind: String
    var path: String?
    var sources: [String]?
    var exclude: [String]
}

/// Reads a `Package.swift` as syntax, never running it (ADR-0024 item 2).
enum PackageManifestReader {
    enum Reading: Sendable, Equatable {
        case targets([DeclaredPackageTarget])
        /// Why the targets cannot be known without running the manifest.
        case unknown(String)
    }

    static let kinds: Set<String> = [
        "target", "executableTarget", "testTarget", "macro", "plugin", "systemLibrary", "binaryTarget",
    ]

    static func read(_ source: String) -> Reading {
        let tree = Parser.parse(source: source)
        if tree.hasError { return .unknown("the manifest does not parse") }
        let finder = PackageCallFinder(viewMode: .sourceAccurate)
        finder.walk(tree)
        if let mutation = finder.mutation { return .unknown(mutation) }
        guard finder.calls.count == 1, let call = finder.calls.first else {
            return .unknown(finder.calls.isEmpty ? "no Package(…) call" : "more than one Package(…) call")
        }
        guard let argument = call.arguments.first(where: { $0.label?.text == "targets" }) else { return .targets([]) }
        guard let list = argument.expression.as(ArrayExprSyntax.self) else {
            return .unknown("`targets:` is not a literal list")
        }
        var targets: [DeclaredPackageTarget] = []
        for element in list.elements {
            switch target(element.expression) {
            case .success(let target): targets.append(target)
            case .failure(let reason): return .unknown(reason.text)
            }
        }
        return .targets(targets)
    }

    struct Reason: Error {
        let text: String
    }

    private static func target(_ expression: ExprSyntax) -> Result<DeclaredPackageTarget, Reason> {
        guard let call = expression.as(FunctionCallExprSyntax.self),
            let member = call.calledExpression.as(MemberAccessExprSyntax.self),
            member.base == nil || member.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == "Target",
            kinds.contains(member.declName.baseName.text)
        else { return .failure(Reason(text: "a target is not a `.target(…)`-style call")) }
        var target = DeclaredPackageTarget(
            name: "", kind: member.declName.baseName.text, path: nil, sources: nil, exclude: [])
        for argument in call.arguments {
            switch argument.label?.text {
            case "name":
                guard let name = literal(argument.expression) else {
                    return .failure(Reason(text: "a target's name is not a literal"))
                }
                target.name = name
            case "path":
                guard let path = literal(argument.expression) else {
                    return .failure(
                        Reason(text: "the path of \(target.name.isEmpty ? "a target" : target.name) is not a literal"))
                }
                target.path = path
            case "sources", "exclude":
                guard let list = literals(argument.expression) else {
                    return .failure(
                        Reason(text: "the \(argument.label?.text ?? "") of \(target.name) is not a literal list"))
                }
                if argument.label?.text == "sources" { target.sources = list } else { target.exclude = list }
            default: continue
            }
        }
        guard !target.name.isEmpty else { return .failure(Reason(text: "a target has no name")) }
        return .success(target)
    }

    /// A string literal without interpolation.
    private static func literal(_ expression: ExprSyntax) -> String? {
        guard let string = expression.as(StringLiteralExprSyntax.self) else { return nil }
        var text = ""
        for segment in string.segments {
            guard let piece = segment.as(StringSegmentSyntax.self) else { return nil }
            text += piece.content.text
        }
        return text
    }

    private static func literals(_ expression: ExprSyntax) -> [String]? {
        guard let array = expression.as(ArrayExprSyntax.self) else { return nil }
        var result: [String] = []
        for element in array.elements {
            guard let text = literal(element.expression) else { return nil }
            result.append(text)
        }
        return result
    }
}

/// Finds the `Package(…)` calls, and any statement that changes targets after them.
private final class PackageCallFinder: SyntaxVisitor {
    var calls: [FunctionCallExprSyntax] = []
    var mutation: String?

    /// Properties whose change alters which files a target compiles.
    static let membershipProperties: Set<String> = ["targets", "path", "sources", "exclude"]
    static let mutatingMethods: Set<String> = [
        "append", "insert", "remove", "removeAll", "removeFirst", "removeLast", "removeSubrange", "replaceSubrange",
        "popLast",
    ]

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        let callee = node.calledExpression
        let name =
            callee.as(DeclReferenceExprSyntax.self)?.baseName.text
            ?? callee.as(MemberAccessExprSyntax.self).flatMap { access in
                access.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == "PackageDescription"
                    ? access.declName.baseName.text : nil
            }
        if name == "Package" { calls.append(node) }
        return .visitChildren
    }

    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        guard node.base != nil, Self.membershipProperties.contains(node.declName.baseName.text) else {
            return .visitChildren
        }
        let property = node.declName.baseName.text
        // `x.targets.append(…)`
        if let parent = node.parent?.as(MemberAccessExprSyntax.self), parent.base?.id == node.id,
            Self.mutatingMethods.contains(parent.declName.baseName.text)
        {
            mutation = "`\(property)` is changed after the Package(…) call"
        }
        // `x.targets = …`, `x.targets += …`
        if let list = node.parent?.as(ExprListSyntax.self) {
            let elements = Array(list)
            if let index = elements.firstIndex(where: { $0.id == node.id }), index + 1 < elements.count {
                let next = elements[index + 1]
                if next.is(AssignmentExprSyntax.self)
                    || next.as(BinaryOperatorExprSyntax.self).map({ ["+=", "-="].contains($0.operator.text) }) == true
                {
                    mutation = "`\(property)` is changed after the Package(…) call"
                }
            }
        }
        return .visitChildren
    }
}
