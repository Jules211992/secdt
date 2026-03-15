#!/usr/bin/env bash
set -euo pipefail

SRC="$HOME/secdt-caliper-benchmark/final-results"
DST="$HOME/secdt-results/Resultat_valider/phase2_caliper"

mkdir -p "$DST/1000" "$DST/1500" "$DST/2000"

cp "$SRC/distributed_1000/summary.txt" "$DST/1000/" 2>/dev/null || true
cp "$SRC/distributed_1500/summary.txt" "$DST/1500/" 2>/dev/null || true
cp "$SRC/distributed_2000/summary.txt" "$DST/2000/" 2>/dev/null || true

echo
echo "=== PHASE2 CALIPER WITH SUMMARIES ==="
find "$DST" -maxdepth 2 -type f | sort
