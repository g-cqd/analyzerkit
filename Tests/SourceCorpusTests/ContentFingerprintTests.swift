import SourceCorpus
import Testing

@Suite struct ContentFingerprintTests {
    @Test func `equal content gives an equal fingerprint`() {
        #expect(ContentFingerprint.of(Array("abc".utf8)) == ContentFingerprint.of(Array("abc".utf8)))
    }

    @Test func `one changed byte changes the fingerprint`() {
        #expect(ContentFingerprint.of(Array("abc".utf8)) != ContentFingerprint.of(Array("abd".utf8)))
    }

    @Test func `the salt changes the fingerprint and an empty salt is none`() {
        let bytes = Array("abc".utf8)
        #expect(ContentFingerprint.of(bytes, salt: "DEBUG") != ContentFingerprint.of(bytes))
        #expect(ContentFingerprint.of(bytes, salt: "DEBUG") != ContentFingerprint.of(bytes, salt: "RELEASE"))
        #expect(ContentFingerprint.of(bytes, salt: "") == ContentFingerprint.of(bytes))
    }

    @Test func `the length is part of the fingerprint`() {
        #expect(ContentFingerprint.of([]).hasSuffix("-0"))
        #expect(ContentFingerprint.of([0, 0]).hasSuffix("-2"))
    }
}
