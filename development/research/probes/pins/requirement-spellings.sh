#!/bin/zsh
# ADR-0025's probe: does SwiftPM accept indexstore-db required in two spellings? Builds throwaway packages under $1
# (default /tmp/pinprobe) and resolves each case. C1 revision `main` vs branch `release/6.4.x`; C2 the same commit as a
# revision and as a branch; C3 the branch twice; C4 the revision twice; C5 two branches; C6 C1 with the root also
# requiring the revision. Results on 2026-10-30: C3 and C4 resolve, the others fail.
set -eu
D=${1:-/tmp/pinprobe}; rm -rf $D; mkdir -p $D; cd $D
MAIN=0390867818c28241af4650eb4ef29af5669335a3; R64=64aa0b26913249c4e7c21d351a215fba02702003
mk() { mkdir -p $1/Sources/$1; echo "public let x = 1" > $1/Sources/$1/a.swift; cat > $1/Package.swift <<M
// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "$1", platforms: [.macOS(.v15)],
  products: [.library(name: "$1", targets: ["$1"])],
  dependencies: [.package(url: "https://github.com/swiftlang/indexstore-db.git", $2)],
  targets: [.target(name: "$1", dependencies: [.product(name: "IndexStoreDB", package: "indexstore-db")])])
M
}
root() { mkdir -p $1/Sources/$1; echo "import $2; import $3" > $1/Sources/$1/main.swift; cat > $1/Package.swift <<M
// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "$1", platforms: [.macOS(.v15)],
  dependencies: [.package(path: "../$2"), .package(path: "../$3")$4],
  targets: [.executableTarget(name: "$1", dependencies: ["$2", "$3"])])
M
}
mk RevMain "revision: \"$MAIN\""; mk Rev64 "revision: \"$R64\""; mk Rev64b "revision: \"$R64\""
mk Branch64 'branch: "release/6.4.x"'; mk Branch64b 'branch: "release/6.4.x"'; mk BranchMain 'branch: "main"'
root C1 RevMain Branch64 ""; root C2 Rev64 Branch64 ""; root C3 Branch64 Branch64b ""; root C4 Rev64 Rev64b ""
root C5 BranchMain Branch64 ""
root C6 RevMain Branch64 ", .package(url: \"https://github.com/swiftlang/indexstore-db.git\", revision: \"$MAIN\")"
for c in C1 C2 C3 C4 C5 C6; do
  (cd $c; if swift package resolve > ../$c.log 2>&1; then echo "$c resolves"; else echo "$c fails: $(grep -m1 error ../$c.log)"; fi)
done
