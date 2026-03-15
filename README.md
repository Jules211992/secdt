# SecDT: A Secure and Decentralized Approach for Industrial Digital Twins
### Hyperledger Fabric 2.5 + IPFS + Smart Contracts | IEEE IoT Journal Submission


> **Reproducibility repository** for the paper:
> *"A Secure and Decentralized Approach for Industrial Digital Twins Using Blockchain and IPFS"*
> Submitted to IEEE Internet of Things Journal

---

## Table of Contents

1. [Overview](#1-overview)
2. [System Architecture](#2-system-architecture)
3. [Testbed: 14-VM Infrastructure](#3-testbed-14-vm-infrastructure)
4. [Prerequisites](#4-prerequisites)
5. [Repository Structure](#5-repository-structure)
6. [Environment Setup](#6-environment-setup)
   - 6.1 [Clone & Configure](#61-clone--configure)
   - 6.2 [Fabric Network Bootstrap](#62-fabric-network-bootstrap)
   - 6.3 [IPFS Cluster Bootstrap](#63-ipfs-cluster-bootstrap)
   - 6.4 [Edge Gateway Setup](#64-edge-gateway-setup)
   - 6.5 [Prometheus Monitoring](#65-prometheus-monitoring)
7. [Dataset Preparation](#7-dataset-preparation)
8. [Running the Scenarios](#8-running-the-scenarios)
   - 8.1 [S0 – Nominal Workflow Validation](#81-s0--nominal-workflow-validation)
   - 8.2 [S1 – Nominal Performance](#82-s1--nominal-performance)
   - 8.3 [S2 – Scalability](#83-s2--scalability)
   - 8.4 [S3 – Integrity, Traceability, and Auditability](#84-s3--integrity-traceability-and-auditability)
   - 8.5 [S4 – Baseline Comparison](#85-s4--baseline-comparison)
   - 8.6 [S5 – Overhead Analysis](#86-s5--overhead-analysis)
   - 8.7 [S6 – Resilience under Partial Failure](#87-s6--resilience-under-partial-failure)
9. [Caliper Benchmark](#9-caliper-benchmark)
10. [Results Reproduction](#10-results-reproduction)
11. [Generating Figures and Tables](#11-generating-figures-and-tables)
12. [Expected Results Summary](#12-expected-results-summary)
13. [Troubleshooting](#13-troubleshooting)
14. [License](#14-license)

---

## 1. Overview

This repository contains the complete prototype implementation of **SecDT**, a secure and decentralized approach for industrial Digital Twins combining Hyperledger Fabric 2.5 with IPFS. The system is evaluated on a 14-VM private cloud infrastructure (Beluga, Digital Research Alliance of Canada) using the NASA CMAPSS FD001 turbofan degradation dataset.

The approach integrates three layers:

| Layer | Technology | Role |
|---|---|---|
| **Edge** | Python, cbor2, Fabric Gateway SDK | Snapshot serialization, IPFS submission, Fabric transaction |
| **Off-chain Storage** | go-ipfs 0.18 (5-node cluster) | Content-addressed persistence of DT state snapshots |
| **Blockchain** | Hyperledger Fabric 2.5 (RAFT) | CID anchoring, smart contract automation, 2-of-3 endorsement |

**Key results (reproducible):**

| Metric | Value |
|---|---|
| E2E latency (nominal, mean) | 915.3 ms |
| E2E latency range (all scenarios) | 909 – 1,031 ms |
| Transaction success rate | 100% (all configurations) |
| Integrity detection rate δ | 1.0 (4/4 threat categories) |
| Audit reconstruction rate α | 1.0 |
| On-chain storage reduction ρ | ~50% |
| IPFS recovery time (1–2 nodes lost) | 16 – 20 ms |
| Fabric raw throughput (Caliper) | 1,947 – 2,085 TPS |
| Total Fabric transactions | 162,000 (0 failures) |

---

## 2. System Architecture


┌─────────────────────────────────────────────────────────────────────┐
│                         EDGE LAYER                                  │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │                   edge-gateway (10.0.1.10)                   │   │
│  │   Python 3.10 | cbor2 | Fabric Gateway SDK | θ = 0.40       │   │
│  │   Snapshot construction → CBOR serialization → IPFS → Fabric │   │
│  └──────────────────────────┬───────────────────────────────────┘   │
└─────────────────────────────┼───────────────────────────────────────┘
                              │  b_i^t (CBOR payload ~450-550 bytes)
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      IPFS STORAGE LAYER                             │
│                                                                     │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ │
│  │ipfs-node0│ │ipfs-node1│ │ipfs-node2│ │ipfs-node3│ │ipfs-node4│ │
│  │10.0.1.20 │ │10.0.1.21 │ │10.0.1.22 │ │10.0.1.23 │ │10.0.1.24 │ │
│  │go-ipfs   │ │go-ipfs   │ │go-ipfs   │ │go-ipfs   │ │go-ipfs   │ │
│  │0.18      │ │0.18      │ │0.18      │ │0.18      │ │0.18      │ │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘ └──────────┘ │
│              Replication factor r=3 | CIDv1 SHA2-256               │
└─────────────────────────────┬───────────────────────────────────────┘
                              │  CID_i^t + SHA256(b_i^t)
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    FABRIC BLOCKCHAIN LAYER                          │
│                                                                     │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐  │
│  │peer0.org1        │  │peer0.org2        │  │peer0.org3        │  │
│  │10.0.1.30         │  │10.0.1.31         │  │10.0.1.32         │  │
│  │Fabric 2.5        │  │Fabric 2.5        │  │Fabric 2.5        │  │
│  │GoLevelDB         │  │GoLevelDB         │  │GoLevelDB         │  │
│  └──────────────────┘  └──────────────────┘  └──────────────────┘  │
│                                                                     │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐  │
│  │orderer1          │  │orderer2          │  │orderer3          │  │
│  │10.0.1.33         │  │10.0.1.34         │  │10.0.1.35         │  │
│  │RAFT (f=1)        │  │RAFT (f=1)        │  │RAFT (f=1)        │  │
│  └──────────────────┘  └──────────────────┘  └──────────────────┘  │
│                                                                     │
│  Chaincode (Go): RegisterState | VerifyIntegrity                   │
│                  GetHistory    | TriggerMaintenance (θ=0.40)       │
│  Policy: 2-of-3 endorsement | iot-channel                         │
└─────────────────────────────┬───────────────────────────────────────┘
                              │
                ┌─────────────▼────────────┐
                │  monitoring (10.0.1.40)  │
                │  Prometheus + Grafana    │
                │  Node Exporter (all VMs) │
                └──────────────────────────┘



## 3. Testbed: 14-VM Infrastructure

All VMs run **Ubuntu 22.04 LTS** on the Beluga private cloud
(Digital Research Alliance of Canada). NTP synchronization via
Chrony is verified to remain below 1 ms before each campaign.

| # | VM Name | IP Address | vCPUs | RAM | Storage | Role |
|---|---------|-----------|-------|-----|---------|------|
| 1–3 | `fabric-peer-{1,2,3}` | `10.0.1.30–32` | 8 | 16 GB | 80 GB | Fabric peer nodes, GoLevelDB, endorsers |
| 4–6 | `fabric-orderer-{1,2,3}` | `10.0.1.33–35` | 6 | 12 GB | 60 GB | RAFT orderers (f=1, BatchTimeout=500 ms) |
| 7–11 | `ipfs-node-{0,1,2,3,4}` | `10.0.1.20–24` | 4 | 8 GB | 80 GB | go-ipfs 0.18, replication r=3 |
| 12 | `edge-gateway` | `10.0.1.10` | 8 | 16 GB | 80 GB | Python edge module, Fabric Gateway SDK, Caliper |
| 13 | `baseline-postgresql` | `10.0.1.50` | 6 | 12 GB | 80 GB | PostgreSQL 14 centralized baseline |
| 14 | `monitoring` | `10.0.1.40` | 4 | 8 GB | 40 GB | Prometheus, Grafana, Node Exporter |
| | **Total** | | **80** | **160 GB** | **~1 TB** | |

> **Note:** SSH key: `~/.ssh/secdt-key.pem` (replace with your key path throughout).

---

## 4. Prerequisites

### All VMs
```bash
sudo apt-get update && sudo apt-get install -y \
    docker.io docker-compose curl wget git \
    python3.10 python3-pip python3-venv \
    build-essential libssl-dev chrony
sudo usermod -aG docker $USER && newgrp docker

# Verify NTP synchronization (must be < 1 ms between all VMs)
chronyc tracking | grep "RMS offset"
```

### Edge Gateway VM only (`10.0.1.10`)
```bash
# Node.js 18 (for Caliper)
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs

# Hyperledger Caliper CLI
npm install --save-dev @hyperledger/caliper-cli@0.5.0
npx caliper --version

# Go 1.20 (for chaincode development)
wget https://go.dev/dl/go1.20.linux-amd64.tar.gz
sudo tar -C /usr/local -xzf go1.20.linux-amd64.tar.gz
echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc && source ~/.bashrc
```

### Python dependencies (edge gateway VM)
```bash
python3 -m venv venv && source venv/bin/activate
pip install -r requirements.txt
```

`requirements.txt`:
```
cbor2==5.4.6
fabric-sdk-py==1.0.0
prometheus-client==0.17.0
numpy==1.24.3
pandas==2.0.2
scikit-learn==1.3.0
requests==2.31.0
pyyaml==6.0
tqdm==4.65.0
```

---

## 5. Repository Structure

```
secdt/
├── README.md
├── requirements.txt
│
├── fabric/                            # Hyperledger Fabric network
│   ├── network/
│   │   ├── docker-compose.yaml        # Peers + orderers (3+3)
│   │   ├── configtx.yaml              # Channel + consortium config
│   │   ├── crypto-config.yaml         # MSP identity generation
│   │   └── scripts/
│   │       ├── bootstrap.sh           # Full network up script
│   │       ├── teardown.sh
│   │       └── create-channel.sh      # iot-channel creation
│   └── chaincode/
│       └── secdt-cc/                  # Go chaincode
│           ├── go.mod
│           └── secdt.go               # RegisterState | VerifyIntegrity
│                                      # GetHistory | TriggerMaintenance
│
├── ipfs/                              # IPFS cluster config
│   ├── bootstrap-cluster.sh
│   └── test-ipfs.sh
│
├── edge/                              # Edge gateway module
│   ├── gateway.py                     # Main edge loop
│   ├── snapshot.py                    # Snapshot construction + CBOR
│   ├── health.py                      # RUL normalization → h_i^t
│   ├── ipfs_client.py                 # IPFS HTTP API wrapper
│   └── fabric_client.py               # Fabric Gateway SDK wrapper
│
├── baselines/                         # Baseline systems
│   ├── postgresql/
│   │   └── baseline_pg.py             # PostgreSQL centralized baseline
│   └── fabric_only/
│       └── baseline_fabric.py         # Fabric-only baseline (no IPFS)
│
├── caliper/                           # Hyperledger Caliper benchmark
│   ├── benchmarks/
│   │   └── secdt-workload.yaml        # 3 loads × target TPS
│   ├── networks/
│   │   └── fabric-network.yaml        # Network topology for Caliper
│   └── workload/
│       └── register-state.js          # RegisterState workload module
│
├── monitoring/                        # Prometheus + Grafana
│   ├── prometheus.yml
│   ├── docker-compose-monitoring.yml
│   └── dashboards/
│       └── secdt-dashboard.json
│
├── scripts/                           # Scenario runners
│   ├── run_s0_validation.sh
│   ├── run_s1_nominal.sh
│   ├── run_s2_scalability.sh
│   ├── run_s3_integrity.sh
│   ├── run_s4_baseline.sh
│   ├── run_s5_overhead.sh
│   ├── run_s6_resilience.sh
│   └── run_all_scenarios.sh
│
├── analysis/                          # Post-processing + figure generation
│   ├── parse_logs.py
│   ├── compute_metrics.py
│   └── figures/
│       ├── fig_caliper.py
│       ├── fig_nominal.py
│       ├── fig_scalability.py
│       ├── fig_baseline.py
│       ├── fig_storage.py
│       ├── fig_resilience.py
│       └── fig_ipfs.py
│
├── data/                              # Dataset (not included — see §7)
│   └── CMAPSS/
│       ├── train_FD001.txt
│       └── test_FD001.txt
│
├── logs/                              # Scenario output logs (git-ignored)
│   └── .gitkeep
│
└── paper/                             # LaTeX paper source
    ├── main.tex
    ├── ref.bib
    └── figures/
```

---

## 6. Environment Setup

### 6.1 Clone & Configure

Run on **all VMs**:
```bash
git clone https://github.com/YOUR_USERNAME/secdt.git
cd secdt

# Copy and edit your IP configuration
cp config/network.yaml.example config/network.yaml
nano config/network.yaml
```

`config/network.yaml`:
```yaml
fabric:
  peers:
    - host: 10.0.1.30
      port: 7051
      org: org1
    - host: 10.0.1.31
      port: 7051
      org: org2
    - host: 10.0.1.32
      port: 7051
      org: org3
  orderers:
    - host: 10.0.1.33
      port: 7050
    - host: 10.0.1.34
      port: 7050
    - host: 10.0.1.35
      port: 7050
  channel: iot-channel
  chaincode: secdt-cc
  endorsement_policy: "2-of-3"
  batch_size: 10000
  batch_timeout: 500ms

ipfs:
  nodes:
    - http://10.0.1.20:5001
    - http://10.0.1.21:5001
    - http://10.0.1.22:5001
    - http://10.0.1.23:5001
    - http://10.0.1.24:5001
  replication_factor: 3

edge:
  emission_frequencies:   # Hz
    - 1.0
    - 0.1
    - 0.01667             # 1/60 Hz
  machine_counts: [10, 25, 50, 100]
  health_threshold: 0.40  # θ
  run_duration_min: 30
  repetitions: 3

postgresql:
  host: 10.0.1.50
  port: 5432
  database: secdt_baseline

prometheus:
  host: 10.0.1.40
  port: 9090
```

---

### 6.2 Fabric Network Bootstrap

Run on **`fabric-orderer-1` VM (`10.0.1.33`)**:

```bash
cd secdt/fabric/network

# 1. Generate crypto material
export PATH=$PATH:$HOME/secdt/fabric/bin
cryptogen generate --config=./crypto-config.yaml

# 2. Generate genesis block and channel artifacts
configtxgen -profile ThreeOrgsOrdererGenesis \
  -channelID system-channel \
  -outputBlock ./channel-artifacts/genesis.block

configtxgen -profile ThreeOrgsChannel \
  -outputCreateChannelTx ./channel-artifacts/iot-channel.tx \
  -channelID iot-channel

# 3. Bring up the network
docker-compose -f docker-compose.yaml up -d

# 4. Create and join channel
./scripts/create-channel.sh

# 5. Deploy chaincode
./scripts/deploy-chaincode.sh

# Verify
docker ps | grep -E "peer|orderer"
```

Expected output:
```
peer0.org1.example.com   Up   0.0.0.0:7051->7051/tcp
peer0.org2.example.com   Up   0.0.0.0:8051->7051/tcp
peer0.org3.example.com   Up   0.0.0.0:9051->7051/tcp
orderer1.example.com     Up   0.0.0.0:7050->7050/tcp
orderer2.example.com     Up   0.0.0.0:8050->7050/tcp
orderer3.example.com     Up   0.0.0.0:9050->7050/tcp
```

**Chaincode verification:**
```bash
# Should return: {"status":"OK","machines":0,"records":0}
peer chaincode query -C iot-channel -n secdt-cc \
  -c '{"function":"GetSystemStatus","Args":[]}'
```

---

### 6.3 IPFS Cluster Bootstrap

Run on **each IPFS VM (`10.0.1.20`–`10.0.1.24`)**:

```bash
# Install go-ipfs 0.18
wget https://dist.ipfs.tech/kubo/v0.18.0/kubo_v0.18.0_linux-amd64.tar.gz
tar -xzf kubo_v0.18.0_linux-amd64.tar.gz && sudo mv kubo/ipfs /usr/local/bin/

# Initialize and start IPFS daemon
ipfs init
ipfs daemon &

# On node 0 (10.0.1.20) — get peer ID
ipfs id | grep '"ID"'
```

**Verify cluster (from edge gateway `10.0.1.10`):**
```bash
# Test with CMAPSS snapshot size (~512 bytes)
python3 -c "
import requests, json
r = requests.post('http://10.0.1.20:5001/api/v0/add',
    files={'file': b'A'*512})
print(json.loads(r.text)['Hash'])
"
# Expected: CID string (Qm... or bafy...)

# Verify replication on 3+ nodes
curl http://10.0.1.20:5001/api/v0/pin/ls?arg=<CID>
curl http://10.0.1.21:5001/api/v0/pin/ls?arg=<CID>
curl http://10.0.1.22:5001/api/v0/pin/ls?arg=<CID>
```

---

### 6.4 Edge Gateway Setup

Run on **edge gateway VM (`10.0.1.10`)**:

```bash
cd secdt
python3 -m venv venv && source venv/bin/activate
pip install -r requirements.txt

# Place CMAPSS data (see §7)
ls data/CMAPSS/
# train_FD001.txt  test_FD001.txt  RUL_FD001.txt

# Verify edge module
python3 edge/gateway.py --dry-run \
  --config config/network.yaml \
  --dataset data/CMAPSS/train_FD001.txt \
  --n-machines 1 --frequency 0.1
# Expected: "Dry run OK: snapshot size = 4XX bytes"
```

---

### 6.5 Prometheus Monitoring

Run on **monitoring VM (`10.0.1.40`)**:

```bash
cd secdt/monitoring
docker-compose -f docker-compose-monitoring.yml up -d

# Verify all targets
curl http://10.0.1.40:9090/api/v1/targets | \
  python3 -m json.tool | grep '"health"'
# All 14 VMs should show "up"
```

Access Grafana: `http://10.0.1.40:3000` (admin/admin)
Import dashboard: `monitoring/dashboards/secdt-dashboard.json`

---

## 7. Dataset Preparation

**Dataset:** NASA CMAPSS FD001 — Turbofan Engine Degradation Simulation
(Saxena & Goebel, NASA Ames Research Center, 2008)

```bash
# Download from the official NASA repository:
# https://data.nasa.gov/dataset/C-MAPSS-Aircraft-Engine-Simulator-Data

mkdir -p data/CMAPSS
# Place the following files:
# - train_FD001.txt  (14,096 time steps, 100 engine units)
# - test_FD001.txt
# - RUL_FD001.txt

# Verify dataset
python3 - <<'EOF'
import pandas as pd
cols = ['unit','cycle'] + [f's{i}' for i in range(1,22)] + ['op1','op2','op3']
df = pd.read_csv('data/CMAPSS/train_FD001.txt',
                 sep='\s+', header=None, names=cols[:26])
print(f"Units: {df['unit'].nunique()} | Cycles: {len(df):,}")
print(f"Sensors retained: 14 (columns s2,s3,s4,s7,s8,s9,s11,s12,"
      f"s13,s14,s15,s17,s20,s21)")
EOF
```

Expected output:
```
Units: 100 | Cycles: 14,096
Sensors retained: 14 (columns s2,s3,s4,s7,s8,s9,s11,s12,s13,s14,s15,s17,s20,s21)
```

---

## 8. Running the Scenarios

### 8.1 S0 – Nominal Workflow Validation

Run on **edge gateway (`10.0.1.10`)**.

```bash
source venv/bin/activate
bash scripts/run_s0_validation.sh

# Or manually:
python3 edge/gateway.py \
  --config config/network.yaml \
  --dataset data/CMAPSS/train_FD001.txt \
  --n-machines 1 \
  --frequency 0.1 \
  --duration-min 10 \
  --output logs/s0/
```

**Expected output:**
```
logs/s0/
├── pipeline_metrics.json    # success_rate, e2e_mean, ipfs_mean, fabric_mean
└── history_check.json       # GetHistory reconstruction verification
```

**Verify S0:**
```bash
python3 -c "
import json
m = json.load(open('logs/s0/pipeline_metrics.json'))
print(f'Success rate: {m[\"success_rate\"]:.3f} (target: 1.000)')
print(f'E2E mean: {m[\"e2e_mean_ms\"]:.1f} ms')
"
```

---

### 8.2 S1 – Nominal Performance

```bash
bash scripts/run_s1_nominal.sh

# Or manually (3 frequencies × 3 repetitions):
for freq in 1.0 0.1 0.01667; do
  python3 edge/gateway.py \
    --config config/network.yaml \
    --dataset data/CMAPSS/train_FD001.txt \
    --n-machines 25 \
    --frequency $freq \
    --duration-min 30 \
    --repetitions 3 \
    --output logs/s1/freq_${freq}/
done


**Expected runtime:** ~3 hours (3 frequencies × 3 repetitions × 30 min).



### 8.3 S2 – Scalability

bash
bash scripts/run_s2_scalability.sh

# Or manually (N × interval × 3 repetitions):
for n in 10 25 50 100; do
  for interval in 500 1000; do
    python3 edge/gateway.py \
      --config config/network.yaml \
      --dataset data/CMAPSS/train_FD001.txt \
      --n-machines $n \
      --interval-ms $interval \
      --duration-min 30 \
      --repetitions 3 \
      --output logs/s2/n${n}_i${interval}/
  done
done


### 8.4 S3 – Integrity, Traceability, and Auditability

bash
bash scripts/run_s3_integrity.sh

# Or run individual attack scenarios:

# T1: Pre-anchoring tampering
python3 scripts/attack_t1_tampering.py \
  --config config/network.yaml \
  --output logs/s3/t1/
# Expected: VerifyIntegrity returns false

# T3: Replay attack
python3 scripts/attack_t3_replay.py \
  --config config/network.yaml \
  --output logs/s3/t3/
# Expected: "Error: t <= t_last, replay rejected"

# T4: Unauthorized registration
python3 scripts/attack_t4_unauthorized.py \
  --config config/network.yaml \
  --output logs/s3/t4/
# Expected: "Error: MSP identity not authorized"

# Audit reconstruction
python3 scripts/audit_reconstruction.py \
  --config config/network.yaml \
  --machine-id engine_001 \
  --output logs/s3/audit/
# Expected: alpha = 1.0

**Verify detection rate:**
bash
python3 -c "
import json, glob
detected = sum(json.load(open(f))['detected']
               for f in glob.glob('logs/s3/*/result.json'))
print(f'delta = {detected}/4 = {detected/4:.1f} (target: 1.0)')
"

### 8.5 S4 – Baseline Comparison

bash
bash scripts/run_s4_baseline.sh

# Or run each system individually (same workload: f=0.1 Hz, N=25, 20 runs):

# SecDT Full
python3 edge/gateway.py \
  --config config/network.yaml \
  --dataset data/CMAPSS/train_FD001.txt \
  --n-machines 25 --frequency 0.1 \
  --duration-min 30 --repetitions 20 \
  --output logs/s4/secdt/

# Fabric-only baseline
python3 baselines/fabric_only/baseline_fabric.py \
  --config config/network.yaml \
  --dataset data/CMAPSS/train_FD001.txt \
  --n-machines 25 --frequency 0.1 \
  --duration-min 30 --repetitions 20 \
  --output logs/s4/fabric_only/

# PostgreSQL centralized baseline
python3 baselines/postgresql/baseline_pg.py \
  --config config/network.yaml \
  --dataset data/CMAPSS/train_FD001.txt \
  --n-machines 25 --frequency 0.1 \
  --duration-min 30 --repetitions 20 \
  --output logs/s4/postgresql/


### 8.6 S5 – Overhead Analysis

bash
bash scripts/run_s5_overhead.sh

# Or run configurations A → D individually (20 runs each):

# A: Local storage only
python3 edge/gateway.py --mode local_only \
  --dataset data/CMAPSS/train_FD001.txt \
  --repetitions 20 --output logs/s5/a_local/

# B: IPFS only
python3 edge/gateway.py --mode ipfs_only \
  --config config/network.yaml \
  --dataset data/CMAPSS/train_FD001.txt \
  --repetitions 20 --output logs/s5/b_ipfs/

# C: Fabric only
python3 edge/gateway.py --mode fabric_only \
  --config config/network.yaml \
  --dataset data/CMAPSS/train_FD001.txt \
  --repetitions 20 --output logs/s5/c_fabric/

# D: SecDT Full
python3 edge/gateway.py --mode full \
  --config config/network.yaml \
  --dataset data/CMAPSS/train_FD001.txt \
  --repetitions 20 --output logs/s5/d_secdt/


### 8.7 S6 – Resilience under Partial Failure

bash
bash scripts/run_s6_resilience.sh

# --- IPFS node loss (manual steps) ---

# Start continuous workload
python3 edge/gateway.py \
  --config config/network.yaml \
  --dataset data/CMAPSS/train_FD001.txt \
  --n-machines 25 --frequency 0.1 \
  --duration-min 60 \
  --output logs/s6/ipfs_fault/ &
GW_PID=$!

# After 10 min: stop 1 IPFS node
sleep 600
ssh ubuntu@10.0.1.22 "sudo systemctl stop ipfs"

# After 10 more min: stop a 2nd node
sleep 600
ssh ubuntu@10.0.1.23 "sudo systemctl stop ipfs"

# After 10 more min: restore both
sleep 600
ssh ubuntu@10.0.1.22 "sudo systemctl start ipfs"
ssh ubuntu@10.0.1.23 "sudo systemctl start ipfs"

wait $GW_PID

# --- RAFT orderer fault (manual steps) ---
python3 edge/gateway.py \
  --config config/network.yaml \
  --dataset data/CMAPSS/train_FD001.txt \
  --n-machines 25 --frequency 0.1 \
  --duration-min 60 \
  --output logs/s6/raft_fault/ &
GW_PID=$!

sleep 600
ssh ubuntu@10.0.1.35 "docker stop orderer3.example.com"

sleep 600
ssh ubuntu@10.0.1.35 "docker start orderer3.example.com"

wait $GW_PID

# --- RAFT peer fault ---
python3 edge/gateway.py \
  --config config/network.yaml \
  --dataset data/CMAPSS/train_FD001.txt \
  --n-machines 25 --frequency 0.1 \
  --duration-min 60 \
  --output logs/s6/peer_fault/ &
GW_PID=$!

sleep 600
ssh ubuntu@10.0.1.32 "docker stop peer0.org3.example.com"

sleep 600
ssh ubuntu@10.0.1.32 "docker start peer0.org3.example.com"

wait $GW_PID


## 9. Caliper Benchmark

The Caliper benchmark characterizes the raw Fabric layer capacity
independently of the IPFS and edge pipeline.

bash
cd secdt/caliper
npx caliper launch manager \
  --caliper-workspace . \
  --caliper-networkconfig networks/fabric-network.yaml \
  --caliper-benchconfig benchmarks/secdt-workload.yaml \
  --caliper-flow-only-test

**Caliper workload config** (`caliper/benchmarks/secdt-workload.yaml`):
yaml
test:
  name: SecDT Fabric Benchmark
  description: 3 target loads × 36,000 transactions each
  workers:
    number: 5
  rounds:
    - label: "1000TPS"
      txNumber: 36000
      rateControl:
        type: fixed-rate
        opts:
          tps: 1000
    - label: "1500TPS"
      txNumber: 54000
      rateControl:
        type: fixed-rate
        opts:
          tps: 1500
    - label: "2000TPS"
      txNumber: 72000
      rateControl:
        type: fixed-rate
        opts:
          tps: 2000
```

**Expected Caliper output** (in `caliper/reports/`):

| Name | Succ | Fail | Agg. TPS | Mean Lat | Max Lat |
|------|------|------|----------|----------|---------|
| 1000TPS | 36,000 | 0 | 1,947 | 0.93 s | 1.66 s |
| 1500TPS | 54,000 | 0 | 2,055 | 0.97 s | 1.95 s |
| 2000TPS | 72,000 | 0 | 2,085 | 1.03 s | 2.49 s |

---

## 10. Results Reproduction

After running all scenarios, compute all metrics:

bash
source venv/bin/activate
python3 analysis/compute_metrics.py \
  --logs-dir logs/ \
  --caliper-reports caliper/reports/ \
  --output results/metrics_summary.json

**Full reproduction script (all 7 scenarios sequentially):**

bash
# WARNING: Full run takes approximately 8–10 hours
bash scripts/run_all_scenarios.sh 2>&1 | tee logs/full_run.log


`scripts/run_all_scenarios.sh`:
bash
#!/bin/bash
set -e
echo "=== S0: Nominal Workflow Validation ==="
bash scripts/run_s0_validation.sh

echo "=== S1: Nominal Performance ==="
bash scripts/run_s1_nominal.sh

echo "=== S2: Scalability ==="
bash scripts/run_s2_scalability.sh

echo "=== S3: Integrity, Traceability, Auditability ==="
bash scripts/run_s3_integrity.sh

echo "=== S4: Baseline Comparison ==="
bash scripts/run_s4_baseline.sh

echo "=== S5: Overhead Analysis ==="
bash scripts/run_s5_overhead.sh

echo "=== S6: Resilience under Partial Failure ==="
bash scripts/run_s6_resilience.sh

echo "=== Computing all metrics ==="
python3 analysis/compute_metrics.py \
  --logs-dir logs/ \
  --caliper-reports caliper/reports/ \
  --output results/metrics_summary.json

echo "=== Generating figures ==="
python3 analysis/figures/fig_caliper.py
python3 analysis/figures/fig_nominal.py
python3 analysis/figures/fig_scalability.py
python3 analysis/figures/fig_baseline.py
python3 analysis/figures/fig_storage.py
python3 analysis/figures/fig_resilience.py
python3 analysis/figures/fig_ipfs.py

echo "=== Done. Results in results/ and paper/figures/ ==="

## 11. Generating Figures and Tables

bash
source venv/bin/activate

# Individual figures
python3 analysis/figures/fig_caliper.py   --input logs/ caliper/reports/ --output paper/figures/
python3 analysis/figures/fig_nominal.py   --input logs/s1/               --output paper/figures/
python3 analysis/figures/fig_scalability.py --input logs/s2/             --output paper/figures/
python3 analysis/figures/fig_baseline.py  --input logs/s4/               --output paper/figures/
python3 analysis/figures/fig_storage.py   --input logs/s5/               --output paper/figures/
python3 analysis/figures/fig_resilience.py --input logs/s6/              --output paper/figures/
python3 analysis/figures/fig_ipfs.py      --input logs/s1/               --output paper/figures/

# Verify figures against paper
ls paper/figures/
# v7_fig1_caliper.pdf  v7_fig2_nominal.pdf  v7_fig3b_scalability_values.pdf
# v7_fig4_baseline.pdf v7_fig5_storage.pdf  v7_fig6_resilience.pdf
# v7_fig7_ipfs.pdf

# Transfer to local machine
scp -i ~/.ssh/secdt-key.pem \
  ubuntu@10.0.1.10:/home/ubuntu/secdt/paper/figures/* \
  ~/Downloads/secdt-paper/figures/

## 12. Expected Results Summary

The following values should be reproduced within reported ranges.

### S0–S1 — Nominal Latency (Table II)
| Layer | Mean (ms) | Median (ms) | P95 (ms) | P99 (ms) |
|---|---|---|---|---|
| IPFS (add+cat) | 95.5 | 94.0 | 103.1 | 103.8 |
| Fabric commit | 661.4 | 658.5 | 675.3 | 677.5 |
| End-to-End | 915.3 | 911.0 | 937.2 | 938.6 |

### S2 — Scalability (Table III)
| N | Interval (ms) | E2E mean (ms) | E2E P95 (ms) | E2E P99 (ms) |
|---|---|---|---|---|
| 10 | 500 | 911.8 | 930.9 | 933.4 |
| 25 | 500 | 909.2 | 924.0 | 930.8 |
| 50 | 500 | 916.3 | 934.6 | 938.0 |
| 100 | 500 | 936.3 | 1,014.1 | 1,031.2 |

### S3 — Integrity (Table V)
| Scenario | Expected |
|---|---|
| T1: Pre-anchoring tampering | Detected (VerifyIntegrity = false) |
| T3: Replay attack | Rejected (chaincode precondition) |
| T4: Unauthorized registration | Rejected (MSP endorsement) |
| Audit reconstruction α | 1.0 |
| Detection rate δ | 1.0 (4/4) |

### S4 — Baseline Comparison (Table VI)
| System | Latency mean (ms) | P95 (ms) | Throughput (rps) | σ_on (bytes) |
|---|---|---|---|---|
| PostgreSQL | 171.7 | 186.6 | 1.091 | 0 |
| Fabric-only | 805.6 | 824.2 | 0.648 | 3,832 |
| SecDT Full | 902.8 | 925.2 | 0.610 | 4,332 |

### S5 — Overhead (Table VII)
| Config | Latency (ms) | CPU (%) | Network (bytes) | σ_on | σ_off |
|---|---|---|---|---|---|
| A Local | 11.3 | 12.8 | 7,760 | 0 | 0 |
| B IPFS | 106.1 | 10.3 | 142,994 | 0 | 8,618 |
| C Fabric | 796.9 | 6.0 | 4,373,267 | 3,672 | 0 |
| D SecDT | 890.2 | 6.2 | 4,608,096 | 4,372 | 8,698 |

### S6 — Resilience (Table V)
| Test | Expected |
|---|---|
| IPFS −1 node: recovery time | 16 ms |
| IPFS −2 nodes: recovery time | 20 ms |
| IPFS CID retrievability | 1.0 (both cases) |
| RAFT orderer loss: service continuity | 655 ms |
| Peer loss: service continuity | 672 ms |

### Caliper Benchmark (Table IV)
| Target TPS/VM | Agg. TPS | Mean Lat (s) | Max Lat (s) | Succ. Txns | Fail |
|---|---|---|---|---|---|
| 1,000 | 1,947.1 | 0.9267 | 1.66 | 36,000 | 0 |
| 1,500 | 2,054.7 | 0.9700 | 1.95 | 54,000 | 0 |
| 2,000 | 2,085.3 | 1.0300 | 2.49 | 72,000 | 0 |
| **Total** | | | | **162,000** | **0** |


## 13. Troubleshooting

**Fabric peer not joining channel:**
bash
docker exec peer0.org1.example.com peer channel list
# If empty: re-run ./scripts/create-channel.sh
# Check MSP certificates in crypto-config/


**IPFS node unreachable:**
bash
curl http://10.0.1.20:5001/api/v0/id
# If timeout: check firewall port 5001 (API) and 4001 (swarm)
sudo ufw allow 5001/tcp && sudo ufw allow 4001/tcp


**Edge gateway IPFS timeout:**
bash
# Verify IPFS API accessible
curl http://10.0.1.20:5001/api/v0/version
# Check edge/ipfs_client.py → timeout parameter (default 30s)

**Fabric commit latency too high:**
bash
# Verify GoLevelDB is selected (not CouchDB)
grep -i "stateDatabase" fabric/network/docker-compose.yaml
# Should show: CORE_LEDGER_STATE_STATEDATABASE=goleveldb


**NTP clock offset > 1 ms:**
bash
# Check Chrony status on all VMs
chronyc tracking | grep "RMS offset"
# If > 1 ms: sudo systemctl restart chrony


**Caliper transaction failures:**
bash
# Check BatchTimeout configuration
grep -i "batchtimeout" fabric/network/configtx.yaml
# Should be: BatchTimeout: 500ms
# Check Fabric channel health
peer channel fetch config -c iot-channel -o 10.0.1.33:7050


**Prometheus targets down:**
bash
docker restart node-exporter
curl http://10.0.1.30:9100/metrics | head -5


## 14. License

This project is licensed under the MIT License — see [LICENSE](LICENSE)
for details.

Dataset (NASA CMAPSS) is provided by NASA Ames Research Center under
its own terms of use.
Hyperledger Fabric is licensed under Apache 2.0.
go-ipfs is licensed under MIT/Apache 2.0.


<p align="center">
  <em>Developed at the Université du Québec à Chicoutimi (UQAC)
  and Université de Sherbrooke — IEEE IoT Journal Submission 2026</em>
</p>
