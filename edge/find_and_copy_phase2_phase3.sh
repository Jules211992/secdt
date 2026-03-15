#!/usr/bin/env bash
set -euo pipefail

ROOT="$HOME/secdt-results/Resultat_valider"
PHASE2_DIR="$ROOT/phase2_caliper"
PHASE3_DIR="$ROOT/phase3"

mkdir -p "$PHASE2_DIR"
mkdir -p "$PHASE3_DIR"

copy_first_found() {
  local pattern="$1"
  local dest_dir="$2"

  local found=""
  found=$(find "$HOME" -type f -name "$pattern" 2>/dev/null | grep -v '/Resultat_valider/' | sort | head -n 1 || true)

  if [ -n "${found:-}" ]; then
    cp "$found" "$dest_dir/"
    echo "COPIED: $found -> $dest_dir/"
  else
    echo "NOT FOUND: $pattern"
  fi
}

echo "=== PHASE 2 CALIPER ==="
copy_first_found "report*1000*.html" "$PHASE2_DIR"
copy_first_found "report*1500*.html" "$PHASE2_DIR"
copy_first_found "report*2000*.html" "$PHASE2_DIR"

copy_first_found "summary*1000*.txt" "$PHASE2_DIR"
copy_first_found "summary*1500*.txt" "$PHASE2_DIR"
copy_first_found "summary*2000*.txt" "$PHASE2_DIR"

echo
echo "=== PHASE 3 ==="
copy_first_found "phase3*.json" "$PHASE3_DIR"
copy_first_found "*phase3*.json" "$PHASE3_DIR"
copy_first_found "phase3*.csv" "$PHASE3_DIR"
copy_first_found "*phase3*.csv" "$PHASE3_DIR"
copy_first_found "phase3*.html" "$PHASE3_DIR"
copy_first_found "*phase3*.html" "$PHASE3_DIR"

echo
echo "=== RESULTAT_VALIDER ==="
find "$ROOT" -maxdepth 2 -type f | sort
