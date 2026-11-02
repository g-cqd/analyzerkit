/// What a baseline needs of a finding: its stable identity.
public protocol Fingerprinted: Sendable {
    /// Stable identity for baselines and SARIF `partialFingerprints`.
    var fingerprint: String { get }
}

/// The identity of a finding: FNV-1a 64-bit over its identifying fields, in lower-case hexadecimal without padding.
///
/// Identity hashing, not security; a collision only over-baselines one finding. The format is part of every baseline
/// file on disk (ADR-0017), so it changes only with a baseline version.
public enum Fingerprint {
    /// FNV-1a 64-bit offset basis.
    public static let offsetBasis: UInt64 = 0xcbf2_9ce4_8422_2325
    /// FNV-1a 64-bit prime.
    public static let prime: UInt64 = 0x0000_0100_0000_01b3

    /// The FNV-1a hash of the UTF-8 bytes of `string`.
    public static func hash(_ string: String) -> UInt64 {
        var hash = offsetBasis
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= prime
        }
        return hash
    }

    /// A hash as a fingerprint string: lower-case hexadecimal, no leading zeros.
    public static func string(of hash: UInt64) -> String {
        String(hash, radix: 16, uppercase: false)
    }

    /// The fingerprint of one finding, from the fields every analyzer's finding has. `path` is the
    /// repository-relative spelling where the tool has one, so a developer's machine and a CI runner agree.
    public static func make(rule: String, path: String, line: Int, column: Int, message: String) -> String {
        string(of: hash("\(rule)|\(path)|\(line)|\(column)|\(message)"))
    }

    /// An identity that survives edits elsewhere in the file (ADR-0030): the rule, the path, the enclosing
    /// declaration's name (`Type.method(_:)`, or empty at file scope), the finding's source text with its whitespace
    /// collapsed, and which occurrence of that text it is within the declaration (0 for the first).
    ///
    /// ``make(rule:path:line:column:message:)`` changes whenever a line is added above a finding, so a baseline breaks
    /// on unrelated edits; this one changes only when the finding's own code, its declaration's name, or the order of
    /// identical texts in that declaration does. It is a second identity, written beside the first in SARIF
    /// (`partialFingerprints`, key `<tool>/anchored/v1`); baselines keep the first until they adopt a version that
    /// reads both.
    public static func anchored(rule: String, path: String, declaration: String, text: String, ordinal: Int) -> String {
        "a" + string(of: hash("\(rule)|\(path)|\(declaration)|\(normalized(text))|\(ordinal)"))
    }

    /// `text` with every run of whitespace replaced by one space, and none at either end.
    static func normalized(_ text: String) -> String {
        text.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" }).joined(separator: " ")
    }
}
