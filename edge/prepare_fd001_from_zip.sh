#!/usr/bin/env bash
set -euo pipefail

RAW_DIR="$HOME/secdt-data/raw"
ZIP_FILE="$RAW_DIR/CMAPSSData.zip"
EXTRACT_DIR="$RAW_DIR/CMAPSSData"
PREP_DIR="$HOME/secdt-data/prepared_fd001"

[ -f "$ZIP_FILE" ] || { echo "ERROR: $ZIP_FILE introuvable"; exit 1; }

mkdir -p "$EXTRACT_DIR"
mkdir -p "$PREP_DIR"

python3 - <<PY
from pathlib import Path
import zipfile
import json
import csv

raw_dir = Path("$RAW_DIR")
zip_file = Path("$ZIP_FILE")
extract_dir = Path("$EXTRACT_DIR")
prep_dir = Path("$PREP_DIR")

with zipfile.ZipFile(zip_file, "r") as z:
    z.extractall(extract_dir)

train_file = next(extract_dir.rglob("train_FD001.txt"), None)
test_file = next(extract_dir.rglob("test_FD001.txt"), None)
rul_file = next(extract_dir.rglob("RUL_FD001.txt"), None)

if not train_file or not test_file or not rul_file:
    raise SystemExit("ERROR: fichiers FD001 introuvables apres extraction")

cols = [
    "unit_id","cycle",
    "op_setting_1","op_setting_2","op_setting_3",
    "sensor_1","sensor_2","sensor_3","sensor_4","sensor_5",
    "sensor_6","sensor_7","sensor_8","sensor_9","sensor_10",
    "sensor_11","sensor_12","sensor_13","sensor_14","sensor_15",
    "sensor_16","sensor_17","sensor_18","sensor_19","sensor_20",
    "sensor_21"
]

def convert_txt_to_csv(src, dst, expected_cols=26):
    rows = 0
    units = set()
    with open(src, "r", encoding="utf-8") as fin, open(dst, "w", newline="", encoding="utf-8") as fout:
        writer = csv.writer(fout)
        writer.writerow(cols)
        for line in fin:
            parts = line.strip().split()
            if not parts:
                continue
            parts = parts[:expected_cols]
            if len(parts) != expected_cols:
                continue
            writer.writerow(parts)
            rows += 1
            units.add(int(float(parts[0])))
    return rows, len(units)

def convert_rul_to_csv(src, dst):
    rows = 0
    with open(src, "r", encoding="utf-8") as fin, open(dst, "w", newline="", encoding="utf-8") as fout:
        writer = csv.writer(fout)
        writer.writerow(["rul"])
        for line in fin:
            parts = line.strip().split()
            if not parts:
                continue
            writer.writerow([parts[0]])
            rows += 1
    return rows

train_csv = prep_dir / "train_fd001.csv"
test_csv = prep_dir / "test_fd001.csv"
rul_csv = prep_dir / "rul_fd001.csv"

train_rows, train_units = convert_txt_to_csv(train_file, train_csv)
test_rows, test_units = convert_txt_to_csv(test_file, test_csv)
rul_rows = convert_rul_to_csv(rul_file, rul_csv)

manifest = {
    "dataset": "NASA CMAPSS FD001",
    "zip_file": str(zip_file),
    "extract_dir": str(extract_dir),
    "prepared_dir": str(prep_dir),
    "train_source": str(train_file),
    "test_source": str(test_file),
    "rul_source": str(rul_file),
    "train_rows": train_rows,
    "test_rows": test_rows,
    "rul_rows": rul_rows,
    "train_units": train_units,
    "test_units": test_units,
    "status": "downloaded_extracted_prepared"
}

(prep_dir / "manifest_fd001.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
print(json.dumps(manifest, indent=2))
PY

echo
echo "FILES_PREPARED_IN=$PREP_DIR"
ls -lah "$PREP_DIR"
