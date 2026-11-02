import Foundation
import Testing

@testable import ProjectModel

/// Which test targets can reach a file, from manifests and projects without building (ADR-0030).
@Suite struct TestTargetsTests {
    @Test func `a package's test targets that depend on the file's target, directly or not, cover it`() throws {
        try ProjectFixture.with { f in
            try f.file(
                "Package.swift",
                """
                // swift-tools-version: 6.0
                import PackageDescription

                let deps: [Target.Dependency] = ["Core"]
                let package = Package(
                    name: "P",
                    targets: [
                        .target(name: "Core"),
                        .target(name: "Feature", dependencies: [.target(name: "Core"), .product(name: "X", package: "x")]),
                        .target(name: "Other"),
                        .testTarget(name: "FeatureTests", dependencies: ["Feature"]),
                        .testTarget(name: "CoreTests", dependencies: [.byName(name: "Core", condition: nil)]),
                        .testTarget(name: "OtherTests", dependencies: ["Other"]),
                        .testTarget(name: "UnknownTests", dependencies: deps),
                    ]
                )
                """
            )
            let core = try f.file("Sources/Core/Core.swift")
            let other = try f.file("Sources/Other/Other.swift")
            let test = try f.file("Tests/CoreTests/CoreTests.swift")
            try f.file("Sources/Feature/Feature.swift")
            let classification = try f.classification(of: [core, other, test])
            #expect(
                classification.testTargets(covering: core).map(\.name) == ["CoreTests", "FeatureTests", "UnknownTests"]
            )
            #expect(classification.testTargets(covering: other).map(\.name) == ["OtherTests", "UnknownTests"])
            #expect(classification.testTargets(covering: test).map(\.name) == ["CoreTests"])
            #expect(classification.testTargets(covering: f.path("Nowhere.swift")).isEmpty)
        }
    }

    @Test func `a project's test bundles that depend on the file's target cover it`() throws {
        try ProjectFixture.with { f in
            var xcode = XcodeFixture()
            let app = xcode.folder("App")
            let kit = xcode.folder("Kit")
            let tests = xcode.folder("AppTests")
            let kitTests = xcode.folder("KitTests")
            let ui = xcode.folder("UITests")
            xcode.target("Kit", type: ProductType.framework, folders: [kit])
            xcode.target("App", type: ProductType.application, folders: [app], dependencies: ["Kit"])
            xcode.target("AppTests", type: ProductType.unitTest, folders: [tests], dependencies: ["App"])
            xcode.target("KitTests", type: ProductType.unitTest, folders: [kitTests], dependencies: ["Kit"])
            xcode.target("UITests", type: ProductType.uiTest, folders: [ui])
            try f.project("App", xcode)
            let files = try [
                "App/App.swift", "Kit/Kit.swift", "AppTests/T.swift", "KitTests/K.swift", "UITests/U.swift",
            ]
            .map { try f.file($0) }
            let classification = try f.classification(of: files)
            #expect(classification.testTargets(covering: files[1]).map(\.name) == ["AppTests", "KitTests"])
            #expect(classification.testTargets(covering: files[0]).map(\.name) == ["AppTests"])
        }
    }

    @Test func `a scheme's test targets come from its testables and its enabled test plans`() throws {
        try ProjectFixture.with { f in
            try f.file(
                "App.xcodeproj/xcshareddata/xcschemes/App.xcscheme",
                """
                <?xml version="1.0" encoding="UTF-8"?>
                <Scheme LastUpgradeVersion = "2700" version = "1.7">
                   <BuildAction parallelizeBuildables = "YES">
                      <BuildActionEntries>
                         <BuildActionEntry buildForTesting = "YES">
                            <BuildableReference BlueprintName = "NotATest" BuildableName = "App.app"/>
                         </BuildActionEntry>
                      </BuildActionEntries>
                   </BuildAction>
                   <TestAction buildConfiguration = "Debug">
                      <TestPlans>
                         <TestPlanReference reference = "container:Plans/All.xctestplan" default = "YES">
                         </TestPlanReference>
                      </TestPlans>
                      <Testables>
                         <TestableReference skipped = "NO">
                            <BuildableReference BuildableIdentifier = "primary" BlueprintName = "AppTests" ReferencedContainer = "container:App.xcodeproj">
                            </BuildableReference>
                         </TestableReference>
                         <TestableReference skipped = "YES">
                            <BuildableReference BlueprintName = "SlowTests"/>
                         </TestableReference>
                      </Testables>
                   </TestAction>
                </Scheme>
                """
            )
            try f.file(
                "Plans/All.xctestplan",
                #"{"testTargets": [{"target": {"name": "KitTests"}}, {"enabled": false, "target": {"name": "Off"}}, {"target": {"name": "AppTests"}}], "version": 1}"#
            )
            let schemes = XcodeSchemeReader.schemes(in: f.path("App.xcodeproj"))
            let scheme = try #require(schemes.first)
            #expect(schemes.count == 1)
            #expect(scheme.name == "App")
            #expect(scheme.testTargets == ["AppTests"])
            #expect(scheme.testPlans == [f.path("Plans/All.xctestplan")])
            #expect(scheme.allTestTargets == ["AppTests", "KitTests"])
            #expect(XcodeSchemeReader.testPlanTargets(f.path("missing.xctestplan")) == nil)
        }
    }

    @Test func `attributes are read whole, with entities decoded`() {
        let element: Substring = #"<Ref Name = "a &amp; b" OtherName = "x" Name2="y">"#
        #expect(XcodeSchemeReader.attribute("Name", in: element) == "a & b")
        #expect(XcodeSchemeReader.attribute("Name2", in: element) == "y")
        #expect(XcodeSchemeReader.attribute("Missing", in: element) == nil)
        #expect(XcodeSchemeReader.elements("A", in: "<AB/><A x=\"1\"/><A>in</A>").count == 2)
    }
}
