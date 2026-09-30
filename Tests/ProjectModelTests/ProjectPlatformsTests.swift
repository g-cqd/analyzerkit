import ProjectModel
import Testing

@Suite struct ProjectPlatformsTests {
    @Test func `an Xcode project names its platforms by SDKROOT`() {
        let project = """
            buildSettings = {
                SDKROOT = iphoneos;
                TARGETED_DEVICE_FAMILY = "1,2";
            };
            buildSettings = {
                SDKROOT = xros;
            };
            """

        let platforms = ProjectPlatforms.platforms(path: "Sample.xcodeproj/project.pbxproj", contents: project)

        #expect(platforms == ["iOS", "visionOS"])
    }

    @Test func `a package manifest names its platforms`() {
        let manifest = """
            let package = Package(
                name: "Sample",
                platforms: [.iOS(.v17), .macOS(.v14)]
            )
            """

        #expect(ProjectPlatforms.platforms(path: "Sample/Package.swift", contents: manifest) == ["iOS", "macOS"])
        #expect(ProjectPlatforms.platforms(path: "Sample/Notes.txt", contents: manifest).isEmpty)
    }
}
