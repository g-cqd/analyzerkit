#!/bin/zsh
# Index-store probes A1, A3, A4, A6, D1, D2. Needs ARCLEAK and DEADWOOD (paths to the binaries under test).
set -eu
: ${ARCLEAK:?path to arcleak} ${DEADWOOD:?path to deadwood}
SWIFTC=$(xcrun --find swiftc); SDK=$(xcrun --show-sdk-path)
R=$(mktemp -d /private/tmp/analyzer-probes.XXXXXX); trap 'rm -rf "$R"' EXIT
mods=$R/mods; mkdir -p $mods
mk() { mkdir -p "$(dirname "$1")"; printf "%b" "$2" > "$1"; }
ix() { local store=$1 mod=$2; shift 2; (cd $R && $SWIFTC -sdk $SDK -index-store-path $store -index-ignore-system-modules \
  -module-name $mod -parse-as-library -emit-module -emit-module-path $mods/$mod.swiftmodule "$@" >/dev/null 2>&1); }
run() { echo "--- $1"; shift; "$@" --no-cache 2>&1 | grep -vE '^\s*$' | cut -c1-200 | head -4; }

# A1: one never-compiled file drops the index for the run.
mk $R/a1/src/Hub.swift "class Hub {\n    var plugin: Plugin?\n    init() {}\n}\n"
mk $R/a1/ext/Plugin.swift "class Plugin {\n    var hub: Hub?\n    init() {}\n}\n"
ix $R/a1/store A1 $R/a1/src/Hub.swift $R/a1/ext/Plugin.swift
run "A1 Hub alone: expect the cross-module cycle" $ARCLEAK analyze $R/a1/src/Hub.swift --index-store-path $R/a1/store
sleep 1; mk $R/a1/src/Script.swift "let x = 1\n"
run "A1 Hub + never-compiled Script: the cycle must stay" $ARCLEAK analyze $R/a1/src --index-store-path $R/a1/store

# A4: the declaring file changed after the build; Plugin is a struct now, elsewhere.
mk $R/a4/src/Ext.swift "extension Plugin {\n    func arm() {\n        self.handler = { self.fire() }\n    }\n}\n"
mk $R/a4/ext/Old.swift "class Plugin {\n    var handler: (() -> Void)?\n    func fire() {}\n}\n"
ix $R/a4/store A4 $R/a4/src/Ext.swift $R/a4/ext/Old.swift
sleep 1; mk $R/a4/ext/Old.swift "// moved\n"; mk $R/a4/ext/New.swift "struct Plugin {\n    var handler: (() -> Void)?\n    func fire() {}\n}\n"
run "A4 after the edit: no stored-closure finding may come from the stale record" $ARCLEAK analyze $R/a4/src --index-store-path $R/a4/store

# A3: two modules declare Coordinator, one struct, one class with a back-edge.
mk $R/a3/m1/Coordinator.swift "public struct Coordinator { public init() {} }\n"
mk $R/a3/m2/Coordinator.swift "public class Coordinator {\n    var owner: Owner?\n    init() {}\n}\n"
mk $R/a3/c1/Owner.swift "class Owner {\n    var c: Coordinator?\n}\n"
ix $R/a3/s1 M1 $R/a3/m1/Coordinator.swift; ix $R/a3/s1 M2 $R/a3/m2/Coordinator.swift $R/a3/c1/Owner.swift
ix $R/a3/s2 M2 $R/a3/m2/Coordinator.swift $R/a3/c1/Owner.swift
run "A3 control, one module: cycle" $ARCLEAK analyze $R/a3/c1 --index-store-path $R/a3/s2
run "A3 two modules: the answer must not depend on which definition comes first" $ARCLEAK analyze $R/a3/c1 --index-store-path $R/a3/s1

# A6 / D1: Xcode -derivedDataPath layout given at three depths; nothing may be created in the wrong directory.
mkdir -p $R/dd/Index.noindex; ix $R/dd/Index.noindex/DataStore A6 $R/a1/src/Hub.swift $R/a1/ext/Plugin.swift
for p in dd dd/Index.noindex dd/Index.noindex/DataStore; do
  for tool in $ARCLEAK $DEADWOOD; do
    run "A6/D1 $(basename $tool) --index-store-path <$p>" $tool analyze $R/a1/src/Hub.swift --index-store-path $R/$p
  done
  echo "    created: $(cd $R/dd && find . -maxdepth 2 \( -name v5 -o -name IndexDatabase \) | grep -v DataStore/ | tr '\n' ' ')"
done

# D2: a declaration used only by a file the index never saw.
mk $R/d2/Sources/App/App.swift "@main\nstruct App {\n    static func main() {\n        run()\n    }\n}\n\nfunc run() {\n    print(1)\n}\n\nfunc helper() -> Int {\n    42\n}\n\nfunc reallyDead() -> Int {\n    0\n}\n"
(cd $R/d2 && $SWIFTC -sdk $SDK -index-store-path $R/d2/store -index-ignore-system-modules -module-name App -parse-as-library \
  -emit-module -emit-module-path $mods/App.swiftmodule Sources/App/App.swift >/dev/null 2>&1)
sleep 1; mk $R/d2/Tests/AppTests/HelperTests.swift "import Testing\n@testable import App\n\n@Test func usesHelper() {\n    #expect(helper() == 42)\n}\n"
(cd $R/d2 && run "D2 name-based: only reallyDead()" $DEADWOOD analyze .)
(cd $R/d2 && run "D2 index: helper() must not be reported" $DEADWOOD analyze . --index-store-path $R/d2/store)
