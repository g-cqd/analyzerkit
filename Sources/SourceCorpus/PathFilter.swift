/// One exclusion rule for every tool (ADR-0008, roadmap 0005).
///
/// An entry without `*`, `?` or `[` is a substring of the path, as every tool has always read it: `Package.swift`
/// excludes `MyPackage.swift` too. An entry with them is a glob over the path relative to ``root``:
/// - `*` matches within one component, `?` one character, `[abc]`, `[a-z]` and `[!a]` (or `[^a]`) one character of a
///   set; a `[` without its `]` is literal.
/// - A component that is exactly `**` matches any number of components, none included; `**` inside a component is `*`.
/// - A leading `/` anchors the glob at the root; without it the glob matches at any depth, as if it began with `**/`.
/// - A trailing `/` matches directories only.
///
/// A directory that a glob matches excludes everything under it, so a tool that filters a list of files excludes what a
/// tool that prunes its walk never reaches. A path is asked about as a directory when it ends with `/`.
///
/// Matching reads UTF-8 bytes, with no regular expression; `?` and a set consume one whole Unicode scalar.
public struct PathFilter: Sendable {
    /// The directory a glob's path is relative to: the project's root, without a trailing `/`.
    public let root: String?
    /// The root as given and, when it differs, as it resolves: a walk asks about paths spelled through the root, an
    /// analyzer about canonical ones (``SourcePath``), and an anchored glob must match both.
    private let roots: [[UInt8]]
    private let substrings: [[UInt8]]
    private let globs: [Glob]

    /// - Parameters:
    ///   - entries: the configuration's `exclude` entries; empty ones are ignored.
    ///   - root: the project's root, absolute; nil when every path given is already relative.
    public init(_ entries: [String], root: String? = nil) {
        var root = root
        while let spelled = root, spelled.count > 1, spelled.hasSuffix("/") { root = String(spelled.dropLast()) }
        self.root = root
        if let root {
            let canonical = SourcePath.canonical(root)
            roots = canonical == root ? [Array(root.utf8)] : [Array(root.utf8), Array(canonical.utf8)]
        } else {
            roots = []
        }
        var substrings: [[UInt8]] = []
        var globs: [Glob] = []
        for entry in entries where !entry.isEmpty {
            if entry.utf8.contains(where: {
                $0 == UInt8(ascii: "*") || $0 == UInt8(ascii: "?") || $0 == UInt8(ascii: "[")
            }) {
                globs.append(Glob(entry))
            } else {
                substrings.append(Array(entry.utf8))
            }
        }
        self.substrings = substrings
        self.globs = globs
    }

    /// Whether no entry can exclude anything.
    public var isEmpty: Bool { substrings.isEmpty && globs.isEmpty }

    /// Whether `path` is excluded; a trailing `/` asks about a directory.
    /// - Complexity: O(*e* · *n* · *p*) for *e* entries, a path of *n* bytes and entries of at most *p* bytes; in
    ///   practice linear in the path.
    public func excludes(_ path: String) -> Bool {
        if isEmpty { return false }
        let bytes = Array(path.utf8)
        for needle in substrings where Self.contains(bytes, needle) { return true }
        guard !globs.isEmpty else { return false }
        let query = Query(bytes, roots: roots)
        return globs.contains { $0.matches(query) }
    }

    private static func contains(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
        guard needle.count <= haystack.count else { return false }
        let first = needle[0]
        var start = 0
        let last = haystack.count - needle.count
        while start <= last {
            if haystack[start] == first {
                var offset = 1
                while offset < needle.count, haystack[start + offset] == needle[offset] { offset += 1 }
                if offset == needle.count { return true }
            }
            start += 1
        }
        return false
    }
}

// MARK: - The path, as a glob reads it

extension PathFilter {
    /// A path split into components, relative to the root when it lies under it.
    fileprivate struct Query {
        let bytes: [UInt8]
        /// Byte ranges of the components, in order.
        let components: [Range<Int>]
        let isDirectory: Bool
        /// Whether the components are relative to the root, which anchored globs require.
        let isUnderRoot: Bool

        init(_ bytes: [UInt8], roots: [[UInt8]]) {
            self.bytes = bytes
            let slash = UInt8(ascii: "/")
            isDirectory = bytes.last == slash
            var start = 0
            var isUnderRoot = bytes.first != slash
            if bytes.first == slash {
                for rootBytes in roots {
                    if rootBytes == [slash] {
                        isUnderRoot = true
                        break
                    }
                    if bytes.count > rootBytes.count, bytes[rootBytes.count] == slash,
                        bytes[0..<rootBytes.count].elementsEqual(rootBytes)
                    {
                        start = rootBytes.count
                        isUnderRoot = true
                        break
                    }
                }
            }
            self.isUnderRoot = isUnderRoot
            var components: [Range<Int>] = []
            var componentStart = start
            for index in start...bytes.count where index == bytes.count || bytes[index] == slash {
                if index > componentStart { components.append(componentStart..<index) }
                componentStart = index + 1
            }
            self.components = components
        }
    }
}

// MARK: - Globs

extension PathFilter {
    fileprivate struct Glob: Sendable {
        enum Component: Sendable {
            /// `**`: any number of components.
            case anyComponents
            case pattern([Token])
        }

        enum Token: Sendable {
            case byte(UInt8)
            /// `?`: one scalar.
            case anyScalar
            /// `*`: any bytes within the component.
            case star
            /// `[…]`: one scalar in (or, negated, not in) the ranges.
            case set(ranges: [ClosedRange<UInt32>], negated: Bool)
        }

        let components: [Component]
        let directoriesOnly: Bool
        let anchored: Bool

        init(_ entry: String) {
            var text = Substring(entry)
            anchored = text.hasPrefix("/")
            if anchored { text = text.drop { $0 == "/" } }
            directoriesOnly = text.hasSuffix("/")
            var components: [Component] = anchored ? [] : [.anyComponents]
            for part in text.split(separator: "/", omittingEmptySubsequences: true) {
                components.append(part == "**" ? .anyComponents : .pattern(Self.tokens(part)))
            }
            self.components = components
        }

        private static func tokens(_ part: Substring) -> [Token] {
            let scalars = Array(part.unicodeScalars)
            var tokens: [Token] = []
            var index = 0
            while index < scalars.count {
                let scalar = scalars[index]
                switch scalar {
                case "*":
                    if case .star = tokens.last {} else { tokens.append(.star) }
                    index += 1
                case "?":
                    tokens.append(.anyScalar)
                    index += 1
                case "[":
                    if let (set, next) = Self.set(scalars, from: index + 1) {
                        tokens.append(set)
                        index = next
                    } else {
                        tokens.append(.byte(UInt8(ascii: "[")))
                        index += 1
                    }
                default:
                    tokens.append(contentsOf: String(scalar).utf8.map(Token.byte))
                    index += 1
                }
            }
            return tokens
        }

        /// The set opening before `start`, and the index after its `]`; nil when it never closes.
        private static func set(_ scalars: [Unicode.Scalar], from start: Int) -> (Token, Int)? {
            var index = start
            var negated = false
            if index < scalars.count, scalars[index] == "!" || scalars[index] == "^" {
                negated = true
                index += 1
            }
            var ranges: [ClosedRange<UInt32>] = []
            var first = true
            while index < scalars.count {
                let scalar = scalars[index]
                if scalar == "]", !first { return (.set(ranges: ranges, negated: negated), index + 1) }
                first = false
                if index + 2 < scalars.count, scalars[index + 1] == "-", scalars[index + 2] != "]" {
                    let low = scalar.value
                    let high = scalars[index + 2].value
                    ranges.append(min(low, high)...max(low, high))
                    index += 3
                } else {
                    ranges.append(scalar.value...scalar.value)
                    index += 1
                }
            }
            return nil
        }

        /// Whether the path, or one of the directories it lies in, matches.
        func matches(_ query: Query) -> Bool {
            if anchored, !query.isUnderRoot { return false }
            let count = query.components.count
            guard count > 0 else { return false }
            // Each directory prefix, then the whole path, which is a directory only when asked as one.
            for length in 1...count {
                let isDirectory = length < count || query.isDirectory
                if directoriesOnly, !isDirectory { continue }
                if matches(query, prefix: length) { return true }
            }
            return false
        }

        /// Wildcard matching over components: `**` as the star, a pattern component as one element. Greedy with one
        /// backtrack point, O(*p* · *n*) component matches.
        private func matches(_ query: Query, prefix length: Int) -> Bool {
            var pattern = 0
            var component = 0
            var starPattern = -1
            var starComponent = 0
            while component < length {
                if pattern < components.count, case .anyComponents = components[pattern] {
                    starPattern = pattern
                    starComponent = component
                    pattern += 1
                } else if pattern < components.count, case .pattern(let tokens) = components[pattern],
                    Self.matches(tokens, query.bytes, query.components[component])
                {
                    pattern += 1
                    component += 1
                } else if starPattern >= 0 {
                    pattern = starPattern + 1
                    starComponent += 1
                    component = starComponent
                } else {
                    return false
                }
            }
            while pattern < components.count, case .anyComponents = components[pattern] { pattern += 1 }
            return pattern == components.count
        }

        /// Wildcard matching within one component, over bytes; `?` and sets take a whole scalar, and a backtracking
        /// `*` resumes at a scalar boundary.
        private static func matches(_ tokens: [Token], _ bytes: [UInt8], _ range: Range<Int>) -> Bool {
            var token = 0
            var position = range.lowerBound
            var starToken = -1
            var starPosition = 0
            while position < range.upperBound {
                if token < tokens.count, let next = step(tokens[token], bytes, position, range.upperBound) {
                    if case .star = tokens[token] {
                        starToken = token
                        starPosition = position
                        token += 1
                    } else {
                        token += 1
                        position = next
                    }
                } else if starToken >= 0 {
                    token = starToken + 1
                    starPosition = scalarEnd(bytes, starPosition, range.upperBound)
                    position = starPosition
                } else {
                    return false
                }
            }
            while token < tokens.count, case .star = tokens[token] { token += 1 }
            return token == tokens.count
        }

        /// Where `token` leaves off when it matches at `position`, or nil; a star matches empty here.
        private static func step(_ token: Token, _ bytes: [UInt8], _ position: Int, _ end: Int) -> Int? {
            switch token {
            case .star:
                return position
            case .byte(let byte):
                return bytes[position] == byte ? position + 1 : nil
            case .anyScalar:
                return scalarEnd(bytes, position, end)
            case .set(let ranges, let negated):
                let next = scalarEnd(bytes, position, end)
                let value = scalarValue(bytes[position..<next])
                let inSet = ranges.contains { $0.contains(value) }
                return inSet != negated ? next : nil
            }
        }

        /// The index after the scalar that starts at `position`.
        private static func scalarEnd(_ bytes: [UInt8], _ position: Int, _ end: Int) -> Int {
            var next = position + 1
            while next < end, bytes[next] & 0xC0 == 0x80 { next += 1 }
            return next
        }

        private static func scalarValue(_ bytes: ArraySlice<UInt8>) -> UInt32 {
            var iterator = bytes.makeIterator()
            var decoder = UTF8()
            if case .scalarValue(let scalar) = decoder.decode(&iterator) { return scalar.value }
            return UInt32(bytes.first ?? 0)
        }
    }
}
