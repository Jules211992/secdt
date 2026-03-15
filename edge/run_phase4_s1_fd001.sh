#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$HOME/secdt-phase4"
RUNSET_ID="phase4_s1_fd001_$(date -u +%Y%m%dT%H%M%SZ)"
RUNSET_DIR="$BASE_DIR/$RUNSET_ID"
mkdir -p "$RUNSET_DIR"

IPFS_API="${IPFS_API:-http://ipfs-node-1:5001/api/v0}"
N_RUNS="${N_RUNS:-10}"
FIXED_INTERVAL_MS="${FIXED_INTERVAL_MS:-1000}"
SNAPSHOT_SOURCE="${SNAPSHOT_SOURCE:-$HOME/secdt-data/prepared/fd001_snapshots.jsonl}"

FABRIC_DIR="${FABRIC_DIR:-$HOME/secdt-fabric}"
CHANNEL_NAME="${CHANNEL_NAME:-secdt-channel}"
CC_NAME="${CC_NAME:-secdt}"
ORDERER_ADDRESS="${ORDERER_ADDRESS:-orderer-fabric-1:7050}"

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

for i in $(seq 1 "$N_RUNS"); do
  RUN_DIR="$RUNSET_DIR/run_$i"
  mkdir -p "$RUN_DIR"

  python3 - <<PY > "$RUN_DIR/snapshot.json"
from pathlib import Path
src = Path("$SNAPSHOT_SOURCE")
idx = $i - 1
with src.open("r", encoding="utf-8") as f:
    for n, line in enumerate(f):
        if n == idx:
            print(line.strip())
            break
    else:
        raise SystemExit(f"ERROR: index {idx} hors limite dans {src}")
PY

  MACHINE_ID=$(python3 - <<PY
import json
print(json.load(open("$RUN_DIR/snapshot.json"))["machine_id"])
PY
)

  SESSION_ID=$(python3 - <<PY
import json
print(json.load(open("$RUN_DIR/snapshot.json"))["session_id"])
PY
)

  CYCLE=$(python3 - <<PY
import json
print(json.load(open("$RUN_DIR/snapshot.json"))["cycle"])
PY
)

  HEALTH_SCORE=$(python3 - <<PY
import json
print(json.load(open("$RUN_DIR/snapshot.json"))["health_score"])
PY
)

  T0=$(date +%s%3N)

  HASH=$(sha256sum "$RUN_DIR/snapshot.json" | awk '{print $1}')
  T1=$(date +%s%3N)

  curl -sS --fail -X POST -F file=@"$RUN_DIR/snapshot.json" "$IPFS_API/add" > "$RUN_DIR/ipfs_add_result.json"
  CID=$(python3 - <<PY
import json
print(json.load(open("$RUN_DIR/ipfs_add_result.json"))["Hash"])
PY
)
  T2=$(date +%s%3N)

  curl -sS --fail -X POST "$IPFS_API/cat?arg=$CID" > "$RUN_DIR/ipfs_cat.json"
  T3=$(date +%s%3N)

  INVOKE_OK=false
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
    > "$RUN_DIR/fabric_invoke.txt" 2>&1
  then
    INVOKE_OK=true
  fi
  T4=$(date +%s%3N)

  VERIFY_OK=false
  if peer chaincode query \
    -C "$CHANNEL_NAME" \
    -n "$CC_NAME" \
    -c "{\"Args\":[\"VerifyIntegrity\",\"$MACHINE_ID\",\"$HASH\"]}" \
    > "$RUN_DIR/verify.json" 2>&1
  then
    if grep -qx "true" "$RUN_DIR/verify.json"; then
      VERIFY_OK=true
    fi
  fi

  HISTORY_OK=false
  if peer chaincode query \
    -C "$CHANNEL_NAME" \
    -n "$CC_NAME" \
    -c "{\"Args\":[\"GetHistory\",\"$MACHINE_ID\"]}" \
    > "$RUN_DIR/history.json" 2>&1
  then
    HISTORY_OK=true
  fi
  T5=$(date +%s%3N)

  python3 - <<PY
import json
import hashlib
from pathlib import Path

run_dir = Path("$RUN_DIR")
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

if history_ok:
    try:
        history = json.loads(history_path.read_text())
        if isinstance(history, list):
            history_length = len(history)
            if history_length > 0:
                last = next((h for h in history if h.get("cid") == "$CID"), history[-1])
                cid_match = last.get("cid") == "$CID"
                hash_match = last.get("hash") == "$HASH"
    except Exception:
        history_ok = False

report = {
    "run_index": $i,
    "machine_id": "$MACHINE_ID",
    "cid": "$CID",
    "hash": "$HASH",
    "invoke_ok": invoke_ok,
    "verify_ok": verify_ok,
    "history_ok": history_ok,
    "history_length": history_length,
    "cid_matches_history": cid_match,
    "hash_matches_history": hash_match,
    "success_end_to_end": all([
        invoke_ok,
        verify_ok,
        history_ok,
        hash_local == "$HASH",
        hash_ipfs == "$HASH",
        cid_match,
        hash_match
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
print(json.dumps(report, indent=2))
PY

  cat "$RUN_DIR/run_report.json" >> "$RUNSET_DIR/runs_index.jsonl"
  echo >> "$RUNSET_DIR/runs_index.jsonl"

  sleep $(python3 - <<PY
print($FIXED_INTERVAL_MS / 1000)
PY
)
done

python3 - <<PY
import json
import statistics
import math
from pathlib import Path

runset_dir = Path("$RUNSET_DIR")
runs = []

with open(runset_dir / "runs_index.jsonl", "r", encoding="utf-8") as f:
    content = f.read().strip()

decoder = json.JSONDecoder()
idx = 0
while idx < len(content):
    while idx < len(content) and content[idx].isspace():
        idx += 1
    if idx >= len(content):
        break
    obj, end = decoder.raw_decode(content, idx)
    runs.append(obj)
    idx = end

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

e2e = [r["timing_ms"]["end_to_end_total"] for r in runs]
ipfs_total = [r["timing_ms"]["ipfs_add_cid"] + r["timing_ms"]["ipfs_cat_check"] for r in runs]
fabric_commit = [r["timing_ms"]["fabric_submit_commit"] for r in runs]
successes = [1 if r["success_end_to_end"] else 0 for r in runs]

summary = {
    "phase": "phase4_s1_fd001",
    "runset_id": "$RUNSET_ID",
    "n_runs": len(runs),
    "snapshot_source": "$SNAPSHOT_SOURCE",
    "success_rate": round(sum(successes) / len(successes), 4) if runs else 0,
    "emission_interval_ms": $FIXED_INTERVAL_MS,
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

(runset_dir / "phase4_s1_summary.json").write_text(json.dumps(summary, indent=2))
print(json.dumps(summary, indent=2))
PY

echo
echo "RUNSET_DIR=$RUNSET_DIR"
