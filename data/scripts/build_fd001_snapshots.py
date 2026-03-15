import json
from pathlib import Path
import pandas as pd

base = Path.home() / "secdt-data"
prep = base / "prepared_fd001" / "train_fd001.csv"
spec_path = base / "spec" / "dataset_fixed_spec.json"
out_dir = base / "prepared"
out_dir.mkdir(parents=True, exist_ok=True)

df = pd.read_csv(prep)
spec = json.loads(spec_path.read_text(encoding="utf-8"))

selected_sensors = spec["selected_sensors"]
field_order = spec["snapshot_format"]["field_order"]
float_digits = spec["snapshot_format"]["float_round_digits"]
health_digits = spec["health_score_definition"]["round_digits"]

max_cycle = df.groupby("unit_id")["cycle"].max().to_dict()

def round_float(x, digits=float_digits):
    return round(float(x), digits)

def compute_health_score(cycle, max_cycle_unit):
    if max_cycle_unit <= 1:
        return 100.0
    score = 100.0 * (1.0 - ((cycle - 1) / (max_cycle_unit - 1)))
    score = max(0.0, min(100.0, score))
    return round(score, health_digits)

records = []
for _, row in df.iterrows():
    unit_id = int(row["unit_id"])
    cycle = int(row["cycle"])
    max_cycle_unit = int(max_cycle[unit_id])

    snapshot = {
        "machine_id": f"machine-{unit_id:04d}",
        "timestamp": f"2026-01-01T00:00:{cycle % 60:02d}Z",
        "cycle": cycle,
        "session_id": f"fd001-unit-{unit_id:04d}",
        "health_score": compute_health_score(cycle, max_cycle_unit),
        "op_setting_1": round_float(row["op_setting_1"]),
        "op_setting_2": round_float(row["op_setting_2"]),
        "op_setting_3": round_float(row["op_setting_3"]),
    }

    for s in selected_sensors:
        snapshot[s] = round_float(row[s])

    ordered_snapshot = {k: snapshot[k] for k in field_order}
    records.append(ordered_snapshot)

jsonl_path = out_dir / "fd001_snapshots.jsonl"
with open(jsonl_path, "w", encoding="utf-8") as f:
    for rec in records:
        f.write(json.dumps(rec, separators=(",", ":"), ensure_ascii=False) + "\n")

manifest = {
    "dataset": "NASA CMAPSS FD001",
    "source_csv": str(prep),
    "spec_file": str(spec_path),
    "output_jsonl": str(jsonl_path),
    "n_snapshots": len(records),
    "n_units": int(df["unit_id"].nunique()),
    "selected_sensors": selected_sensors,
    "status": "snapshots_generated"
}

(base / "prepared" / "fd001_snapshots_manifest.json").write_text(
    json.dumps(manifest, indent=2),
    encoding="utf-8"
)

print(json.dumps(manifest, indent=2))
print()
print("FIRST 3 SNAPSHOTS:")
with open(jsonl_path, "r", encoding="utf-8") as f:
    for i, line in enumerate(f):
        print(line.strip())
        if i == 2:
            break
