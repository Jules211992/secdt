#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$HOME/secdt-phase8"
RUNSET_ID="phase8_s5_$(date -u +%Y%m%dT%H%M%SZ)"
RUNSET_DIR="$BASE_DIR/$RUNSET_ID"
mkdir -p "$RUNSET_DIR"

SNAPSHOT_SOURCE="${SNAPSHOT_SOURCE:-$HOME/secdt-data/prepared/fd001_snapshots.jsonl}"
IPFS_API="${IPFS_API:-http://ipfs-node-1:5001/api/v0}"

FABRIC_DIR="${FABRIC_DIR:-$HOME/secdt-fabric}"
CHANNEL_NAME="${CHANNEL_NAME:-secdt-channel}"
CC_NAME="${CC_NAME:-secdt}"
ORDERER_ADDRESS="${ORDERER_ADDRESS:-orderer-fabric-1:7050}"
ORDERER_HOSTNAME="${ORDERER_HOSTNAME:-orderer-fabric-1.secdt.com}"

N_RUNS="${N_RUNS:-20}"
EMISSION_INTERVAL_MS="${EMISSION_INTERVAL_MS:-500}"

PHASE7_SUMMARY="${PHASE7_SUMMARY:-$(ls -dt "$HOME"/secdt-phase7/resultats_phase7/phase7_s4_*/phase7_s4_summary.json 2>/dev/null | head -n 1 || true)}"

LOCAL_DIR="$RUNSET_DIR/case_a_local_only"
IPFS_DIR="$RUNSET_DIR/case_b_ipfs_only"
FABRIC_DIR_CASE="$RUNSET_DIR/case_c_fabric_only"
HYBRID_DIR="$RUNSET_DIR/case_d_ipfs_fabric"

mkdir -p "$LOCAL_DIR" "$IPFS_DIR" "$FABRIC_DIR_CASE" "$HYBRID_DIR"

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

host_counters() {
  python3 - <<'PY'
import json
from pathlib import Path

cpu_line = Path("/proc/stat").read_text().splitlines()[0].split()
cpu_vals = list(map(int, cpu_line[1:]))
cpu_total = sum(cpu_vals)
cpu_idle = cpu_vals[3] + cpu_vals[4]

mem = {}
for line in Path("/proc/meminfo").read_text().splitlines():
    key, val = line.split(":", 1)
    mem[key.strip()] = int(val.strip().split()[0])

rx = 0
tx = 0
for netdev in Path("/sys/class/net").iterdir():
    if netdev.name == "lo":
        continue
    try:
        rx += int((netdev / "statistics" / "rx_bytes").read_text().strip())
        tx += int((netdev / "statistics" / "tx_bytes").read_text().strip())
    except Exception:
        pass

print(json.dumps({
    "cpu_total": cpu_total,
    "cpu_idle": cpu_idle,
    "mem_total_kb": mem.get("MemTotal", 0),
    "mem_available_kb": mem.get("MemAvailable", 0),
    "rx_bytes": rx,
    "tx_bytes": tx
}))
PY
}

build_snapshot() {
  local base_json="$1"
  local out_json="$2"
  local suffix="$3"
  python3 - <<PY > "$out_json"
import json
from pathlib import Path
obj = json.loads(Path("$base_json").read_text())
obj["machine_id"] = obj["machine_id"] + "-$suffix-$RUNSET_ID"
obj["session_id"] = obj["session_id"] + "-$suffix-$RUNSET_ID"
print(json.dumps(obj, separators=(",", ":"), ensure_ascii=False))
PY
}

write_report() {
  local run_dir="$1"
  local case_name="$2"
  local success="$3"
  local start_json="$4"
  local end_json="$5"
  local t0="$6"
  local t1="$7"
  local data_bytes="$8"
  local on_chain="$9"
  local off_chain="${10}"
  local note="${11}"

  python3 - <<PY > "$run_dir/run_report.json"
import json
from pathlib import Path

start = json.loads(Path("$start_json").read_text())
end = json.loads(Path("$end_json").read_text())

cpu_total_delta = end["cpu_total"] - start["cpu_total"]
cpu_idle_delta = end["cpu_idle"] - start["cpu_idle"]
cpu_busy_pct = 0.0
if cpu_total_delta > 0:
    cpu_busy_pct = 100.0 * (cpu_total_delta - cpu_idle_delta) / cpu_total_delta

mem_used_before_mb = (start["mem_total_kb"] - start["mem_available_kb"]) / 1024.0
mem_used_after_mb = (end["mem_total_kb"] - end["mem_available_kb"]) / 1024.0
mem_delta_mb = mem_used_after_mb - mem_used_before_mb

rx_delta = end["rx_bytes"] - start["rx_bytes"]
tx_delta = end["tx_bytes"] - start["tx_bytes"]
net_total = rx_delta + tx_delta

snapshot_path = Path("$run_dir/snapshot.json")
machine_id = None
if snapshot_path.exists():
    try:
        machine_id = json.loads(snapshot_path.read_text())["machine_id"]
    except Exception:
        pass

report = {
    "case": "$case_name",
    "run_index": int(Path("$run_dir").name.split("_")[-1]),
    "machine_id": machine_id,
    "success": "$success".lower() == "true",
    "timing_ms": {
        "end_to_end_total": int("$t1") - int("$t0")
    },
    "resource_usage": {
        "cpu_busy_pct": round(cpu_busy_pct, 3),
        "mem_used_before_mb": round(mem_used_before_mb, 3),
        "mem_used_after_mb": round(mem_used_after_mb, 3),
        "mem_delta_mb": round(mem_delta_mb, 3),
        "network_rx_bytes": int(rx_delta),
        "network_tx_bytes": int(tx_delta),
        "network_total_bytes": int(net_total)
    },
    "storage_bytes": {
        "data_manipulated_total": int("$data_bytes"),
        "on_chain": int("$on_chain"),
        "off_chain": int("$off_chain")
    },
    "note": "$note"
}
print(json.dumps(report, indent=2))
PY
}

summarize_case() {
  local case_dir="$1"
  local case_name="$2"

  python3 - <<PY > "$case_dir/case_summary.json"
import json, statistics, math
from pathlib import Path

case_dir = Path("$case_dir")
reports = [json.loads(p.read_text()) for p in sorted(case_dir.glob("run_*/run_report.json"))]

def pct(vals, p):
    vals = sorted(vals)
    if len(vals) == 1:
        return vals[0]
    k = (len(vals)-1)*(p/100.0)
    lo = math.floor(k)
    hi = math.ceil(k)
    if lo == hi:
        return vals[int(k)]
    return vals[lo] + (vals[hi]-vals[lo])*(k-lo)

lat = [r["timing_ms"]["end_to_end_total"] for r in reports]
cpu = [r["resource_usage"]["cpu_busy_pct"] for r in reports]
mem = [r["resource_usage"]["mem_delta_mb"] for r in reports]
net = [r["resource_usage"]["network_total_bytes"] for r in reports]
data = [r["storage_bytes"]["data_manipulated_total"] for r in reports]
on_chain = sum(r["storage_bytes"]["on_chain"] for r in reports)
off_chain = sum(r["storage_bytes"]["off_chain"] for r in reports)
succ = [1 if r["success"] else 0 for r in reports]

summary = {
    "case": "$case_name",
    "n_runs": len(reports),
    "success_rate": round(sum(succ)/len(succ), 4) if reports else 0,
    "latency_ms": {
        "mean": round(statistics.mean(lat), 3),
        "median": round(statistics.median(lat), 3),
        "p95": round(pct(lat, 95), 3),
        "p99": round(pct(lat, 99), 3)
    },
    "cpu_busy_pct": {
        "mean": round(statistics.mean(cpu), 3),
        "median": round(statistics.median(cpu), 3),
        "p95": round(pct(cpu, 95), 3),
        "p99": round(pct(cpu, 99), 3)
    },
    "mem_delta_mb": {
        "mean": round(statistics.mean(mem), 3),
        "median": round(statistics.median(mem), 3),
        "p95": round(pct(mem, 95), 3),
        "p99": round(pct(mem, 99), 3)
    },
    "network_total_bytes": {
        "mean": round(statistics.mean(net), 3),
        "median": round(statistics.median(net), 3),
        "p95": round(pct(net, 95), 3),
        "p99": round(pct(net, 99), 3),
        "sum": int(sum(net))
    },
    "data_manipulated_bytes": {
        "mean": round(statistics.mean(data), 3),
        "median": round(statistics.median(data), 3),
        "p95": round(pct(data, 95), 3),
        "p99": round(pct(data, 99), 3),
        "sum": int(sum(data))
    },
    "storage_bytes": {
        "on_chain": int(on_chain),
        "off_chain": int(off_chain)
    }
}
print(json.dumps(summary, indent=2))
PY
}

run_case_local() {
  for i in $(seq 1 "$N_RUNS"); do
    local run_dir="$LOCAL_DIR/run_$i"
    mkdir -p "$run_dir"

    fetch_snapshot $((i - 1)) "$run_dir/base_snapshot.json"
    build_snapshot "$run_dir/base_snapshot.json" "$run_dir/snapshot.json" "local-r$i"

    local start_json end_json t0 t1 hash data_bytes note
    start_json="$run_dir/start_metrics.json"
    end_json="$run_dir/end_metrics.json"
    host_counters > "$start_json"
    t0=$(date +%s%3N)

    cp "$run_dir/snapshot.json" "$run_dir/local_store.json"
    hash=$(sha256sum "$run_dir/local_store.json" | awk '{print $1}')
    printf '%s\n' "$hash" > "$run_dir/local_hash.txt"

    t1=$(date +%s%3N)
    host_counters > "$end_json"

    data_bytes=$(($(stat -c%s "$run_dir/snapshot.json") + $(stat -c%s "$run_dir/local_store.json") + $(stat -c%s "$run_dir/local_hash.txt")))
    note="local_storage_only"

    write_report "$run_dir" "case_a_local_only" true "$start_json" "$end_json" "$t0" "$t1" "$data_bytes" 0 0 "$note"

    sleep "$(python3 - <<PY
print($EMISSION_INTERVAL_MS / 1000)
PY
)"
  done

  summarize_case "$LOCAL_DIR" "case_a_local_only"
}

run_case_ipfs() {
  for i in $(seq 1 "$N_RUNS"); do
    local run_dir="$IPFS_DIR/run_$i"
    mkdir -p "$run_dir"

    fetch_snapshot $((i - 1)) "$run_dir/base_snapshot.json"
    build_snapshot "$run_dir/base_snapshot.json" "$run_dir/snapshot.json" "ipfs-r$i"

    local start_json end_json t0 t1 hash cid ipfs_hash success data_bytes off_chain note
    start_json="$run_dir/start_metrics.json"
    end_json="$run_dir/end_metrics.json"
    host_counters > "$start_json"
    t0=$(date +%s%3N)

    hash=$(sha256sum "$run_dir/snapshot.json" | awk '{print $1}')
    curl -sS --fail -X POST -F file=@"$run_dir/snapshot.json" "$IPFS_API/add?pin=true" > "$run_dir/ipfs_add.json"
    cid=$(python3 - <<PY
import json
print(json.load(open("$run_dir/ipfs_add.json"))["Hash"])
PY
)
    curl -sS --fail -X POST "$IPFS_API/cat?arg=$cid" > "$run_dir/ipfs_cat.json"
    ipfs_hash=$(sha256sum "$run_dir/ipfs_cat.json" | awk '{print $1}')

    t1=$(date +%s%3N)
    host_counters > "$end_json"

    success=false
    if [[ "$hash" == "$ipfs_hash" ]]; then
      success=true
    fi

    off_chain=$(stat -c%s "$run_dir/snapshot.json")
    data_bytes=$(($(stat -c%s "$run_dir/snapshot.json") + $(stat -c%s "$run_dir/ipfs_add.json") + $(stat -c%s "$run_dir/ipfs_cat.json")))
    note="ipfs_only"

    write_report "$run_dir" "case_b_ipfs_only" "$success" "$start_json" "$end_json" "$t0" "$t1" "$data_bytes" 0 "$off_chain" "$note"

    sleep "$(python3 - <<PY
print($EMISSION_INTERVAL_MS / 1000)
PY
)"
  done

  summarize_case "$IPFS_DIR" "case_b_ipfs_only"
}

run_case_fabric() {
  local FABRIC_ONLY_LITERAL="FABRIC_ONLY"
  for i in $(seq 1 "$N_RUNS"); do
    local run_dir="$FABRIC_DIR_CASE/run_$i"
    mkdir -p "$run_dir"

    fetch_snapshot $((i - 1)) "$run_dir/base_snapshot.json"
    build_snapshot "$run_dir/base_snapshot.json" "$run_dir/snapshot.json" "fabric-r$i"

    local MACHINE_ID SESSION_ID CYCLE HEALTH_SCORE HASH
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
    HASH=$(sha256sum "$run_dir/snapshot.json" | awk '{print $1}')

    local start_json end_json t0 t1 INVOKE_OK VERIFY_OK data_bytes on_chain note
    start_json="$run_dir/start_metrics.json"
    end_json="$run_dir/end_metrics.json"
    host_counters > "$start_json"
    t0=$(date +%s%3N)

    INVOKE_OK=false
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
      -c "{\"Args\":[\"RegisterState\",\"$MACHINE_ID\",\"FABRIC_ONLY\",\"$HEALTH_SCORE\",\"$CYCLE\",\"$SESSION_ID\",\"$HASH\"]}" \
      > "$run_dir/invoke.txt" 2>&1
    then
      INVOKE_OK=true
    fi

    VERIFY_OK=false
    if peer chaincode query \
      -C "$CHANNEL_NAME" \
      -n "$CC_NAME" \
      -c "{\"Args\":[\"VerifyIntegrity\",\"$MACHINE_ID\",\"$HASH\"]}" \
      > "$run_dir/verify.json" 2>&1
    then
      VERIFY_RAW=$(tr -d '\r\n" ' < "$run_dir/verify.json" | tr '[:upper:]' '[:lower:]')
      if [[ "$VERIFY_RAW" == "true" ]]; then
        VERIFY_OK=true
      fi
    fi

    peer chaincode query \
      -C "$CHANNEL_NAME" \
      -n "$CC_NAME" \
      -c "{\"Args\":[\"GetHistory\",\"$MACHINE_ID\"]}" \
      > "$run_dir/history.json" 2>&1 || true

    t1=$(date +%s%3N)
    host_counters > "$end_json"

    on_chain=$(( ${#MACHINE_ID} + ${#SESSION_ID} + ${#CYCLE} + ${#HEALTH_SCORE} + ${#HASH} + ${#FABRIC_ONLY_LITERAL} ))
    data_bytes=$(($(stat -c%s "$run_dir/snapshot.json") + $(stat -c%s "$run_dir/invoke.txt") + $(stat -c%s "$run_dir/verify.json") + $(stat -c%s "$run_dir/history.json")))
    note="fabric_only"

    local success=false
    if [[ "$INVOKE_OK" == "true" && "$VERIFY_OK" == "true" ]]; then
      success=true
    fi

    write_report "$run_dir" "case_c_fabric_only" "$success" "$start_json" "$end_json" "$t0" "$t1" "$data_bytes" "$on_chain" 0 "$note"

    sleep "$(python3 - <<PY
print($EMISSION_INTERVAL_MS / 1000)
PY
)"
  done

  summarize_case "$FABRIC_DIR_CASE" "case_c_fabric_only"
}

run_case_hybrid() {
  for i in $(seq 1 "$N_RUNS"); do
    local run_dir="$HYBRID_DIR/run_$i"
    mkdir -p "$run_dir"

    fetch_snapshot $((i - 1)) "$run_dir/base_snapshot.json"
    build_snapshot "$run_dir/base_snapshot.json" "$run_dir/snapshot.json" "hybrid-r$i"

    local MACHINE_ID SESSION_ID CYCLE HEALTH_SCORE HASH CID
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
    HASH=$(sha256sum "$run_dir/snapshot.json" | awk '{print $1}')

    local start_json end_json t0 t1 INVOKE_OK VERIFY_OK data_bytes on_chain off_chain note success
    start_json="$run_dir/start_metrics.json"
    end_json="$run_dir/end_metrics.json"
    host_counters > "$start_json"
    t0=$(date +%s%3N)

    curl -sS --fail -X POST -F file=@"$run_dir/snapshot.json" "$IPFS_API/add?pin=true" > "$run_dir/ipfs_add.json"
    CID=$(python3 - <<PY
import json
print(json.load(open("$run_dir/ipfs_add.json"))["Hash"])
PY
)
    curl -sS --fail -X POST "$IPFS_API/cat?arg=$CID" > "$run_dir/ipfs_cat.json"

    INVOKE_OK=false
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
      -c "{\"Args\":[\"RegisterState\",\"$MACHINE_ID\",\"$CID\",\"$HEALTH_SCORE\",\"$CYCLE\",\"$SESSION_ID\",\"$HASH\"]}" \
      > "$run_dir/invoke.txt" 2>&1
    then
      INVOKE_OK=true
    fi

    VERIFY_OK=false
    if peer chaincode query \
      -C "$CHANNEL_NAME" \
      -n "$CC_NAME" \
      -c "{\"Args\":[\"VerifyIntegrity\",\"$MACHINE_ID\",\"$HASH\"]}" \
      > "$run_dir/verify.json" 2>&1
    then
      VERIFY_RAW=$(tr -d '\r\n" ' < "$run_dir/verify.json" | tr '[:upper:]' '[:lower:]')
      if [[ "$VERIFY_RAW" == "true" ]]; then
        VERIFY_OK=true
      fi
    fi

    peer chaincode query \
      -C "$CHANNEL_NAME" \
      -n "$CC_NAME" \
      -c "{\"Args\":[\"GetHistory\",\"$MACHINE_ID\"]}" \
      > "$run_dir/history.json" 2>&1 || true

    t1=$(date +%s%3N)
    host_counters > "$end_json"

    on_chain=$(( ${#MACHINE_ID} + ${#SESSION_ID} + ${#CYCLE} + ${#HEALTH_SCORE} + ${#HASH} + ${#CID} ))
    off_chain=$(stat -c%s "$run_dir/snapshot.json")
    data_bytes=$(($(stat -c%s "$run_dir/snapshot.json") + $(stat -c%s "$run_dir/ipfs_add.json") + $(stat -c%s "$run_dir/ipfs_cat.json") + $(stat -c%s "$run_dir/invoke.txt") + $(stat -c%s "$run_dir/verify.json") + $(stat -c%s "$run_dir/history.json")))
    note="ipfs_plus_fabric"

    success=false
    if [[ "$INVOKE_OK" == "true" && "$VERIFY_OK" == "true" ]]; then
      success=true
    fi

    write_report "$run_dir" "case_d_ipfs_fabric" "$success" "$start_json" "$end_json" "$t0" "$t1" "$data_bytes" "$on_chain" "$off_chain" "$note"

    sleep "$(python3 - <<PY
print($EMISSION_INTERVAL_MS / 1000)
PY
)"
  done

  summarize_case "$HYBRID_DIR" "case_d_ipfs_fabric"
}

run_case_local
run_case_ipfs
run_case_fabric
run_case_hybrid

python3 - <<PY > "$RUNSET_DIR/phase8_s5_summary.json"
import json
from pathlib import Path

root = Path("$RUNSET_DIR")
cases = [
    json.loads((root / "case_a_local_only" / "case_summary.json").read_text()),
    json.loads((root / "case_b_ipfs_only" / "case_summary.json").read_text()),
    json.loads((root / "case_c_fabric_only" / "case_summary.json").read_text()),
    json.loads((root / "case_d_ipfs_fabric" / "case_summary.json").read_text()),
]

baseline_case = cases[0]
baseline_latency = baseline_case["latency_ms"]["mean"]
baseline_cpu = baseline_case["cpu_busy_pct"]["mean"]
baseline_mem = baseline_case["mem_delta_mb"]["mean"]
baseline_net = baseline_case["network_total_bytes"]["mean"]
baseline_data = baseline_case["data_manipulated_bytes"]["mean"]

phase7_pg_mean = None
phase7_pg_db_per_run = None
phase7_path = "$PHASE7_SUMMARY".strip()

if phase7_path:
    p = Path(phase7_path)
    if p.exists():
        phase7 = json.loads(p.read_text())
        for s in phase7.get("systems", []):
            if s.get("system") == "postgresql_centralized":
                phase7_pg_mean = s["latency_ms"]["mean"]
                if s.get("n_runs", 0) > 0:
                    phase7_pg_db_per_run = s["storage_bytes"]["database_total"] / s["n_runs"]
                break

for c in cases:
    c["relative_overhead_vs_case_a"] = {
        "latency_ratio": round(c["latency_ms"]["mean"] / baseline_latency, 4) if baseline_latency else None,
        "cpu_ratio": round(c["cpu_busy_pct"]["mean"] / baseline_cpu, 4) if baseline_cpu else None,
        "mem_ratio": round(c["mem_delta_mb"]["mean"] / baseline_mem, 4) if baseline_mem not in (0, None) else None,
        "network_ratio": round(c["network_total_bytes"]["mean"] / baseline_net, 4) if baseline_net else None,
        "data_ratio": round(c["data_manipulated_bytes"]["mean"] / baseline_data, 4) if baseline_data else None
    }
    if phase7_pg_mean is not None:
        c["relative_vs_phase7_postgresql"] = {
            "latency_ratio": round(c["latency_ms"]["mean"] / phase7_pg_mean, 4) if phase7_pg_mean else None,
            "storage_ratio_per_run": round(c["data_manipulated_bytes"]["mean"] / phase7_pg_db_per_run, 4) if phase7_pg_db_per_run else None
        }

summary = {
    "phase": "phase8_s5",
    "runset_id": "$RUNSET_ID",
    "n_runs_per_case": $N_RUNS,
    "emission_interval_ms": $EMISSION_INTERVAL_MS,
    "baseline_case": "case_a_local_only",
    "phase7_postgresql_reference": phase7_path if phase7_path else None,
    "cases": cases
}
print(json.dumps(summary, indent=2))
PY

RESULTS_ROOT="$HOME/secdt-phase8/resultats_phase8"
DEST="$RESULTS_ROOT/$RUNSET_ID"
mkdir -p "$RESULTS_ROOT"
rm -rf "$DEST"
mkdir -p "$DEST"
cp -a "$RUNSET_DIR/"* "$DEST"/
cp "$HOME/secdt-edge/run_phase8_s5_full.sh" "$DEST"/

cat <<TXT > "$DEST/README_RESULTAT.txt"
Phase: Phase 8
Scenario: S5 overhead analysis
Statut: valide
Source runset: $RUNSET_DIR
Résumé officiel: phase8_s5_summary.json
TXT

echo
echo "RUNSET_DIR=$RUNSET_DIR"
echo "RESULTS_SAVED_IN=$DEST"
echo
cat "$RUNSET_DIR/phase8_s5_summary.json"
