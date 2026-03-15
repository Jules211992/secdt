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

export PATH=$PATH:~/fabric-samples/bin
export CORE_PEER_LOCALMSPID=PeerMSP
export CORE_PEER_MSPCONFIGPATH=~/secdt-fabric/crypto-config/peerOrganizations/secdt.com/users/Admin@secdt.com/msp
export CORE_PEER_ADDRESS=peer-fabric-1:7051

peer chaincode invoke -o orderer-fabric-1:7050 -C secdt-channel -n secdt --peerAddresses peer-fabric-1:7051 -c "{\"Args\":[\"RegisterState\",\"$MACHINE_ID\",\"$CID\",\"$HEALTH_SCORE\",\"$CYCLE\",\"$SESSION_ID\",\"$HASH\"]}" > "$RUN_DIR/fabric_invoke.txt" 2>&1
T4_NS=$(date +%s%N)

peer chaincode query -C secdt-channel -n secdt -c "{\"Args\":[\"VerifyIntegrity\",\"$MACHINE_ID\",\"$HASH\"]}" > "$RUN_DIR/verify_integrity.txt" 2>&1
peer chaincode query -C secdt-channel -n secdt -c "{\"Args\":[\"GetHistory\",\"$MACHINE_ID\"]}" > "$RUN_DIR/history.json" 2>&1
T5_NS=$(date +%s%N)

echo "{
  \"run_id\": \"$RUN_ID\",
  \"machine_id\": \"$MACHINE_ID\",
  \"cid\": \"$CID\",
  \"hash\": \"$HASH\",
  \"timing_ms\": {
    \"snapshot_hash\": $(echo "scale=3; ($T1_NS - $T0_NS)/1000000" | bc),
    \"ipfs_add_cid\": $(echo "scale=3; ($T2_NS - $T1_NS)/1000000" | bc),
    \"ipfs_cat_check\": $(echo "scale=3; ($T3_NS - $T2_NS)/1000000" | bc),
    \"fabric_submit_commit\": $(echo "scale=3; ($T4_NS - $T3_NS)/1000000" | bc),
    \"fabric_query\": $(echo "scale=3; ($T5_NS - $T4_NS)/1000000" | bc),
    \"end_to_end_total\": $(echo "scale=3; ($T5_NS - $T0_NS)/1000000" | bc)
  }
}" | tee "$RUN_DIR/phase3_report.json"

echo
echo "RUN_DIR=$RUN_DIR"
