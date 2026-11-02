internal import Foundation
public import SwiftIfConfig
public import SwiftSyntax

/// A build configuration that also answers `canImport`, from a list of the modules a target can import (ADR-0030).
///
/// SwiftIfConfig's `StaticBuildConfiguration` throws for every `canImport`, and a condition that throws makes its clause
/// inactive: under it, `#if canImport(UIKit)` is never active, on iOS included. With the SDK's modules
/// (``CompilationConditions/sdkModules(at:)``) and the project's own, the answer is the compiler's for every module in
/// the list. A module outside it is answered by ``otherModulesImportable``: nil keeps the static configuration's
/// behaviour (the condition throws), false treats the list as complete.
public struct ModuleAwareBuildConfiguration: BuildConfiguration {
    public var base: StaticBuildConfiguration
    public var importableModules: Set<String>
    public var otherModulesImportable: Bool?

    public init(base: StaticBuildConfiguration, importableModules: Set<String>, otherModulesImportable: Bool? = nil) {
        self.base = base
        self.importableModules = importableModules
        self.otherModulesImportable = otherModulesImportable
    }

    /// A `canImport` this configuration cannot decide: a version asked of a listed module (the list has no versions),
    /// or a module outside the list when ``otherModulesImportable`` is nil.
    public struct Undecided: Error, Sendable, CustomStringConvertible {
        public let module: String
        public var description: String { "canImport(\(module)) cannot be decided from the module list" }
    }

    public func canImport(importPath: [(TokenSyntax, String)], version: CanImportVersion) throws -> Bool {
        let module = importPath.first?.1 ?? ""
        if importableModules.contains(module) {
            guard case .unversioned = version else { throw Undecided(module: module) }
            return true
        }
        guard let other = otherModulesImportable else { throw Undecided(module: module) }
        return other
    }

    public func isCustomConditionSet(name: String) throws -> Bool { base.isCustomConditionSet(name: name) }
    public func hasFeature(name: String) throws -> Bool { base.hasFeature(name: name) }
    public func hasAttribute(name: String) throws -> Bool { base.hasAttribute(name: name) }
    public func isActiveTargetOS(name: String) throws -> Bool { base.isActiveTargetOS(name: name) }
    public func isActiveTargetArchitecture(name: String) throws -> Bool {
        base.isActiveTargetArchitecture(name: name)
    }
    public func isActiveTargetEnvironment(name: String) throws -> Bool { base.isActiveTargetEnvironment(name: name) }
    public func isActiveTargetRuntime(name: String) throws -> Bool { base.isActiveTargetRuntime(name: name) }
    public func isActiveTargetPointerAuthentication(name: String) throws -> Bool {
        base.isActiveTargetPointerAuthentication(name: name)
    }
    public func isActiveTargetObjectFormat(name: String) throws -> Bool { base.isActiveTargetObjectFormat(name: name) }
    public var targetPointerBitWidth: Int { base.targetPointerBitWidth }
    public var targetAtomicBitWidths: [Int] { base.targetAtomicBitWidths }
    public var endianness: Endianness { base.endianness }
    public var languageVersion: VersionTuple { base.languageVersion }
    public var compilerVersion: VersionTuple { base.compilerVersion }
}

extension CompilationConditions {
    /// The compiler's own configuration for a target, from the JSON `swift-frontend -print-static-build-config` writes
    /// (with `-target`, `-sdk`, `-D` and `-swift-version` as the target is built). Exact for everything but
    /// `canImport`, which it does not carry.
    public static func compilerConfiguration(json: [UInt8]) throws -> StaticBuildConfiguration {
        try JSONDecoder().decode(StaticBuildConfiguration.self, from: Data(json))
    }

    /// The modules an SDK provides: its Swift modules (`usr/lib/swift/*.swiftmodule`), its frameworks
    /// (`System/Library/Frameworks`, `System/Library/SubFrameworks`), and the top-level modules its module maps declare
    /// (`usr/include`, one level of subdirectories). Empty when `sdk` cannot be read.
    public static func sdkModules(at sdk: String) -> Set<String> {
        var modules: Set<String> = []
        let files = FileManager.default
        func names(in directory: String, suffix: String) {
            for entry in (try? files.contentsOfDirectory(atPath: directory)) ?? [] where entry.hasSuffix(suffix) {
                modules.insert(String(entry.dropLast(suffix.count)))
            }
        }
        names(in: sdk + "/usr/lib/swift", suffix: ".swiftmodule")
        names(in: sdk + "/System/Library/Frameworks", suffix: ".framework")
        names(in: sdk + "/System/Library/SubFrameworks", suffix: ".framework")
        var maps = [sdk + "/usr/include/module.modulemap"]
        for entry in (try? files.contentsOfDirectory(atPath: sdk + "/usr/include")) ?? [] {
            maps.append(sdk + "/usr/include/" + entry + "/module.modulemap")
        }
        for map in maps {
            guard let data = files.contents(atPath: map) else { continue }
            modules.formUnion(moduleMapModules(String(decoding: data, as: UTF8.self)))
        }
        return modules
    }

    /// The top-level module names a module map declares: `module Name`, `explicit module` excepted, with `framework`,
    /// `extern` and attributes allowed before the name.
    static func moduleMapModules(_ text: String) -> Set<String> {
        var modules: Set<String> = []
        var depth = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let words = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            if depth == 0, let index = words.firstIndex(of: "module"), index + 1 < words.count,
                !words[..<index].contains("explicit")
            {
                let name = words[index + 1].prefix { $0.isLetter || $0.isNumber || $0 == "_" }
                if !name.isEmpty { modules.insert(String(name)) }
            }
            for character in line {
                if character == "{" { depth += 1 } else if character == "}" { depth = max(0, depth - 1) }
            }
        }
        return modules
    }

    /// This configuration (``buildConfiguration``), answering `canImport` from `modules`.
    public func buildConfiguration(
        importing modules: Set<String>,
        otherModulesImportable: Bool? = nil
    ) -> ModuleAwareBuildConfiguration {
        ModuleAwareBuildConfiguration(
            base: buildConfiguration,
            importableModules: modules,
            otherModulesImportable: otherModulesImportable
        )
    }
}
