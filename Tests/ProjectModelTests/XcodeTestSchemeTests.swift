import ProjectModel
import Testing

#if canImport(FoundationEssentials)
    import FoundationEssentials
#else
    import Foundation
#endif

@Suite struct XcodeTestSchemeTests {
    private let pbxproj = """
        // !$*UTF8*$!
        {
            archiveVersion = 1;
            objects = {
                ROOT = { isa = PBXProject; targets = (APP, UNIT, UI, LIB); };
                APP = { isa = PBXNativeTarget; name = App; productName = App; productType = "com.apple.product-type.application"; };
                UNIT = { isa = PBXNativeTarget; name = AppTests; productName = AppTests; productType = "com.apple.product-type.bundle.unit-test"; };
                UI = { isa = PBXNativeTarget; name = AppUITests; productName = AppUITests; productType = "com.apple.product-type.bundle.ui-testing"; };
                LIB = { isa = PBXNativeTarget; name = "Core Tests"; productName = "Core Tests"; productType = "com.apple.product-type.bundle.unit-test"; };
            };
            rootObject = ROOT;
        }
        """

    private func project() throws -> (root: String, project: String) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("scheme-\(UUID().uuidString)").path
        let project = root + "/App.xcodeproj"
        try FileManager.default.createDirectory(atPath: project, withIntermediateDirectories: true)
        try Data(pbxproj.utf8).write(to: URL(fileURLWithPath: project + "/project.pbxproj"))
        return (root, project)
    }

    @Test func `the native targets of a project are read with their identifiers and product types`() throws {
        let (root, project) = try project()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let targets = try #require(XcodeNativeTargets.read(project: project))
        #expect(targets.map(\.name) == ["App", "AppTests", "AppUITests", "Core Tests"])
        #expect(targets.filter(\.isUnitTest).map(\.id) == ["UNIT", "LIB"])
        #expect(targets.filter(\.isUITest).map(\.name) == ["AppUITests"])
        #expect(XcodeNativeTargets.read(project: root + "/Missing.xcodeproj") == nil)
    }

    @Test func `a synthesized scheme tests every given target and reads back through the scheme reader`() throws {
        let (root, project) = try project()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let units = try #require(XcodeNativeTargets.read(project: project)).filter(\.isUnitTest)
        let xml = XcodeSchemeWriter.testScheme(units, containerDirectory: root)
        #expect(xml.contains(#"BuildableName = "Core Tests.xctest""#))
        #expect(xml.contains(#"ReferencedContainer = "container:App.xcodeproj""#))
        let directory = project + "/xcshareddata/xcschemes"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try Data(xml.utf8).write(to: URL(fileURLWithPath: directory + "/All.xcscheme"))
        let scheme = try #require(XcodeSchemeReader.schemes(in: project).first)
        #expect(scheme.name == "All" && scheme.testTargets == ["AppTests", "Core Tests"])
    }

    @Test func `names that are not XML-safe are escaped`() {
        let target = XcodeNativeTarget(
            id: "X",
            name: #"A&B<"C">"#,
            productName: "P",
            productType: "com.apple.product-type.bundle.unit-test",
            project: "/r/A.xcodeproj"
        )
        let xml = XcodeSchemeWriter.testScheme([target], containerDirectory: "/r")
        #expect(xml.contains("A&amp;B&lt;&quot;C&quot;&gt;"))
        #expect(!xml.contains(#"A&B<"C">"#))
    }
}
