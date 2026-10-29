#!/usr/bin/env python3
"""Roadmap 0013: the exit status of each analyzer in the same scenarios. Run from the g-cqd directory, debug builds.
Prints a table; nothing is written outside a temporary directory."""
import json, os, subprocess, sys, tempfile
from pathlib import Path

G = Path(__file__).resolve().parents[4]
TOOLS = {
    "arcleak": ("final class Box {\n    var handler: (() -> Void)?\n    func arm() { handler = { self.fire() } }\n    func fire() {}\n}\n",
                "stored-closure-strong-self", ".arcleak.json", lambda rule, sev: {"rules": {rule: {"severity": sev}}}),
    "deadwood": ("private func unusedHelper() {}\n", "unused-function", ".deadwood.json",
                 lambda rule, sev: {"rules": {rule: {"severity": sev}}}),
    "dolly": ("".join(f"func stitch{n}Row(cells: [Int]) -> String {{\n    var text = \"\"\n    for cell in cells {{\n"
                      f"        if cell > 4 {{ text += \"<\\(cell)>\" }} else {{ text += \"(\\(cell))\" }}\n        text += \", \"\n"
                      f"    }}\n    return text\n}}\n" for n in ("Banner", "Footer")),
              "exact-clone", ".dolly.json", lambda rule, sev: {"rules": {rule: {"severity": sev}}}),
    "fcheck": ("func leaks(_ p: String) throws {\n    let d = open(p, 0)\n    try work()\n    close(d)\n}\n",
               "leak-on-exit", ".fcheck.json", lambda rule, sev: {"severity": {rule: sev}}),
    "modeler": ("actor Counter {\n    var value = 0\n    func bump() async {\n        if value == 0 {\n            await work()\n"
                "            value = 1\n        }\n    }\n    func work() async {}\n}\n", None, None, None),
}
CLEAN = "struct Clean {}\n"

def run(tool, args, cwd):
    exe = G / tool / ".build/debug" / tool
    command = [str(exe)] + (["check"] if tool == "modeler" else ["analyze"]) + args
    return subprocess.run(command, cwd=cwd, capture_output=True).returncode

def scenarios(tool):
    source, rule, config, severity = TOOLS[tool]
    cache = [] if tool == "modeler" else ["--no-cache"]
    rows = {}
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        (root / ".git").write_text("gitdir: none\n")
        def corpus(name, text):
            path = root / name
            path.mkdir()
            (path / "A.swift").write_bytes(text if isinstance(text, bytes) else text.encode())
            return str(path)
        clean, finding, skipped = corpus("clean", CLEAN), corpus("finding", source), corpus("skipped", b"let \xff = 1\n")
        rows["clean"] = run(tool, [clean] + cache, root)
        rows["finding (default severity)"] = run(tool, [finding] + cache, root)
        rows["finding --strict"] = run(tool, [finding, "--strict"] + cache, root)
        if config:
            for sev in ("note", "warning", "error"):
                path = root / f"{sev}.json"
                path.write_text(json.dumps(severity(rule, sev)))
                rows[f"finding as {sev}"] = run(tool, [finding, "--config", str(path)] + cache, root)
                rows[f"finding as {sev} --strict"] = run(tool, [finding, "--config", str(path), "--strict"] + cache, root)
            bad = root / "bad.json"
            bad.write_text("{ not json")
            rows["malformed --config"] = run(tool, [clean, "--config", str(bad)] + cache, root)
            rows["missing --config"] = run(tool, [clean, "--config", str(root / "absent.json")] + cache, root)
            rows["malformed --baseline"] = run(tool, [clean, "--baseline", str(bad)] + cache, root)
            rows["missing --baseline"] = run(tool, [clean, "--baseline", str(root / "absent.json")] + cache, root)
            rows["unwritable --write-baseline"] = run(tool, [finding, "--write-baseline", "/nonexistent/dir/b.json"] + cache, root)
        rows["unknown flag"] = run(tool, [clean, "--no-such-flag"] + cache, root)
        rows["missing path"] = run(tool, [str(root / "absent")] + cache, root)
        (root / "empty").mkdir()
        rows["no Swift file under the path"] = run(tool, [str(root / "empty")] + cache, root)
        rows["every file invalid UTF-8"] = run(tool, [skipped] + cache, root)
        locked = corpus("locked", CLEAN)
        os.chmod(Path(locked) / "A.swift", 0)
        rows["every file unreadable (mode 000)"] = run(tool, [locked] + cache, root)
        os.chmod(Path(locked) / "A.swift", 0o644)
    return rows

tools = sys.argv[1:] or list(TOOLS)
table = {tool: scenarios(tool) for tool in tools}
names = list(dict.fromkeys(name for rows in table.values() for name in rows))
print(f"{'scenario':32}" + "".join(f"{t:>10}" for t in tools))
for name in names:
    print(f"{name:32}" + "".join(f"{str(table[t].get(name, '-')):>10}" for t in tools))
