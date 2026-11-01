import ReportSupport
import Testing

#if canImport(FoundationEssentials)
    import FoundationEssentials
#else
    import Foundation
#endif

private struct Probe: Fingerprinted, Equatable {
    let identity: String
    var fingerprint: String { Fingerprint.make(rule: "r", path: identity, line: 1, column: 1, message: "m") }
}

@Suite struct FingerprintTests {
    /// The values arcleak, deadwood and dolly wrote before this type existed: baselines on disk must keep matching.
    @Test func `the fingerprint is the lower-case FNV-1a of rule, path, line, column and message`() {
        #expect(Fingerprint.hash("") == 0xcbf2_9ce4_8422_2325)
        #expect(Fingerprint.hash("a") == 0xaf63_dc4c_8601_ec8c)
        #expect(Fingerprint.hash("foobar") == 0x8594_4171_f739_67e8)
        let text = "unused-function|/repo/Sources/A.swift|12|3|function 'f' is never referenced"
        #expect(
            Fingerprint.make(
                rule: "unused-function",
                path: "/repo/Sources/A.swift",
                line: 12,
                column: 3,
                message: "function 'f' is never referenced"
            ) == String(Fingerprint.hash(text), radix: 16)
        )
    }

    @Test func `a hash with leading zero bits is not padded`() {
        // arcleak and deadwood printed `String(hash, radix: 16)`; a padded form would orphan their baselines.
        #expect(Fingerprint.string(of: 0xff) == "ff")
    }
}

@Suite struct BaselineTests {
    @Test func `a baseline keeps what it contains and sets the rest apart`() {
        let known = Probe(identity: "a"), fresh = Probe(identity: "b")
        let baseline = Baseline<Probe>(findings: [known])
        let (kept, baselined) = baseline.filter([known, fresh])
        #expect(kept == [fresh] && baselined == [known])
        #expect(baseline.contains(known) && !baseline.contains(fresh))
    }

    @Test func `the file is sorted, unique, versioned, and read back to the same set`() throws {
        let baseline = Baseline<Probe>(fingerprints: ["b", "a", "b"])
        let data = try baseline.encoded(tool: "t")
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\"version\" : 1") && text.contains("\"tool\" : \"t\""))
        #expect(try Baseline<Probe>(decoding: data) == baseline)
    }

    @Test func `a file without a version, with another version, or that is not a baseline is refused with its reason`()
    {
        func failure(_ json: String) -> String? {
            do { _ = try Baseline<Probe>(decoding: Data(json.utf8)); return nil } catch { return error.description }
        }
        #expect(failure(#"{"fingerprints":[],"tool":"t"}"#) == "the baseline has no version")
        #expect(failure(#"{"fingerprints":[],"tool":"t","version":2}"#) == "unsupported baseline version 2")
        #expect(failure("[]")?.contains("typeMismatch") == true)
    }
}
