#!/usr/bin/env bash
set -euo pipefail

MASTER="$HOME/secdt-results/master-results"
BACKUP_ROOT="$HOME/secdt-results"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP="$BACKUP_ROOT/master-results-backup-$TS"

mkdir -p "$BACKUP_ROOT"

if [ -d "$MASTER" ]; then
  rm -rf "$BACKUP"
  mv "$MASTER" "$BACKUP"
fi

mkdir -p "$MASTER"

PHASE4_SRC=""
for d in \
  "$HOME/secdt-phase4/resultats_phase4/"phase4_s1_* \
  "$HOME/secdt-phase4/"phase4_s1_* \
; do
  if [ -d "$d" ] && [ -f "$d/phase4_s1_summary.json" ]; then
    if python3 - <<PY >/dev/null 2>&1
import json
p = "$d/phase4_s1_summary.json"
data = json.load(open(p))
ok = float(data.get("success_rate", 0)) == 1.0
print("ok" if ok else "no")
raise SystemExit(0 if ok else 1)
PY
    then
      PHASE4_SRC="$d"
      break
    fi
  fi
done

PHASE5_SRC="$HOME/secdt-phase5/phase5_s2_fd001_fixed_20260314T200018Z"
if [ ! -d "$PHASE5_SRC" ]; then
  for d in "$HOME/secdt-phase5/resultats_phase5/"phase5_s2_fd001_fixed_* "$HOME/secdt-phase5/"phase5_s2_fd001_fixed_*; do
    if [ -d "$d" ] && [ -f "$d/phase5_s2_summary.json" ]; then
      PHASE5_SRC="$d"
      break
    fi
  done
fi

PHASE6_SRC="$HOME/secdt-results/master-results/phase6_s3"
[ -d "$HOME/secdt-phase6/resultats_phase6" ] && PHASE6_SRC="$(ls -dt "$HOME"/secdt-phase6/resultats_phase6/phase6_s3_* 2>/dev/null | head -n 1 || echo "$PHASE6_SRC")"
[ -d "$HOME/secdt-phase6" ] && [ -z "${PHASE6_SRC:-}" ] && PHASE6_SRC="$(ls -dt "$HOME"/secdt-phase6/phase6_s3_* 2>/dev/null | head -n 1 || true)"

PHASE7_SRC="$(ls -dt "$HOME"/secdt-phase7/resultats_phase7/phase7_s4_* 2>/dev/null | head -n 1 || true)"
PHASE8_SRC="$(ls -dt "$HOME"/secdt-phase8/resultats_phase8/phase8_s5_* 2>/dev/null | head -n 1 || true)"
PHASE9_SRC="$(ls -dt "$HOME"/secdt-phase9/resultats_phase9/phase9_s6_* 2>/dev/null | head -n 1 || true)"

[ -n "${PHASE4_SRC:-}" ] || { echo "ERROR: phase4 valide introuvable"; exit 1; }
[ -n "${PHASE5_SRC:-}" ] || { echo "ERROR: phase5 valide introuvable"; exit 1; }
[ -n "${PHASE6_SRC:-}" ] || { echo "ERROR: phase6 valide introuvable"; exit 1; }
[ -n "${PHASE7_SRC:-}" ] || { echo "ERROR: phase7 valide introuvable"; exit 1; }
[ -n "${PHASE8_SRC:-}" ] || { echo "ERROR: phase8 valide introuvable"; exit 1; }
[ -n "${PHASE9_SRC:-}" ] || { echo "ERROR: phase9 valide introuvable"; exit 1; }

cp -a "$PHASE4_SRC" "$MASTER/phase4_s1"
cp -a "$PHASE5_SRC" "$MASTER/phase5_s2"
cp -a "$PHASE6_SRC" "$MASTER/phase6_s3"
cp -a "$PHASE7_SRC" "$MASTER/phase7_s4"
cp -a "$PHASE8_SRC" "$MASTER/phase8_s5"
cp -a "$PHASE9_SRC" "$MASTER/phase9_s6"

python3 - <<PY
import json
from pathlib import Path

master = Path("$MASTER")

def load_summary(path):
    p = Path(path)
    if not p.exists():
        return None
    try:
        return json.load(open(p))
    except Exception:
        return None

index = {
    "master_dir": str(master),
    "validated_phases_only": True,
    "backup_previous_master": "$BACKUP",
    "phases": {
        "phase4_s1": {
            "exists": (master / "phase4_s1").exists(),
            "path": str(master / "phase4_s1"),
            "summary_file": str(master / "phase4_s1" / "phase4_s1_summary.json"),
            "summary_preview": load_summary(master / "phase4_s1" / "phase4_s1_summary.json"),
        },
        "phase5_s2": {
            "exists": (master / "phase5_s2").exists(),
            "path": str(master / "phase5_s2"),
            "summary_file": str(master / "phase5_s2" / "phase5_s2_summary.json"),
            "summary_preview": load_summary(master / "phase5_s2" / "phase5_s2_summary.json"),
        },
        "phase6_s3": {
            "exists": (master / "phase6_s3").exists(),
            "path": str(master / "phase6_s3"),
            "summary_file": str(master / "phase6_s3" / "phase6_s3_summary.json"),
            "summary_preview": load_summary(master / "phase6_s3" / "phase6_s3_summary.json"),
        },
        "phase7_s4": {
            "exists": (master / "phase7_s4").exists(),
            "path": str(master / "phase7_s4"),
            "summary_file": str(master / "phase7_s4" / "phase7_s4_summary.json"),
            "summary_preview": load_summary(master / "phase7_s4" / "phase7_s4_summary.json"),
        },
        "phase8_s5": {
            "exists": (master / "phase8_s5").exists(),
            "path": str(master / "phase8_s5"),
            "summary_file": str(master / "phase8_s5" / "phase8_s5_summary.json"),
            "summary_preview": load_summary(master / "phase8_s5" / "phase8_s5_summary.json"),
        },
        "phase9_s6": {
            "exists": (master / "phase9_s6").exists(),
            "path": str(master / "phase9_s6"),
            "summary_file": str(master / "phase9_s6" / "phase9_s6_summary.json"),
            "summary_preview": load_summary(master / "phase9_s6" / "phase9_s6_summary.json"),
        }
    }
}

(master / "results_index.json").write_text(json.dumps(index, indent=2), encoding="utf-8")
print(json.dumps(index, indent=2))
PY

echo
echo "MASTER_REBUILT=$MASTER"
echo "BACKUP_OLD_MASTER=$BACKUP"
