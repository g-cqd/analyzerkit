import AemiProtobuf
import AemiProtobufCore
import CorpusScan
import Foundation
import Suppression
import Testing

/// The directive as arcleak, deadwood and dolly cached it before the type moved here: their payloads on disk keep
/// reading, and the bytes stay what they were (a cache hit never depends on which build wrote it).
@Suite struct DirectiveCodingTests {
    private enum Rule: String, Hashable, Sendable, Codable, Comparable {
        case alpha, beta
        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    private typealias Sample = Directive<Rule>

    @Test
    func `the fields are the rules sorted and unique, the kind's name, the line, and the reason when there is one`()
        throws
    {
        let directive = Sample(rules: [.beta, .alpha, .beta], kind: .acceptThis, line: 7, reason: "why")
        var expected = WireWriter()
        expected.field(1, "alpha")
        expected.field(1, "beta")
        expected.field(2, "acceptThis")
        expected.field(3, 7)
        expected.field(4, "why")
        #expect(try ProtobufEncoder().encodeToBytes(directive) == expected.bytes)

        var bare = WireWriter()
        bare.field(2, "regionEnable")
        bare.field(3, 0)
        #expect(
            try ProtobufEncoder().encodeToBytes(Sample(rules: [], kind: .regionEnable, line: 0, reason: nil))
                == bare.bytes
        )
    }

    @Test func `a directive reads back with its rules in order and without repeats`() throws {
        let directive = Sample(rules: [.beta, .alpha, .beta], kind: .regionDisable, line: 3, reason: nil)
        let bytes = try ProtobufEncoder().encodeToBytes(directive)
        let read = try ProtobufDecoder().decode(Sample.self, fromBytes: bytes)
        #expect(read == Sample(rules: [.alpha, .beta], kind: .regionDisable, line: 3, reason: nil))
        #expect(read.covers(.alpha) && !Sample(rules: [.alpha], kind: .accept, line: 1, reason: nil).covers(.beta))
    }

    @Test func `every kind keeps its name, and a name this build does not know fails the decode`() throws {
        for kind in [DirectiveKind.acceptThis, .acceptNext, .accept, .regionDisable, .regionEnable] {
            let bytes = try ProtobufEncoder().encodeToBytes(Sample(rules: [], kind: kind, line: 1, reason: nil))
            #expect(try ProtobufDecoder().decode(Sample.self, fromBytes: bytes).kind == kind)
        }
        var unknown = WireWriter()
        unknown.field(2, "futureKind")
        #expect(throws: (any Error).self) { try ProtobufDecoder().decode(Sample.self, fromBytes: unknown.bytes) }
    }

    @Test func `the JSON form round-trips`() throws {
        let directive = Sample(rules: [.alpha], kind: .acceptNext, line: 9, reason: "r")
        let data = try JSONEncoder().encode(directive)
        #expect(try JSONDecoder().decode(Sample.self, from: data) == directive)
    }
}
