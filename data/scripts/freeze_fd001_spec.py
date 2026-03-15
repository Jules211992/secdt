import json
from pathlib import Path
import pandas as pd

prep = Path.home() / "secdt-data" / "prepared_fd001"
spec_dir = Path.home() / "secdt-data" / "spec"
spec_dir.mkdir(parents=True, exist_ok=True)

df = pd.read_csv(prep / "train_fd001.csv")

sensor_cols = [c for c in df.columns if c.startswith("sensor_")]
std_series = df[sensor_cols].std().sort_values()

constant_like = std_series[std_series < 1e-6].index.tolist()
variable_sensors = std_series[std_series >= 1e-6].index.tolist()

unit_max_cycle = df.groupby("unit_id")["cycle"].max().to_dict()

selected_sensors = [
    "sensor_2",
    "sensor_3",
    "sensor_4",
    "sensor_7",
    "sensor_11",
    "sensor_12",
    "sensor_15",
    "sensor_20",
    "sensor_21"
]

missing_selected = [c for c in selected_sensors if c not in df.columns]
if missing_selected:
    raise SystemExit(f"Sensors introuvables: {missing_selected}")

spec = {
    "dataset": "NASA CMAPSS FD001",
    "source_prepared_file": str(prep / "train_fd001.csv"),
    "n_units_train": int(df["unit_id"].nunique()),
    "n_rows_train": int(len(df)),
    "columns_base": ["unit_id", "cycle", "op_setting_1", "op_setting_2", "op_setting_3"],
    "all_sensor_columns": sensor_cols,
    "constant_like_sensors": constant_like,
    "variable_sensors": variable_sensors,
    "selected_sensors": selected_sensors,
    "health_score_definition": {
        "name": "cycle_normalized_health_score",
        "formula": "100 * (1 - (cycle - 1) / (max_cycle_unit - 1))",
        "bounds": [0.0, 100.0],
        "round_digits": 2
    },
    "snapshot_format": {
        "encoding": "canonical_json",
        "float_round_digits": 4,
        "field_order": [
            "machine_id",
            "timestamp",
            "cycle",
            "session_id",
            "health_score",
            "op_setting_1",
            "op_setting_2",
            "op_setting_3",
            "sensor_2",
            "sensor_3",
            "sensor_4",
            "sensor_7",
            "sensor_11",
            "sensor_12",
            "sensor_15",
            "sensor_20",
            "sensor_21"
        ]
    }
}

(spec_dir / "dataset_fixed_spec.json").write_text(json.dumps(spec, indent=2), encoding="utf-8")

print("=== STD ASC ===")
print(std_series.to_string())
print()
print("=== CONSTANT LIKE SENSORS ===")
print(constant_like)
print()
print("=== VARIABLE SENSORS ===")
print(variable_sensors)
print()
print("=== SELECTED SENSORS ===")
print(selected_sensors)
print()
print("=== SPEC FILE ===")
print(spec_dir / "dataset_fixed_spec.json")
