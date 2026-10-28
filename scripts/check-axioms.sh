#!/usr/bin/env bash
# Fail if a sandbox theorem depends on sorryAx or on an axiom other than
# propext, Classical.choice, and Quot.sound.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
OUT=$(lake env lean Tests/PrintAxioms.lean 2>&1) || {
  echo "$OUT" >&2
  exit 1
}
echo "$OUT"
OUT="$OUT" python3 - <<'PY'
import os, re, sys
text = os.environ["OUT"]
if "error:" in text:
    sys.exit("lean reported an error")
reports = re.findall(r"depends on axioms: \[([^\]]*)\]", text)
none_ax = len(re.findall(r"does not depend on any axioms", text))
if len(reports) + none_ax < 13:
    sys.exit(f"expected 13 axiom reports, got {len(reports)} lists and {none_ax} empty")
allowed = {"propext", "Classical.choice", "Quot.sound"}
for group in reports:
    for name in (n.strip() for n in group.split(",")):
        if not name:
            continue
        if name == "sorryAx" or name not in allowed:
            sys.exit(f"axiom not allowed: {name}")
print(f"axioms ok ({len(reports) + none_ax} theorems)")
PY
