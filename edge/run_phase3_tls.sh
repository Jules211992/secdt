#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$HOME/secdt-phase3"
RUN_ID="phase3_$(date -u +%Y%m%dT%H%M%SZ)"
RUN_DIR="$BASE_DIR/$RUN_ID"
mkdir -p "$RUN_DIR"

SAMPLE_FILE="$HOME/secdt-edge/sample_state.json"
IPFS_API="http://ipfs-node-1:5001/api/v0"

if [ ! -f "$SAMPLE_FILE" ]; then
cat <<'JSON' > "$SAMPLE_FILE"
{
  "machine_id": "machine-004",
  "timestamp": "2026-03-14T16:35:00Z",
  "temperature": 72.9,
  "pressure": 1.21,
  "vibration": 0.029,
  "health_score": 94.1,
  "cycle": 241,
  "session_id": "session-004"
}
JSON
fi

MACHINE_ID=$(python3 -c "import json; print(json.load(open('$SAMPLE_FILE'))['machine_id'])")
HEALTH_SCORE=$(python3 -c "import json; print(json.load(open('$SAMPLE_FILE'))['health_score'])")
CYCLE=$(python3 -c "import json; print(json.load(open('$SAMPLE_FILE'))['cycle'])")
SESSION_ID=$(python3 -c "import json; print(json.load(open('$SAMPLE_FILE'))['session_id'])")

T0_NS=$(date +%s%N)
cp "$SAMPLE_FILE" "$RUN_DIR/snapshot.json"
HASH=$(sha256sum "$RUN_DIR/snapshot.json" | awk '{print $1}')
T1_NS=$(date +%s%N)

curl -sS --fail -X POST -F file=@"$RUN_DIR/snapshot.json" "$IPFS_API/add" > "$RUN_DIR/ipfs_add_result.json"

CID=$(python3 -c "import json; print(json.load(open('$RUN_DIR/ipfs_add_result.json'))['Hash'])")
T2_NS=$(date +%s%N)

curl -sS --fail -X POST "$IPFS_API/cat?arg=$CID" > "$RUN_DIR/ipfs_cat.json"
T3_NS=$(date +%s%N)

cd ~/secdt-fabric
export PATH=$PATH:~/fabric-samples/bin
export CORE_PEER_LOCALMSPID=PeerMSP
export CORE_PEER_MSPCONFIGPATH=~/secdt-fabric/crypto-config/peerOrganizations/secdt.com/users/Admin@secdt.com/msp
export CORE_PEER_ADDRESS=peer-fabric-1:7051
export CORE_PEER_TLS_ENABLED=true
export CORE_PEER_TLS_ROOTCERT_FILE=~/secdt-fabric/crypto-config/peerOrganizations/secdt.com/peers/peer-fabric-1.secdt.com/tls/ca.crt
export ORDERER_CA=~/secdt-fabric/crypto-config/ordererOrganizations/secdt.com/orderers/orderer-fabric-1.secdt.com/tls/ca.crt
export PEER_CA=~/secdt-fabric/crypto-config/peerOrganizations/secdt.com/peers/peer-fabric-1.secdt.com/tls/ca.crt

peer chaincode invoke \
  -o orderer-fabric-1:7050 \
  --tls --cafile "$ORDERER_CA" \
  -C secdt-channel \
  -n secdt \
  --peerAddresses peer-fabric-1:7051 \
  --tlsRootCertFiles "$PEER_CA" \
  --waitForEvent \
  --waitForEventTimeout 30s \
  -c "{\"Args\":[\"RegisterState\",\"$MACHINE_ID\",\"$CID\",\"$HEALTH_SCORE\",\"$CYCLE\",\"$SESSION_ID\",\"$HASH\"]}" \
  > "$RUN_DIR/fabric_invoke.txt" 2>&1

T4_NS=$(date +%s%N)

peer chaincode query \
  -C secdt-channel \
  -n secdt \
  -c "{\"Args\":[\"VerifyIntegrity\",\"$MACHINE_ID\",\"$HASH\"]}" \
  > "$RUN_DIR/verify_integrity.txt" 2>&1

peer chaincode query \
  -C secdt-channel \
  -n secdt \
  -c "{\"Args\":[\"GetHistory\",\"$MACHINE_ID\"]}" \
  > "$RUN_DIR/history.json" 2>&1

T5_NS=$(date +%s%N)

python3 - <<PY
import json, hashlib, pathlib

run_dir = pathlib.Path("$RUN_DIR")
snapshot_path = run_dir / "snapshot.json"
ipfs_cat_path = run_dir / "ipfs_cat.json"
hist_path = run_dir / "history.json"
verify_path = run_dir / "verify_integrity.txt"

snapshot_bytes = snapshot_path.read_bytes()
ipfs_bytes = ipfs_cat_path.read_bytes()
hash_local = hashlib.sha256(snapshot_bytes).hexdigest()
hash_ipfs = hashlib.sha256(ipfs_bytes).hexdigest()

verify_ok = verify_path.read_text().strip() == "true"

hist_raw = hist_path.read_text().strip()
history = json.loads(hist_raw)

history_ok = isinstance(history, list) and len(history) > 0
cid_ok = history_ok and history[-1].get("cid") == "$CID"
hash_ok = history_ok and history[-1].get("hash") == "$HASH"

report = {
  "run_id": "$RUN_ID",
  "machine_id": "$MACHINE_ID",
  "cid": "$CID",
  "hash": "$HASH",
  "verify_integrity": verify_ok,
  "history_length": len(history) if isinstance(history, list) else 0,
  "cid_matches_history": cid_ok,
  "hash_matches_history": hash_ok,
  "success_end_to_end": all([
    hash_local == "$HASH",
    hash_ipfs == "$HASH",
    verify_ok,
    history_ok,
    cid_ok,
    hash_ok
  ]),
  "timing_ms": {
    "snapshot_hash": round(($T1_NS - $T0_NS)/1000000, 3),
    "ipfs_add_cid": round(($T2_NS - $T1_NS)/1000000, 3),
    "ipfs_cat_check": round(($T3_NS - $T2_NS)/1000000, 3),
    "fabric_submit_commit": round(($T4_NS - $T3_NS)/1000000, 3),
    "fabric_query": round(($T5_NS - $T4_NS)/1000000, 3),
    "end_to_end_total": round(($T5_NS - $T0_NS)/1000000, 3)
  }
}

(run_dir / "phase3_report.json").write_text(json.dumps(report, indent=2))
print(json.dumps(report, indent=2))
PY

echo
echo "RUN_DIR=$RUN_DIR"
