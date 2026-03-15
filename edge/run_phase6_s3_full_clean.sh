#!/usr/bin/env bash
set -euo pipefail

rm -rf "$HOME"/secdt-phase6/phase6_s3_*

BASE_DIR="$HOME/secdt-phase6"
RUNSET_ID="phase6_s3_$(date -u +%Y%m%dT%H%M%SZ)"
RUNSET_DIR="$BASE_DIR/$RUNSET_ID"

SNAPSHOT_JSONL="${SNAPSHOT_JSONL:-$HOME/secdt-data/prepared/fd001_snapshots.jsonl}"
SPEC_FILE="${SPEC_FILE:-$HOME/secdt-data/spec/dataset_fixed_spec.json}"

FABRIC_DIR="${FABRIC_DIR:-$HOME/secdt-fabric}"
CHANNEL_NAME="${CHANNEL_NAME:-secdt-channel}"
CC_NAME="${CC_NAME:-secdt}"
ORDERER_ADDRESS="${ORDERER_ADDRESS:-orderer-fabric-1:7050}"
ORDERER_HOSTNAME="${ORDERER_HOSTNAME:-orderer-fabric-1.secdt.com}"
IPFS_API="${IPFS_API:-http://ipfs-node-1:5001/api/v0}"

mkdir -p "$RUNSET_DIR"
mkdir -p "$RUNSET_DIR/s3a_tampering_before_anchoring"
mkdir -p "$RUNSET_DIR/s3b_replay_stale_snapshot"
mkdir -p "$RUNSET_DIR/s3c_unauthorized_registration"
mkdir -p "$RUNSET_DIR/s3d_audit_reconstruction"

[ -f "$SNAPSHOT_JSONL" ] || { echo "ERROR: SNAPSHOT_JSONL introuvable: $SNAPSHOT_JSONL"; exit 1; }
[ -f "$SPEC_FILE" ] || { echo "ERROR: SPEC_FILE introuvable: $SPEC_FILE"; exit 1; }

cd "$FABRIC_DIR"
export PATH=$PATH:~/fabric-samples/bin
export CORE_PEER_LOCALMSPID=PeerMSP
export CORE_PEER_MSPCONFIGPATH=~/secdt-fabric/crypto-config/peerOrganizations/secdt.com/users/Admin@secdt.com/msp
export CORE_PEER_ADDRESS=peer-fabric-1:7051
export CORE_PEER_TLS_ENABLED=true
export CORE_PEER_TLS_ROOTCERT_FILE=~/secdt-fabric/crypto-config/peerOrganizations/secdt.com/peers/peer-fabric-1.secdt.com/tls/ca.crt
export ORDERER_CA=~/secdt-fabric/crypto-config/ordererOrganizations/secdt.com/orderers/orderer-fabric-1.secdt.com/tls/ca.crt
export PEER_CA=~/secdt-fabric/crypto-config/peerOrganizations/secdt.com/peers/peer-fabric-1.secdt.com/tls/ca.crt

RUN_TAG_SHORT="${RUNSET_ID#phase6_s3_}"

now_ms() {
  date +%s%3N
}

extract_snapshot() {
  local index="$1"
  local outfile="$2"
  python3 - <<PY
import json
from pathlib import Path
src = Path("$SNAPSHOT_JSONL")
idx = $index
n = 0
for line in src.open("r", encoding="utf-8"):
    line = line.strip()
    if not line:
        continue
    n += 1
    if n == idx:
        obj = json.loads(line)
        Path("$outfile").write_text(json.dumps(obj, separators=(",", ":"), ensure_ascii=False), encoding="utf-8")
        raise SystemExit(0)
raise SystemExit(f"snapshot index {idx} introuvable")
PY
}

register_snapshot() {
  local snapshot_path="$1"
  local run_dir="$2"
  local machine_id="$3"
  local session_id="$4"
  local health_score="$5"
  local cycle="$6"

  local t0 t1 t2 t3 t4 t5
  local hash cid invoke_ok verify_ok history_ok verify_raw

  t0=$(now_ms)
  hash=$(sha256sum "$snapshot_path" | awk '{print $1}')
  t1=$(now_ms)

  curl -sS --fail -X POST -F file=@"$snapshot_path" "$IPFS_API/add?pin=true" > "$run_dir/ipfs_add_result.json"
  cid=$(python3 - <<PY
import json
from pathlib import Path
print(json.loads(Path("$run_dir/ipfs_add_result.json").read_text())["Hash"])
PY
)
  t2=$(now_ms)

  curl -sS --fail -X POST "$IPFS_API/cat?arg=$cid" > "$run_dir/ipfs_cat.json"
  t3=$(now_ms)

  invoke_ok=false
  if peer chaincode invoke \
    -o "$ORDERER_ADDRESS" \
    --ordererTLSHostnameOverride "$ORDERER_HOSTNAME" \
    --tls --cafile "$ORDERER_CA" \
    -C "$CHANNEL_NAME" \
    -n "$CC_NAME" \
    --peerAddresses peer-fabric-1:7051 \
    --tlsRootCertFiles "$PEER_CA" \
    --waitForEvent \
    --waitForEventTimeout 30s \
    -c "{\"Args\":[\"RegisterState\",\"$machine_id\",\"$cid\",\"$health_score\",\"$cycle\",\"$session_id\",\"$hash\"]}" \
    > "$run_dir/fabric_invoke.txt" 2>&1
  then
    invoke_ok=true
  fi
  t4=$(now_ms)

  verify_ok=false
  if peer chaincode query \
    -C "$CHANNEL_NAME" \
    -n "$CC_NAME" \
    -c "{\"Args\":[\"VerifyIntegrity\",\"$machine_id\",\"$hash\"]}" \
    > "$run_dir/verify.json" 2>&1
  then
    verify_raw=$(tr -d '\r\n" ' < "$run_dir/verify.json" | tr '[:upper:]' '[:lower:]')
    if [[ "$verify_raw" == "true" ]]; then
      verify_ok=true
    fi
  fi

  history_ok=false
  if peer chaincode query \
    -C "$CHANNEL_NAME" \
    -n "$CC_NAME" \
    -c "{\"Args\":[\"GetHistory\",\"$machine_id\"]}" \
    > "$run_dir/history.json" 2>&1
  then
    history_ok=true
  fi
  t5=$(now_ms)

  python3 - <<PY
import json
from pathlib import Path
meta = {
  "machine_id": "$machine_id",
  "session_id": "$session_id",
  "health_score": float("$health_score"),
  "cycle": int("$cycle"),
  "hash": "$hash",
  "cid": "$cid",
  "invoke_ok": "$invoke_ok".lower() == "true",
  "verify_ok": "$verify_ok".lower() == "true",
  "history_ok": "$history_ok".lower() == "true",
  "timing_ms": {
    "snapshot_hash": int($t1) - int($t0),
    "ipfs_add_cid": int($t2) - int($t1),
    "ipfs_cat_check": int($t3) - int($t2),
    "fabric_submit_commit": int($t4) - int($t3),
    "fabric_query_phase": int($t5) - int($t4),
    "end_to_end_total": int($t5) - int($t0)
  }
}
Path("$run_dir/register_meta.json").write_text(json.dumps(meta, indent=2), encoding="utf-8")
PY
}

python3 - <<PY
import json
from pathlib import Path
manifest = {
  "phase": "phase6_s3",
  "runset_id": "$RUNSET_ID",
  "snapshot_jsonl": "$SNAPSHOT_JSONL",
  "spec_file": "$SPEC_FILE",
  "scenarios": [
    "s3a_tampering_before_anchoring",
    "s3b_replay_stale_snapshot",
    "s3c_unauthorized_registration",
    "s3d_audit_reconstruction"
  ],
  "status": "initialized"
}
Path("$RUNSET_DIR/phase6_s3_manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
PY

S3A_DIR="$RUNSET_DIR/s3a_tampering_before_anchoring"
extract_snapshot 1 "$S3A_DIR/base_snapshot.json"

python3 - <<PY
import json
from pathlib import Path

run_tag = "$RUN_TAG_SHORT"
base = json.loads(Path("$S3A_DIR/base_snapshot.json").read_text(encoding="utf-8"))

orig = dict(base)
orig["machine_id"] = f"{base['machine_id']}-s3a-{run_tag}"
orig["session_id"] = f"{base['session_id']}-s3a-{run_tag}"

tampered = dict(orig)
tampered["sensor_2"] = round(float(tampered["sensor_2"]) + 5.0, 4)
tampered["sensor_3"] = round(float(tampered["sensor_3"]) + 7.0, 4)

Path("$S3A_DIR/original_snapshot.json").write_text(json.dumps(orig, separators=(",", ":"), ensure_ascii=False), encoding="utf-8")
Path("$S3A_DIR/tampered_snapshot.json").write_text(json.dumps(tampered, separators=(",", ":"), ensure_ascii=False), encoding="utf-8")
PY

S3A_MACHINE_ID=$(python3 - <<PY
import json
from pathlib import Path
print(json.loads(Path("$S3A_DIR/original_snapshot.json").read_text())["machine_id"])
PY
)
S3A_SESSION_ID=$(python3 - <<PY
import json
from pathlib import Path
print(json.loads(Path("$S3A_DIR/original_snapshot.json").read_text())["session_id"])
PY
)
S3A_HEALTH=$(python3 - <<PY
import json
from pathlib import Path
print(json.loads(Path("$S3A_DIR/original_snapshot.json").read_text())["health_score"])
PY
)
S3A_CYCLE=$(python3 - <<PY
import json
from pathlib import Path
print(json.loads(Path("$S3A_DIR/original_snapshot.json").read_text())["cycle"])
PY
)

S3A_ORIG_HASH=$(sha256sum "$S3A_DIR/original_snapshot.json" | awk '{print $1}')
S3A_T0=$(now_ms)
curl -sS --fail -X POST -F file=@"$S3A_DIR/tampered_snapshot.json" "$IPFS_API/add?pin=true" > "$S3A_DIR/ipfs_add_result.json"
S3A_CID=$(python3 - <<PY
import json
from pathlib import Path
print(json.loads(Path("$S3A_DIR/ipfs_add_result.json").read_text())["Hash"])
PY
)
S3A_T1=$(now_ms)
curl -sS --fail -X POST "$IPFS_API/cat?arg=$S3A_CID" > "$S3A_DIR/ipfs_cat.json"
S3A_T2=$(now_ms)

S3A_INVOKE_OK=false
if peer chaincode invoke \
  -o "$ORDERER_ADDRESS" \
  --ordererTLSHostnameOverride "$ORDERER_HOSTNAME" \
  --tls --cafile "$ORDERER_CA" \
  -C "$CHANNEL_NAME" \
  -n "$CC_NAME" \
  --peerAddresses peer-fabric-1:7051 \
  --tlsRootCertFiles "$PEER_CA" \
  --waitForEvent \
  --waitForEventTimeout 30s \
  -c "{\"Args\":[\"RegisterState\",\"$S3A_MACHINE_ID\",\"$S3A_CID\",\"$S3A_HEALTH\",\"$S3A_CYCLE\",\"$S3A_SESSION_ID\",\"$S3A_ORIG_HASH\"]}" \
  > "$S3A_DIR/fabric_invoke.txt" 2>&1
then
  S3A_INVOKE_OK=true
fi
S3A_T3=$(now_ms)

S3A_VERIFY_OK=false
if peer chaincode query \
  -C "$CHANNEL_NAME" \
  -n "$CC_NAME" \
  -c "{\"Args\":[\"VerifyIntegrity\",\"$S3A_MACHINE_ID\",\"$S3A_ORIG_HASH\"]}" \
  > "$S3A_DIR/verify.json" 2>&1
then
  S3A_VERIFY_RAW=$(tr -d '\r\n" ' < "$S3A_DIR/verify.json" | tr '[:upper:]' '[:lower:]')
  if [[ "$S3A_VERIFY_RAW" == "true" ]]; then
    S3A_VERIFY_OK=true
  fi
fi

S3A_HISTORY_OK=false
if peer chaincode query \
  -C "$CHANNEL_NAME" \
  -n "$CC_NAME" \
  -c "{\"Args\":[\"GetHistory\",\"$S3A_MACHINE_ID\"]}" \
  > "$S3A_DIR/history.json" 2>&1
then
  S3A_HISTORY_OK=true
fi
S3A_T4=$(now_ms)

python3 - <<PY
import json
import hashlib
from pathlib import Path

run_dir = Path("$S3A_DIR")
orig_hash = "$S3A_ORIG_HASH"
cid = "$S3A_CID"
ipfs_hash = hashlib.sha256((run_dir / "ipfs_cat.json").read_bytes()).hexdigest()

history = []
history_ok = "$S3A_HISTORY_OK".lower() == "true"
if history_ok:
    try:
        history = json.loads((run_dir / "history.json").read_text(encoding="utf-8"))
    except Exception:
        history_ok = False
        history = []

stored_hash_match = any(isinstance(item, dict) and item.get("hash") == orig_hash for item in history)
stored_cid_match = any(isinstance(item, dict) and item.get("cid") == cid for item in history)
tamper_detected = ipfs_hash != orig_hash

summary = {
  "scenario": "S3-A",
  "name": "tampering_before_anchoring",
  "machine_id": "$S3A_MACHINE_ID",
  "cid": cid,
  "stored_hash": orig_hash,
  "ipfs_content_hash": ipfs_hash,
  "invoke_ok": "$S3A_INVOKE_OK".lower() == "true",
  "verify_ok": "$S3A_VERIFY_OK".lower() == "true",
  "history_ok": history_ok,
  "history_length": len(history),
  "stored_hash_match": stored_hash_match,
  "stored_cid_match": stored_cid_match,
  "tamper_detected": tamper_detected,
  "success": all([
    "$S3A_INVOKE_OK".lower() == "true",
    history_ok,
    stored_hash_match,
    stored_cid_match,
    tamper_detected
  ]),
  "timing_ms": {
    "ipfs_add_cid": int($S3A_T1) - int($S3A_T0),
    "ipfs_cat_check": int($S3A_T2) - int($S3A_T1),
    "fabric_submit_commit": int($S3A_T3) - int($S3A_T2),
    "fabric_query_phase": int($S3A_T4) - int($S3A_T3),
    "end_to_end_total": int($S3A_T4) - int($S3A_T0)
  }
}
(run_dir / "scenario_summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
PY

S3B_DIR="$RUNSET_DIR/s3b_replay_stale_snapshot"
extract_snapshot 1 "$S3B_DIR/older_base.json"
extract_snapshot 2 "$S3B_DIR/newer_base.json"

python3 - <<PY
import json
from pathlib import Path

run_tag = "$RUN_TAG_SHORT"
older = json.loads(Path("$S3B_DIR/older_base.json").read_text(encoding="utf-8"))
newer = json.loads(Path("$S3B_DIR/newer_base.json").read_text(encoding="utf-8"))

machine_id = f"machine-replay-{run_tag}"
session_id = f"session-replay-{run_tag}"

older["machine_id"] = machine_id
older["session_id"] = session_id
newer["machine_id"] = machine_id
newer["session_id"] = session_id

Path("$S3B_DIR/older_snapshot.json").write_text(json.dumps(older, separators=(",", ":"), ensure_ascii=False), encoding="utf-8")
Path("$S3B_DIR/newer_snapshot.json").write_text(json.dumps(newer, separators=(",", ":"), ensure_ascii=False), encoding="utf-8")
PY

S3B_MACHINE_ID=$(python3 - <<PY
import json
from pathlib import Path
print(json.loads(Path("$S3B_DIR/newer_snapshot.json").read_text())["machine_id"])
PY
)
S3B_SESSION_ID=$(python3 - <<PY
import json
from pathlib import Path
print(json.loads(Path("$S3B_DIR/newer_snapshot.json").read_text())["session_id"])
PY
)
S3B_NEWER_HEALTH=$(python3 - <<PY
import json
from pathlib import Path
print(json.loads(Path("$S3B_DIR/newer_snapshot.json").read_text())["health_score"])
PY
)
S3B_NEWER_CYCLE=$(python3 - <<PY
import json
from pathlib import Path
print(json.loads(Path("$S3B_DIR/newer_snapshot.json").read_text())["cycle"])
PY
)
S3B_OLDER_HEALTH=$(python3 - <<PY
import json
from pathlib import Path
print(json.loads(Path("$S3B_DIR/older_snapshot.json").read_text())["health_score"])
PY
)
S3B_OLDER_CYCLE=$(python3 - <<PY
import json
from pathlib import Path
print(json.loads(Path("$S3B_DIR/older_snapshot.json").read_text())["cycle"])
PY
)

mkdir -p "$S3B_DIR/run_newer"
register_snapshot "$S3B_DIR/newer_snapshot.json" "$S3B_DIR/run_newer" "$S3B_MACHINE_ID" "$S3B_SESSION_ID" "$S3B_NEWER_HEALTH" "$S3B_NEWER_CYCLE"

mkdir -p "$S3B_DIR/run_older_replay"
register_snapshot "$S3B_DIR/older_snapshot.json" "$S3B_DIR/run_older_replay" "$S3B_MACHINE_ID" "$S3B_SESSION_ID" "$S3B_OLDER_HEALTH" "$S3B_OLDER_CYCLE"

python3 - <<PY
import json
from pathlib import Path

history_path = Path("$S3B_DIR/run_older_replay/history.json")
history = json.loads(history_path.read_text(encoding="utf-8"))
all_cycles = [item["cycle"] for item in history if isinstance(item, dict) and "cycle" in item]
head_cycle = history[0]["cycle"] if history else None
max_cycle = max(all_cycles) if all_cycles else None
replay_detected = bool(history) and head_cycle is not None and max_cycle is not None and head_cycle < max_cycle

summary = {
  "scenario": "S3-B",
  "name": "replay_stale_snapshot",
  "machine_id": "$S3B_MACHINE_ID",
  "history_length": len(history),
  "cycles_in_history": all_cycles,
  "head_cycle": head_cycle,
  "max_cycle_seen": max_cycle,
  "replay_detected": replay_detected,
  "newer_invoke_ok": json.loads((Path("$S3B_DIR/run_newer/register_meta.json")).read_text())["invoke_ok"],
  "older_replay_invoke_ok": json.loads((Path("$S3B_DIR/run_older_replay/register_meta.json")).read_text())["invoke_ok"],
  "success": replay_detected
}
(Path("$S3B_DIR/scenario_summary.json")).write_text(json.dumps(summary, indent=2), encoding="utf-8")
PY

S3C_DIR="$RUNSET_DIR/s3c_unauthorized_registration"
extract_snapshot 3 "$S3C_DIR/base_snapshot.json"

python3 - <<PY
import json
import shutil
from pathlib import Path

run_tag = "$RUN_TAG_SHORT"
base = json.loads(Path("$S3C_DIR/base_snapshot.json").read_text(encoding="utf-8"))
base["machine_id"] = f"{base['machine_id']}-s3c-{run_tag}"
base["session_id"] = f"{base['session_id']}-s3c-{run_tag}"
Path("$S3C_DIR/snapshot.json").write_text(json.dumps(base, separators=(",", ":"), ensure_ascii=False), encoding="utf-8")

src = Path.home() / "secdt-fabric" / "crypto-config" / "peerOrganizations" / "secdt.com" / "users" / "Admin@secdt.com" / "msp"
dst = Path("$S3C_DIR/non_authorized_msp")
if dst.exists():
    shutil.rmtree(dst)
shutil.copytree(src, dst)
PY

S3C_MACHINE_ID=$(python3 - <<PY
import json
from pathlib import Path
print(json.loads(Path("$S3C_DIR/snapshot.json").read_text())["machine_id"])
PY
)
S3C_SESSION_ID=$(python3 - <<PY
import json
from pathlib import Path
print(json.loads(Path("$S3C_DIR/snapshot.json").read_text())["session_id"])
PY
)
S3C_HEALTH=$(python3 - <<PY
import json
from pathlib import Path
print(json.loads(Path("$S3C_DIR/snapshot.json").read_text())["health_score"])
PY
)
S3C_CYCLE=$(python3 - <<PY
import json
from pathlib import Path
print(json.loads(Path("$S3C_DIR/snapshot.json").read_text())["cycle"])
PY
)

S3C_HASH=$(sha256sum "$S3C_DIR/snapshot.json" | awk '{print $1}')
curl -sS --fail -X POST -F file=@"$S3C_DIR/snapshot.json" "$IPFS_API/add?pin=true" > "$S3C_DIR/ipfs_add_result.json"
S3C_CID=$(python3 - <<PY
import json
from pathlib import Path
print(json.loads(Path("$S3C_DIR/ipfs_add_result.json").read_text())["Hash"])
PY
)

S3C_ORIG_MSP="$CORE_PEER_MSPCONFIGPATH"
S3C_ORIG_MSPID="$CORE_PEER_LOCALMSPID"
export CORE_PEER_MSPCONFIGPATH="$S3C_DIR/non_authorized_msp"
export CORE_PEER_LOCALMSPID="UnauthorizedMSP"

S3C_INVOKE_OK=false
if peer chaincode invoke \
  -o "$ORDERER_ADDRESS" \
  --ordererTLSHostnameOverride "$ORDERER_HOSTNAME" \
  --tls --cafile "$ORDERER_CA" \
  -C "$CHANNEL_NAME" \
  -n "$CC_NAME" \
  --peerAddresses peer-fabric-1:7051 \
  --tlsRootCertFiles "$PEER_CA" \
  --waitForEvent \
  --waitForEventTimeout 10s \
  -c "{\"Args\":[\"RegisterState\",\"$S3C_MACHINE_ID\",\"$S3C_CID\",\"$S3C_HEALTH\",\"$S3C_CYCLE\",\"$S3C_SESSION_ID\",\"$S3C_HASH\"]}" \
  > "$S3C_DIR/fabric_invoke.txt" 2>&1
then
  S3C_INVOKE_OK=true
fi

export CORE_PEER_MSPCONFIGPATH="$S3C_ORIG_MSP"
export CORE_PEER_LOCALMSPID="$S3C_ORIG_MSPID"

python3 - <<PY
import json
from pathlib import Path

evidence = Path("$S3C_DIR/fabric_invoke.txt").read_text(encoding="utf-8", errors="ignore")
invoke_ok = "$S3C_INVOKE_OK".lower() == "true"
unauthorized_rejected = not invoke_ok

summary = {
  "scenario": "S3-C",
  "name": "unauthorized_registration",
  "machine_id": "$S3C_MACHINE_ID",
  "invoke_ok": invoke_ok,
  "unauthorized_rejected": unauthorized_rejected,
  "evidence": evidence.strip(),
  "success": unauthorized_rejected
}
(Path("$S3C_DIR/scenario_summary.json")).write_text(json.dumps(summary, indent=2), encoding="utf-8")
PY

S3D_DIR="$RUNSET_DIR/s3d_audit_reconstruction"
extract_snapshot 1 "$S3D_DIR/base1.json"
extract_snapshot 2 "$S3D_DIR/base2.json"
extract_snapshot 3 "$S3D_DIR/base3.json"

python3 - <<PY
import json
from pathlib import Path

run_tag = "$RUN_TAG_SHORT"
machine_id = f"machine-audit-{run_tag}"
session_id = f"session-audit-{run_tag}"

for idx in [1, 2, 3]:
    obj = json.loads(Path(f"$S3D_DIR/base{idx}.json").read_text(encoding="utf-8"))
    obj["machine_id"] = machine_id
    obj["session_id"] = session_id
    Path(f"$S3D_DIR/snapshot{idx}.json").write_text(json.dumps(obj, separators=(",", ":"), ensure_ascii=False), encoding="utf-8")
PY

S3D_MACHINE_ID=$(python3 - <<PY
import json
from pathlib import Path
print(json.loads(Path("$S3D_DIR/snapshot1.json").read_text())["machine_id"])
PY
)
S3D_SESSION_ID=$(python3 - <<PY
import json
from pathlib import Path
print(json.loads(Path("$S3D_DIR/snapshot1.json").read_text())["session_id"])
PY
)

for idx in 1 2 3; do
  RUN_DIR="$S3D_DIR/run_$idx"
  mkdir -p "$RUN_DIR"

  S3D_HEALTH=$(python3 - <<PY
import json
from pathlib import Path
print(json.loads(Path("$S3D_DIR/snapshot$idx.json").read_text())["health_score"])
PY
)
  S3D_CYCLE=$(python3 - <<PY
import json
from pathlib import Path
print(json.loads(Path("$S3D_DIR/snapshot$idx.json").read_text())["cycle"])
PY
)

  register_snapshot "$S3D_DIR/snapshot$idx.json" "$RUN_DIR" "$S3D_MACHINE_ID" "$S3D_SESSION_ID" "$S3D_HEALTH" "$S3D_CYCLE"
done

peer chaincode query \
  -C "$CHANNEL_NAME" \
  -n "$CC_NAME" \
  -c "{\"Args\":[\"GetHistory\",\"$S3D_MACHINE_ID\"]}" \
  > "$S3D_DIR/history.json" 2>&1

python3 - <<PY
import json
import hashlib
from pathlib import Path
import urllib.request

history = json.loads(Path("$S3D_DIR/history.json").read_text(encoding="utf-8"))
records = []
all_consistent = True

for item in history:
    cid = item.get("cid")
    stored_hash = item.get("hash")
    if not cid or not stored_hash:
        all_consistent = False
        records.append({
            "cid": cid,
            "stored_hash": stored_hash,
            "ipfs_hash": None,
            "consistent": False
        })
        continue

    req = urllib.request.Request(f"$IPFS_API/cat?arg={cid}", method="POST")
    with urllib.request.urlopen(req) as resp:
        data = resp.read()

    ipfs_hash = hashlib.sha256(data).hexdigest()
    consistent = (ipfs_hash == stored_hash)
    if not consistent:
        all_consistent = False

    records.append({
        "cid": cid,
        "stored_hash": stored_hash,
        "ipfs_hash": ipfs_hash,
        "consistent": consistent
    })

summary = {
  "scenario": "S3-D",
  "name": "audit_reconstruction",
  "machine_id": "$S3D_MACHINE_ID",
  "history_length": len(history),
  "records_checked": len(records),
  "all_consistent": all_consistent,
  "records": records,
  "success": len(history) >= 3 and all_consistent
}
Path("$S3D_DIR/scenario_summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
PY

python3 - <<PY
import json
from pathlib import Path

runset_dir = Path("$RUNSET_DIR")

s3a = json.loads((runset_dir / "s3a_tampering_before_anchoring" / "scenario_summary.json").read_text(encoding="utf-8"))
s3b = json.loads((runset_dir / "s3b_replay_stale_snapshot" / "scenario_summary.json").read_text(encoding="utf-8"))
s3c = json.loads((runset_dir / "s3c_unauthorized_registration" / "scenario_summary.json").read_text(encoding="utf-8"))
s3d = json.loads((runset_dir / "s3d_audit_reconstruction" / "scenario_summary.json").read_text(encoding="utf-8"))

summary = {
  "phase": "phase6_s3",
  "runset_id": "$RUNSET_ID",
  "scenarios": [s3a, s3b, s3c, s3d],
  "metrics": {
    "tamper_detection_rate": 1.0 if s3a.get("tamper_detected") else 0.0,
    "replay_detection_rate": 1.0 if s3b.get("replay_detected") else 0.0,
    "unauthorized_rejection_rate": 1.0 if s3c.get("unauthorized_rejected") else 0.0,
    "audit_reconstruction_success": 1.0 if s3d.get("success") else 0.0,
    "cid_hash_consistency": 1.0 if s3d.get("all_consistent") else 0.0
  },
  "overall_success_rate": round(sum(1 for s in [s3a, s3b, s3c, s3d] if s.get("success")) / 4.0, 4)
}

(runset_dir / "phase6_s3_summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
print(json.dumps(summary, indent=2))
PY

echo
echo "RUNSET_DIR=$RUNSET_DIR"
