import ProjectModel
import Testing

/// `ChangedLines` (ADR-0031): the new-side lines of a unified diff, per file, for changed-line scopes.
@Suite struct ChangedLinesTests {
    private func parse(_ text: String, strip: Int? = nil) throws -> ChangedLines {
        try ChangedLines.parse(Array(text.utf8), strip: strip)
    }

    @Test func `added lines are counted on the new side, context and removals move the count correctly`() throws {
        let diff = """
            diff --git a/Sources/A.swift b/Sources/A.swift
            index 1111111..2222222 100644
            --- a/Sources/A.swift
            +++ b/Sources/A.swift
            @@ -10,5 +10,6 @@ struct A {
                 let a = 1
            -    let b = 2
            +    let b = 3
            +    let c = 4
                 let d = 5
                 let e = 6
                 let f = 7
            @@ -40,2 +41,2 @@
            -old
            +new
             same

            """
        let changed = try parse(diff)
        #expect(changed.files == ["Sources/A.swift": [11...12, 41...41]])
        #expect(changed.contains("Sources/A.swift", lines: 12...20))
        #expect(!changed.contains("Sources/A.swift", lines: 13...40))
        #expect(changed.contains("Sources/A.swift", lines: 30...41))
        #expect(changed.lineCount == 3)
    }

    @Test func `zero-context diffs, pure deletions and new files`() throws {
        let diff = """
            diff --git a/A.swift b/A.swift
            --- a/A.swift
            +++ b/A.swift
            @@ -5,2 +4,0 @@ func f() {
            -    a()
            -    b()
            @@ -20 +18,2 @@
            -x
            +y
            +z
            diff --git a/New.swift b/New.swift
            new file mode 100644
            --- /dev/null
            +++ b/New.swift
            @@ -0,0 +1,2 @@
            +let a = 1
            +let b = 2
            diff --git a/Gone.swift b/Gone.swift
            deleted file mode 100644
            --- a/Gone.swift
            +++ /dev/null
            @@ -1 +0,0 @@
            -let gone = 1

            """
        let changed = try parse(diff)
        #expect(changed.files == ["A.swift": [18...19], "New.swift": [1...2]])
        #expect(changed.deleted == ["Gone.swift"])
        #expect(changed.touches("A.swift"))
        #expect(!changed.touches("Gone.swift"))
    }

    @Test func `renames, binaries and mode changes are changed files without lines`() throws {
        let diff = """
            diff --git a/Old.swift b/Moved.swift
            similarity index 100%
            rename from Old.swift
            rename to Moved.swift
            diff --git a/Icon.png b/Icon.png
            index 1..2 100644
            Binary files a/Icon.png and b/Icon.png differ
            diff --git a/run.sh b/run.sh
            old mode 100644
            new mode 100755

            """
        let changed = try parse(diff)
        #expect(changed.files == ["Moved.swift": [], "Icon.png": [], "run.sh": []])
    }

    @Test func `quoted paths are decoded and the a and b prefixes detected`() throws {
        let diff = """
            diff --git "a/caf\\303\\251 x.swift" "b/caf\\303\\251 x.swift"
            --- "a/caf\\303\\251 x.swift"
            +++ "b/caf\\303\\251 x.swift"
            @@ -1 +1 @@
            -a
            +b

            """
        #expect(try parse(diff).files == ["café x.swift": [1...1]])
        let unprefixed = """
            --- Sources/A.swift\t2026-11-02 10:00:00
            +++ Sources/A.swift\t2026-11-02 10:01:00
            @@ -1 +1 @@
            -a
            +b
            --- Sources/B.swift
            +++ Sources/B.swift
            @@ -3,0 +4 @@
            +c

            """
        #expect(try parse(unprefixed).files == ["Sources/A.swift": [1...1], "Sources/B.swift": [4...4]])
        #expect(try parse(unprefixed, strip: 1).files == ["A.swift": [1...1], "B.swift": [4...4]])
    }

    @Test func `content lines that look like headers stay content inside a hunk`() throws {
        let diff = """
            diff --git a/A.swift b/A.swift
            --- a/A.swift
            +++ b/A.swift
            @@ -1,2 +1,2 @@
            ---- a comment
            +++ b plus
             diff --git kept

            """
        #expect(try parse(diff).files == ["A.swift": [1...1]])
    }

    @Test func `a short hunk, a malformed header, a path leaving the root and oversize input are refused`() {
        let short = "--- a/A.swift\n+++ b/A.swift\n@@ -1,3 +1,3 @@\n-a\n+b\n"
        #expect(throws: ChangedLines.Failure.self) { try parse(short) }
        let malformed = "--- a/A.swift\n+++ b/A.swift\n@@ -x +1 @@\n+b\n"
        #expect(throws: ChangedLines.Failure.self) { try parse(malformed) }
        let escaping = "--- a/../A.swift\n+++ b/../A.swift\n@@ -1 +1 @@\n-a\n+b\n"
        #expect(throws: ChangedLines.Failure.self) { try parse(escaping) }
        let absolute = "--- /tmp/A.swift\n+++ /tmp/A.swift\n@@ -1 +1 @@\n-a\n+b\n"
        #expect(throws: ChangedLines.Failure.self) { try parse(absolute) }
        var limits = ChangedLines.Limits()
        limits.maxBytes = 8
        #expect(throws: ChangedLines.Failure.self) { try ChangedLines.parse(Array(short.utf8), limits: limits) }
    }

    @Test func `an empty diff changes nothing, and rebasing keeps a subdirectory`() throws {
        #expect(try parse("").files.isEmpty)
        let changed = ChangedLines(files: ["App/Sources/A.swift": [3...4, 1...2], "Other/B.swift": [1...1]])
        #expect(changed.files["App/Sources/A.swift"] == [1...4])
        #expect(changed.rebased(onto: "App").files == ["Sources/A.swift": [1...4]])
        #expect(changed.rebased(onto: "").files.count == 2)
    }
}
