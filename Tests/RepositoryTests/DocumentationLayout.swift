import Foundation

/// The documentation law of `development/WHITE-PAPER.md`, as functions over file names and text, so tests can break each
/// rule on purpose (roadmap 0001).
///
/// The same law as ask's, TerminalKit's and AemiProtobuf's: the white paper holds principles and is capped; an architecture
/// record is accepted or superseded, and a superseded one names a successor that names it back; a roadmap entry has a status
/// and blockers that exist and are not already done; the diary is the log and has a line budget. Added here: every record
/// is dated, and a local reference between records resolves.
enum DocumentationLayout {
    static let maximumWhitePaperLines = 200
    static let minimumWhitePaperLines = 20
    static let maximumDiaryLines = 256
    private static let roadmapStatuses: Set<String> = ["not-started", "in-progress", "done"]

    /// The repository root, found from this file's path (`Tests/RepositoryTests/<file>`).
    static let repositoryRoot: URL = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()

    /// The Markdown files directly in `development/<directory>`: name and text, sorted by name.
    static func documents(in directory: String) -> [(name: String, text: String)] {
        let url = repositoryRoot.appending(path: "development/\(directory)")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        return names.filter { $0.hasSuffix(".md") }.sorted()
            .compactMap { name in
                (try? String(contentsOf: url.appending(path: name), encoding: .utf8)).map { (name, $0) }
            }
    }

    static func lineCount(_ text: String) -> Int {
        text.split(separator: "\n", omittingEmptySubsequences: false).count - 1
    }

    /// The `key: value` lines between the opening and closing `---`.
    static func frontMatter(of text: String) -> [String: String] {
        var fields: [String: String] = [:]
        var inside = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line == "---" {
                if inside { break }
                inside = true
            } else if inside, let colon = line.firstIndex(of: ":") {
                fields[String(line[..<colon])] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
        }
        return fields
    }

    // MARK: - Rules

    static func whitePaperProblems(_ text: String) -> [String] {
        let lines = lineCount(text)
        if lines > maximumWhitePaperLines {
            return ["WHITE-PAPER.md: \(lines) lines, over the cap of \(maximumWhitePaperLines)"]
        }
        if lines < minimumWhitePaperLines {
            return ["WHITE-PAPER.md: \(lines) lines; a white paper that says nothing is not one"]
        }
        return []
    }

    /// What is wrong with a set of architecture records, one sentence each; empty when they are sound.
    static func adrProblems(in records: [(name: String, text: String)]) -> [String] {
        var problems: [String] = []
        let byNumber = numbered(records, kind: "record", problems: &problems)
        for record in records {
            guard let number = number(of: record.name), let fields = byNumber[number] else { continue }
            if let problem = dateProblem(record.name, fields) { problems.append(problem) }
            switch fields["status"] {
            case "accepted":
                continue
            case "superseded":
                guard let successor = fields["superseded-by"] else {
                    problems.append("\(record.name): superseded, but names no successor")
                    continue
                }
                guard let successorFields = byNumber[String(successor.drop(while: { !$0.isNumber }))] else {
                    problems.append("\(record.name): superseded by \(successor), which does not exist")
                    continue
                }
                if !successorFields["supersedes", default: ""].contains("ADR-\(number)") {
                    problems.append(
                        "\(record.name): superseded by \(successor), which does not name it in `supersedes:`")
                }
            case let other:
                problems.append("\(record.name): status is \(other ?? "missing"), not accepted or superseded")
            }
        }
        return problems
    }

    /// What is wrong with a set of roadmap entries: a missing date, a status outside the three, a blocker that does not
    /// exist, or an unfinished entry still waiting on finished work.
    static func roadmapProblems(in entries: [(name: String, text: String)]) -> [String] {
        var problems: [String] = []
        let byNumber = numbered(entries, kind: "entry", problems: &problems)
        for entry in entries {
            guard let number = number(of: entry.name), let fields = byNumber[number] else { continue }
            if let problem = dateProblem(entry.name, fields) { problems.append(problem) }
            guard let status = fields["status"], roadmapStatuses.contains(status) else {
                problems.append(
                    "\(entry.name): status is \(fields["status"] ?? "missing"), not not-started, in-progress or done")
                continue
            }
            for blocker in fourDigitNumbers(in: fields["blocked-by", default: ""]) {
                guard let blockerStatus = byNumber[blocker]?["status"] else {
                    problems.append("\(entry.name): blocked by \(blocker), which does not exist")
                    continue
                }
                if status != "done", blockerStatus == "done" {
                    problems.append("\(entry.name): still blocked by \(blocker), which is done")
                }
            }
        }
        return problems
    }

    /// Diary files whose name is not `YYYY-MM-DD-NN.md`, or that exceed the line budget.
    static func diaryProblems(in files: [(name: String, text: String)]) -> [String] {
        files.compactMap { file in
            guard file.name.hasSuffix(".md"), isDate(file.name.dropLast(3), withSequence: true) else {
                return "\(file.name): the name is not YYYY-MM-DD-NN.md"
            }
            let lines = lineCount(file.text)
            return lines > maximumDiaryLines
                ? "\(file.name): \(lines) lines, over the budget of \(maximumDiaryLines)" : nil
        }
    }

    /// References to records of this repository that do not resolve: `ADR-NNNN`, `roadmap NNNN` (either case) and
    /// research `<file>.md`. A reference qualified by a possessive (`its roadmap 0018`, `AemiProtobuf's roadmap 0015`,
    /// `ask's ADR-0128`) names another repository and is not checked.
    static func referenceProblems(
        in documents: [(name: String, text: String)], adrs: Set<String>, roadmap: Set<String>, research: Set<String>
    ) -> [String] {
        var problems: [String] = []
        for document in documents {
            let text = document.text
            for number in local(references: "ADR-", in: text) where !adrs.contains(number) {
                problems.append("\(document.name): ADR-\(number) does not exist")
            }
            for marker in ["roadmap ", "Roadmap "] {
                for number in local(references: marker, in: text) where !roadmap.contains(number) {
                    problems.append("\(document.name): \(marker)\(number) does not exist")
                }
            }
            for file in researchReferences(in: text) where !research.contains(file) {
                problems.append("\(document.name): research `\(file)` does not exist")
            }
        }
        return problems
    }

    // MARK: - Helpers

    private static func number(of name: String) -> String? {
        let digits = name.prefix(4)
        guard digits.count == 4, digits.allSatisfy(\.isNumber), name.dropFirst(4).first == "-" else { return nil }
        return String(digits)
    }

    /// Front matter by number; a name without a number, or a number used twice, is a problem.
    private static func numbered(
        _ documents: [(name: String, text: String)], kind: String, problems: inout [String]
    ) -> [String: [String: String]] {
        var byNumber: [String: [String: String]] = [:]
        for document in documents {
            guard let number = number(of: document.name) else {
                problems.append("\(document.name): the name does not start with a four-digit number and a dash")
                continue
            }
            if byNumber[number] != nil { problems.append("\(document.name): number \(number) is used by two \(kind)s") }
            byNumber[number] = frontMatter(of: document.text)
        }
        return byNumber
    }

    private static func dateProblem(_ name: String, _ fields: [String: String]) -> String? {
        guard let date = fields["date"], isDate(Substring(date), withSequence: false) else {
            return "\(name): `date:` is \(fields["date"].map { "`\($0)`" } ?? "missing"), not YYYY-MM-DD"
        }
        return nil
    }

    /// `YYYY-MM-DD`, or `YYYY-MM-DD-NN` with `withSequence`.
    private static func isDate(_ text: Substring, withSequence: Bool) -> Bool {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        let widths = withSequence ? [4, 2, 2, 2] : [4, 2, 2]
        return parts.count == widths.count
            && zip(parts, widths).allSatisfy { part, width in part.count == width && part.allSatisfy(\.isNumber) }
    }

    private static func fourDigitNumbers(in value: String) -> [String] {
        value.split(whereSeparator: { !$0.isNumber }).filter { $0.count == 4 }.map(String.init)
    }

    /// The four-digit numbers that follow `marker` in `text`, except where a possessive qualifies the reference.
    private static func local(references marker: String, in text: String) -> [String] {
        var numbers: [String] = []
        var rest = text[...]
        while let range = rest.range(of: marker) {
            let digits = rest[range.upperBound...].prefix(4)
            let before = text[..<range.lowerBound].suffix(4)
            let qualified = before.hasSuffix("'s ") || before.hasSuffix("’s ") || before.hasSuffix("its ")
            if digits.count == 4, digits.allSatisfy(\.isNumber), !qualified { numbers.append(String(digits)) }
            rest = rest[range.upperBound...]
        }
        return numbers
    }

    /// The file names in "research `<file>.md`", placeholders (a name with `<`) excepted.
    private static func researchReferences(in text: String) -> [String] {
        var files: [String] = []
        var rest = text[...]
        while let range = rest.range(of: "research `") {
            let after = rest[range.upperBound...]
            // `<file>.md` is a placeholder in prose, not a reference.
            if let close = after.firstIndex(of: "`"), after[..<close].hasSuffix(".md"), !after[..<close].contains("<") {
                files.append(String(after[..<close]))
            }
            rest = after
        }
        return files
    }
}
