import Foundation
import SourceCorpus
import Testing

@Suite struct BoundedFileReaderTests {
    @Test func `a regular file under the cap is read whole`() throws {
        try Scratch.with { scratch in
            let path = try scratch.write("A.swift", "héllo")
            #expect(try BoundedFileReader.read(path: path, cap: 100) == Array("héllo".utf8))
        }
    }

    @Test func `an empty file reads as no bytes`() throws {
        try Scratch.with { scratch in
            let path = try scratch.write("Empty.swift", "")
            #expect(try BoundedFileReader.read(path: path).isEmpty)
        }
    }

    @Test(arguments: [(10, true), (9, false)])
    func `the cap is inclusive`(cap: Int, accepted: Bool) throws {
        try Scratch.with { scratch in
            let path = try scratch.write("A.swift", "0123456789")
            if accepted {
                #expect(try BoundedFileReader.read(path: path, cap: cap).count == 10)
            } else {
                #expect(throws: BoundedFileReader.Failure.tooLarge(cap: cap)) {
                    try BoundedFileReader.read(path: path, cap: cap)
                }
            }
        }
    }

    @Test func `a directory is not a regular file`() throws {
        try Scratch.with { scratch in
            #expect(throws: BoundedFileReader.Failure.notRegularFile) {
                try BoundedFileReader.read(path: scratch.root.path)
            }
        }
    }

    @Test func `a missing file is an io failure`() throws {
        try Scratch.with { scratch in
            #expect {
                try BoundedFileReader.read(path: scratch.path("Missing.swift"))
            } throws: { error in
                if case .io = error as? BoundedFileReader.Failure { true } else { false }
            }
        }
    }
}

@Suite struct ConfigurationReaderTests {
    @Test func `a regular file under the cap is read whole`() throws {
        try Scratch.with { scratch in
            let path = try scratch.write("c.json", "{}")
            #expect(try BoundedFileReader.readConfiguration(path: path) == Data("{}".utf8))
        }
    }

    @Test func `a missing path and a directory both read as not a regular file`() throws {
        try Scratch.with { scratch in
            #expect(throws: BoundedFileReader.ConfigurationFailure.unreadable("not a regular file")) {
                try BoundedFileReader.readConfiguration(path: scratch.path("missing.json"))
            }
            #expect(throws: BoundedFileReader.ConfigurationFailure.unreadable("not a regular file")) {
                try BoundedFileReader.readConfiguration(path: scratch.root.path)
            }
        }
    }

    @Test func `a file over the cap is refused with the detail the analyzers print`() throws {
        try Scratch.with { scratch in
            let path = try scratch.write("big.json", "0123456789")
            #expect(throws: BoundedFileReader.ConfigurationFailure.tooLarge(cap: 9)) {
                try BoundedFileReader.readConfiguration(path: path, cap: 9)
            }
            #expect(BoundedFileReader.ConfigurationFailure.tooLarge(cap: 9).invalidDetail == "exceeds 9 byte cap")
            #expect(BoundedFileReader.ConfigurationFailure.unreadable("x").invalidDetail == nil)
        }
    }

    @Test(.enabled(if: getuid() != 0))
    func `a regular file the system refuses reads as Foundation's error`() throws {
        try Scratch.with { scratch in
            let path = try scratch.write("locked.json", "{}")
            try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: path)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path) }
            #expect {
                try BoundedFileReader.readConfiguration(path: path)
            } throws: { error in
                guard case .unreadable(let text) = error as? BoundedFileReader.ConfigurationFailure else {
                    return false
                }
                return text != "not a regular file" && !text.isEmpty
            }
        }
    }
}
