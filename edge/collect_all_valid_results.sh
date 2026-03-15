#!/usr/bin/env bash
set -euo pipefail

MASTER_DIR="$HOME/secdt-results/master-results"
INDEX_JSON="$MASTER_DIR/results_index.json"

mkdir -p "$MASTER_DIR"

copy_phase() {
  local phase_name="$1"
  local src="$2"
  local dst="$MASTER_DIR/$phase_name"

  if [ -d "$src" ]; then
    rm -rf "$dst"
    mkdir -p "$dst"
    cp -r "$src"/. "$dst"/
    echo "[OK] $phase_name <= $src"
  else
    echo "[WARN] source absente pour $phase_name : $src"
  fi
}

copy_phase "phase4_s1" "$HOME/secdt-phase4/phase4_s1_fd001_20260314T183227Z"
copy_phase "phase5_s2" "$HOME/secdt-results/final/phase5_s2/phase5_s2_fd001_fixed_20260314T200018Z"
copy_phase "phase6_s3" "$HOME/secdt-results/final/phase6_s3/phase6_s3_20260314T204859Z"
copy_phase "phase7_s4" "$HOME/secdt-results/final/phase7_s4/phase7_s4_20260314T212954Z"
copy_phase "phase8_s5" "$HOME/secdt-results/final/phase8_s5/phase8_s5_20260314T214916Z"
copy_phase "phase9_s6" "$HOME/secdt-results/final/phase9_s6/phase9_s6_20260314T221227Z"

mkdir -p "$MASTER_DIR/phase2_caliper"

for d in \
  "$HOME/secdt-caliper-benchmark/final-results/distributed_1500" \
  "$HOME/secdt-caliper-benchmark/final-results/distributed_2000"
do
  if [ -d "$d" ]; then
    name="$(basename "$d")"
    rm -rf "$MASTER_DIR/phase2_caliper/$name"
    cp -r "$d" "$MASTER_DIR/phase2_caliper/"
    echo "[OK] phase2_caliper <= $d"
  else
    echo "[WARN] source absente pour phase2_caliper : $d"
  fi
done

python3 - <<PY
import json
from pathlib import Path

master = Path("$MASTER_DIR")

def safe_load(p):
    try:
        return json.loads(Path(p).read_text())
    except Exception:
        return None

index = {
    "master_dir": str(master),
    "phases": {}
}

phase_map = {
    "phase4_s1": "phase4_s1_summary.json",
    "phase5_s2": "phase5_s2_summary.json",
    "phase6_s3": "phase6_s3_summary.json",
    "phase7_s4": "phase7_s4_summary.json",
    "phase8_s5": "phase8_s5_summary.json",
    "phase9_s6": "phase9_s6_summary.json",
}

for phase, summary_file in phase_map.items():
    pdir = master / phase
    summary_path = pdir / summary_file
    entry = {
        "exists": pdir.exists(),
        "path": str(pdir),
        "summary_file": str(summary_path) if summary_path.exists() else None,
        "files": []
    }
    if pdir.exists():
        entry["files"] = sorted(str(x) for x in pdir.rglob("*") if x.is_file())
        obj = safe_load(summary_path)
        if obj is not None:
            entry["summary_json_loaded"] = True
            entry["summary_preview"] = obj
        else:
            entry["summary_json_loaded"] = False
    index["phases"][phase] = entry

p2dir = master / "phase2_caliper"
p2entry = {
    "exists": p2dir.exists(),
    "path": str(p2dir),
    "files": []
}
if p2dir.exists():
    p2entry["files"] = sorted(str(x) for x in p2dir.rglob("*") if x.is_file())
index["phases"]["phase2_caliper"] = p2entry

(master / "results_index.json").write_text(json.dumps(index, indent=2), encoding="utf-8")
print(json.dumps({
    "master_dir": str(master),
    "index_file": str(master / "results_index.json")
}, indent=2))
PY

echo
echo "MASTER_DIR=$MASTER_DIR"
echo "INDEX_JSON=$INDEX_JSON"
