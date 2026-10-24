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
