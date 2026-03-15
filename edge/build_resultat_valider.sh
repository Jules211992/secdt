#!/usr/bin/env bash
set -euo pipefail

ROOT="$HOME/secdt-results/Resultat_valider"
rm -rf "$ROOT"
mkdir -p "$ROOT"

copy_best_file() {
  local phase_name="$1"
  local src_dir="$2"
  local expected_json="$3"

  local dest_dir="$ROOT/$phase_name"
  mkdir -p "$dest_dir"

  if [ -n "$expected_json" ] && [ -f "$src_dir/$expected_json" ]; then
    cp "$src_dir/$expected_json" "$dest_dir/"
    return 0
  fi

  local first_json
  first_json=$(find "$src_dir" -maxdepth 2 -type f -name "*.json" | sort | head -n 1 || true)
  if [ -n "${first_json:-}" ]; then
    cp "$first_json" "$dest_dir/"
    return 0
  fi

  local first_csv
  first_csv=$(find "$src_dir" -maxdepth 2 -type f -name "*.csv" | sort | head -n 1 || true)
  if [ -n "${first_csv:-}" ]; then
    cp "$first_csv" "$dest_dir/"
    return 0
  fi

  rm -rf "$dest_dir"
  return 0
}

PHASE4_SRC="$HOME/secdt-phase4/phase4_s1_20260314T172001Z"
PHASE5_SRC="$HOME/secdt-phase5/phase5_s2_fd001_fixed_20260314T200018Z"
PHASE6_SRC="$HOME/secdt-phase6/phase6_s3_20260314T204859Z"
PHASE7_SRC="$HOME/secdt-phase7/resultats_phase7/phase7_s4_20260314T212954Z"
PHASE8_SRC="$HOME/secdt-phase8/resultats_phase8/phase8_s5_20260314T214916Z"
PHASE9_SRC="$HOME/secdt-phase9/phase9_s6_20260314T221227Z"

[ -d "$PHASE4_SRC" ] || { echo "ERROR: Phase 4 introuvable: $PHASE4_SRC"; exit 1; }
[ -d "$PHASE5_SRC" ] || { echo "ERROR: Phase 5 introuvable: $PHASE5_SRC"; exit 1; }
[ -d "$PHASE6_SRC" ] || { echo "ERROR: Phase 6 introuvable: $PHASE6_SRC"; exit 1; }
[ -d "$PHASE7_SRC" ] || { echo "ERROR: Phase 7 introuvable: $PHASE7_SRC"; exit 1; }
[ -d "$PHASE8_SRC" ] || { echo "ERROR: Phase 8 introuvable: $PHASE8_SRC"; exit 1; }
[ -d "$PHASE9_SRC" ] || { echo "ERROR: Phase 9 introuvable: $PHASE9_SRC"; exit 1; }

copy_best_file "phase4_s1" "$PHASE4_SRC" "phase4_s1_summary.json"
copy_best_file "phase5_s2" "$PHASE5_SRC" "phase5_s2_summary.json"
copy_best_file "phase6_s3" "$PHASE6_SRC" "phase6_s3_summary.json"
copy_best_file "phase7_s4" "$PHASE7_SRC" "phase7_s4_summary.json"
copy_best_file "phase8_s5" "$PHASE8_SRC" "phase8_s5_summary.json"
copy_best_file "phase9_s6" "$PHASE9_SRC" "phase9_s6_summary.json"

python3 - <<PY
import json
from pathlib import Path

root = Path("$ROOT")
index = {"root": str(root), "validated_phases": {}}

for phase_dir in sorted([p for p in root.iterdir() if p.is_dir()]):
    files = sorted([str(x) for x in phase_dir.glob("*") if x.is_file()])
    index["validated_phases"][phase_dir.name] = {
        "exists": True,
        "files": files
    }

(root / "index_resultat_valider.json").write_text(json.dumps(index, indent=2), encoding="utf-8")
print(json.dumps(index, indent=2))
PY

echo
echo "RESULTAT_VALIDER=$ROOT"
find "$ROOT" -maxdepth 2 -type f | sort
