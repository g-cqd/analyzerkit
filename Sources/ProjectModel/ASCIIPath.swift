/// Byte-wise forms of the path and header conventions, for ASCII input. Each returns nil when the input is not plain
/// ASCII, and the caller then compares characters as before: in ASCII without a carriage return, every character is
/// one byte, so both give the same answer.
enum ASCIIPath {
    private static let slash = UInt8(ascii: "/")

    static func isTestPath(_ path: String.UTF8View) -> Bool? {
        guard isASCII(path) else { return nil }
        var found = false
        components(of: path) { component in
            found =
                component.elementsEqual("Tests".utf8)
                || (hasSuffix(component, "Tests") && !component.contains(UInt8(ascii: ".")))
            return found
        }
        return found || hasSuffix(path[...], "Tests.swift") || hasSuffix(path[...], "Test.swift")
    }

    static func isGeneratedPath(_ path: String.UTF8View) -> Bool? {
        guard isASCII(path) else { return nil }
        if hasSuffix(path[...], ".generated.swift") { return true }
        var found = false
        components(of: path) { component in
            found = component.elementsEqual("Generated".utf8)
            return found
        }
        return found
    }

    /// Whether the first ``GeneratedCode/headerLength`` characters hold a marker, ignoring ASCII letter case.
    ///
    /// The byte after the limit is checked too: when it is ASCII, it cannot extend the last character inside the limit.
    static func hasMarker(_ header: some Collection<UInt8>, markers: [String]) -> Bool? {
        let window = header.prefix(GeneratedCode.headerLength + 1)
        guard isASCII(window), !window.contains(0x0D) else { return nil }
        let head = Array(window.prefix(GeneratedCode.headerLength))
        return markers.contains { marker in
            let needle = Array(marker.utf8)
            guard let first = needle.first else { return true }
            guard needle.count <= head.count else { return false }
            for offset in 0...(head.count - needle.count) where lowered(head[offset]) == first {
                var index = 1
                while index < needle.count, lowered(head[offset + index]) == needle[index] { index += 1 }
                if index == needle.count { return true }
            }
            return false
        }
    }

    /// Calls `body` with each `/`-separated component, empty ones included, until it returns true.
    private static func components(of path: String.UTF8View, _ body: (Substring.UTF8View) -> Bool) {
        var start = path.startIndex
        var index = path.startIndex
        while true {
            if index == path.endIndex || path[index] == slash {
                if body(Substring(path[start..<index]).utf8) || index == path.endIndex { return }
                start = path.index(after: index)
            }
            index = path.index(after: index)
        }
    }

    private static func lowered(_ byte: UInt8) -> UInt8 {
        (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte) ? byte | 0x20 : byte
    }

    private static func isASCII(_ bytes: some Collection<UInt8>) -> Bool {
        var combined: UInt8 = 0
        for byte in bytes { combined |= byte }
        return combined < 0x80
    }

    private static func hasSuffix(_ bytes: some BidirectionalCollection<UInt8>, _ text: String) -> Bool {
        var index = bytes.endIndex
        for byte in text.utf8.reversed() {
            guard index != bytes.startIndex else { return false }
            index = bytes.index(before: index)
            guard bytes[index] == byte else { return false }
        }
        return true
    }
}
