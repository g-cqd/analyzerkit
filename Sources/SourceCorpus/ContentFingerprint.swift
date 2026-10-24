internal import AemiKernel

/// A content fingerprint: identity for a cache entry, not security. A collision serves one file's stale
/// facts until its next real change.
public enum ContentFingerprint {
    /// `xxh64(bytes, seed: xxh64(salt))` in hex, then the byte count, so equal hashes of different lengths
    /// still differ. XXH64 runs at memory bandwidth, where the byte-at-a-time FNV-1a it replaces ran at
    /// roughly one byte per cycle, and this runs on every file of every run, cache hit or not.
    /// - Parameters:
    ///   - bytes: the file's contents.
    ///   - salt: whatever else the facts depend on, such as the configuration that selects code regions.
    /// - Complexity: O(*n*) in `bytes.count` plus O(*s*) in the salt.
    public static func of(_ bytes: [UInt8], salt: String = "") -> String {
        let seed = salt.isEmpty ? 0 : XXH64.hash(Array(salt.utf8))
        return String(XXH64.hash(bytes, seed: seed), radix: 16) + "-" + String(bytes.count)
    }
}
