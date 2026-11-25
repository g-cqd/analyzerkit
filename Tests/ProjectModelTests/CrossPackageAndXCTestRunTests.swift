import Foundation
import ProjectModel
import Testing

@Suite("Cross-package TEST_HOST edges and XCTestRunReader (T-ECO-4)")
struct CrossPackageAndXCTestRunTests {
    @Test func xcodeTestTargetReachesLocalPackageViaPackageProductAndTestHost() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ak-xpkg-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // Local Swift package: CorePkg with target CoreLib
        let pkgDir = dir.appendingPathComponent("CorePkg")
        let pkgSrc = pkgDir.appendingPathComponent("Sources/CoreLib")
        try FileManager.default.createDirectory(at: pkgSrc, withIntermediateDirectories: true)
        try """
        // swift-tools-version: 6.0
        import PackageDescription
        let package = Package(
            name: "CorePkg",
            products: [.library(name: "CoreLib", targets: ["CoreLib"])],
            targets: [.target(name: "CoreLib")]
        )
        """.write(to: pkgDir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        let libFile = pkgSrc.appendingPathComponent("Core.swift")
        try "public struct Core {}\n".write(to: libFile, atomically: true, encoding: .utf8)

        // Xcode project: App target links CoreLib; AppTests sets TEST_HOST pointing to App.app/App (no PBXTargetDependency).
        let xcodeproj = dir.appendingPathComponent("Sample.xcodeproj")
        try FileManager.default.createDirectory(at: xcodeproj, withIntermediateDirectories: true)
        let pbxproj = """
            // !$*UTF8*$!
            {
                archiveVersion = 1;
                objects = {
                    PROJ = { isa = PBXProject; targets = (APP, TESTS); };
                    APP = {
                        isa = PBXNativeTarget;
                        name = SampleApp;
                        productType = "com.apple.product-type.application";
                        buildPhases = ();
                        dependencies = ();
                        packageProductDependencies = (PKGPROD);
                    };
                    PKGPROD = {
                        isa = XCSwiftPackageProductDependency;
                        productName = CoreLib;
                    };
                    TESTS = {
                        isa = PBXNativeTarget;
                        name = SampleAppTests;
                        productType = "com.apple.product-type.bundle.unit-test";
                        buildPhases = ();
                        dependencies = ();
                        buildConfigurationList = CFGLIST;
                    };
                    CFGLIST = {
                        isa = XCConfigurationList;
                        buildConfigurations = (DBG);
                    };
                    DBG = {
                        isa = XCBuildConfiguration;
                        name = Debug;
                        buildSettings = {
                            TEST_HOST = "$(BUILT_PRODUCTS_DIR)/SampleApp.app/SampleApp";
                        };
                    };
                };
                rootObject = PROJ;
            }
            """
        try pbxproj.write(to: xcodeproj.appendingPathComponent("project.pbxproj"), atomically: true, encoding: .utf8)

        let layout = try #require(ProjectLayout.discover(paths: [libFile.path]))
        let classification = ProjectClassification.load(layout)
        let canonicalLib = URL(fileURLWithPath: libFile.path).resolvingSymlinksInPath().path
        let tests = classification.testTargets(covering: canonicalLib)
        #expect(tests.map(\.name) == ["SampleAppTests"])
    }

    @Test func readsXCTestRunV1AndV2() throws {
        let v2 = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>__xctestrun_metadata__</key>
                <dict><key>FormatVersion</key><integer>2</integer></dict>
                <key>TestConfigurations</key>
                <array>
                    <dict>
                        <key>TestTargets</key>
                        <array>
                            <dict>
                                <key>BlueprintName</key><string>CoreTests</string>
                                <key>ProductModuleName</key><string>CoreTests</string>
                                <key>TestBundlePath</key><string>__TESTROOT__/CoreTests.xctest</string>
                                <key>SkipTestIdentifiers</key><array><string>SlowTests</string></array>
                            </dict>
                        </array>
                    </dict>
                </array>
            </dict>
            </plist>
            """
        let parsedV2 = try #require(XCTestRunReader.read(Data(v2.utf8)))
        #expect(parsedV2.formatVersion == 2)
        #expect(parsedV2.targets.count == 1)
        #expect(parsedV2.targets[0].blueprintName == "CoreTests")
        #expect(parsedV2.targets[0].skipTestIdentifiers == ["SlowTests"])

        let v1 = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>AppTests</key>
                <dict>
                    <key>BlueprintName</key><string>AppTests</string>
                    <key>OnlyTestIdentifiers</key><array><string>SmokeTests</string></array>
                </dict>
            </dict>
            </plist>
            """
        let parsedV1 = try #require(XCTestRunReader.read(Data(v1.utf8)))
        #expect(parsedV1.formatVersion == 1)
        #expect(parsedV1.targets.map(\.blueprintName) == ["AppTests"])
        #expect(parsedV1.targets[0].onlyTestIdentifiers == ["SmokeTests"])

        #expect(XCTestRunReader.read(Data("not a plist".utf8)) == nil)
    }
}
