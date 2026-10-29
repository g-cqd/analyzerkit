// A2. Copy into arcleak/Tests/ArcLeakCoreTests/. Expected after the fix: no finding (the corpus declares Plugin as a struct).
import ArcLeakCore
import Testing

@Suite struct ZZProbeTests {
    struct FakeIndex: IndexReading {
        let types: [String: ExternalTypeFacts]
        func externalTypeFacts(name: String) -> ExternalTypeFacts? { types[name] }
    }

    @Test func corpusStructIsNotLookedUp() {
        let source = "class Hub {\n    var plugin: Plugin?\n}\nstruct Plugin {\n    var x = 0\n}\n"
        let back = ExternalStrongReference(
            property: "hub", referencedTypeNames: ["Hub"], position: SourcePosition(line: 2, column: 5))
        let index = FakeIndex(types: [
            "Plugin": ExternalTypeFacts(
                isReferenceType: true, strongReferences: [back], declaringPath: "Other/Plugin.swift")
        ])
        print("A2:", Analyzer().analyze(source: source, path: "Hub.swift", index: index).findings.map(\.rule))
    }
}
