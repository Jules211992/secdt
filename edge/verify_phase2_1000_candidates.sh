#!/usr/bin/env bash
set -euo pipefail

ROOT="$HOME/secdt-results/Resultat_valider/phase2_caliper/1000_a_verifier"

for d in "$ROOT"/*; do
  [ -d "$d" ] || continue

  echo
  echo "=================================================================="
  echo "CANDIDATE: $(basename "$d")"
  echo "=================================================================="

  if [ -f "$d/caliper.log" ]; then
    echo "--- LOG: patterns 1000 / rate / workers / benchmark / rounds / tx ---"
    grep -Ein '1000|rate|fixed|tps|throughput|workers|benchmark|round|tx|transaction|send' "$d/caliper.log" | head -n 80 || true
    echo
  fi

  if [ -f "$d/report.html" ]; then
    echo "--- HTML: patterns 1000 / rate / workers / benchmark / rounds / tx ---"
    grep -Ein '1000|rate|fixed|tps|throughput|workers|benchmark|round|tx|transaction|send' "$d/report.html" | head -n 80 || true
    echo
  fi
done
