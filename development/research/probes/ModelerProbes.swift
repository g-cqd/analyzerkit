// M1–M3. Copy into modeler/Tests/ModelerCoreTests/. Expected after the fix: M1 no finding (no other writer of `phase`),
// and a finding of the new kind when another method writes `phase`; M2 one finding; M3 no finding.
import ModelerCore
import Testing

@Suite struct ZZProbeTests {
    private func run(_ body: String, extra: String = "") -> [String] {
        ReentrancyAnalysis.findings(
            in: modelFacts("actor A {\n var phase = 0\n func f() async {\n\(body)\n }\n\(extra)\n}")
        )
        .map { "\($0.checkLine)-\($0.suspendLine)-\($0.writeLine)" }
    }

    @Test func probes() {
        print("M1 claim before await:", run("guard phase == 0 else { return }\nphase = 1\nawait g()\nphase = 2"))
        print(
            "M1 with another writer:",
            run(
                "guard phase == 0 else { return }\nphase = 1\nawait g()\nphase = 2",
                extra: "func reset() { phase = 0 }"))
        print("M2 loop-carried:", run("while true {\nphase = 3\nif phase == 0 { }\nawait g()\n}"))
        print("M3 branches:", run("if phase == 0 { await g() } else { phase = 1 }"))
    }
}
