#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$HOME/secdt-phase3"
RUN_ID="phase3_$(date -u +%Y%m%dT%H%M%SZ)"
RUN_DIR="$BASE_DIR/$RUN_ID"
mkdir -p "$RUN_DIR"

SAMPLE_FILE="$HOME/secdt-edge/sample_state.json"
IPFS_API="http://ipfs-node-1:5001/api/v0"
SSH_KEY="$HOME/.ssh/fl-ids-key.pem"
FABRIC_DIR="$HOME/secdt-fabric"

if [ ! -f "$SAMPLE_FILE" ]; then
cat <<'JSON' > "$SAMPLE_FILE"
{
  "machine_id": "machine-003",
  "timestamp": "2026-03-14T05:10:00Z",
  "temperature": 72.4,
  "pressure": 1.18,
  "vibration": 0.031,
  "health_score": 93.7,
  "cycle": 240,
  "session_id": "session-003"
}
JSON
fi

MACHINE_ID=$(python3 - <<'PY'
import json
with open("/home/ubuntu/secdt-edge/sample_state.json","r") as f:
    d = json.load(f)
print(d["machine_id"])
PY
)

HEALTH_SCORE=$(python3 - <<'PY'
import json
with open("/home/ubuntu/secdt-edge/sample_state.json","r") as f:
    d = json.load(f)
print(d["health_score"])
PY
)

CYCLE=$(python3 - <<'PY'
import json
with open("/home/ubuntu/secdt-edge/sample_state.json","r") as f:
    d = json.load(f)
print(d["cycle"])
PY
)

SESSION_ID=$(python3 - <<'PY'
import json
with open("/home/ubuntu/secdt-edge/sample_state.json","r") as f:
    d = json.load(f)
print(d["session_id"])
PY
)

T0_NS=$(date +%s%N)
cp "$SAMPLE_FILE" "$RUN_DIR/snapshot.json"

HASH=$(sha256sum "$RUN_DIR/snapshot.json" | awk '{print $1}')
T1_NS=$(date +%s%N)

curl -sS --fail -X POST -F file=@"$RUN_DIR/snapshot.json" "$IPFS_API/add" > "$RUN_DIR/ipfs_add_result.json"

CID=$(python3 - <<PY
import json
with open("$RUN_DIR/ipfs_add_result.json","r") as f:
    print(json.load(f)["Hash"])
PY
)
T2_NS=$(date +%s%N)

curl -sS --fail -X POST "$IPFS_API/cat?arg=$CID" > "$RUN_DIR/ipfs_cat.json"
T3_NS=$(date +%s%N)

ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@peer-fabric-1 "
cd $FABRIC_DIR
export PATH=\$PATH:\$HOME/bin:/usr/local/go/bin
export FABRIC_CFG_PATH=\$HOME/config
export CORE_PEER_TLS_ENABLED=true
export CORE_PEER_LOCALMSPID=PeerMSP
export CORE_PEER_MSPCONFIGPATH=\$HOME/secdt-fabric/crypto-config/peerOrganizations/secdt.com/users/Admin@secdt.com/msp
export CORE_PEER_TLS_ROOTCERT_FILE=\$HOME/secdt-fabric/crypto-config/peerOrganizations/secdt.com/peers/peer-fabric-1.secdt.com/tls/ca.crt
export CORE_PEER_ADDRESS=peer-fabric-1:7051
export ORDERER_CA=\$HOME/secdt-fabric/crypto-config/ordererOrganizations/secdt.com/orderers/orderer-fabric-1.secdt.com/tls/ca.crt

peer chaincode invoke \
  -o orderer-fabric-1:7050 \
  --tls --cafile \$ORDERER_CA \
  -C secdt-channel \
  -n secdt \
  --peerAddresses peer-fabric-1:7051 \
  --tlsRootCertFiles \$HOME/secdt-fabric/crypto-config/peerOrganizations/secdt.com/peers/peer-fabric-1.secdt.com/tls/ca.crt \
  -c '{\"Args\":[\"RegisterState\",\"$MACHINE_ID\",\"$CID\",\"$HEALTH_SCORE\",\"$CYCLE\",\"$SESSION_ID\",\"$HASH\"]}'
" > "$RUN_DIR/fabric_invoke.txt" 2>&1
T4_NS=$(date +%s%N)

ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@peer-fabric-1 "
cd $FABRIC_DIR
export PATH=\$PATH:\$HOME/bin:/usr/local/go/bin
export FABRIC_CFG_PATH=\$HOME/config
export CORE_PEER_TLS_ENABLED=true
export CORE_PEER_LOCALMSPID=PeerMSP
export CORE_PEER_MSPCONFIGPATH=\$HOME/secdt-fabric/crypto-config/peerOrganizations/secdt.com/users/Admin@secdt.com/msp
export CORE_PEER_TLS_ROOTCERT_FILE=\$HOME/secdt-fabric/crypto-config/peerOrganizations/secdt.com/peers/peer-fabric-1.secdt.com/tls/ca.crt
export CORE_PEER_ADDRESS=peer-fabric-1:7051

peer chaincode query -C secdt-channel -n secdt -c '{\"Args\":[\"VerifyIntegrity\",\"$MACHINE_ID\",\"$HASH\"]}'
" > "$RUN_DIR/verify_integrity.txt" 2>&1

ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@peer-fabric-1 "
cd $FABRIC_DIR
export PATH=\$PATH:\$HOME/bin:/usr/local/go/bin
export FABRIC_CFG_PATH=\$HOME/config
export CORE_PEER_TLS_ENABLED=true
export CORE_PEER_LOCALMSPID=PeerMSP
export CORE_PEER_MSPCONFIGPATH=\$HOME/secdt-fabric/crypto-config/peerOrganizations/secdt.com/users/Admin@secdt.com/msp
export CORE_PEER_TLS_ROOTCERT_FILE=\$HOME/secdt-fabric/crypto-config/peerOrganizations/secdt.com/peers/peer-fabric-1.secdt.com/tls/ca.crt
export CORE_PEER_ADDRESS=peer-fabric-1:7051

peer chaincode query -C secdt-channel -n secdt -c '{\"Args\":[\"GetHistory\",\"$MACHINE_ID\"]}'
" > "$RUN_DIR/history.json" 2>&1
T5_NS=$(date +%s%N)

python3 - <<PY
import json, hashlib, pathlib

run_dir = pathlib.Path("$RUN_DIR")
snapshot_path = run_dir / "snapshot.json"
ipfs_cat_path = run_dir / "ipfs_cat.json"
hist_path = run_dir / "history.json"
verify_path = run_dir / "verify_integrity.txt"

t0=$T0_NS
t1=$T1_NS
t2=$T2_NS
t3=$T3_NS
t4=$T4_NS
t5=$T5_NS

snapshot_bytes = snapshot_path.read_bytes()
ipfs_bytes = ipfs_cat_path.read_bytes()
hash_local = hashlib.sha256(snapshot_bytes).hexdigest()
hash_ipfs = hashlib.sha256(ipfs_bytes).hexdigest()

verify_raw = verify_path.read_text().strip()
verify_ok = verify_raw.endswith("true") or verify_raw.endswith("True")

hist_raw = hist_path.read_text().strip()
try:
    history = json.loads(hist_raw)
except Exception:
    history = []

history_ok = False
cid_ok = False
hash_ok = False
history_len = 0

if isinstance(history, list) and len(history) > 0:
    history_len = len(history)
    last = history[-1]
    cid_ok = last.get("cid") == "$CID"
    hash_ok = last.get("hash") == "$HASH"
    history_ok = True

report = {
    "run_id": "$RUN_ID",
    "machine_id": "$MACHINE_ID",
    "cid": "$CID",
    "hash_local": hash_local,
    "hash_ipfs": hash_ipfs,
    "expected_hash": "$HASH",
    "verify_integrity": verify_ok,
    "history_ok": history_ok,
    "history_length": history_len,
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
        "snapshot_hash": round((t1 - t0) / 1_000_000, 3),
        "ipfs_add_cid": round((t2 - t1) / 1_000_000, 3),
        "ipfs_cat_check": round((t3 - t2) / 1_000_000, 3),
        "fabric_submit_commit": round((t4 - t3) / 1_000_000, 3),
        "fabric_query_history_verify": round((t5 - t4) / 1_000_000, 3),
        "end_to_end_total": round((t5 - t0) / 1_000_000, 3)
    }
}

(run_dir / "phase3_report.json").write_text(json.dumps(report, indent=2))
print(json.dumps(report, indent=2))
PY

echo
echo "RUN_DIR=$RUN_DIR"
