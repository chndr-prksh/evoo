#!/usr/bin/env python3
"""Exports the Mac app's rule tests as a shared contract for the Android port:
   Tests/EvooCoreTests (DictationRulesTests: fix("said") == "expected", and ("said", "expected") tuples)
   → android/core/src/test/resources/rules.tsv     Run:  python3 scripts/export-rule-cases.py"""
import re, pathlib
root = pathlib.Path(__file__).resolve().parent.parent
src = (root / "Tests/EvooCoreTests/EvooCoreTests.swift").read_text(encoding="utf-8")
start = src.index("@Suite struct DictationRulesTests")
nxt = re.search(r"\n@Suite struct |\nstruct \w+Tests", src[start + 10:])
suite = src[start: start + 10 + nxt.start()] if nxt else src[start:]
S = r'"((?:[^"\\]|\\.)*)"'
pairs = re.findall(r"fix\(" + S + r"\)\s*==\s*" + S, suite) + re.findall(r"\(\s*" + S + r",\s*" + S + r"\s*\)", suite)
un = lambda s: s.replace('\\"', '"').replace("\\\\", "\\")
seen, rows = set(), []
for a, b in pairs:
    a, b = un(a), un(b)
    if "\\n" in a or "\\n" in b or "\t" in a or a in seen: continue
    seen.add(a); rows.append(f"{a}\t{b}")
out = root / "android/core/src/test/resources/rules.tsv"
out.write_text("# said <TAB> expected — exported from the Mac app's DictationRulesTests by scripts/export-rule-cases.py\n" + "\n".join(rows) + "\n", encoding="utf-8")
print(len(rows), "cases →", out.relative_to(root))
