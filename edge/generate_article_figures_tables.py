from pathlib import Path
import json
import csv
import re
import math
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

ROOT = Path.home() / "secdt-results" / "Resultat_valider"
OUT = Path.home() / "secdt-results" / "article_assets"
FIG = OUT / "figures"
TAB = OUT / "tables"

FIG.mkdir(parents=True, exist_ok=True)
TAB.mkdir(parents=True, exist_ok=True)

def read_json(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))

def write_csv(path, headers, rows):
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(headers)
        for row in rows:
            w.writerow(row)

def ensure(path):
    p = Path(path)
    if not p.exists():
        raise SystemExit(f"ERROR: fichier introuvable: {p}")
    return p

def parse_phase2_summary(path):
    text = Path(path).read_text(encoding="utf-8", errors="replace")

    m_target = re.search(r"Distributed benchmark:\s*(\d+)\s*TPS per VM", text)
    m_agg = re.search(r"Aggregated throughput\s*([\d.]+)\s*TPS", text)

    peer_matches = re.findall(
        r"Peer\s+(\d+)\s+Throughput:\s+([\d.]+)\s+TPS\s+Average latency:\s+([\d.]+)\s+s\s+Max latency:\s+([\d.]+)\s+s\s+Successful transactions:\s+(\d+)\s+Failed transactions:\s+(\d+)",
        text,
        flags=re.MULTILINE
    )

    if not m_target or not m_agg or not peer_matches:
        raise SystemExit(f"ERROR: impossible de parser {path}")

    peers = []
    for peer, thr, avg_lat, max_lat, succ, fail in peer_matches:
        peers.append({
            "peer": int(peer),
            "throughput_tps": float(thr),
            "avg_latency_s": float(avg_lat),
            "max_latency_s": float(max_lat),
            "successful_transactions": int(succ),
            "failed_transactions": int(fail)
        })

    peers = sorted(peers, key=lambda x: x["peer"])

    return {
        "target_tps_per_vm": int(m_target.group(1)),
        "n_orgs": len(peers),
        "total_target_tps": int(m_target.group(1)) * len(peers),
        "aggregated_throughput_tps": float(m_agg.group(1)),
        "total_successful_transactions": sum(p["successful_transactions"] for p in peers),
        "total_failed_transactions": sum(p["failed_transactions"] for p in peers),
        "mean_peer_avg_latency_s": round(sum(p["avg_latency_s"] for p in peers) / len(peers), 4),
        "max_peer_latency_s": max(p["max_latency_s"] for p in peers),
        "peers": peers
    }

def kb(v):
    return round(v / 1024.0, 4)

def mb(v):
    return round(v / (1024.0 * 1024.0), 4)

phase2_files = [
    ROOT / "phase2_caliper" / "1000" / "summary.txt",
    ROOT / "phase2_caliper" / "1500" / "summary.txt",
    ROOT / "phase2_caliper" / "2000" / "summary.txt"
]

for f in phase2_files:
    ensure(f)

phase4_file = ensure(ROOT / "phase4_s1" / "phase4_s1_summary.json")
phase5_file = ensure(ROOT / "phase5_s2" / "phase5_s2_summary.json")
phase6_file = ensure(ROOT / "phase6_s3" / "phase6_s3_summary.json")
phase7_file = ensure(ROOT / "phase7_s4" / "phase7_s4_summary.json")
phase8_file = ensure(ROOT / "phase8_s5" / "phase8_s5_summary.json")
phase9_file = ensure(ROOT / "phase9_s6" / "phase9_s6_summary.json")
phase10_file = ensure(ROOT / "phase10_ipfs_filesize" / "phase10_ipfs_filesize_summary.json")

phase2 = [parse_phase2_summary(f) for f in phase2_files]
phase2 = sorted(phase2, key=lambda x: x["target_tps_per_vm"])

phase4 = read_json(phase4_file)
phase5 = read_json(phase5_file)
phase6 = read_json(phase6_file)
phase7 = read_json(phase7_file)
phase8 = read_json(phase8_file)
phase9 = read_json(phase9_file)
phase10 = read_json(phase10_file)

table1_rows = []
for item in phase2:
    p1 = item["peers"][0]
    p2 = item["peers"][1]
    p3 = item["peers"][2]
    table1_rows.append([
        item["target_tps_per_vm"],
        item["n_orgs"],
        item["total_target_tps"],
        p1["throughput_tps"],
        p2["throughput_tps"],
        p3["throughput_tps"],
        item["aggregated_throughput_tps"],
        item["mean_peer_avg_latency_s"],
        item["max_peer_latency_s"],
        item["total_successful_transactions"],
        item["total_failed_transactions"]
    ])

write_csv(
    TAB / "table_01_phase2_caliper_distributed.csv",
    [
        "target_tps_per_vm",
        "n_orgs",
        "total_target_tps",
        "peer1_throughput_tps",
        "peer2_throughput_tps",
        "peer3_throughput_tps",
        "aggregated_throughput_tps",
        "mean_peer_avg_latency_s",
        "max_peer_latency_s",
        "total_successful_transactions",
        "total_failed_transactions"
    ],
    table1_rows
)

x = [i["target_tps_per_vm"] for i in phase2]
y_thr = [i["aggregated_throughput_tps"] for i in phase2]
y_lat = [i["mean_peer_avg_latency_s"] for i in phase2]

plt.figure(figsize=(8, 5.5))
ax1 = plt.gca()
ax1.plot(x, y_thr, marker="o", linewidth=2, label="Aggregated throughput")
ax1.set_xlabel("Target load per VM (TPS)")
ax1.set_ylabel("Aggregated throughput (TPS)")
ax1.set_title("Fig. 1 — Distributed Caliper performance under load")
ax1.grid(True, alpha=0.3)

ax2 = ax1.twinx()
ax2.plot(x, y_lat, marker="s", linewidth=2, linestyle="--", label="Mean peer latency")
ax2.set_ylabel("Mean peer latency (s)")

lines = ax1.get_lines() + ax2.get_lines()
labels = [l.get_label() for l in lines]
ax1.legend(lines, labels, loc="best")
plt.tight_layout()
plt.savefig(FIG / "fig_01_phase2_caliper_distributed.png", dpi=300)
plt.close()

p4_e2e = phase4["latency_ms"]["end_to_end"]
p4_ipfs = phase4["latency_ms"]["ipfs_total"]
p4_fabric = phase4["latency_ms"]["fabric_commit"]

write_csv(
    TAB / "table_02_phase4_nominal_latency.csv",
    [
        "runset_id",
        "n_runs",
        "success_rate",
        "emission_interval_ms",
        "end_to_end_mean_ms",
        "end_to_end_median_ms",
        "end_to_end_p95_ms",
        "end_to_end_p99_ms",
        "ipfs_mean_ms",
        "ipfs_median_ms",
        "ipfs_p95_ms",
        "ipfs_p99_ms",
        "fabric_mean_ms",
        "fabric_median_ms",
        "fabric_p95_ms",
        "fabric_p99_ms"
    ],
    [[
        phase4.get("runset_id"),
        phase4.get("n_runs"),
        phase4.get("success_rate"),
        phase4.get("emission_interval_ms"),
        p4_e2e.get("mean"),
        p4_e2e.get("median"),
        p4_e2e.get("p95"),
        p4_e2e.get("p99"),
        p4_ipfs.get("mean"),
        p4_ipfs.get("median"),
        p4_ipfs.get("p95"),
        p4_ipfs.get("p99"),
        p4_fabric.get("mean"),
        p4_fabric.get("median"),
        p4_fabric.get("p95"),
        p4_fabric.get("p99")
    ]]
)

plt.figure(figsize=(8, 5.5))
labels = ["End-to-end", "IPFS", "Fabric commit"]
values = [p4_e2e["mean"], p4_ipfs["mean"], p4_fabric["mean"]]
plt.bar(labels, values)
plt.ylabel("Mean latency (ms)")
plt.title("Fig. 2 — Nominal SecDT latency breakdown")
plt.grid(axis="y", alpha=0.3)
plt.tight_layout()
plt.savefig(FIG / "fig_02_phase4_nominal_latency.png", dpi=300)
plt.close()

phase5_cases = sorted(
    phase5["cases"],
    key=lambda x: (x["interval_ms"], x["machine_count"])
)

table3_rows = []
for c in phase5_cases:
    table3_rows.append([
        c["machine_count"],
        c["interval_ms"],
        c["n_runs"],
        c["success_rate"],
        c["throughput_rps"],
        c["network_cost_bytes"],
        c["latency_ms"]["end_to_end"]["mean"],
        c["latency_ms"]["end_to_end"]["p95"],
        c["latency_ms"]["end_to_end"]["p99"],
        c["latency_ms"]["ipfs_total"]["mean"],
        c["latency_ms"]["fabric_commit"]["mean"]
    ])

write_csv(
    TAB / "table_03_phase5_scalability.csv",
    [
        "machine_count",
        "interval_ms",
        "n_runs",
        "success_rate",
        "throughput_rps",
        "network_cost_bytes",
        "end_to_end_mean_ms",
        "end_to_end_p95_ms",
        "end_to_end_p99_ms",
        "ipfs_mean_ms",
        "fabric_commit_mean_ms"
    ],
    table3_rows
)

x500 = [c["machine_count"] for c in phase5_cases if c["interval_ms"] == 500]
y500_lat = [c["latency_ms"]["end_to_end"]["mean"] for c in phase5_cases if c["interval_ms"] == 500]
y500_thr = [c["throughput_rps"] for c in phase5_cases if c["interval_ms"] == 500]

x1000 = [c["machine_count"] for c in phase5_cases if c["interval_ms"] == 1000]
y1000_lat = [c["latency_ms"]["end_to_end"]["mean"] for c in phase5_cases if c["interval_ms"] == 1000]
y1000_thr = [c["throughput_rps"] for c in phase5_cases if c["interval_ms"] == 1000]

plt.figure(figsize=(8.5, 5.5))
ax1 = plt.gca()
ax1.plot(x500, y500_lat, marker="o", linewidth=2, label="Latency 500 ms")
ax1.plot(x1000, y1000_lat, marker="s", linewidth=2, label="Latency 1000 ms")
ax1.set_xlabel("Number of digital twins")
ax1.set_ylabel("Mean end-to-end latency (ms)")
ax1.set_title("Fig. 3 — Digital twin scalability from 10 to 100 machines")
ax1.grid(True, alpha=0.3)

ax2 = ax1.twinx()
ax2.plot(x500, y500_thr, marker="^", linewidth=2, linestyle="--", label="Throughput 500 ms")
ax2.plot(x1000, y1000_thr, marker="d", linewidth=2, linestyle="--", label="Throughput 1000 ms")
ax2.set_ylabel("Throughput (rps)")

lines = ax1.get_lines() + ax2.get_lines()
labels = [l.get_label() for l in lines]
ax1.legend(lines, labels, loc="best")
plt.tight_layout()
plt.savefig(FIG / "fig_03_phase5_scalability.png", dpi=300)
plt.close()

phase7_systems = phase7["systems"]

table4_rows = []
for s in phase7_systems:
    table4_rows.append([
        s["system"],
        s["n_runs"],
        s["success_rate"],
        s["throughput_rps"],
        s["latency_ms"]["mean"],
        s["latency_ms"]["p95"],
        s["storage_bytes"]["on_chain"],
        s["storage_bytes"]["off_chain"],
        s["storage_bytes"]["database_total"],
        s["auditability"]["history_reconstructable"],
        s["auditability"]["integrity_proof_strength"]
    ])

write_csv(
    TAB / "table_04_phase7_baseline_comparison.csv",
    [
        "system",
        "n_runs",
        "success_rate",
        "throughput_rps",
        "latency_mean_ms",
        "latency_p95_ms",
        "on_chain_bytes",
        "off_chain_bytes",
        "database_total_bytes",
        "history_reconstructable",
        "integrity_proof_strength"
    ],
    table4_rows
)

labels = [s["system"] for s in phase7_systems]
lat = [s["latency_ms"]["mean"] for s in phase7_systems]
thr = [s["throughput_rps"] for s in phase7_systems]

plt.figure(figsize=(8.5, 5.5))
ax1 = plt.gca()
ax1.bar(labels, lat)
ax1.set_ylabel("Mean latency (ms)")
ax1.set_title("Fig. 4 — Baseline comparison")
ax1.grid(axis="y", alpha=0.3)

ax2 = ax1.twinx()
ax2.plot(labels, thr, marker="o", linewidth=2)
ax2.set_ylabel("Throughput (rps)")

plt.tight_layout()
plt.savefig(FIG / "fig_04_phase7_baselines.png", dpi=300)
plt.close()

phase8_cases = phase8["cases"]

table5_rows = []
for c in phase8_cases:
    table5_rows.append([
        c["case"],
        c["n_runs"],
        c["success_rate"],
        c["latency_ms"]["mean"],
        c["cpu_busy_pct"]["mean"],
        c["mem_delta_mb"]["mean"],
        c["network_total_bytes"]["sum"],
        c["data_manipulated_bytes"]["sum"],
        c["storage_bytes"]["on_chain"],
        c["storage_bytes"]["off_chain"]
    ])

write_csv(
    TAB / "table_05_phase8_storage_overhead.csv",
    [
        "case",
        "n_runs",
        "success_rate",
        "latency_mean_ms",
        "cpu_busy_mean_pct",
        "mem_delta_mean_mb",
        "network_total_bytes_sum",
        "data_manipulated_bytes_sum",
        "on_chain_bytes",
        "off_chain_bytes"
    ],
    table5_rows
)

labels = [c["case"] for c in phase8_cases]
on_chain_kb = [kb(c["storage_bytes"]["on_chain"]) for c in phase8_cases]
off_chain_kb = [kb(c["storage_bytes"]["off_chain"]) for c in phase8_cases]
network_kb = [kb(c["network_total_bytes"]["sum"]) for c in phase8_cases]

plt.figure(figsize=(9, 5.5))
ax1 = plt.gca()
ax1.bar(labels, on_chain_kb, label="On-chain storage (KB)")
ax1.bar(labels, off_chain_kb, bottom=on_chain_kb, label="Off-chain storage (KB)")
ax1.set_ylabel("Storage volume (KB)")
ax1.set_title("Fig. 5 — On-chain / off-chain storage and network cost")
ax1.grid(axis="y", alpha=0.3)

ax2 = ax1.twinx()
ax2.plot(labels, network_kb, marker="o", linewidth=2, label="Network volume (KB)")
ax2.set_ylabel("Network volume (KB)")

lines1, labels1 = ax1.get_legend_handles_labels()
lines2, labels2 = ax2.get_legend_handles_labels()
ax1.legend(lines1 + lines2, labels1 + labels2, loc="best")
plt.tight_layout()
plt.savefig(FIG / "fig_05_phase8_storage_network.png", dpi=300)
plt.close()

phase6_rows = []
for s in phase6["scenarios"]:
    phase6_rows.append([
        "phase6_s3",
        s.get("scenario"),
        s.get("name"),
        s.get("success"),
        s.get("history_length"),
        s.get("tamper_detected", s.get("replay_detected", s.get("unauthorized_rejected", s.get("all_consistent")))),
        ""
    ])

phase9_rows = []
for s in phase9["scenarios"]:
    phase9_rows.append([
        "phase9_s6",
        s.get("scenario"),
        "",
        s.get("success"),
        s.get("history_length"),
        s.get("retrievable_after_failure", s.get("service_continuity_preserved")),
        s.get("recovery_ms", s.get("latency_under_failure_ms"))
    ])

write_csv(
    TAB / "table_06_phase6_phase9_security_resilience.csv",
    [
        "phase",
        "scenario",
        "name",
        "success",
        "history_length",
        "key_validation_flag",
        "timing_or_recovery_ms"
    ],
    phase6_rows + phase9_rows
)

phase9_labels = []
phase9_values = []

for s in phase9["scenarios"]:
    phase9_labels.append(s["scenario"])
    if s.get("recovery_ms") is not None:
        phase9_values.append(float(s["recovery_ms"]))
    else:
        phase9_values.append(float(s.get("latency_under_failure_ms", 0)))

plt.figure(figsize=(9, 5.5))
plt.bar(phase9_labels, phase9_values)
plt.ylabel("Observed time under partial failure (ms)")
plt.title("Fig. 6 — Availability under partial failure")
plt.grid(axis="y", alpha=0.3)
plt.tight_layout()
plt.savefig(FIG / "fig_06_phase9_partial_failure.png", dpi=300)
plt.close()

phase10_cases = sorted(phase10["cases"], key=lambda x: x["file_size_bytes"])

table7_rows = []
for c in phase10_cases:
    table7_rows.append([
        c["file_size_label"],
        c["file_size_bytes"],
        c["n_runs"],
        c["add_success_rate"],
        c["retrieval_success_rate"],
        c["hash_consistency_rate"],
        c["add_latency_ms"]["mean"],
        c["add_latency_ms"]["p95"],
        c["cat_latency_ms"]["mean"],
        c["cat_latency_ms"]["p95"],
        c["write_throughput_mbps"]["mean"],
        c["write_throughput_mbps"]["p95"],
        c["read_throughput_mbps"]["mean"],
        c["read_throughput_mbps"]["p95"]
    ])

write_csv(
    TAB / "table_07_phase10_ipfs_file_size.csv",
    [
        "file_size_label",
        "file_size_bytes",
        "n_runs",
        "add_success_rate",
        "retrieval_success_rate",
        "hash_consistency_rate",
        "add_mean_ms",
        "add_p95_ms",
        "cat_mean_ms",
        "cat_p95_ms",
        "write_throughput_MBps_mean",
        "write_throughput_MBps_p95",
        "read_throughput_MBps_mean",
        "read_throughput_MBps_p95"
    ],
    table7_rows
)

x = [c["file_size_bytes"] for c in phase10_cases]
xlabels = [c["file_size_label"] for c in phase10_cases]
add_mean = [c["add_latency_ms"]["mean"] for c in phase10_cases]
cat_mean = [c["cat_latency_ms"]["mean"] for c in phase10_cases]
write_mean = [c["write_throughput_mbps"]["mean"] for c in phase10_cases]
read_mean = [c["read_throughput_mbps"]["mean"] for c in phase10_cases]

plt.figure(figsize=(9, 5.5))
ax1 = plt.gca()
ax1.plot(x, add_mean, marker="o", linewidth=2, label="IPFS add latency")
ax1.plot(x, cat_mean, marker="s", linewidth=2, label="IPFS retrieval latency")
ax1.set_xscale("log")
ax1.set_xticks(x)
ax1.set_xticklabels(xlabels, rotation=45)
ax1.set_xlabel("File size")
ax1.set_ylabel("Latency (ms)")
ax1.set_title("Fig. 7 — IPFS storage performance and retrieval rates by file size")
ax1.grid(True, alpha=0.3)

ax2 = ax1.twinx()
ax2.plot(x, write_mean, marker="^", linewidth=2, linestyle="--", label="Write throughput")
ax2.plot(x, read_mean, marker="d", linewidth=2, linestyle="--", label="Read throughput")
ax2.set_ylabel("Throughput (MB/s)")

lines = ax1.get_lines() + ax2.get_lines()
labels = [l.get_label() for l in lines]
ax1.legend(lines, labels, loc="best")
plt.tight_layout()
plt.savefig(FIG / "fig_07_phase10_ipfs_filesize.png", dpi=300)
plt.close()

manifest = {
    "root_validated_results": str(ROOT),
    "output_dir": str(OUT),
    "article_result_figures_only": True,
    "phase3_present_but_not_used_in_current_article_plan": str(ROOT / "phase3" / "phase3_report.json"),
    "figures": sorted(str(p) for p in FIG.glob("*.png")),
    "tables": sorted(str(p) for p in TAB.glob("*.csv"))
}

(OUT / "article_assets_manifest.json").write_text(
    json.dumps(manifest, indent=2),
    encoding="utf-8"
)

print(json.dumps(manifest, indent=2))
