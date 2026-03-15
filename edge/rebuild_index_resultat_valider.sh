#!/usr/bin/env bash
set -euo pipefail

ROOT="$HOME/secdt-results/Resultat_valider"
INDEX="$ROOT/index_resultat_valider.json"

python3 - <<PY
import json
from pathlib import Path

root = Path("$ROOT")

def list_files(p):
    if not p.exists():
        return []
    return sorted(str(x) for x in p.rglob("*") if x.is_file())

index = {
    "root": str(root),
    "validated_only": True,
    "phases": {}
}

phase2 = root / "phase2_caliper"
index["phases"]["phase2_caliper"] = {
    "found": phase2.exists(),
    "path": str(phase2),
    "files": list_files(phase2),
    "subsets": {
        "1000": list_files(phase2 / "1000"),
        "1500": list_files(phase2 / "1500"),
        "2000": list_files(phase2 / "2000")
    }
}

phase3 = root / "phase3"
index["phases"]["phase3"] = {
    "found": phase3.exists(),
    "path": str(phase3),
    "files": list_files(phase3)
}

for name in ["phase4_s1", "phase5_s2", "phase6_s3", "phase7_s4", "phase8_s5", "phase9_s6"]:
    p = root / name
    summary = p / f"{name}_summary.json"
    entry = {
        "found": p.exists(),
        "path": str(p),
        "summary_file": str(summary) if summary.exists() else None,
        "files": list_files(p)
    }
    if summary.exists():
        try:
            entry["summary_preview"] = json.loads(summary.read_text(encoding="utf-8"))
        except Exception as e:
            entry["summary_preview_error"] = str(e)
    index["phases"][name] = entry

Path("$INDEX").write_text(json.dumps(index, indent=2), encoding="utf-8")
print(json.dumps(index, indent=2))
PY
