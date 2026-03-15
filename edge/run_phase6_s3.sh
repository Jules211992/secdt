#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$HOME/secdt-phase6"
RUNSET_ID="phase6_s3_$(date -u +%Y%m%dT%H%M%SZ)"
RUNSET_DIR="$BASE_DIR/$RUNSET_ID"
mkdir -p "$RUNSET_DIR"

IPFS_API="${IPFS_API:-http://ipfs-node-1:5001/api/v0}"
SNAPSHOT_SOURCE="${SNAPSHOT_SOURCE:-$HOME/secdt-data/prepared/fd001_snapshots.jsonl}"

FABRIC_DIR="${FABRIC_DIR:-$HOME/secdt-fabric}"
CHANNEL_NAME="${CHANNEL_NAME:-secdt-channel}"
CC_NAME="${CC_NAME:-secdt}"
ORDERER_ADDRESS="${ORDERER_ADDRESS:-orderer-fabric-1:7050}"

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

hash_file() {
  sha256sum "$1" | awk '{print $1}'
}

ipfs_add() {
  local in_file="$1"
  local out_json="$2"
  curl -sS --fail -X POST -F file=@"$in_file" "$IPFS_API/add" > "$out_json"
}

ipfs_cat() {
  local cid="$1"
  local out_file="$2"
  curl -sS --fail -X POST "$IPFS_API/cat?arg=$cid" > "$out_file"
}

fabric_invoke_register() {
  local machine_id="$1"
  local cid="$2"
  local health_score="$3"
  local cycle="$4"
  local session_id="$5"
  local hash="$6"
  local out_file="$7"

  peer chaincode invoke \
    -o "$ORDERER_ADDRESS" \
    --tls --cafile "$ORDERER_CA" \
    -C "$CHANNEL_NAME" \
    -n "$CC_NAME" \
    --peerAddresses peer-fabric-1:7051 \
    --tlsRootCertFiles "$PEER_CA" \
    --waitForEvent \
    --waitForEventTimeout 30s \
    -c "{\"Args\":[\"RegisterState\",\"$machine_id\",\"$cid\",\"$health_score\",\"$cycle\",\"$session_id\",\"$hash\"]}" \
    > "$out_file" 2>&1
}

fabric_query_verify() {
  local machine_id="$1"
  local hash="$2"
  local out_file="$3"

  peer chaincode query \
    -C "$CHANNEL_NAME" \
    -n "$CC_NAME" \
    -c "{\"Args\":[\"VerifyIntegrity\",\"$machine_id\",\"$hash\"]}" \
    > "$out_file" 2>&1
}

fabric_query_history() {
  local machine_id="$1"
  local out_file="$2"

  peer chaincode query \
    -C "$CHANNEL_NAME" \
    -n "$CC_NAME" \
    -c "{\"Args\":[\"GetHistory\",\"$machine_id\"]}" \
    > "$out_file" 2>&1
}

scenario_tampering_before_anchoring() {
  local d="$RUNSET_DIR/s1_tampering_before_anchoring"
  mkdir -p "$d"

  fetch_snapshot 0 "$d/original.json"

  python3 - <<PY > "$d/tampered.json"
import json
from pathlib import Path
obj = json.loads(Path("$d/original.json").read_text())
obj["machine_id"] = obj["machine_id"] + "-$RUNSET_ID-s1"
obj["session_id"] = obj["session_id"] + "-$RUNSET_ID-s1"
obj["sensor_11"] = round(float(obj["sensor_11"]) + 5.0, 4)
print(json.dumps(obj, separators=(",", ":")))
PY

  ORIG_HASH=$(hash_file "$d/original.json")
  TAMP_HASH=$(hash_file "$d/tampered.json")

  ipfs_add "$d/original.json" "$d/ipfs_add_original.json"
  CID=$(python3 - <<PY
import json
print(json.load(open("$d/ipfs_add_original.json"))["Hash"])
PY
)

  python3 - <<PY > "$d/meta.json"
import json
obj = json.loads(open("$d/tampered.json").read())
print(json.dumps({
  "machine_id": obj["machine_id"],
  "session_id": obj["session_id"],
  "cycle": obj["cycle"],
  "health_score": obj["health_score"]
}, indent=2))
PY

  MACHINE_ID=$(python3 - <<PY
import json
print(json.load(open("$d/meta.json"))["machine_id"])
PY
)
  SESSION_ID=$(python3 - <<PY
import json
print(json.load(open("$d/meta.json"))["session_id"])
PY
)
  CYCLE=$(python3 - <<PY
import json
print(json.load(open("$d/meta.json"))["cycle"])
PY
)
  HEALTH_SCORE=$(python3 - <<PY
import json
print(json.load(open("$d/meta.json"))["health_score"])
PY
)

  INVOKE_OK=true
  fabric_invoke_register "$MACHINE_ID" "$CID" "$HEALTH_SCORE" "$CYCLE" "$SESSION_ID" "$TAMP_HASH" "$d/fabric_invoke.txt" || INVOKE_OK=false

  fabric_query_verify "$MACHINE_ID" "$TAMP_HASH" "$d/verify.txt" || true
  fabric_query_history "$MACHINE_ID" "$d/history.json" || true
  ipfs_cat "$CID" "$d/ipfs_cat.json" || true

  python3 - <<PY > "$d/scenario_report.json"
import json, hashlib
from pathlib import Path

d = Path("$d")
orig = d/"original.json"
tam = d/"tampered.json"
catf = d/"ipfs_cat.json"
verify = (d/"verify.txt").read_text().strip() if (d/"verify.txt").exists() else ""
history = json.loads((d/"history.json").read_text()) if (d/"history.json").exists() else []

orig_hash = hashlib.sha256(orig.read_bytes()).hexdigest()
tam_hash = hashlib.sha256(tam.read_bytes()).hexdigest()
ipfs_hash = hashlib.sha256(catf.read_bytes()).hexdigest() if catf.exists() else None

report = {
  "scenario": "tampering_before_anchoring",
  "invoke_ok": "$INVOKE_OK".lower() == "true",
  "verify_integrity_result": verify,
  "original_hash": orig_hash,
  "tampered_hash": tam_hash,
  "ipfs_hash": ipfs_hash,
  "hash_cid_consistent_after_tampering": tam_hash == ipfs_hash,
  "tampering_detected": tam_hash != ipfs_hash,
  "history_length": len(history)
}
print(json.dumps(report, indent=2))
PY
}

scenario_replay_stale_snapshot() {
  local d="$RUNSET_DIR/s2_replay_stale_snapshot"
  mkdir -p "$d"

  fetch_snapshot 1 "$d/old_base.json"
  fetch_snapshot 2 "$d/new_base.json"

  python3 - <<PY > "$d/old.json"
import json
from pathlib import Path
obj = json.loads(Path("$d/old_base.json").read_text())
obj["machine_id"] = "machine-replay-$RUNSET_ID"
obj["session_id"] = "session-replay-old-$RUNSET_ID"
print(json.dumps(obj, separators=(",", ":")))
PY

  python3 - <<PY > "$d/new.json"
import json
from pathlib import Path
obj = json.loads(Path("$d/new_base.json").read_text())
obj["machine_id"] = "machine-replay-$RUNSET_ID"
obj["session_id"] = "session-replay-new-$RUNSET_ID"
obj["cycle"] = int(obj["cycle"]) + 50
print(json.dumps(obj, separators=(",", ":")))
PY

  OLD_HASH=$(hash_file "$d/old.json")
  NEW_HASH=$(hash_file "$d/new.json")

  ipfs_add "$d/new.json" "$d/ipfs_add_new.json"
  NEW_CID=$(python3 - <<PY
import json
print(json.load(open("$d/ipfs_add_new.json"))["Hash"])
PY
)

  ipfs_add "$d/old.json" "$d/ipfs_add_old.json"
  OLD_CID=$(python3 - <<PY
import json
print(json.load(open("$d/ipfs_add_old.json"))["Hash"])
PY
)

  M="machine-replay-$RUNSET_ID"

  NEW_CYCLE=$(python3 - <<PY
import json
print(json.load(open("$d/new.json"))["cycle"])
PY
)
  NEW_HS=$(python3 - <<PY
import json
print(json.load(open("$d/new.json"))["health_score"])
PY
)

  OLD_CYCLE=$(python3 - <<PY
import json
print(json.load(open("$d/old.json"))["cycle"])
PY
)
  OLD_HS=$(python3 - <<PY
import json
print(json.load(open("$d/old.json"))["health_score"])
PY
)

  fabric_invoke_register "$M" "$NEW_CID" "$NEW_HS" "$NEW_CYCLE" "session-replay-new-$RUNSET_ID" "$NEW_HASH" "$d/invoke_new.txt" || true
  fabric_invoke_register "$M" "$OLD_CID" "$OLD_HS" "$OLD_CYCLE" "session-replay-old-$RUNSET_ID" "$OLD_HASH" "$d/invoke_old.txt" || true

  fabric_query_history "$M" "$d/history.json" || true

  python3 - <<PY > "$d/scenario_report.json"
import json
from pathlib import Path

hist = json.loads(Path("$d/history.json").read_text()) if Path("$d/history.json").exists() else []
cycles = [int(x.get("cycle", -1)) for x in hist]
report = {
  "scenario": "replay_stale_snapshot",
  "history_length": len(hist),
  "cycles_seen": cycles,
  "stale_replay_submitted": True,
  "replay_detectable_in_audit": len(cycles) >= 2 and cycles != sorted(cycles),
  "max_cycle": max(cycles) if cycles else None,
  "min_cycle": min(cycles) if cycles else None
}
print(json.dumps(report, indent=2))
PY
}

scenario_unauthorized_registration() {
  local d="$RUNSET_DIR/s3_unauthorized_registration"
  mkdir -p "$d"

  fetch_snapshot 3 "$d/base.json"

  python3 - <<PY > "$d/snapshot.json"
import json
from pathlib import Path
obj = json.loads(Path("$d/base.json").read_text())
obj["machine_id"] = obj["machine_id"] + "-unauth-$RUNSET_ID"
obj["session_id"] = obj["session_id"] + "-unauth-$RUNSET_ID"
print(json.dumps(obj, separators=(",", ":")))
PY

  HASH=$(hash_file "$d/snapshot.json")
  ipfs_add "$d/snapshot.json" "$d/ipfs_add.json"
  CID=$(python3 - <<PY
import json
print(json.load(open("$d/ipfs_add.json"))["Hash"])
PY
)

  MACHINE_ID=$(python3 - <<PY
import json
print(json.load(open("$d/snapshot.json"))["machine_id"])
PY
)
  SESSION_ID=$(python3 - <<PY
import json
print(json.load(open("$d/snapshot.json"))["session_id"])
PY
)
  CYCLE=$(python3 - <<PY
import json
print(json.load(open("$d/snapshot.json"))["cycle"])
PY
)
  HEALTH_SCORE=$(python3 - <<PY
import json
print(json.load(open("$d/snapshot.json"))["health_score"])
PY
)

  export CORE_PEER_MSPCONFIGPATH=~/secdt-fabric/crypto-config/peerOrganizations/secdt.com/peers/peer-fabric-1.secdt.com/msp

  INVOKE_OK=true
  peer chaincode invoke \
    -o "$ORDERER_ADDRESS" \
    --tls --cafile "$ORDERER_CA" \
    -C "$CHANNEL_NAME" \
    -n "$CC_NAME" \
    --peerAddresses peer-fabric-1:7051 \
    --tlsRootCertFiles "$PEER_CA" \
    --waitForEvent \
    --waitForEventTimeout 20s \
    -c "{\"Args\":[\"RegisterState\",\"$MACHINE_ID\",\"$CID\",\"$HEALTH_SCORE\",\"$CYCLE\",\"$SESSION_ID\",\"$HASH\"]}" \
    > "$d/unauthorized_invoke.txt" 2>&1 || INVOKE_OK=false

  export CORE_PEER_MSPCONFIGPATH=~/secdt-fabric/crypto-config/peerOrganizations/secdt.com/users/Admin@secdt.com/msp

  python3 - <<PY > "$d/scenario_report.json"
import json
from pathlib import Path
txt = Path("$d/unauthorized_invoke.txt").read_text()
report = {
  "scenario": "unauthorized_registration",
  "invoke_ok": "$INVOKE_OK".lower() == "true",
  "access_control_enforced": "$INVOKE_OK".lower() != "true",
  "raw_result_excerpt": txt[:1000]
}
print(json.dumps(report, indent=2))
PY
}

scenario_audit_reconstruction() {
  local d="$RUNSET_DIR/s4_audit_reconstruction"
  mkdir -p "$d"

  fetch_snapshot 4 "$d/base.json"

  python3 - <<PY > "$d/snapshot.json"
import json
from pathlib import Path
obj = json.loads(Path("$d/base.json").read_text())
obj["machine_id"] = "machine-audit-$RUNSET_ID"
obj["session_id"] = "session-audit-$RUNSET_ID"
print(json.dumps(obj, separators=(",", ":")))
PY

  HASH=$(hash_file "$d/snapshot.json")
  ipfs_add "$d/snapshot.json" "$d/ipfs_add.json"
  CID=$(python3 - <<PY
import json
print(json.load(open("$d/ipfs_add.json"))["Hash"])
PY
)

  MACHINE_ID="machine-audit-$RUNSET_ID"
  SESSION_ID="session-audit-$RUNSET_ID"
  CYCLE=$(python3 - <<PY
import json
print(json.load(open("$d/snapshot.json"))["cycle"])
PY
)
  HEALTH_SCORE=$(python3 - <<PY
import json
print(json.load(open("$d/snapshot.json"))["health_score"])
PY
)

  fabric_invoke_register "$MACHINE_ID" "$CID" "$HEALTH_SCORE" "$CYCLE" "$SESSION_ID" "$HASH" "$d/invoke.txt" || true
  fabric_query_history "$MACHINE_ID" "$d/history.json" || true
  ipfs_cat "$CID" "$d/ipfs_cat.json" || true

  python3 - <<PY > "$d/scenario_report.json"
import json, hashlib
from pathlib import Path

hist = json.loads(Path("$d/history.json").read_text()) if Path("$d/history.json").exists() else []
ipfs_file = Path("$d/ipfs_cat.json")
snap_hash = hashlib.sha256(ipfs_file.read_bytes()).hexdigest() if ipfs_file.exists() else None

ok = False
if hist:
    rec = hist[-1]
    ok = rec.get("cid") == "$CID" and rec.get("hash") == "$HASH" and snap_hash == "$HASH"

report = {
  "scenario": "audit_reconstruction",
  "history_length": len(hist),
  "cid": "$CID",
  "expected_hash": "$HASH",
  "reconstructed_hash_from_ipfs": snap_hash,
  "audit_reconstruction_success": ok
}
print(json.dumps(report, indent=2))
PY
}

scenario_tampering_before_anchoring
scenario_replay_stale_snapshot
scenario_unauthorized_registration
scenario_audit_reconstruction

python3 - <<PY > "$RUNSET_DIR/phase6_s3_summary.json"
import json
from pathlib import Path

root = Path("$RUNSET_DIR")
reports = []
for p in sorted(root.glob("s*/scenario_report.json")):
    reports.append(json.loads(p.read_text()))

summary = {
  "phase": "phase6_s3",
  "runset_id": "$RUNSET_ID",
  "n_scenarios": len(reports),
  "scenarios": reports
}
print(json.dumps(summary, indent=2))
PY

echo "RUNSET_DIR=$RUNSET_DIR"
cat "$RUNSET_DIR/phase6_s3_summary.json"
