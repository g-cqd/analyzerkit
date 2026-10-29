// D4. Copy into arcleak (MODULE = ArcLeakCore) and deadwood (MODULE = DeadwoodCore) test targets. Expected after the fix:
// both true for Xcode's dylib and for a user-owned toolchain's, whoever owns Xcode.app.
#if os(macOS)
    @testable import MODULE
    import Foundation
    import Testing

    @Suite struct ZZProbeTests {
        @Test func trust() {
            let xcode =
                "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/libIndexStore.dylib"
            let user = URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent(
                    "Library/Developer/Toolchains/swift-latest.xctoolchain/usr/lib/libIndexStore.dylib"
                )
                .resolvingSymlinksInPath().path
            print(
                "D4 Xcode:", BinaryTrustChecker.isTrusted(at: xcode), "user toolchain:",
                BinaryTrustChecker.isTrusted(at: user))
        }
    }
#endif
