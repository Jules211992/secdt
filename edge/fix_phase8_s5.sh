#!/usr/bin/env bash
set -euo pipefail

FILE="$HOME/secdt-edge/run_phase8_s5_full.sh"
[ -f "$FILE" ] || { echo "ERROR: $FILE introuvable"; exit 1; }

python3 - <<'PY'
from pathlib import Path

p = Path.home() / "secdt-edge" / "run_phase8_s5_full.sh"
s = p.read_text()

marker = 'run_case_fabric() {'
insert = 'run_case_fabric() {\n  local FABRIC_ONLY_LITERAL="FABRIC_ONLY"'
if marker in s and 'local FABRIC_ONLY_LITERAL="FABRIC_ONLY"' not in s:
    s = s.replace(marker, insert, 1)

old = '${#"FABRIC_ONLY"}'
new = '${#FABRIC_ONLY_LITERAL}'
if old not in s:
    raise SystemExit("pattern not found: ${#\"FABRIC_ONLY\"}")
s = s.replace(old, new)

p.write_text(s)
print("phase8 script fixed")
PY

grep -n 'FABRIC_ONLY' "$FILE"
