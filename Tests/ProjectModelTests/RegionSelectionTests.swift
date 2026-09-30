import ProjectModel
import Testing

@Suite struct RegionSelectionTests {
    @Test func `a name parses to its region, all parses to every region`() throws {
        #expect(try RegionArgument.parse("preview") == .preview)
        #expect(try RegionArgument.parse("preview,debug") == [.preview, .debugOnly])
        #expect(try RegionArgument.parse("all") == CodeRegion.allRegions)
        #expect(try RegionArgument.parse("") == [])
    }

    @Test func `an unknown name is rejected, naming itself`() {
        #expect(throws: UnknownRegionName(name: "bogus")) {
            try RegionArgument.parse("preview,bogus")
        }
    }

    @Test func `a region not included is never in scope`() {
        let selection = RegionSelection.none
        #expect(!selection.isIncluded(.preview))
    }

    @Test func `an included region is in scope`() throws {
        let selection = try RegionSelection(include: "preview,test", exclude: nil)
        #expect(selection.isIncluded(.preview))
        #expect(selection.isIncluded(.test))
        #expect(!selection.isIncluded(.mock))
    }

    @Test func `exclude wins over a broader include for the same region`() throws {
        let selection = try RegionSelection(include: "all", exclude: "generated")
        #expect(selection.isIncluded(.preview))
        #expect(!selection.isIncluded(.generated))
    }

    @Test func `production is never included`() throws {
        let selection = try RegionSelection(include: "all", exclude: nil)
        #expect(!selection.isIncluded(.production))
    }
}

@Suite struct MockConventionsTests {
    @Test(arguments: ["SampleMock", "SampleSpy", "SampleStub", "SampleFake"])
    func `a type name with a test-double suffix is a mock`(name: String) {
        #expect(MockConventions.isMockName(name))
    }

    @Test func `a plain type name is not a mock`() {
        #expect(!MockConventions.isMockName("SampleHandler"))
    }

    @Test(arguments: [
        "Sources/Sample/Mocks/SampleServiceMock.swift", "Tests/SampleTests/Fakes/SampleFake.swift",
        "Sources/Sample/SampleSpy.swift",
    ])
    func `a mocks directory or a mock-named file is a mock path`(path: String) {
        #expect(MockConventions.isMockPath(path))
    }

    @Test func `an ordinary path is not a mock path`() {
        #expect(!MockConventions.isMockPath("Sources/Sample/SampleHandler.swift"))
    }
}
