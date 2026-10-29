import Foundation
import SwiftParser
import Testing

@testable import ProjectModel

/// Roadmap 0043, ADR-0024: target kinds and product types decide before path conventions.
@Suite struct ProjectClassificationTests {
    private func manifest(_ targets: String, name: String = "Package") -> String {
        """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "\(name)",
            products: [.library(name: "\(name)", targets: ["\(name)"])],
            targets: [
        \(targets)
            ]
        )
        """
    }

    private func isTest(_ classification: FileClassification) -> Bool { classification.region.contains(.test) }

    // MARK: SwiftPM

    @Test func `a test target at an unconventional path is test, its library production`() throws {
        try ProjectFixture.with { f in
            try f.file(
                "Package.swift",
                manifest(
                    """
                    .target(name: "Lib"),
                    .testTarget(name: "Checks", dependencies: ["Lib"], path: "Checks"),
                    """))
            let library = try f.file("Sources/Lib/Lib.swift")
            let check = try f.file("Checks/LibCheck.swift")
            let model = try f.classification(of: [library, check])
            #expect(isTest(model.classify(check)))
            #expect(!isTest(model.classify(library)))
            let provenance = model.classify(check).provenance
            #expect(
                provenance
                    == .targets([
                        ProjectTarget(
                            name: "Checks", kind: "testTarget", isTest: true, container: f.path("Package.swift"))
                    ]))
        }
    }

    @Test func `code under Tests that no test target compiles is production`() throws {
        try ProjectFixture.with { f in
            try f.file(
                "Package.swift",
                manifest(
                    """
                    .target(name: "Package"),
                    .executableTarget(name: "FixtureGen", path: "Tests/FixtureGen"),
                    .testTarget(name: "PackageTests"),
                    """))
            let tool = try f.file("Tests/FixtureGen/main.swift")
            let test = try f.file("Tests/PackageTests/PackageTests.swift")
            let model = try f.classification(of: [tool, test])
            #expect(!isTest(model.classify(tool)), "an executable target, whatever its directory is called")
            #expect(isTest(model.classify(test)))
        }
    }

    @Test func `SwiftPM's default directories, sources and exclude decide membership`() throws {
        try ProjectFixture.with { f in
            try f.file(
                "Package.swift",
                manifest(
                    """
                    .target(name: "Package", exclude: ["Old"]),
                    .target(name: "Picked", path: "Modules/Picked", sources: ["Kept.swift", "Nested"]),
                    """))
            let inSource = try f.file("Source/Package/A.swift")
            let excluded = try f.file("Source/Package/Old/Legacy.swift")
            let kept = try f.file("Modules/Picked/Kept.swift")
            let nested = try f.file("Modules/Picked/Nested/Deep.swift")
            let notListed = try f.file("Modules/Picked/Other.swift")
            let model = try f.classification(of: [inSource, excluded, kept, nested, notListed])
            #expect(model.classify(inSource).provenance != .convention(.unclaimed), "Source/ is a default directory")
            #expect(model.classify(kept).provenance != .convention(.unclaimed))
            #expect(model.classify(nested).provenance != .convention(.unclaimed))
            #expect(model.classify(excluded).provenance == .convention(.unclaimed))
            #expect(model.classify(notListed).provenance == .convention(.unclaimed))
        }
    }

    @Test func `a nested local package owns its own tree`() throws {
        try ProjectFixture.with { f in
            try f.file("Package.swift", manifest(".target(name: \"Outer\", path: \"Modules\"),", name: "Outer"))
            try f.file(
                "Modules/Inner/Package.swift",
                manifest(".target(name: \"Inner\"),\n.testTarget(name: \"InnerTests\"),", name: "Inner"))
            let outer = try f.file("Modules/Outer.swift")
            let inner = try f.file("Modules/Inner/Sources/Inner/Inner.swift")
            let innerTest = try f.file("Modules/Inner/Tests/InnerTests/InnerTests.swift")
            let model = try f.classification(of: [outer, inner, innerTest])
            guard case .targets(let targets) = model.classify(inner).provenance else {
                Issue.record("Inner.swift unclaimed")
                return
            }
            #expect(targets.map(\.name) == ["Inner"], "not also Outer, whose directory holds the nested package")
            #expect(isTest(model.classify(innerTest)))
            #expect(!isTest(model.classify(outer)))
        }
    }

    @Test func `a package manifest is a script`() throws {
        try ProjectFixture.with { f in
            let manifestPath = try f.file("Package.swift", manifest(".target(name: \"Package\"),"))
            let source = try f.file("Sources/Package/A.swift")
            let model = try f.classification(of: [manifestPath, source])
            #expect(model.classify(manifestPath) == FileClassification(region: .script, provenance: .manifest))
        }
    }

    @Test(arguments: [
        ("targets", ".target(name: \"Package\")", "let targets: [Target] = [.target(name: \"Package\")]"),
        ("map", "", "let names = [\"Package\"]\nlet more = names.map { Target.target(name: $0) }"),
        ("conditional", "#if os(macOS)\n.target(name: \"Package\"),\n#endif", ""),
        ("appended", ".target(name: \"Package\"),", "package.targets.append(.testTarget(name: \"PackageTests\"))"),
        ("non-literal path", ".target(name: \"Package\", path: base + \"/Sources\"),", "let base = \".\""),
    ])
    func `a manifest that must run to be known is unknown, and its files fall back to conventions`(
        shape: String, targets: String, extra: String
    ) throws {
        try ProjectFixture.with { f in
            var text = manifest(shape == "targets" ? "" : targets) + "\n" + extra + "\n"
            if shape == "targets" {
                text = text.replacingOccurrences(of: "targets: [\n\n    ]", with: "targets: targets")
            }
            if shape == "map" { text = text.replacingOccurrences(of: "targets: [\n\n    ]", with: "targets: more") }
            let manifestPath = try f.file("Package.swift", text)
            let test = try f.file("Tests/PackageTests/T.swift")
            let source = try f.file("Sources/Package/A.swift")
            let model = try f.classification(of: [test, source])
            #expect(model.unknownProjects.map(\.path) == [manifestPath], "\(shape)")
            #expect(
                model.classify(test)
                    == FileClassification(region: .test, provenance: .convention(.unknownProject(manifestPath))))
            let issue = model.issues(for: [test, source]).first { $0.code == "project-unknown" }
            #expect(issue?.paths == [test, source].sorted(), "\(shape)")
        }
    }

    // MARK: Xcode

    @Test func `Xcode product types decide test and production`() throws {
        try ProjectFixture.with { f in
            var xcode = XcodeFixture()
            let app = xcode.folder("App")
            let kit = xcode.folder("Kit")
            let tests = xcode.folder("AppTests")
            let screenshots = xcode.folder("Screenshots")
            xcode.target("App", type: ProductType.application, folders: [app])
            xcode.target("Kit", type: ProductType.framework, folders: [kit])
            xcode.target("AppTests", type: ProductType.unitTest, folders: [tests])
            xcode.target("Screenshots", type: ProductType.uiTest, folders: [screenshots])
            try f.project("App", xcode)
            let files = try ["App/AppTests.swift", "Kit/Kit.swift", "AppTests/A.swift", "Screenshots/Shot.swift"].map {
                try f.file($0)
            }
            let model = try f.classification(of: files)
            #expect(files.map { isTest(model.classify($0)) } == [false, false, true, true])
            #expect(model.unknownProjects.isEmpty)
        }
    }

    @Test func `a membership exception removes a file from an owning target and adds it to another`() throws {
        try ProjectFixture.with { f in
            var xcode = XcodeFixture()
            let app = xcode.folder(
                "App",
                exceptions: [
                    (target: "App", files: ["Info.plist", "Debug/Only.swift"]),
                    (target: "Widget", files: ["Shared.swift"]),
                ])
            let widgetFolder = xcode.folder("Widget", exceptions: [(target: "Widget", files: ["Entry.swift"])])
            xcode.target("App", type: ProductType.application, folders: [app])
            xcode.target("Widget", type: ProductType.appExtension)
            _ = widgetFolder
            try f.project("App", xcode)
            let plain = try f.file("App/View.swift")
            let removed = try f.file("App/Debug/Only.swift")
            let shared = try f.file("App/Shared.swift")
            let added = try f.file("Widget/Entry.swift")
            let other = try f.file("Widget/Other.swift")
            let model = try f.classification(of: [plain, removed, shared, added, other])
            func names(_ path: String) -> [String] {
                guard case .targets(let targets) = model.classify(path).provenance else { return [] }
                return targets.map(\.name)
            }
            #expect(names(plain) == ["App"])
            #expect(names(removed) == [])
            #expect(names(shared) == ["App", "Widget"])
            #expect(names(added) == ["Widget"], "the folder belongs to no target; the exception adds the file")
            #expect(names(other) == [])
        }
    }

    @Test func `a source both the app and its tests compile is production`() throws {
        try ProjectFixture.with { f in
            var xcode = XcodeFixture()
            let app = xcode.folder("App", exceptions: [(target: "AppUITests", files: ["Screens/Screen.swift"])])
            let tests = xcode.folder("AppUITests")
            xcode.target("App", type: ProductType.application, folders: [app])
            xcode.target("AppUITests", type: ProductType.uiTest, folders: [tests])
            try f.project("App", xcode)
            let shared = try f.file("App/Screens/Screen.swift")
            let model = try f.classification(of: [shared])
            let classification = model.classify(shared)
            #expect(!isTest(classification), "it ships in the app")
            guard case .targets(let targets) = classification.provenance else {
                Issue.record("unclaimed")
                return
            }
            #expect(targets.map(\.isTest) == [false, true])
        }
    }

    @Test func `explicit sources resolve through their groups and source trees`() throws {
        try ProjectFixture.with { f in
            var xcode = XcodeFixture()
            let inGroup = xcode.reference("Model.swift")
            let inner = xcode.group("Model", children: [inGroup], top: false)
            _ = xcode.group("Legacy Code", children: [inner])
            let fromRoot = xcode.reference("Support/Helpers.swift", sourceTree: "SOURCE_ROOT")
            let built = xcode.reference("Derived.swift", sourceTree: "BUILT_PRODUCTS_DIR")
            xcode.target("Legacy", type: ProductType.application, sources: [inGroup, fromRoot, built])
            xcode.target("LegacyTests", type: ProductType.unitTest, sources: [fromRoot])
            try f.project("Legacy", xcode, in: "Apps")
            let model1 = try f.file("Apps/Legacy Code/Model/Model.swift")
            let helper = try f.file("Apps/Support/Helpers.swift")
            let model = try f.classification(of: [model1, helper])
            guard case .targets(let modelTargets) = model.classify(model1).provenance,
                case .targets(let helperTargets) = model.classify(helper).provenance
            else {
                Issue.record("unclaimed")
                return
            }
            #expect(modelTargets.map(\.name) == ["Legacy"])
            #expect(helperTargets.map(\.name) == ["Legacy", "LegacyTests"])
        }
    }

    @Test func `a run script's outputs are generated, and a Swift file it runs is a script`() throws {
        try ProjectFixture.with { f in
            var xcode = XcodeFixture()
            let app = xcode.folder("App")
            let generate = xcode.script(
                "Generate \"Strings\"", "\"${SRCROOT}/tools/gen\" > \"$SCRIPT_OUTPUT_FILE_0\"\n",
                outputs: ["$(SRCROOT)/App/Strings.swift"])
            let clean = xcode.script(
                "Clean", "if [ \"$CONFIGURATION\" = Debug ]; then\n  xcrun swift ./scripts/clean.swift\nfi\n",
                outputs: ["$(SRCROOT)/scripts/clean.swift"])
            xcode.target("App", type: ProductType.application, folders: [app], phases: [generate, clean])
            try f.project("App", xcode)
            let strings = try f.file("App/Strings.swift")
            let cleaner = try f.file("scripts/clean.swift")
            let view = try f.file("App/View.swift")
            let model = try f.classification(of: [strings, cleaner, view])
            #expect(model.classify(strings).region.contains(.generated))
            #expect(model.classify(view).region == [])
            #expect(model.classify(cleaner).region == .script, "listed as an output, but the phase runs it")
            #expect(
                model.classify(cleaner).provenance == .runScript(phase: "Clean", container: f.path("App.xcodeproj")))
        }
    }

    @Test func `a project that does not parse is unknown`() throws {
        try ProjectFixture.with { f in
            try f.file("App.xcodeproj/project.pbxproj", "// !$*UTF8*$!\n{ objects = { A = { isa = PBXNativeTarget; ")
            let test = try f.file("AppTests/T.swift")
            let model = try f.classification(of: [test])
            #expect(model.unknownProjects.map(\.path) == [f.path("App.xcodeproj")])
            #expect(model.classify(test).provenance == .convention(.unknownProject(f.path("App.xcodeproj"))))
            #expect(isTest(model.classify(test)))
        }
    }

    // MARK: Mixed, unclaimed, content

    @Test func `a project with a local package classifies both`() throws {
        try ProjectFixture.with { f in
            var xcode = XcodeFixture()
            let app = xcode.folder("App")
            xcode.target("App", type: ProductType.application, folders: [app])
            try f.project("App", xcode)
            try f.file(
                "Packages/Feature/Package.swift",
                manifest(".target(name: \"Feature\"),\n.testTarget(name: \"FeatureTests\"),", name: "Feature"))
            let view = try f.file("App/View.swift")
            let feature = try f.file("Packages/Feature/Sources/Feature/F.swift")
            let featureTest = try f.file("Packages/Feature/Tests/FeatureTests/FT.swift")
            let model = try f.classification(of: [view, feature, featureTest])
            #expect([view, feature, featureTest].map { isTest(model.classify($0)) } == [false, false, true])
            for path in [view, feature, featureTest] {
                guard case .targets = model.classify(path).provenance else {
                    Issue.record("\(path) was not decided by a target")
                    continue
                }
            }
            #expect(model.issues(for: [view, feature, featureTest]).isEmpty)
        }
    }

    @Test func `a file no target compiles falls back to conventions and is reported`() throws {
        try ProjectFixture.with { f in
            try f.file("Package.swift", manifest(".target(name: \"Package\"),"))
            let source = try f.file("Sources/Package/A.swift")
            let stray = try f.file("Tests/Stray/StrayTests.swift")
            let model = try f.classification(of: [source, stray])
            #expect(model.classify(stray) == FileClassification(region: .test, provenance: .convention(.unclaimed)))
            let issues = model.issues(for: [source, stray])
            #expect(issues.map(\.code) == ["project-unclaimed"])
            #expect(issues.first?.paths == [stray])
        }
    }

    @Test func `with no project, conventions decide and nothing is reported`() throws {
        try ProjectFixture.with { f in
            let test = try f.file("Tests/ThingTests.swift")
            let code = try f.file("Code/Thing.swift")
            let model = try f.classification(of: [test, code])
            #expect(model.classify(test) == FileClassification(region: .test, provenance: .convention(.noProject)))
            #expect(model.classify(code).region == [])
            #expect(model.issues(for: [test, code]).isEmpty)
        }
    }

    @Test func `content signals add to the project's answer, and a test path no longer does`() throws {
        try ProjectFixture.with { f in
            try f.file(
                "Package.swift",
                manifest(
                    """
                    .target(name: "Package"),
                    .target(name: "TestSupport", path: "Tests/Support"),
                    """))
            let helper = try f.file("Sources/Package/Expect.swift", "import XCTest\nfunc check() {}\n")
            let generated = try f.file(
                "Sources/Package/Out.swift", "// Generated by SwiftGen. Do not edit.\nlet a = 1\n")
            let support = try f.file("Tests/Support/Fixture.swift", "struct Fixture {}\n")
            let model = try f.classification(of: [helper, generated, support])
            func classify(_ path: String) throws -> FileClassification {
                let source = try String(contentsOfFile: path, encoding: .utf8)
                return model.classify(path, tree: Parser.parse(source: source))
            }
            #expect(try classify(helper).region == .test, "it imports a test framework")
            #expect(try classify(generated).region == .generated)
            #expect(try classify(support).region == [], "a library target, though its path says Tests")
        }
    }

    // MARK: The reader

    @Test func `the OpenStep reader reads what Xcode writes`() throws {
        let text = """
            // !$*UTF8*$!
            {
            \tarchiveVersion = 1; /* a comment */
            \tlist = (a, "b c", /* skipped */ "d\\"e\\\\f\\ng", );
            \tnested = { key = value; "quoted key" = <0aFF 10>; };
            \tempty = ( );
            \t// a line comment
            \tpath = $(SRCROOT)/a-b_c.swift;
            }
            """
        let value = try #require(OpenStepPlist.parse(Array(text.utf8)))
        let root = try #require(value.dictionary)
        #expect(root["archiveVersion"] == .string("1"))
        #expect(root["list"] == .array([.string("a"), .string("b c"), .string("d\"e\\f\ng")]))
        #expect(root["nested"] == .dictionary(["key": .string("value"), "quoted key": .data([0x0A, 0xFF, 0x10])]))
        #expect(root["empty"] == .array([]))
        #expect(root["path"] == .string("$(SRCROOT)/a-b_c.swift"))
    }

    @Test(arguments: ["{ a = 1 }", "{ a = (1, 2; }", "{ a = \"open; }", "{ a = 1; } trailing", "", "{ /* open"])
    func `the OpenStep reader refuses what it cannot read`(text: String) {
        #expect(OpenStepPlist.parse(Array(text.utf8)) == nil)
    }
}
