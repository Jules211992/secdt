#!/usr/bin/env bash
set -euo pipefail

LATEST=$(ls -dt "$HOME"/secdt-phase7/phase7_s4_* 2>/dev/null | head -n 1 || true)
[ -n "${LATEST:-}" ] || { echo "ERROR: aucun dossier phase7_s4 trouvé"; exit 1; }

RESULTS_ROOT="$HOME/secdt-phase7/resultats_phase7"
RUNSET_NAME="$(basename "$LATEST")"
DEST="$RESULTS_ROOT/$RUNSET_NAME"

mkdir -p "$RESULTS_ROOT"
rm -rf "$DEST"
mkdir -p "$DEST"

cp -a "$LATEST/"* "$DEST"/
cp "$HOME/secdt-edge/run_phase7_s4_real.sh" "$DEST"/ 2>/dev/null || true
cp "$HOME/secdt-edge/run_phase7_s4.sh" "$DEST"/ 2>/dev/null || true

cat <<TXT > "$DEST/README_RESULTAT.txt"
Phase: Phase 7
Scenario: S4 baseline comparison
Statut: valide
Source runset: $LATEST
Résumé officiel: phase7_s4_summary.json
TXT

echo
echo "RESULTS_SAVED_IN=$DEST"
echo
ls -lah "$DEST"
echo
cat "$DEST/phase7_s4_summary.json"
