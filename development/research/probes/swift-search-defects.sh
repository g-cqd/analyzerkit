#!/bin/zsh
# Roadmap 0057: swift-search's four defects (its diary 2026-10-29-01, probes 2, 3, 4, 6), probed in deadwood and arcleak.
# Needs ARCLEAK and DEADWOOD (paths to the binaries under test). Fixtures live under $TMPDIR, which macOS spells
# /var/folders/... while the compiler records /private/var/... in the store.
set -eu
: ${ARCLEAK:?path to arcleak} ${DEADWOOD:?path to deadwood}
SWIFTC=$(xcrun --find swiftc); SDK=$(xcrun --show-sdk-path)
R=$(mktemp -d "${TMPDIR:-/tmp}/defects.XXXXXX"); trap 'rm -rf "$R"' EXIT
mods=$R/mods; mkdir -p $mods
mk() { mkdir -p "$(dirname "$1")"; printf "%b" "$2" > "$1"; }
ix() { local dir=$1 store=$2 mod=$3; shift 3; (cd $dir && $SWIFTC -sdk $SDK -index-store-path $store -index-ignore-system-modules \
  -module-name $mod -parse-as-library -emit-module -emit-module-path $mods/$mod.swiftmodule "$@" >/dev/null 2>&1); }
run() { echo "--- $1"; shift; "$@" --no-cache 2>&1 | grep -vE '^\s*$' | cut -c1-220 | head -${LINES_SHOWN:-6}; }
echo "root as given: $R"; echo "root as recorded: $(cd $R && pwd -P)"

# 1. /var against /private/var: the store records the resolved spelling; the tools are given the /var one.
mk $R/p1/Sources/App/Hub.swift "class Hub {\n    var plugin: Plugin?\n    init() {}\n}\n"
mk $R/p1/Sources/App/Plugin.swift "class Plugin {\n    var hub: Hub?\n    init() {}\n}\n"
mk $R/p1/Sources/App/Dead.swift "func neverCalled() -> Int {\n    0\n}\n\nfunc called() -> Int {\n    1\n}\n\nlet value = called()\n"
ix $R/p1 $R/p1/store App Sources/App/Hub.swift Sources/App/Plugin.swift Sources/App/Dead.swift
strings $R/p1/store/v5/units/* 2>/dev/null | grep -m1 -o '/[^ ]*/p1/Sources/App/Hub.swift' | sed 's/^/    the store records: /'
run "1 arcleak, /var spelling, index: the cycle, the index used" $ARCLEAK analyze $R/p1/Sources --index-store-path $R/p1/store --verbose
run "1 deadwood, /var spelling, index: neverCalled only, the index used" $DEADWOOD analyze $R/p1/Sources --index-store-path $R/p1/store --verbose

# 3. CRLF. (a) Findings after CRLF lines: line numbers and the snippet the text report prints.
mk $R/p3/Sources/App/Cycle.swift "// one\r\n// two\r\n// three\r\nclass Hub {\r\n    var plugin: Plugin?\r\n}\r\nclass Plugin {\r\n    var hub: Hub?\r\n}\r\n"
mk $R/p3/Sources/App/Dead.swift "// one\r\n// two\r\n// three\r\nfunc neverCalled() -> Int {\r\n    0\r\n}\r\n"
LINES_SHOWN=12 run "3a arcleak on CRLF: the cycle at lines 4-8, snippets from those lines" $ARCLEAK analyze $R/p3/Sources
LINES_SHOWN=12 run "3a deadwood on CRLF: neverCalled at line 4" $DEADWOOD analyze $R/p3/Sources
# (b) A CRLF --only-from scope file naming both files: every finding stays in scope.
printf "%s\r\n%s\r\n" "$R/p3/Sources/App/Cycle.swift" "$R/p3/Sources/App/Dead.swift" > $R/p3/scope-crlf.txt
printf "%s\n%s\n" "$R/p3/Sources/App/Cycle.swift" "$R/p3/Sources/App/Dead.swift" > $R/p3/scope-lf.txt
for tool in $ARCLEAK $DEADWOOD; do
  for scope in lf crlf; do
    run "3b $(basename $tool) --only-from $scope scope file" $tool analyze $R/p3/Sources --only-from $R/p3/scope-$scope.txt
  done
done

# 4. A public property never read, beside a function of the same base name that is called (swift-search's
# SourcePosition.location and converter.location(for:)).
mk $R/p4/Sources/App/Position.swift "public struct Position {\n    public let line: Int\n    public var location: String { \"L\\\\(line)\" }\n    public init(line: Int) { self.line = line }\n}\n\nstruct Converter {\n    func location(for offset: Int) -> Int { offset }\n}\n\npublic func use() -> Int {\n    let p = Position(line: 1)\n    return Converter().location(for: p.line)\n}\n"
ix $R/p4 $R/p4/store App Sources/App/Position.swift
LINES_SHOWN=10 run "4 deadwood by name: is Position.location reported?" $DEADWOOD analyze $R/p4/Sources
LINES_SHOWN=10 run "4 deadwood with the index: is Position.location reported?" $DEADWOOD analyze $R/p4/Sources --index-store-path $R/p4/store
