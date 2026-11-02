/// The lines a change adds or rewrites, per file, read from a unified diff (`git diff`, `diff -u`) (ADR-0031).
///
/// Every analyzer's pull-request mode scopes by file (`--only`); a mutation tester, and an analyzer that wants to
/// report only on changed code, needs the lines. The diff is the change's own record: a CI system has it, git prints
/// it, nothing about the project has to run to read it.
///
/// What counts as changed is the new side: each `+` line of a hunk, by its line number in the new file. A hunk that
/// only removes lines changes no new line, but its file is still a changed file. A binary file, a pure rename and a
/// mode change are changed files without lines. A deleted file is listed in ``deleted`` and not in ``files``.
public struct ChangedLines: Sendable, Equatable {
    /// The changed files by new-side path, each with its changed lines as sorted, disjoint, non-adjacent ranges.
    public let files: [String: [ClosedRange<Int>]]
    /// The files the change deletes, by old-side path.
    public let deleted: Set<String>

    /// Why a diff could not be read. The input is refused whole: a diff read halfway would scope a run to part of a
    /// change and pass the rest unexamined.
    public struct Failure: Error, Sendable, Equatable, CustomStringConvertible {
        /// The 1-based line of the diff where reading stopped.
        public let line: Int
        public let reason: String
        public var description: String { "diff line \(line): \(reason)" }
    }

    /// What a diff may hold before it is refused.
    public struct Limits: Sendable, Equatable {
        public var maxBytes = 256 << 20
        public var maxFiles = 100_000
        public var maxLineNumber = 50_000_000
        public init() {}
    }

    public init(files: [String: [ClosedRange<Int>]], deleted: Set<String> = []) {
        self.files = files.mapValues(Self.merged)
        self.deleted = deleted
    }

    /// Reads a unified diff.
    /// - Parameters:
    ///   - strip: leading path components removed from each path, as `patch -p`; nil detects git's `a/` and `b/`
    ///     prefixes (stripped when every path has them, kept otherwise, as `git diff --no-prefix` writes them).
    /// - Throws: ``Failure`` on a malformed hunk header, a hunk shorter than its header says, an unterminated quoted
    ///   path, an absolute or `..` path, or input beyond ``Limits``.
    /// - Complexity: O(*n*) in the bytes of the diff.
    public static func parse(_ bytes: [UInt8], strip: Int? = nil, limits: Limits = Limits()) throws(Failure) -> Self {
        guard bytes.count <= limits.maxBytes else {
            throw Failure(line: 0, reason: "diff exceeds \(limits.maxBytes) bytes")
        }
        var sections: [Section] = []
        var current: Section?
        var hunk: (old: Int, new: Int, line: Int)?
        var number = 0
        var start = 0
        func finish() throws(Failure) {
            if let open = hunk, open.old > 0 || open.new > 0 {
                throw Failure(line: number, reason: "hunk ends \(open.old) old and \(open.new) new lines early")
            }
            hunk = nil
            if let section = current { sections.append(section) }
            current = nil
        }
        while start < bytes.count {
            var end = start
            while end < bytes.count, bytes[end] != 0x0A { end += 1 }
            number += 1
            var line = bytes[start..<end]
            start = end + 1
            if let open = hunk, open.old > 0 || open.new > 0 {
                guard let marker = line.first else {
                    // An empty line inside a hunk: a context line whose leading space an editor or mailer removed.
                    guard open.old > 0, open.new > 0 else {
                        throw Failure(line: number, reason: "empty line beyond the hunk's counts")
                    }
                    hunk = (open.old - 1, open.new - 1, open.line + 1)
                    continue
                }
                switch marker {
                case UInt8(ascii: " "):
                    guard open.old > 0, open.new > 0 else {
                        throw Failure(line: number, reason: "context line beyond the hunk's counts")
                    }
                    hunk = (open.old - 1, open.new - 1, open.line + 1)
                case UInt8(ascii: "+"):
                    guard open.new > 0 else {
                        throw Failure(line: number, reason: "added line beyond the hunk's counts")
                    }
                    current?.lines.append(open.line)
                    hunk = (open.old, open.new - 1, open.line + 1)
                case UInt8(ascii: "-"):
                    guard open.old > 0 else {
                        throw Failure(line: number, reason: "removed line beyond the hunk's counts")
                    }
                    hunk = (open.old - 1, open.new, open.line)
                case UInt8(ascii: "\\"): continue
                default: throw Failure(line: number, reason: "unexpected line inside a hunk")
                }
                continue
            }
            if line.last == 0x0D { line = line.dropLast() }
            if line.starts(with: Array("\\ ".utf8)) { continue }
            if line.starts(with: Array("diff ".utf8)) {
                try finish()
                current = Section(start: number)
                if line.starts(with: Array("diff --git ".utf8)) {
                    current?.gitPaths = try gitPaths(line.dropFirst(11), line: number)
                }
            } else if line.starts(with: Array("--- ".utf8)) {
                if current == nil || current?.oldPath != nil {
                    try finish()
                    current = Section(start: number)
                }
                current?.oldPath = try headerPath(line.dropFirst(4), line: number)
            } else if line.starts(with: Array("+++ ".utf8)), current?.oldPath != nil, current?.newPath == nil {
                current?.newPath = try headerPath(line.dropFirst(4), line: number)
            } else if line.starts(with: Array("@@ ".utf8)) {
                guard current?.newPath != nil else {
                    throw Failure(line: number, reason: "hunk before its file headers")
                }
                let header = try hunkHeader(line, line: number, limit: limits.maxLineNumber)
                // `+c,0`: nothing added; the next new line is c + 1, but no `+` line follows.
                hunk = (header.oldCount, header.newCount, header.newStart)
                current?.hunks += 1
            } else if line.starts(with: Array("rename to ".utf8)) {
                current?.renamedTo = try headerPath(line.dropFirst(10), line: number, header: false)
            } else if line.starts(with: Array("rename from ".utf8)) {
                current?.renamedFrom = try headerPath(line.dropFirst(12), line: number, header: false)
            } else if line.starts(with: Array("deleted file mode".utf8)) {
                current?.deletedFile = true
            } else if line.starts(with: Array("Binary files ".utf8))
                || line.starts(with: Array("GIT binary patch".utf8))
            {
                current?.binary = true
            }
        }
        try finish()
        return try assemble(sections, strip: strip, limits: limits)
    }

    /// True when the change touches `path` (a changed file, with or without changed lines).
    public func touches(_ path: String) -> Bool { files[path] != nil }

    /// True when any line of `lines` in `path` is a changed line.
    /// - Complexity: O(log *r*) in the ranges of the file.
    public func contains(_ path: String, lines: ClosedRange<Int>) -> Bool {
        guard let ranges = files[path] else { return false }
        var low = 0
        var high = ranges.count
        while low < high {
            let middle = (low + high) / 2
            if ranges[middle].upperBound < lines.lowerBound { low = middle + 1 } else { high = middle }
        }
        return low < ranges.count && ranges[low].lowerBound <= lines.upperBound
    }

    /// The change seen from a subdirectory of the diff's root: the files under `prefix` (a relative directory, without
    /// a trailing slash; empty for the root itself), with `prefix/` removed from their paths.
    public func rebased(onto prefix: String) -> Self {
        guard !prefix.isEmpty else { return self }
        let lead = prefix + "/"
        func strip(_ path: String) -> String? { path.hasPrefix(lead) ? String(path.dropFirst(lead.count)) : nil }
        var files: [String: [ClosedRange<Int>]] = [:]
        for (path, ranges) in self.files { if let inner = strip(path) { files[inner] = ranges } }
        return Self(files: files, deleted: Set(deleted.compactMap(strip)))
    }

    /// The number of changed lines over every file.
    public var lineCount: Int { files.values.reduce(0) { $0 + $1.reduce(0) { $0 + $1.count } } }

    // MARK: - Reading

    private struct Section {
        var start: Int
        var gitPaths: (old: String, new: String)?
        var oldPath: String?
        var newPath: String?
        var renamedFrom: String?
        var renamedTo: String?
        var deletedFile = false
        var binary = false
        var hunks = 0
        var lines: [Int] = []
    }

    private static func assemble(_ sections: [Section], strip: Int?, limits: Limits) throws(Failure) -> Self {
        // Every spelled path, to detect git's prefixes: `a/` on the old side and `b/` on the new, everywhere.
        var old: [String] = []
        var new: [String] = []
        for section in sections {
            if let paths = section.gitPaths {
                old.append(paths.old)
                new.append(paths.new)
            }
            if let path = section.oldPath, path != "/dev/null" { old.append(path) }
            if let path = section.newPath, path != "/dev/null" { new.append(path) }
        }
        let components =
            strip
            ?? ((old.allSatisfy { $0.hasPrefix("a/") } && new.allSatisfy { $0.hasPrefix("b/") } && !(old + new).isEmpty)
                ? 1 : 0)
        func stripped(_ path: String, line: Int) throws(Failure) -> String {
            var parts = path.split(separator: "/", omittingEmptySubsequences: false)
            guard parts.count > components else {
                throw Failure(line: line, reason: "path \(path) is shorter than -p\(components)")
            }
            parts.removeFirst(components)
            let result = parts.joined(separator: "/")
            guard !result.isEmpty, !result.hasPrefix("/"), !parts.contains(where: { $0 == ".." || $0.isEmpty }) else {
                throw Failure(line: line, reason: "path \(path) is absolute, empty or leaves the root")
            }
            return result
        }
        var files: [String: [Int]] = [:]
        var deleted: Set<String> = []
        for section in sections {
            let newSpelled = section.newPath ?? section.gitPaths?.new
            let oldSpelled = section.oldPath ?? section.gitPaths?.old
            if section.deletedFile || newSpelled == "/dev/null" {
                if let path = oldSpelled, path != "/dev/null" {
                    deleted.insert(try stripped(path, line: section.start))
                }
                continue
            }
            // A pure rename has `rename to` without `+++`: the new path is the rename's, which git spells unprefixed.
            let path: String
            if section.newPath == nil, let renamed = section.renamedTo {
                path = renamed
            } else if let spelled = newSpelled {
                path = try stripped(spelled, line: section.start)
            } else {
                continue
            }
            files[path, default: []] += section.lines
            guard files.count <= limits.maxFiles else {
                throw Failure(line: section.start, reason: "diff names more than \(limits.maxFiles) files")
            }
        }
        return Self(files: files.mapValues(ranges), deleted: deleted)
    }

    /// Sorted line numbers as maximal ranges.
    private static func ranges(_ lines: [Int]) -> [ClosedRange<Int>] {
        var result: [ClosedRange<Int>] = []
        for line in lines.sorted() {
            if let last = result.last, line <= last.upperBound + 1 {
                result[result.count - 1] = last.lowerBound...max(last.upperBound, line)
            } else {
                result.append(line...line)
            }
        }
        return result
    }

    private static func merged(_ ranges: [ClosedRange<Int>]) -> [ClosedRange<Int>] {
        var result: [ClosedRange<Int>] = []
        for range in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = result.last, range.lowerBound <= last.upperBound + 1 {
                result[result.count - 1] = last.lowerBound...max(last.upperBound, range.upperBound)
            } else {
                result.append(range)
            }
        }
        return result
    }

    /// `@@ -a[,b] +c[,d] @@ …`.
    private static func hunkHeader(_ line: ArraySlice<UInt8>, line number: Int, limit: Int) throws(Failure)
        -> (oldCount: Int, newStart: Int, newCount: Int)
    {
        let text = String(decoding: line, as: UTF8.self)
        let fields = text.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true)
        guard fields.count >= 4, fields[0] == "@@", fields[3].hasPrefix("@@"), fields[1].hasPrefix("-"),
            fields[2].hasPrefix("+")
        else { throw Failure(line: number, reason: "malformed hunk header") }
        func range(_ field: Substring) throws(Failure) -> (start: Int, count: Int) {
            let parts = field.dropFirst().split(separator: ",", omittingEmptySubsequences: false)
            guard (1...2).contains(parts.count), let start = Int(parts[0]), start >= 0, start <= limit else {
                throw Failure(line: number, reason: "malformed hunk range \(field)")
            }
            guard parts.count == 2 else { return (start, 1) }
            guard let count = Int(parts[1]), count >= 0, count <= limit else {
                throw Failure(line: number, reason: "malformed hunk count \(field)")
            }
            return (start, count)
        }
        let old = try range(fields[1])
        let new = try range(fields[2])
        return (old.count, new.start, new.count)
    }

    /// The path of a `---`/`+++` header (`header`) or a `rename` line: quoted with C escapes, or plain up to a tab
    /// (`diff -u` puts the time after one).
    private static func headerPath(_ field: ArraySlice<UInt8>, line: Int, header: Bool = true) throws(Failure)
        -> String
    {
        if field.first == UInt8(ascii: "\"") {
            let (path, _) = try quoted(field, line: line)
            return path
        }
        var bytes = field
        if header, let tab = bytes.firstIndex(of: 0x09) { bytes = bytes[..<tab] }
        guard !bytes.isEmpty else { throw Failure(line: line, reason: "empty path") }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// The two paths of `diff --git a/x b/y`, quoted or not. Unquoted paths with spaces are ambiguous; git writes the
    /// same path twice for those unless renamed, so an even split at the middle space is tried first.
    private static func gitPaths(_ field: ArraySlice<UInt8>, line: Int) throws(Failure) -> (old: String, new: String) {
        if field.first == UInt8(ascii: "\"") {
            let (old, rest) = try quoted(field, line: line)
            let tail = rest.drop { $0 == UInt8(ascii: " ") }
            let new =
                tail.first == UInt8(ascii: "\"")
                ? try quoted(tail, line: line).0 : String(decoding: tail, as: UTF8.self)
            return (old, new)
        }
        if let space = field.indices.first(where: {
            field[$0] == UInt8(ascii: " ") && $0 + 1 < field.endIndex && field[$0 + 1] == UInt8(ascii: "\"")
        }) {
            return (String(decoding: field[..<space], as: UTF8.self), try quoted(field[(space + 1)...], line: line).0)
        }
        let text = String(decoding: field, as: UTF8.self)
        let spaces = text.indices.filter { text[$0] == " " }
        for space in spaces {
            let old = text[..<space]
            let new = text[text.index(after: space)...]
            if old.dropFirst(2) == new.dropFirst(2) { return (String(old), String(new)) }
        }
        guard let first = spaces.first else { throw Failure(line: line, reason: "diff --git line without two paths") }
        return (String(text[..<first]), String(text[text.index(after: first)...]))
    }

    /// A C-quoted string at the start of `field` and what follows it.
    private static func quoted(_ field: ArraySlice<UInt8>, line: Int) throws(Failure) -> (String, ArraySlice<UInt8>) {
        var bytes: [UInt8] = []
        var index = field.index(after: field.startIndex)
        while index < field.endIndex {
            let byte = field[index]
            if byte == UInt8(ascii: "\"") { return (String(decoding: bytes, as: UTF8.self), field[(index + 1)...]) }
            if byte == UInt8(ascii: "\\") {
                index += 1
                guard index < field.endIndex else { break }
                let escaped = field[index]
                switch escaped {
                case UInt8(ascii: "n"): bytes.append(0x0A)
                case UInt8(ascii: "t"): bytes.append(0x09)
                case UInt8(ascii: "r"): bytes.append(0x0D)
                case UInt8(ascii: "a"): bytes.append(0x07)
                case UInt8(ascii: "b"): bytes.append(0x08)
                case UInt8(ascii: "f"): bytes.append(0x0C)
                case UInt8(ascii: "v"): bytes.append(0x0B)
                case UInt8(ascii: "0")...UInt8(ascii: "7"):
                    var value = 0
                    var digits = 0
                    while digits < 3, index < field.endIndex,
                        (UInt8(ascii: "0")...UInt8(ascii: "7")).contains(field[index])
                    {
                        value = value * 8 + Int(field[index] - UInt8(ascii: "0"))
                        index += 1
                        digits += 1
                    }
                    guard value <= 255 else { throw Failure(line: line, reason: "octal escape beyond a byte") }
                    bytes.append(UInt8(value))
                    continue
                default: bytes.append(escaped)
                }
                index += 1
                continue
            }
            bytes.append(byte)
            index += 1
        }
        throw Failure(line: line, reason: "unterminated quoted path")
    }
}
