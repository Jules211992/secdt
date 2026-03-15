#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$HOME/secdt-phase9"
RUNSET_ID="phase9_s6_$(date -u +%Y%m%dT%H%M%SZ)"
RUNSET_DIR="$BASE_DIR/$RUNSET_ID"
mkdir -p "$RUNSET_DIR"

IPFS_API="${IPFS_API:-http://ipfs-node-1:5001/api/v0}"
SNAPSHOT_SOURCE="${SNAPSHOT_SOURCE:-$HOME/secdt-data/prepared/fd001_snapshots.jsonl}"

SSH_KEY="${SSH_KEY:-$HOME/.ssh/fl-ids-key.pem}"
SSH_OPTS="-i $SSH_KEY -o StrictHostKeyChecking=no"

IPFS_TARGET_1="${IPFS_TARGET_1:-ubuntu@ipfs-node-4}"
IPFS_TARGET_2="${IPFS_TARGET_2:-ubuntu@ipfs-node-5}"
PEER_TARGET="${PEER_TARGET:-ubuntu@peer-fabric-2}"
ORDERER_TARGET="${ORDERER_TARGET:-ubuntu@orderer-fabric-2}"

IPFS_CONTAINER_NAME="${IPFS_CONTAINER_NAME:-ipfs-node}"
PEER_CONTAINER_NAME="${PEER_CONTAINER_NAME:-secdt-fabric_peer_1}"
ORDERER_CONTAINER_NAME="${ORDERER_CONTAINER_NAME:-secdt-fabric_orderer_1}"

FABRIC_DIR="${FABRIC_DIR:-$HOME/secdt-fabric}"
CHANNEL_NAME="${CHANNEL_NAME:-secdt-channel}"
CC_NAME="${CC_NAME:-secdt}"
ORDERER_ADDRESS="${ORDERER_ADDRESS:-orderer-fabric-1:7050}"

command -v curl >/dev/null 2>&1
command -v peer >/dev/null 2>&1
command -v python3 >/dev/null 2>&1
command -v sha256sum >/dev/null 2>&1
command -v ssh >/dev/null 2>&1

cd "$FABRIC_DIR"
export PATH=$PATH:~/fabric-samples/bin
export CORE_PEER_LOCALMSPID=PeerMSP
export CORE_PEER_MSPCONFIGPATH=~/secdt-fabric/crypto-config/peerOrganizations/secdt.com/users/Admin@secdt.com/msp
export CORE_PEER_ADDRESS=peer-fabric-1:7051
export CORE_PEER_TLS_ENABLED=true
export CORE_PEER_TLS_ROOTCERT_FILE=~/secdt-fabric/crypto-config/peerOrganizations/secdt.com/peers/peer-fabric-1.secdt.com/tls/ca.crt
export ORDERER_CA=~/secdt-fabric/crypto-config/ordererOrganizations/secdt.com/orderers/orderer-fabric-1.secdt.com/tls/ca.crt
export PEER_CA=~/secdt-fabric/crypto-config/peerOrganizations/secdt.com/peers/peer-fabric-1.secdt.com/tls/ca.crt

fetch_snapshot() {
  local idx="$1"
  local out="$2"
  python3 - <<PY > "$out"
from pathlib import Path
src = Path("$SNAPSHOT_SOURCE")
idx = $idx
with src.open("r", encoding="utf-8") as f:
    for n, line in enumerate(f):
        if n == idx:
            print(line.strip())
            break
    else:
        raise SystemExit(f"snapshot index {idx} introuvable")
PY
}

ssh_exec() {
  local target="$1"
  local cmd="$2"
  ssh $SSH_OPTS "$target" "$cmd"
}

stop_container() {
  local target="$1"
  local cname="$2"
  ssh_exec "$target" "sudo docker stop $cname >/dev/null 2>&1 || true"
}

start_container() {
  local target="$1"
  local cname="$2"
  ssh_exec "$target" "sudo docker start $cname >/dev/null 2>&1 || true"
}

wait_container_running() {
  local target="$1"
  local cname="$2"
  local timeout="${3:-120}"
  local t0
  t0=$(date +%s)
  while true; do
    if ssh_exec "$target" "sudo docker ps --format '{{.Names}}' | grep -qx '$cname'"; then
      return 0
    fi
    if [ $(( $(date +%s) - t0 )) -ge "$timeout" ]; then
      return 1
    fi
    sleep 2
  done
}

wait_ipfs_retrieval() {
  local cid="$1"
  local outfile="$2"
  local timeout="${3:-120}"
  local t0
  t0=$(date +%s%3N)
  while true; do
    if curl -sS --fail -X POST "$IPFS_API/cat?arg=$cid" > "$outfile" 2>/dev/null; then
      local t1
      t1=$(date +%s%3N)
      echo $((t1 - t0))
      return 0
    fi
    if [ $(( $(date +%s%3N) - t0 )) -ge $((timeout * 1000)) ]; then
      return 1
    fi
    sleep 2
  done
}

register_state() {
  local machine_id="$1"
  local cid="$2"
  local health="$3"
  local cycle="$4"
  local session_id="$5"
  local hash="$6"
  local out="$7"

  peer chaincode invoke \
    -o "$ORDERER_ADDRESS" \
    --tls --cafile "$ORDERER_CA" \
    -C "$CHANNEL_NAME" \
    -n "$CC_NAME" \
    --peerAddresses peer-fabric-1:7051 \
    --tlsRootCertFiles "$PEER_CA" \
    --waitForEvent \
    --waitForEventTimeout 30s \
    -c "{\"Args\":[\"RegisterState\",\"$machine_id\",\"$cid\",\"$health\",\"$cycle\",\"$session_id\",\"$hash\"]}" \
    > "$out" 2>&1
}

query_history() {
  local machine_id="$1"
  local out="$2"
  peer chaincode query \
    -C "$CHANNEL_NAME" \
    -n "$CC_NAME" \
    -c "{\"Args\":[\"GetHistory\",\"$machine_id\"]}" \
    > "$out" 2>&1
}

build_unique_snapshot() {
  local idx="$1"
  local tag="$2"
  local out="$3"
  python3 - <<PY > "$out"
import json
from pathlib import Path
src = Path("$SNAPSHOT_SOURCE")
idx = $idx
line = None
with src.open("r", encoding="utf-8") as f:
    for n, row in enumerate(f):
        if n == idx:
            line = row
            break
if line is None:
    raise SystemExit("snapshot introuvable")
obj = json.loads(line)
obj["machine_id"] = obj["machine_id"] + "-$tag"
obj["session_id"] = obj["session_id"] + "-$tag"
print(json.dumps(obj, separators=(",", ":")))
PY
}

scenario_ipfs_loss() {
  local scenario_name="$1"
  local stop_one="$2"
  local stop_two="${3:-}"

  local SDIR="$RUNSET_DIR/$scenario_name"
  mkdir -p "$SDIR"

  build_unique_snapshot 0 "$scenario_name-$RUNSET_ID" "$SDIR/snapshot.json"

  local MACHINE_ID SESSION_ID CYCLE HEALTH HASH CID
  MACHINE_ID=$(python3 - <<PY
import json
print(json.load(open("$SDIR/snapshot.json"))["machine_id"])
PY
)
  SESSION_ID=$(python3 - <<PY
import json
print(json.load(open("$SDIR/snapshot.json"))["session_id"])
PY
)
  CYCLE=$(python3 - <<PY
import json
print(json.load(open("$SDIR/snapshot.json"))["cycle"])
PY
)
  HEALTH=$(python3 - <<PY
import json
print(json.load(open("$SDIR/snapshot.json"))["health_score"])
PY
)
  HASH=$(sha256sum "$SDIR/snapshot.json" | awk '{print $1}')

  curl -sS --fail -X POST -F file=@"$SDIR/snapshot.json" "$IPFS_API/add" > "$SDIR/ipfs_add.json"
  CID=$(python3 - <<PY
import json
print(json.load(open("$SDIR/ipfs_add.json"))["Hash"])
PY
)

  register_state "$MACHINE_ID" "$CID" "$HEALTH" "$CYCLE" "$SESSION_ID" "$HASH" "$SDIR/invoke_before_failure.txt"
  query_history "$MACHINE_ID" "$SDIR/history_before_failure.json" || true

  stop_container "$stop_one" "$IPFS_CONTAINER_NAME"
  if [ -n "$stop_two" ]; then
    stop_container "$stop_two" "$IPFS_CONTAINER_NAME"
  fi

  local RECOVERY_MS=""
  local RETRIEVABLE=false
  if RECOVERY_MS=$(wait_ipfs_retrieval "$CID" "$SDIR/ipfs_cat_after_failure.json" 120); then
    RETRIEVABLE=true
  else
    RETRIEVABLE=false
  fi

  query_history "$MACHINE_ID" "$SDIR/history_after_failure.json" || true

  start_container "$stop_one" "$IPFS_CONTAINER_NAME"
  wait_container_running "$stop_one" "$IPFS_CONTAINER_NAME" 120 || true

  if [ -n "$stop_two" ]; then
    start_container "$stop_two" "$IPFS_CONTAINER_NAME"
    wait_container_running "$stop_two" "$IPFS_CONTAINER_NAME" 120 || true
  fi

  python3 - <<PY > "$SDIR/scenario_report.json"
import json, hashlib
from pathlib import Path

cid = "$CID"
hash_expected = "$HASH"
retrievable = "$RETRIEVABLE".lower() == "true"
recovery_ms = None if "$RECOVERY_MS" == "" else int("$RECOVERY_MS")

history_ok = False
history_len = 0
for hp in [Path("$SDIR/history_after_failure.json"), Path("$SDIR/history_before_failure.json")]:
    try:
        hist = json.loads(hp.read_text())
        if isinstance(hist, list):
            history_ok = True
            history_len = len(hist)
            break
    except Exception:
        pass

ipfs_hash = None
consistent = False
cat_path = Path("$SDIR/ipfs_cat_after_failure.json")
if cat_path.exists():
    ipfs_hash = hashlib.sha256(cat_path.read_bytes()).hexdigest()
    consistent = ipfs_hash == hash_expected

report = {
    "scenario": "$scenario_name",
    "cid": cid,
    "expected_hash": hash_expected,
    "retrievable_after_failure": retrievable,
    "recovery_ms": recovery_ms,
    "auditability_preserved": history_ok,
    "history_length": history_len,
    "retrieved_hash": ipfs_hash,
    "cid_hash_consistent": consistent,
    "success": retrievable and history_ok and consistent
}
print(json.dumps(report, indent=2))
PY
}

scenario_peer_loss() {
  local scenario_name="s6_peer_loss"
  local SDIR="$RUNSET_DIR/$scenario_name"
  mkdir -p "$SDIR"

  build_unique_snapshot 1 "$scenario_name-$RUNSET_ID" "$SDIR/snapshot.json"

  local MACHINE_ID SESSION_ID CYCLE HEALTH HASH CID
  MACHINE_ID=$(python3 - <<PY
import json
print(json.load(open("$SDIR/snapshot.json"))["machine_id"])
PY
)
  SESSION_ID=$(python3 - <<PY
import json
print(json.load(open("$SDIR/snapshot.json"))["session_id"])
PY
)
  CYCLE=$(python3 - <<PY
import json
print(json.load(open("$SDIR/snapshot.json"))["cycle"])
PY
)
  HEALTH=$(python3 - <<PY
import json
print(json.load(open("$SDIR/snapshot.json"))["health_score"])
PY
)
  HASH=$(sha256sum "$SDIR/snapshot.json" | awk '{print $1}')

  curl -sS --fail -X POST -F file=@"$SDIR/snapshot.json" "$IPFS_API/add" > "$SDIR/ipfs_add.json"
  CID=$(python3 - <<PY
import json
print(json.load(open("$SDIR/ipfs_add.json"))["Hash"])
PY
)

  stop_container "$PEER_TARGET" "$PEER_CONTAINER_NAME"

  local T0 T1 INVOKE_OK=false
  T0=$(date +%s%3N)
  if register_state "$MACHINE_ID" "$CID" "$HEALTH" "$CYCLE" "$SESSION_ID" "$HASH" "$SDIR/invoke_under_peer_failure.txt"; then
    INVOKE_OK=true
  fi
  T1=$(date +%s%3N)

  query_history "$MACHINE_ID" "$SDIR/history_under_peer_failure.json" || true

  start_container "$PEER_TARGET" "$PEER_CONTAINER_NAME"
  wait_container_running "$PEER_TARGET" "$PEER_CONTAINER_NAME" 120 || true

  python3 - <<PY > "$SDIR/scenario_report.json"
import json
from pathlib import Path

invoke_ok = "$INVOKE_OK".lower() == "true"
history_ok = False
history_len = 0
try:
    hist = json.loads(Path("$SDIR/history_under_peer_failure.json").read_text())
    if isinstance(hist, list):
        history_ok = True
        history_len = len(hist)
except Exception:
    pass

report = {
    "scenario": "$scenario_name",
    "peer_target": "$PEER_TARGET",
    "invoke_ok_during_peer_loss": invoke_ok,
    "history_ok_after_peer_loss": history_ok,
    "history_length": history_len,
    "service_continuity_preserved": invoke_ok and history_ok,
    "recovery_ms": None,
    "latency_under_failure_ms": int($T1 - $T0),
    "success": invoke_ok and history_ok
}
print(json.dumps(report, indent=2))
PY
}

scenario_orderer_loss() {
  local scenario_name="s6_orderer_loss"
  local SDIR="$RUNSET_DIR/$scenario_name"
  mkdir -p "$SDIR"

  build_unique_snapshot 2 "$scenario_name-$RUNSET_ID" "$SDIR/snapshot.json"

  local MACHINE_ID SESSION_ID CYCLE HEALTH HASH CID
  MACHINE_ID=$(python3 - <<PY
import json
print(json.load(open("$SDIR/snapshot.json"))["machine_id"])
PY
)
  SESSION_ID=$(python3 - <<PY
import json
print(json.load(open("$SDIR/snapshot.json"))["session_id"])
PY
)
  CYCLE=$(python3 - <<PY
import json
print(json.load(open("$SDIR/snapshot.json"))["cycle"])
PY
)
  HEALTH=$(python3 - <<PY
import json
print(json.load(open("$SDIR/snapshot.json"))["health_score"])
PY
)
  HASH=$(sha256sum "$SDIR/snapshot.json" | awk '{print $1}')

  curl -sS --fail -X POST -F file=@"$SDIR/snapshot.json" "$IPFS_API/add" > "$SDIR/ipfs_add.json"
  CID=$(python3 - <<PY
import json
print(json.load(open("$SDIR/ipfs_add.json"))["Hash"])
PY
)

  stop_container "$ORDERER_TARGET" "$ORDERER_CONTAINER_NAME"

  local T0 T1 INVOKE_OK=false
  T0=$(date +%s%3N)
  if register_state "$MACHINE_ID" "$CID" "$HEALTH" "$CYCLE" "$SESSION_ID" "$HASH" "$SDIR/invoke_under_orderer_failure.txt"; then
    INVOKE_OK=true
  fi
  T1=$(date +%s%3N)

  query_history "$MACHINE_ID" "$SDIR/history_under_orderer_failure.json" || true

  start_container "$ORDERER_TARGET" "$ORDERER_CONTAINER_NAME"
  wait_container_running "$ORDERER_TARGET" "$ORDERER_CONTAINER_NAME" 120 || true

  python3 - <<PY > "$SDIR/scenario_report.json"
import json
from pathlib import Path

invoke_ok = "$INVOKE_OK".lower() == "true"
history_ok = False
history_len = 0
try:
    hist = json.loads(Path("$SDIR/history_under_orderer_failure.json").read_text())
    if isinstance(hist, list):
        history_ok = True
        history_len = len(hist)
except Exception:
    pass

report = {
    "scenario": "$scenario_name",
    "orderer_target": "$ORDERER_TARGET",
    "invoke_ok_during_orderer_loss": invoke_ok,
    "history_ok_after_orderer_loss": history_ok,
    "history_length": history_len,
    "service_continuity_preserved": invoke_ok and history_ok,
    "recovery_ms": None,
    "latency_under_failure_ms": int($T1 - $T0),
    "success": invoke_ok and history_ok
}
print(json.dumps(report, indent=2))
PY
}

scenario_ipfs_loss "s6_ipfs_loss_1_node" "$IPFS_TARGET_1"
scenario_ipfs_loss "s6_ipfs_loss_2_nodes" "$IPFS_TARGET_1" "$IPFS_TARGET_2"
scenario_peer_loss
scenario_orderer_loss

python3 - <<PY > "$RUNSET_DIR/phase9_s6_summary.json"
import json
from pathlib import Path

root = Path("$RUNSET_DIR")
reports = []
for p in sorted(root.glob("*/scenario_report.json")):
    reports.append(json.loads(p.read_text()))

summary = {
    "phase": "phase9_s6",
    "runset_id": "$RUNSET_ID",
    "n_scenarios": len(reports),
    "scenarios": reports,
    "metrics": {
        "availability_rate": round(sum(1 for r in reports if r.get("success")) / len(reports), 4) if reports else 0.0,
        "ipfs_retrievability_rate": round(sum(1 for r in reports if r.get("scenario","").startswith("s6_ipfs") and r.get("retrievable_after_failure")) / max(1, sum(1 for r in reports if r.get("scenario","").startswith("s6_ipfs"))), 4),
        "service_continuity_rate": round(sum(1 for r in reports if r.get("service_continuity_preserved")) / max(1, sum(1 for r in reports if "service_continuity_preserved" in r)), 4),
        "auditability_preserved_rate": round(sum(1 for r in reports if r.get("auditability_preserved", r.get("history_ok_after_peer_loss", r.get("history_ok_after_orderer_loss", False)))) / len(reports), 4) if reports else 0.0
    }
}
print(json.dumps(summary, indent=2))
PY

echo "RUNSET_DIR=$RUNSET_DIR"
cat "$RUNSET_DIR/phase9_s6_summary.json"
