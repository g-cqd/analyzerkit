public import SwiftIfConfig
public import SwiftSyntax

/// The conditions a run compiles under (`--define`, the configuration's `defines` and `platforms`), and what they make
/// of a file's `#if` clauses (roadmap 0059, ADR-0029).
///
/// arcleak walks only the active clauses with a ``buildConfiguration``. A tool that walks syntax with many visitors
/// (fcheck, modeler) asks for ``activeSource(_:tree:)`` instead: the source with every inactive clause blanked in place,
/// which it parses again. Each byte keeps its offset, so lines, columns and fingerprints of the code that stays do not
/// move.
public struct CompilationConditions: Sendable, Hashable {
    public let defines: Set<String>
    /// Platform names as `os()` spells them; empty for the host's.
    public let platforms: Set<String>

    public init(defines: Set<String> = [], platforms: Set<String> = []) {
        self.defines = defines
        self.platforms = platforms
    }

    /// Whether a run asked for conditions: a define given. Without one every clause is read, which is how the tools
    /// that walk syntax have always read code, so nothing moves for a run that does not ask.
    public var isRequested: Bool { !defines.isEmpty }

    /// What a compile would see: the defines as custom conditions, Swift 6 and compiler 6.4, and the `os()` of the
    /// platforms (the host's when none is given). `canImport` is not modelled.
    public var buildConfiguration: StaticBuildConfiguration {
        var configuration = StaticBuildConfiguration(
            customConditions: defines, languageVersion: VersionTuple(6), compilerVersion: VersionTuple(6, 4))
        if !platforms.isEmpty {
            // `os(OSX)` is the older spelling of `os(macOS)`.
            configuration.targetOSs = platforms.contains("macOS") ? platforms.union(["OSX"]) : platforms
            return configuration
        }
        #if os(macOS)
            configuration.targetOSs = ["macOS", "OSX"]
        #elseif os(Linux)
            configuration.targetOSs = ["Linux"]
        #endif
        return configuration
    }

    /// `bytes`, the source `tree` was parsed from, with the inactive `#if` clauses' elements replaced by spaces (line
    /// breaks kept), or nil when every clause is active.
    /// - Complexity: O(*n*) in the tree's size.
    public func activeSource(_ bytes: [UInt8], tree: SourceFileSyntax) -> [UInt8]? {
        let finder = InactiveClauses(configuration: buildConfiguration)
        finder.walk(tree)
        guard !finder.ranges.isEmpty else { return nil }
        var blanked = bytes
        for range in finder.ranges {
            for offset in range where offset < blanked.count {
                let byte = blanked[offset]
                if byte != UInt8(ascii: "\n"), byte != UInt8(ascii: "\r") { blanked[offset] = UInt8(ascii: " ") }
            }
        }
        return blanked
    }
}

/// The byte ranges of the elements of every inactive clause, outside any other inactive clause.
private final class InactiveClauses: SyntaxVisitor {
    private let configuration: StaticBuildConfiguration
    private(set) var ranges: [Range<Int>] = []

    init(configuration: StaticBuildConfiguration) {
        self.configuration = configuration
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: IfConfigDeclSyntax) -> SyntaxVisitorContinueKind {
        let active = node.activeClause(in: configuration).clause
        for clause in node.clauses {
            guard let elements = clause.elements.map(Syntax.init) else { continue }
            if clause.id == active?.id {
                walk(elements)
            } else {
                ranges.append(elements.position.utf8Offset..<elements.endPosition.utf8Offset)
            }
        }
        return .skipChildren
    }
}
