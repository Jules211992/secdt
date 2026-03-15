#!/bin/bash
set -euo pipefail

NODES=(
  peer-fabric-1
  peer-fabric-2
  peer-fabric-3
  orderer-fabric-1
  orderer-fabric-2
  orderer-fabric-3
  ipfs-node-1
  ipfs-node-2
  ipfs-node-3
  ipfs-node-4
  ipfs-node-5
  edge-gateway
  postgres-baseline
  monitoring
)

SSH_OPTS="-i ~/.ssh/fl-ids-key.pem -o StrictHostKeyChecking=no"

mkdir -p ~/secdt-fabric/phase0-check
OUT=~/secdt-fabric/phase0-check/phase0_report.txt
: > "$OUT"

echo "===== PHASE 0 CHECK =====" | tee -a "$OUT"
date -u | tee -a "$OUT"
echo | tee -a "$OUT"

echo "===== 1. INVENTAIRE DES MACHINES =====" | tee -a "$OUT"
for n in "${NODES[@]}"; do
  echo "--- $n ---" | tee -a "$OUT"
  ssh $SSH_OPTS ubuntu@"$n" 'hostname; hostname -I; uname -sr; command -v chronyc >/dev/null && echo CHRONY=OK || echo CHRONY=ABSENT; command -v docker >/dev/null && echo DOCKER=OK || echo DOCKER=ABSENT' 2>&1 | tee -a "$OUT"
  echo | tee -a "$OUT"
done

echo "===== 2. SYNCHRONISATION TEMPORELLE =====" | tee -a "$OUT"
for n in "${NODES[@]}"; do
  echo "--- $n ---" | tee -a "$OUT"
  ssh $SSH_OPTS ubuntu@"$n" 'timedatectl | sed -n "1,12p"; echo; chronyc tracking || true; echo; chronyc sources -v || true' 2>&1 | tee -a "$OUT"
  echo | tee -a "$OUT"
done

echo "===== 3. CONNECTIVITE INTER-VM =====" | tee -a "$OUT"
for src in edge-gateway peer-fabric-1 monitoring; do
  echo "--- SOURCE: $src ---" | tee -a "$OUT"
  ssh $SSH_OPTS ubuntu@"$src" '
    for dst in peer-fabric-1 peer-fabric-2 peer-fabric-3 orderer-fabric-1 orderer-fabric-2 orderer-fabric-3 ipfs-node-1 ipfs-node-2 ipfs-node-3 ipfs-node-4 ipfs-node-5 edge-gateway postgres-baseline monitoring; do
      printf "%s -> %s : " "$(hostname)" "$dst"
      getent hosts "$dst" >/dev/null 2>&1 && echo DNS_OK || echo DNS_FAIL
    done
  ' 2>&1 | tee -a "$OUT"
  echo | tee -a "$OUT"
done

echo "===== 4. PORTS MINIMAUX =====" | tee -a "$OUT"
ssh $SSH_OPTS ubuntu@peer-fabric-1 '
  for dst in peer-fabric-1 peer-fabric-2 peer-fabric-3; do
    timeout 3 bash -lc "cat < /dev/null > /dev/tcp/$dst/7051" && echo "$dst:7051 OK" || echo "$dst:7051 FAIL"
  done
  for dst in orderer-fabric-1 orderer-fabric-2 orderer-fabric-3; do
    timeout 3 bash -lc "cat < /dev/null > /dev/tcp/$dst/7050" && echo "$dst:7050 OK" || echo "$dst:7050 FAIL"
  done
  for dst in ipfs-node-1 ipfs-node-2 ipfs-node-3 ipfs-node-4 ipfs-node-5; do
    timeout 3 bash -lc "cat < /dev/null > /dev/tcp/$dst/5001" && echo "$dst:5001 OK" || echo "$dst:5001 FAIL"
  done
  timeout 3 bash -lc "cat < /dev/null > /dev/tcp/postgres-baseline/5432" && echo "postgres-baseline:5432 OK" || echo "postgres-baseline:5432 FAIL"
  timeout 3 bash -lc "cat < /dev/null > /dev/tcp/monitoring/9090" && echo "monitoring:9090 OK" || echo "monitoring:9090 FAIL"
' 2>&1 | tee -a "$OUT"

echo | tee -a "$OUT"
echo "===== FIN PHASE 0 CHECK =====" | tee -a "$OUT"
echo "Rapport: $OUT" | tee -a "$OUT"
