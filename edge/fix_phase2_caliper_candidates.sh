#!/usr/bin/env bash
set -euo pipefail

ROOT="$HOME/secdt-results/Resultat_valider/phase2_caliper"
SRC="$HOME/secdt-caliper-benchmark/reports"

rm -rf "$ROOT"
mkdir -p "$ROOT/1500" "$ROOT/2000" "$ROOT/1000_a_verifier"

cp "$SRC/dist1500_peer1_20260314_145813/report.html" "$ROOT/1500/"
cp "$SRC/dist1500_peer1_20260314_145813/caliper.log" "$ROOT/1500/"

cp "$SRC/dist2000_peer1_20260314_153014/report.html" "$ROOT/2000/"
cp "$SRC/dist2000_peer1_20260314_153014/caliper.log" "$ROOT/2000/"

mkdir -p "$ROOT/1000_a_verifier/dist_peer1_20260314_143400"
cp "$SRC/dist_peer1_20260314_143400/report.html" "$ROOT/1000_a_verifier/dist_peer1_20260314_143400/" 2>/dev/null || true
cp "$SRC/dist_peer1_20260314_143400/caliper.log" "$ROOT/1000_a_verifier/dist_peer1_20260314_143400/" 2>/dev/null || true

mkdir -p "$ROOT/1000_a_verifier/dist_peer1_20260314_144700"
cp "$SRC/dist_peer1_20260314_144700/report.html" "$ROOT/1000_a_verifier/dist_peer1_20260314_144700/" 2>/dev/null || true
cp "$SRC/dist_peer1_20260314_144700/caliper.log" "$ROOT/1000_a_verifier/dist_peer1_20260314_144700/" 2>/dev/null || true

mkdir -p "$ROOT/1000_a_verifier/phase2_20260314_135341"
cp "$SRC/phase2_20260314_135341/report.html" "$ROOT/1000_a_verifier/phase2_20260314_135341/" 2>/dev/null || true
cp "$SRC/phase2_20260314_135341/caliper.log" "$ROOT/1000_a_verifier/phase2_20260314_135341/" 2>/dev/null || true

echo
echo "=== PHASE2 CALIPER CLEAN ==="
find "$ROOT" -maxdepth 3 -type f | sort
