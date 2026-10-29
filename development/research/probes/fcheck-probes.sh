#!/bin/zsh
# fcheck probes F1–F6, K1, K2. Needs FCHECK (path to the binary under test). Expected verdicts after the fixes in comments.
set -eu
: ${FCHECK:?path to fcheck}
R=$(mktemp -d /private/tmp/fcheck-probes.XXXXXX); trap 'rm -rf "$R"' EXIT
w() { printf "%b" "$2" > $R/$1.swift; }
# F1: twoLevels() leaks too (expected: findings in direct and twoLevels). F1b: implicit returns (same expectation).
w F1 "import Darwin\nfunc a() -> Int32 { return open(\"x\", O_RDONLY) }\nfunc b() -> Int32 { return a() }\nfunc direct() { let fd = a(); print(fd) }\nfunc twoLevels() { let fd = b(); print(fd) }\n"
w F1b "import Darwin\nfunc a() -> Int32 { open(\"x\", O_RDONLY) }\nfunc direct() { let fd = a(); print(fd) }\n"
# F2: the first descriptor leaks when fd is reassigned (expected: one finding at line 3).
w F2 "import Darwin\nfunc f() {\n    var fd = open(\"a\", O_RDONLY)\n    fd = open(\"b\", O_RDONLY)\n    close(fd)\n}\n"
# F3: login and signin must be treated alike (expected: neither reported).
w F3 "import Darwin\nfunc login(_ fd: Int32) {}\nfunc signin(_ fd: Int32) {}\nfunc viaLogin() { let fd = open(\"a\", O_RDONLY); login(fd) }\nfunc viaSignin() { let fd = open(\"a\", O_RDONLY); signin(fd) }\n"
# F4: Door.open() returns Bool and acquires nothing (expected: no finding).
w F4 "import Darwin\nstruct Store { func open() -> Int32 { return Darwin.open(\"x\", O_RDONLY) } }\nstruct Door { func open() -> Bool { return true } }\nfunc enter(door: Door) { let ok = door.open(); print(ok) }\n"
# F5: neither flushLogs() nor fsync of the file after rename flushes the directory (expected: three findings).
w F5 "import Darwin\nfunc flushLogs() {}\nfunc save(_ fd: Int32) {\n    write(fd, \"x\", 1)\n    fsync(fd)\n    rename(\"a.tmp\", \"a\")\n    flushLogs()\n}\nfunc saveFsyncFile(_ fd: Int32) {\n    write(fd, \"x\", 1)\n    fsync(fd)\n    rename(\"a.tmp\", \"a\")\n    fsync(fd)\n}\nfunc control(_ fd: Int32) {\n    write(fd, \"x\", 1)\n    fsync(fd)\n    rename(\"a.tmp\", \"a\")\n}\n"
# K1/F6: catch let error catches everything (expected: no finding, and never "line 0").
w K1 "import Darwin\nfunc g() throws {}\nfunc f() throws {\n    let fd = open(\"a\", O_RDONLY)\n    do { try g() } catch let error { print(error) }\n    close(fd)\n}\n"
# K2: for try await throws (expected: findings in f and control).
w K2 "import Darwin\nfunc f(_ s: AsyncThrowingStream<Int, any Error>) async throws {\n    let fd = open(\"a\", O_RDONLY)\n    for try await x in s { print(x) }\n    close(fd)\n}\nfunc control(_ s: AsyncThrowingStream<Int, any Error>) async throws {\n    let fd = open(\"a\", O_RDONLY)\n    var it = s.makeAsyncIterator()\n    while let x = try await it.next() { print(x) }\n    close(fd)\n}\n"
for f in F1 F1b F2 F3 F4 F5 K1 K2; do echo "--- $f"; $FCHECK analyze $R/$f.swift --no-cache 2>&1 | grep -E "warning|error" | sed "s|.*/||" | cut -c1-170; done
