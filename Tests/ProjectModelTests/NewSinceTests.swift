import ProjectModel
import Testing

/// `--report-new-since` (ADR-0019, ADR-0028): out of a `--only` scope, the findings the base branch's baseline does not
/// hold are reported as new; the debt that was already there stays out of scope. From deadwood's `NewFindings`.
@Suite struct NewSinceTests {
    private struct Item: Equatable {
        let path: String
        let fingerprint: String
    }

    private let inScope = [Item(path: "/p/A.swift", fingerprint: "a")]
    private let outOfScope = [
        Item(path: "/p/B.swift", fingerprint: "b-old"), Item(path: "/p/C.swift", fingerprint: "c-new"),
    ]

    @Test func `an out-of-scope finding the baseline lacks is promoted, the rest stays out`() {
        let result = NewSince.promote(
            inScope: inScope, outOfScope: outOfScope, notIn: ["b-old"], fingerprint: \.fingerprint)
        #expect(result.reported == inScope + [outOfScope[1]])
        #expect(result.outOfScope == [outOfScope[0]])
        #expect(result.promoted == ["c-new"])
    }

    @Test func `a baseline that holds everything promotes nothing`() {
        let result = NewSince.promote(
            inScope: inScope, outOfScope: outOfScope, notIn: ["b-old", "c-new"], fingerprint: \.fingerprint)
        #expect(result.reported == inScope)
        #expect(result.promoted.isEmpty)
    }

    @Test func `a baseline matching none of the findings is flagged, an empty side never`() {
        #expect(NewSince.matchesNothing(inScope + outOfScope, in: ["zzz"], fingerprint: \.fingerprint))
        #expect(!NewSince.matchesNothing(inScope + outOfScope, in: ["a"], fingerprint: \.fingerprint))
        #expect(!NewSince.matchesNothing(inScope + outOfScope, in: [], fingerprint: \.fingerprint))
        #expect(!NewSince.matchesNothing([Item](), in: ["a"], fingerprint: \.fingerprint))
    }

    @Test func `the notes say how many were promoted and when the baseline matched nothing`() {
        #expect(
            NewSince.notes(promoted: 2, matchesNothing: false, baseline: "base.json") == [
                "2 finding(s) outside --only are new since base.json"
            ])
        #expect(NewSince.notes(promoted: 0, matchesNothing: false, baseline: "base.json").isEmpty)
        #expect(
            NewSince.notes(promoted: 0, matchesNothing: true, baseline: "base.json") == [
                "every out-of-scope finding is new since base.json; the baseline may not match this corpus "
                    + "(check --relative-to and the analyzed paths)"
            ])
    }
}
