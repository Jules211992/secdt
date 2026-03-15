set -euo pipefail
cd ~/secdt-caliper-benchmark
RUN_ID="dist_peer1_$(date +%Y%m%d_%H%M%S)"
RESULT_DIR="$HOME/secdt-caliper-benchmark/reports/$RUN_ID"
mkdir -p "$RESULT_DIR"
npx caliper launch manager \
  --caliper-workspace ~/secdt-caliper-benchmark \
  --caliper-networkconfig networks/network-peer1.yaml \
  --caliper-benchconfig benchmarks/secdt/registerStateBenchmark_singlevm_1000.yaml \
  --caliper-flow-only-test \
  --caliper-monitor-config networks/no-monitor.yaml \
  --caliper-fabric-gateway-enabled | tee "$RESULT_DIR/caliper.log"
cp ~/secdt-caliper-benchmark/report.html "$RESULT_DIR/report.html"
echo "$RESULT_DIR"
