#!/usr/bin/env bash
set -euo pipefail

ROOT="$HOME/secdt-results/Resultat_valider"
rm -rf "$ROOT"
mkdir -p "$ROOT"

python3 - <<PY
import json
import shutil
from pathlib import Path

home = Path.home()
root = Path("$ROOT")

targets = {
    "phase4_s1": "phase4_s1_summary.json",
    "phase5_s2": "phase5_s2_summary.json",
    "phase6_s3": "phase6_s3_summary.json",
    "phase7_s4": "phase7_s4_summary.json",
    "phase8_s5": "phase8_s5_summary.json",
    "phase9_s6": "phase9_s6_summary.json",
}

def load_json(p):
    try:
        return json.loads(p.read_text())
    except Exception:
        return None

def is_validated(phase, data):
    if not isinstance(data, dict):
        return False

    if phase == "phase4_s1":
        return (
            str(data.get("phase", "")).startswith("phase4_s1")
            and float(data.get("success_rate", 0)) == 1.0
        )

    if phase == "phase5_s2":
        return (
            str(data.get("phase", "")).startswith("phase5_s2")
            and all(float(c.get("success_rate", 0)) == 1.0 for c in data.get("cases", []))
            and len(data.get("cases", [])) > 0
        )

    if phase == "phase6_s3":
        return (
            str(data.get("phase", "")) == "phase6_s3"
            and float(data.get("overall_success_rate", 0)) == 1.0
        )

    if phase == "phase7_s4":
        systems = data.get("systems", [])
        return (
            str(data.get("phase", "")) == "phase7_s4"
            and len(systems) > 0
            and all(float(s.get("success_rate", 0)) == 1.0 for s in systems)
        )

    if phase == "phase8_s5":
        cases = data.get("cases", [])
        return (
            str(data.get("phase", "")) == "phase8_s5"
            and len(cases) > 0
            and all(float(c.get("success_rate", 0)) == 1.0 for c in cases)
        )

    if phase == "phase9_s6":
        scenarios = data.get("scenarios", [])
        return (
            str(data.get("phase", "")) == "phase9_s6"
            and len(scenarios) > 0
            and all(bool(s.get("success", False)) for s in scenarios)
        )

    return False

index = {
    "root": str(root),
    "validated_only": True,
    "phases": {}
}

for phase, filename in targets.items():
    candidates = []
    for p in home.rglob(filename):
        if "Resultat_valider" in str(p):
            continue
        data = load_json(p)
        if is_validated(phase, data):
            candidates.append(p)

    candidates = sorted(candidates, key=lambda x: x.stat().st_mtime, reverse=True)

    dest_dir = root / phase
    if candidates:
        chosen = candidates[0]
        dest_dir.mkdir(parents=True, exist_ok=True)
        shutil.copy2(chosen, dest_dir / filename)

        index["phases"][phase] = {
            "found": True,
            "chosen_summary": str(chosen),
            "copied_to": str(dest_dir / filename),
            "all_candidates": [str(c) for c in candidates]
        }
    else:
        index["phases"][phase] = {
            "found": False,
            "chosen_summary": None,
            "copied_to": None,
            "all_candidates": []
        }

(root / "index_resultat_valider.json").write_text(
    json.dumps(index, indent=2),
    encoding="utf-8"
)

print(json.dumps(index, indent=2))
PY

echo
echo "RESULTAT_VALIDER=$ROOT"
find "$ROOT" -maxdepth 2 -type f | sort
