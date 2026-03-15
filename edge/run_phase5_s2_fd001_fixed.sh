#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$HOME/secdt-phase5"
RUNSET_ID="phase5_s2_fd001_fixed_$(date -u +%Y%m%dT%H%M%SZ)"
RUNSET_DIR="$BASE_DIR/$RUNSET_ID"
mkdir -p "$RUNSET_DIR"

IPFS_API="${IPFS_API:-http://ipfs-node-1:5001/api/v0}"
SNAPSHOT_SOURCE="${SNAPSHOT_SOURCE:-$HOME/secdt-data/prepared/fd001_snapshots.jsonl}"

FABRIC_DIR="${FABRIC_DIR:-$HOME/secdt-fabric}"
CHANNEL_NAME="${CHANNEL_NAME:-secdt-channel}"
CC_NAME="${CC_NAME:-secdt}"
ORDERER_ADDRESS="${ORDERER_ADDRESS:-orderer-fabric-1:7050}"

MACHINE_LEVELS="${MACHINE_LEVELS:-10 25 50}"
INTERVAL_LEVELS_MS="${INTERVAL_LEVELS_MS:-1000 500}"

[ -f "$SNAPSHOT_SOURCE" ] || { echo "ERROR: SNAPSHOT_SOURCE introuvable: $SNAPSHOT_SOURCE"; exit 1; }

cd "$FABRIC_DIR"
export PATH=$PATH:~/fabric-samples/bin
export CORE_PEER_LOCALMSPID=PeerMSP
export CORE_PEER_MSPCONFIGPATH=~/secdt-fabric/crypto-config/peerOrganizations/secdt.com/users/Admin@secdt.com/msp
export CORE_PEER_ADDRESS=peer-fabric-1:7051
export CORE_PEER_TLS_ENABLED=true
export CORE_PEER_TLS_ROOTCERT_FILE=~/secdt-fabric/crypto-config/peerOrganizations/secdt.com/peers/peer-fabric-1.secdt.com/tls/ca.crt
export ORDERER_CA=~/secdt-fabric/crypto-config/ordererOrganizations/secdt.com/orderers/orderer-fabric-1.secdt.com/tls/ca.crt
export PEER_CA=~/secdt-fabric/crypto-config/peerOrganizations/secdt.com/peers/peer-fabric-1.secdt.com/tls/ca.crt

run_case() {
  local n_machines="$1"
  local interval_ms="$2"
  local case_dir="$RUNSET_DIR/m${n_machines}_i${interval_ms}"
  mkdir -p "$case_dir"

  local CASE_START_MS
  CASE_START_MS=$(date +%s%3N)

  for run_idx in $(seq 1 "$n_machines"); do
    local run_dir="$case_dir/run_$run_idx"
    mkdir -p "$run_dir"

    python3 - <<PY > "$run_dir/snapshot_base.json"
from pathlib import Path
src = Path("$SNAPSHOT_SOURCE")
idx = $run_idx - 1
with src.open("r", encoding="utf-8") as f:
    for n, line in enumerate(f):
        if n == idx:
            print(line.strip())
            break
    else:
        raise SystemExit(f"ERROR: index {idx} hors limite dans {src}")
PY

    python3 - <<PY > "$run_dir/snapshot.json"
import json
from pathlib import Path

p = Path("$run_dir/snapshot_base.json")
obj = json.loads(p.read_text())

obj["machine_id"] = f'{obj["machine_id"]}-$RUNSET_ID-m${n_machines}-i${interval_ms}-r${run_idx}'
obj["session_id"] = f'{obj["session_id"]}-$RUNSET_ID-m${n_machines}-i${interval_ms}-r${run_idx}'

print(json.dumps(obj, separators=(",", ":")))
PY

    local MACHINE_ID SESSION_ID CYCLE HEALTH_SCORE
    MACHINE_ID=$(python3 - <<PY
import json
print(json.load(open("$run_dir/snapshot.json"))["machine_id"])
PY
)
    SESSION_ID=$(python3 - <<PY
import json
print(json.load(open("$run_dir/snapshot.json"))["session_id"])
PY
)
    CYCLE=$(python3 - <<PY
import json
print(json.load(open("$run_dir/snapshot.json"))["cycle"])
PY
)
    HEALTH_SCORE=$(python3 - <<PY
import json
print(json.load(open("$run_dir/snapshot.json"))["health_score"])
PY
)

    local T0 T1 T2 T3 T4 T5 HASH CID
    T0=$(date +%s%3N)
    HASH=$(sha256sum "$run_dir/snapshot.json" | awk '{print $1}')
    T1=$(date +%s%3N)

    curl -sS --fail -X POST -F file=@"$run_dir/snapshot.json" "$IPFS_API/add" > "$run_dir/ipfs_add_result.json"
    CID=$(python3 - <<PY
import json
print(json.load(open("$run_dir/ipfs_add_result.json"))["Hash"])
PY
)
    T2=$(date +%s%3N)

    curl -sS --fail -X POST "$IPFS_API/cat?arg=$CID" > "$run_dir/ipfs_cat.json"
    T3=$(date +%s%3N)

    local INVOKE_OK=false
    if peer chaincode invoke \
      -o "$ORDERER_ADDRESS" \
      --tls --cafile "$ORDERER_CA" \
      -C "$CHANNEL_NAME" \
      -n "$CC_NAME" \
      --peerAddresses peer-fabric-1:7051 \
      --tlsRootCertFiles "$PEER_CA" \
      --waitForEvent \
      --waitForEventTimeout 30s \
      -c "{\"Args\":[\"RegisterState\",\"$MACHINE_ID\",\"$CID\",\"$HEALTH_SCORE\",\"$CYCLE\",\"$SESSION_ID\",\"$HASH\"]}" \
      > "$run_dir/fabric_invoke.txt" 2>&1
    then
      INVOKE_OK=true
    fi
    T4=$(date +%s%3N)

    local VERIFY_OK=false
    if peer chaincode query \
      -C "$CHANNEL_NAME" \
      -n "$CC_NAME" \
      -c "{\"Args\":[\"VerifyIntegrity\",\"$MACHINE_ID\",\"$HASH\"]}" \
      > "$run_dir/verify.json" 2>&1
    then
      if grep -qx "true" "$run_dir/verify.json"; then
        VERIFY_OK=true
      fi
    fi

    local HISTORY_OK=false
    if peer chaincode query \
      -C "$CHANNEL_NAME" \
      -n "$CC_NAME" \
      -c "{\"Args\":[\"GetHistory\",\"$MACHINE_ID\"]}" \
      > "$run_dir/history.json" 2>&1
    then
      HISTORY_OK=true
    fi
    T5=$(date +%s%3N)

    python3 - <<PY
import json
import hashlib
from pathlib import Path

run_dir = Path("$run_dir")
snapshot_path = run_dir / "snapshot.json"
ipfs_cat_path = run_dir / "ipfs_cat.json"
history_path = run_dir / "history.json"

hash_local = hashlib.sha256(snapshot_path.read_bytes()).hexdigest()
hash_ipfs = hashlib.sha256(ipfs_cat_path.read_bytes()).hexdigest()

invoke_ok = "$INVOKE_OK".lower() == "true"
verify_ok = "$VERIFY_OK".lower() == "true"
history_ok = "$HISTORY_OK".lower() == "true"

cid_match = False
hash_match = False
history_length = 0
history_contains_current = False

if history_ok:
    try:
        history = json.loads(history_path.read_text())
        if isinstance(history, list):
            history_length = len(history)
            for item in history:
                if item.get("cid") == "$CID" and item.get("hash") == "$HASH":
                    cid_match = True
                    hash_match = True
                    history_contains_current = True
                    break
    except Exception:
        history_ok = False

report = {
    "phase": "phase5_s2_fd001_fixed",
    "machine_count": $n_machines,
    "interval_ms": $interval_ms,
    "run_index": $run_idx,
    "machine_id": "$MACHINE_ID",
    "session_id": "$SESSION_ID",
    "cid": "$CID",
    "hash": "$HASH",
    "invoke_ok": invoke_ok,
    "verify_ok": verify_ok,
    "history_ok": history_ok,
    "history_length": history_length,
    "cid_matches_history": cid_match,
    "hash_matches_history": hash_match,
    "history_contains_current_record": history_contains_current,
    "success_end_to_end": all([
        invoke_ok,
        verify_ok,
        history_ok,
        hash_local == "$HASH",
        hash_ipfs == "$HASH",
        history_contains_current
    ]),
    "timing_ms": {
        "snapshot_hash": round(($T1 - $T0), 3),
        "ipfs_add_cid": round(($T2 - $T1), 3),
        "ipfs_cat_check": round(($T3 - $T2), 3),
        "fabric_submit_commit": round(($T4 - $T3), 3),
        "fabric_query_phase": round(($T5 - $T4), 3),
        "end_to_end_total": round(($T5 - $T0), 3)
    }
}
(run_dir / "run_report.json").write_text(json.dumps(report, indent=2))
print(json.dumps(report))
PY

    sleep "$(python3 - <<PY
print($interval_ms / 1000)
PY
)"
  done

  local CASE_END_MS
  CASE_END_MS=$(date +%s%3N)

  python3 - <<PY
import json
import math
import statistics
from pathlib import Path

case_dir = Path("$case_dir")
reports = [json.loads(p.read_text()) for p in sorted(case_dir.glob("run_*/run_report.json"))]

def pct(vals, p):
    vals = sorted(vals)
    if len(vals) == 1:
        return vals[0]
    k = (len(vals) - 1) * (p / 100.0)
    lo = math.floor(k)
    hi = math.ceil(k)
    if lo == hi:
        return vals[int(k)]
    return vals[lo] + (vals[hi] - vals[lo]) * (k - lo)

e2e = [r["timing_ms"]["end_to_end_total"] for r in reports]
ipfs_total = [r["timing_ms"]["ipfs_add_cid"] + r["timing_ms"]["ipfs_cat_check"] for r in reports]
fabric_commit = [r["timing_ms"]["fabric_submit_commit"] for r in reports]
successes = [1 if r["success_end_to_end"] else 0 for r in reports]

wall_clock_s = max((($CASE_END_MS - $CASE_START_MS) / 1000.0), 0.001)
throughput_rps = len(reports) / wall_clock_s

network_cost_bytes = 0
for p in case_dir.glob("run_*/snapshot.json"):
    network_cost_bytes += p.stat().st_size
for p in case_dir.glob("run_*/ipfs_cat.json"):
    network_cost_bytes += p.stat().st_size

summary = {
    "phase": "phase5_s2_fd001_fixed",
    "machine_count": $n_machines,
    "interval_ms": $interval_ms,
    "n_runs": len(reports),
    "wall_clock_s": round(wall_clock_s, 3),
    "success_rate": round(sum(successes) / len(successes), 4) if reports else 0,
    "throughput_rps": round(throughput_rps, 3),
    "network_cost_bytes": network_cost_bytes,
    "latency_ms": {
        "end_to_end": {
            "mean": round(statistics.mean(e2e), 3),
            "median": round(statistics.median(e2e), 3),
            "p95": round(pct(e2e, 95), 3),
            "p99": round(pct(e2e, 99), 3)
        },
        "ipfs_total": {
            "mean": round(statistics.mean(ipfs_total), 3),
            "median": round(statistics.median(ipfs_total), 3),
            "p95": round(pct(ipfs_total, 95), 3),
            "p99": round(pct(ipfs_total, 99), 3)
        },
        "fabric_commit": {
            "mean": round(statistics.mean(fabric_commit), 3),
            "median": round(statistics.median(fabric_commit), 3),
            "p95": round(pct(fabric_commit, 95), 3),
            "p99": round(pct(fabric_commit, 99), 3)
        }
    }
}
(case_dir / "case_summary.json").write_text(json.dumps(summary, indent=2))
print(json.dumps(summary, indent=2))
PY
}

for m in $MACHINE_LEVELS; do
  for i in $INTERVAL_LEVELS_MS; do
    run_case "$m" "$i"
  done
done

python3 - <<PY
import json
from pathlib import Path

runset_dir = Path("$RUNSET_DIR")
cases = [json.loads(p.read_text()) for p in sorted(runset_dir.glob("m*_i*/case_summary.json"))]
cases = sorted(cases, key=lambda c: (c["machine_count"], c["interval_ms"]))

saturation = None
for c in cases:
    if c["success_rate"] < 0.95:
        saturation = {
            "machine_count": c["machine_count"],
            "interval_ms": c["interval_ms"],
            "throughput_rps": c["throughput_rps"],
            "success_rate": c["success_rate"]
        }
        break

final_summary = {
    "phase": "phase5_s2_fd001_fixed",
    "runset_id": runset_dir.name,
    "n_cases": len(cases),
    "cases": cases,
    "first_detected_saturation": saturation
}

(runset_dir / "phase5_s2_summary.json").write_text(json.dumps(final_summary, indent=2))
print(json.dumps(final_summary, indent=2))
PY

echo
echo "RUNSET_DIR=$RUNSET_DIR"
