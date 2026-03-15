#!/usr/bin/env bash
set -euo pipefail

LATEST="${1:-$(ls -dt "$HOME"/secdt-phase5/phase5_s2_fd001_fast_* 2>/dev/null | head -n 1)}"
[ -n "${LATEST:-}" ] || { echo "ERROR: aucun runset phase5_s2_fd001_fast trouvé"; exit 1; }

python3 - <<PY
import json
from pathlib import Path
from collections import defaultdict, Counter

root = Path("$LATEST")
reports = sorted(root.rglob("run_report.json"))

print("RUNSET =", root)
print("N_REPORTS =", len(reports))
print()

by_case = defaultdict(list)
machine_ids = []
session_ids = []

for rp in reports:
    data = json.loads(rp.read_text())
    case_dir = rp.parent.parent.name if rp.parent.name.startswith("run_") else rp.parent.name
    by_case[case_dir].append(data)
    machine_ids.append(data.get("machine_id"))
    if "session_id" in data:
        session_ids.append(data.get("session_id"))

print("=== DUPLICATE MACHINE IDS ===")
dup_m = [k for k,v in Counter(machine_ids).items() if v > 1]
print("count =", len(dup_m))
print(dup_m[:20])
print()

for case, rows in sorted(by_case.items()):
    n = len(rows)
    succ = sum(1 for r in rows if r.get("success_end_to_end") is True)
    inv = sum(1 for r in rows if r.get("invoke_ok") is True)
    ver = sum(1 for r in rows if r.get("verify_ok") is True)
    hist = sum(1 for r in rows if r.get("history_ok") is True)
    cidm = sum(1 for r in rows if r.get("cid_matches_history") is True)
    hashm = sum(1 for r in rows if r.get("hash_matches_history") is True)

    print(f"=== CASE {case} ===")
    print({
        "n_reports": n,
        "successes": succ,
        "invoke_ok": inv,
        "verify_ok": ver,
        "history_ok": hist,
        "cid_matches_history": cidm,
        "hash_matches_history": hashm
    })

    failures = [r for r in rows if not r.get("success_end_to_end", False)]
    if failures:
        print("first_failure =")
        print(json.dumps(failures[0], indent=2))
    print()
PY
