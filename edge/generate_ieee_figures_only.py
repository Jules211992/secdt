from pathlib import Path
import json
import re
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

ROOT = Path.home() / "secdt-results" / "Resultat_valider"
OUT = Path.home() / "secdt-results" / "article_figures_ieee"
OUT.mkdir(parents=True, exist_ok=True)

plt.rcParams.update({
    "font.family": "serif",
    "font.size": 8,
    "axes.labelsize": 8,
    "xtick.labelsize": 7,
    "ytick.labelsize": 7,
    "legend.fontsize": 7,
    "figure.dpi": 300,
    "savefig.dpi": 600
})

def read_json(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))

def save(fig, name):
    fig.savefig(OUT / f"{name}.pdf", bbox_inches="tight")
    fig.savefig(OUT / f"{name}.png", bbox_inches="tight")
    plt.close(fig)

def style_ax(ax):
    ax.grid(True, alpha=0.25, linewidth=0.5)

def panel_label(ax, txt):
    ax.text(-0.16, 1.03, txt, transform=ax.transAxes, fontsize=8, fontweight="bold", va="bottom")

def parse_phase2_summary(path):
    text = Path(path).read_text(encoding="utf-8", errors="replace")

    m_target = re.search(r"Distributed benchmark:\s*(\d+)\s*TPS per VM", text)
    m_agg = re.search(r"Aggregated throughput\s*([\d.]+)\s*TPS", text)

    peer_matches = re.findall(
        r"Peer\s+(\d+)\s+Throughput:\s+([\d.]+)\s+TPS\s+Average latency:\s+([\d.]+)\s+s\s+Max latency:\s+([\d.]+)\s+s\s+Successful transactions:\s+(\d+)\s+Failed transactions:\s+(\d+)",
        text,
        flags=re.MULTILINE
    )

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
        "mean_peer_avg_latency_ms": 1000.0 * sum(p["avg_latency_s"] for p in peers) / len(peers),
        "max_peer_latency_ms": 1000.0 * max(p["max_latency_s"] for p in peers),
        "peers": peers
    }

phase2 = [
    parse_phase2_summary(ROOT / "phase2_caliper" / "1000" / "summary.txt"),
    parse_phase2_summary(ROOT / "phase2_caliper" / "1500" / "summary.txt"),
    parse_phase2_summary(ROOT / "phase2_caliper" / "2000" / "summary.txt")
]
phase2 = sorted(phase2, key=lambda x: x["target_tps_per_vm"])

phase4 = read_json(ROOT / "phase4_s1" / "phase4_s1_summary.json")
phase5 = read_json(ROOT / "phase5_s2" / "phase5_s2_summary.json")
phase6 = read_json(ROOT / "phase6_s3" / "phase6_s3_summary.json")
phase7 = read_json(ROOT / "phase7_s4" / "phase7_s4_summary.json")
phase8 = read_json(ROOT / "phase8_s5" / "phase8_s5_summary.json")
phase9 = read_json(ROOT / "phase9_s6" / "phase9_s6_summary.json")
phase10 = read_json(ROOT / "phase10_ipfs_filesize" / "phase10_ipfs_filesize_summary.json")

fig, axes = plt.subplots(1, 2, figsize=(7.16, 2.7))
offered = [x["total_target_tps"] for x in phase2]
achieved = [x["aggregated_throughput_tps"] for x in phase2]
lat_ms = [x["mean_peer_avg_latency_ms"] for x in phase2]

axes[0].plot(offered, offered, linestyle="--", marker="s", label="Offered load")
axes[0].plot(offered, achieved, marker="o", label="Achieved throughput")
axes[0].set_xlabel("Total offered load (TPS)")
axes[0].set_ylabel("Aggregated throughput (TPS)")
style_ax(axes[0])
axes[0].legend(frameon=True)
panel_label(axes[0], "(a)")

axes[1].plot(offered, lat_ms, marker="o", label="Mean peer latency")
axes[1].set_xlabel("Total offered load (TPS)")
axes[1].set_ylabel("Mean peer latency (ms)")
style_ax(axes[1])
panel_label(axes[1], "(b)")

fig.tight_layout()
save(fig, "fig01_phase2_caliper_ieee")

p4_e2e = phase4["latency_ms"]["end_to_end"]["mean"]
p4_ipfs = phase4["latency_ms"]["ipfs_total"]["mean"]
p4_fabric = phase4["latency_ms"]["fabric_commit"]["mean"]
p4_other = max(p4_e2e - p4_ipfs - p4_fabric, 0.0)

fig, ax = plt.subplots(figsize=(3.45, 2.45))
x = [0]
ax.bar(x, [p4_ipfs], width=0.45, label="IPFS")
ax.bar(x, [p4_fabric], bottom=[p4_ipfs], width=0.45, label="Fabric commit")
ax.bar(x, [p4_other], bottom=[p4_ipfs + p4_fabric], width=0.45, label="Query/Audit")
ax.plot(x, [p4_e2e], marker="D", linestyle="None", label="End-to-end mean")
ax.set_xticks([0])
ax.set_xticklabels(["Nominal run"])
ax.set_ylabel("Latency (ms)")
style_ax(ax)
ax.legend(frameon=True, loc="upper left")
fig.tight_layout()
save(fig, "fig02_phase4_nominal_breakdown_ieee")

cases_500 = sorted([c for c in phase5["cases"] if c["interval_ms"] == 500], key=lambda x: x["machine_count"])
cases_1000 = sorted([c for c in phase5["cases"] if c["interval_ms"] == 1000], key=lambda x: x["machine_count"])

x500 = [c["machine_count"] for c in cases_500]
lat500 = [c["latency_ms"]["end_to_end"]["mean"] for c in cases_500]
thr500 = [c["throughput_rps"] for c in cases_500]

x1000 = [c["machine_count"] for c in cases_1000]
lat1000 = [c["latency_ms"]["end_to_end"]["mean"] for c in cases_1000]
thr1000 = [c["throughput_rps"] for c in cases_1000]

fig, axes = plt.subplots(1, 2, figsize=(7.16, 2.7))

axes[0].plot(x500, lat500, marker="o", label="500 ms")
axes[0].plot(x1000, lat1000, marker="s", label="1000 ms")
axes[0].set_xlabel("Number of digital twins")
axes[0].set_ylabel("Mean end-to-end latency (ms)")
style_ax(axes[0])
axes[0].legend(frameon=True)
panel_label(axes[0], "(a)")

axes[1].plot(x500, thr500, marker="o", label="500 ms")
axes[1].plot(x1000, thr1000, marker="s", label="1000 ms")
axes[1].set_xlabel("Number of digital twins")
axes[1].set_ylabel("Throughput (rps)")
style_ax(axes[1])
panel_label(axes[1], "(b)")

fig.tight_layout()
save(fig, "fig03_phase5_scalability_ieee")

systems = phase7["systems"]
labels = []
lat = []
thr = []

name_map = {
    "postgresql_centralized": "PostgreSQL",
    "fabric_only": "Fabric-only",
    "secdt_full": "SecDT"
}

for s in systems:
    labels.append(name_map.get(s["system"], s["system"]))
    lat.append(s["latency_ms"]["mean"])
    thr.append(s["throughput_rps"])

fig, axes = plt.subplots(1, 2, figsize=(7.16, 2.6))

axes[0].bar(labels, lat, width=0.6)
axes[0].set_ylabel("Mean latency (ms)")
style_ax(axes[0])
panel_label(axes[0], "(a)")

axes[1].bar(labels, thr, width=0.6)
axes[1].set_ylabel("Throughput (rps)")
style_ax(axes[1])
panel_label(axes[1], "(b)")

fig.tight_layout()
save(fig, "fig04_phase7_baselines_ieee")

cases = phase8["cases"]
label_map = {
    "case_a_local_only": "Local",
    "case_b_ipfs_only": "IPFS",
    "case_c_fabric_only": "Fabric",
    "case_d_ipfs_fabric": "Hybrid"
}

labels = [label_map[c["case"]] for c in cases]
on_chain = [c["storage_bytes"]["on_chain"] / 1024.0 for c in cases]
off_chain = [c["storage_bytes"]["off_chain"] / 1024.0 for c in cases]
network_kb = [c["network_total_bytes"]["sum"] / 1024.0 for c in cases]

fig, axes = plt.subplots(1, 2, figsize=(7.16, 2.8))

axes[0].bar(labels, on_chain, width=0.6, label="On-chain")
axes[0].bar(labels, off_chain, bottom=on_chain, width=0.6, label="Off-chain")
axes[0].set_ylabel("Storage volume (KB)")
style_ax(axes[0])
axes[0].legend(frameon=True)
panel_label(axes[0], "(a)")

axes[1].bar(labels, network_kb, width=0.6)
axes[1].set_ylabel("Network volume (KB)")
style_ax(axes[1])
panel_label(axes[1], "(b)")

fig.tight_layout()
save(fig, "fig05_phase8_storage_network_ieee")

m6 = phase6["metrics"]
security_labels = ["Tamper", "Replay", "Unauthorized", "Audit", "CID-hash"]
security_vals = [
    100.0 * m6["tamper_detection_rate"],
    100.0 * m6["replay_detection_rate"],
    100.0 * m6["unauthorized_rejection_rate"],
    100.0 * m6["audit_reconstruction_success"],
    100.0 * m6["cid_hash_consistency"]
]

fail_labels = []
fail_vals = []
for s in phase9["scenarios"]:
    sc = s["scenario"]
    if sc == "s6_ipfs_loss_1_node":
        fail_labels.append("IPFS -1")
        fail_vals.append(float(s["recovery_ms"]))
    elif sc == "s6_ipfs_loss_2_nodes":
        fail_labels.append("IPFS -2")
        fail_vals.append(float(s["recovery_ms"]))
    elif sc == "s6_orderer_loss":
        fail_labels.append("Orderer -1")
        fail_vals.append(float(s["latency_under_failure_ms"]))
    elif sc == "s6_peer_loss":
        fail_labels.append("Peer -1")
        fail_vals.append(float(s["latency_under_failure_ms"]))

fig, axes = plt.subplots(1, 2, figsize=(7.16, 2.8))

axes[0].bar(security_labels, security_vals, width=0.6)
axes[0].set_ylim(0, 110)
axes[0].set_ylabel("Success rate (%)")
style_ax(axes[0])
panel_label(axes[0], "(a)")
for tick in axes[0].get_xticklabels():
    tick.set_rotation(20)

axes[1].bar(fail_labels, fail_vals, width=0.6)
axes[1].set_ylabel("Observed time (ms)")
style_ax(axes[1])
panel_label(axes[1], "(b)")

fig.tight_layout()
save(fig, "fig06_phase6_phase9_security_resilience_ieee")

p10 = sorted(phase10["cases"], key=lambda x: x["file_size_bytes"])
sizes = [c["file_size_bytes"] for c in p10]
size_labels = [c["file_size_label"] for c in p10]
add_lat = [c["add_latency_ms"]["mean"] for c in p10]
cat_lat = [c["cat_latency_ms"]["mean"] for c in p10]
write_thr = [c["write_throughput_mbps"]["mean"] for c in p10]
read_thr = [c["read_throughput_mbps"]["mean"] for c in p10]

fig, axes = plt.subplots(1, 2, figsize=(7.16, 2.9))

axes[0].plot(sizes, add_lat, marker="o", label="Add")
axes[0].plot(sizes, cat_lat, marker="s", label="Retrieve")
axes[0].set_xscale("log")
axes[0].set_xticks(sizes)
axes[0].set_xticklabels(size_labels, rotation=45, ha="right")
axes[0].set_ylabel("Latency (ms)")
style_ax(axes[0])
axes[0].legend(frameon=True)
panel_label(axes[0], "(a)")

axes[1].plot(sizes, write_thr, marker="o", label="Write")
axes[1].plot(sizes, read_thr, marker="s", label="Read")
axes[1].set_xscale("log")
axes[1].set_xticks(sizes)
axes[1].set_xticklabels(size_labels, rotation=45, ha="right")
axes[1].set_ylabel("Throughput (MB/s)")
style_ax(axes[1])
axes[1].legend(frameon=True)
panel_label(axes[1], "(b)")

fig.tight_layout()
save(fig, "fig07_phase10_ipfs_filesize_ieee")

manifest = {
    "root": str(ROOT),
    "output": str(OUT),
    "figures": sorted([str(p) for p in OUT.glob("*.pdf")] + [str(p) for p in OUT.glob("*.png")])
}

(OUT / "manifest_ieee_figures.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
print(json.dumps(manifest, indent=2))
