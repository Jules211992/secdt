from pathlib import Path
from datetime import datetime, timezone
from time import perf_counter
import hashlib
import json
import math
import csv
import urllib.request
import urllib.error
import argparse

def percentile(values, p):
    if not values:
        return None
    values = sorted(values)
    if len(values) == 1:
        return round(values[0], 4)
    k = (len(values) - 1) * (p / 100.0)
    lo = math.floor(k)
    hi = math.ceil(k)
    if lo == hi:
        return round(values[int(k)], 4)
    v = values[lo] + (values[hi] - values[lo]) * (k - lo)
    return round(v, 4)

def stats(values):
    if not values:
        return {
            "mean": None,
            "median": None,
            "p95": None,
            "p99": None
        }
    values = list(values)
    mean = sum(values) / len(values)
    med = percentile(values, 50)
    return {
        "mean": round(mean, 4),
        "median": med,
        "p95": percentile(values, 95),
        "p99": percentile(values, 99)
    }

def size_label(size_bytes):
    units = [
        (1024 * 1024, "MB"),
        (1024, "KB"),
        (1, "B")
    ]
    for base, label in units:
        if size_bytes >= base:
            value = size_bytes / base
            if float(value).is_integer():
                return f"{int(value)}{label}"
            return f"{value:.2f}{label}"
    return f"{size_bytes}B"

def deterministic_payload(size_bytes, token):
    seed = hashlib.sha256(token.encode("utf-8")).digest()
    buf = bytearray()
    counter = 0
    while len(buf) < size_bytes:
        block = hashlib.sha256(seed + counter.to_bytes(8, "big")).digest()
        buf.extend(block)
        counter += 1
    return bytes(buf[:size_bytes])

def ipfs_add(api_base, filename, content_bytes):
    boundary = "----SecDTBoundary7MA4YWxkTrZu0gW"
    pre = (
        f"--{boundary}\r\n"
        f'Content-Disposition: form-data; name="file"; filename="{filename}"\r\n'
        f"Content-Type: application/octet-stream\r\n\r\n"
    ).encode("utf-8")
    post = f"\r\n--{boundary}--\r\n".encode("utf-8")
    body = pre + content_bytes + post
    req = urllib.request.Request(
        url=f"{api_base}/add",
        data=body,
        method="POST",
        headers={"Content-Type": f"multipart/form-data; boundary={boundary}"}
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        raw = resp.read().decode("utf-8", errors="replace").strip()
    lines = [line for line in raw.splitlines() if line.strip()]
    obj = json.loads(lines[-1])
    return obj

def ipfs_cat(api_base, cid):
    req = urllib.request.Request(
        url=f"{api_base}/cat?arg={cid}",
        data=b"",
        method="POST"
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        return resp.read()

def run_case(api_base, out_dir, file_size, repetitions):
    raw_dir = out_dir / "raw"
    raw_dir.mkdir(parents=True, exist_ok=True)

    records = []

    for rep in range(1, repetitions + 1):
        token = f"{file_size}-{rep}"
        payload = deterministic_payload(file_size, token)
        local_hash = hashlib.sha256(payload).hexdigest()
        filename = f"payload_{file_size}_{rep}.bin"

        add_ok = False
        cat_ok = False
        cid = None
        cat_hash = None
        add_latency_ms = None
        cat_latency_ms = None
        write_throughput_mbps = None
        read_throughput_mbps = None
        hash_consistent = False
        error_text = None

        try:
            t0 = perf_counter()
            add_obj = ipfs_add(api_base, filename, payload)
            t1 = perf_counter()

            cid = add_obj.get("Hash")
            add_latency_ms = round((t1 - t0) * 1000.0, 4)
            if add_latency_ms > 0:
                write_throughput_mbps = round((file_size / (1024 * 1024)) / (add_latency_ms / 1000.0), 4)
            add_ok = cid is not None

            t2 = perf_counter()
            cat_bytes = ipfs_cat(api_base, cid)
            t3 = perf_counter()

            cat_latency_ms = round((t3 - t2) * 1000.0, 4)
            if cat_latency_ms > 0:
                read_throughput_mbps = round((file_size / (1024 * 1024)) / (cat_latency_ms / 1000.0), 4)

            cat_hash = hashlib.sha256(cat_bytes).hexdigest()
            hash_consistent = (cat_hash == local_hash)
            cat_ok = True

            add_file = raw_dir / f"{size_label(file_size)}_rep{rep}_add.json"
            add_file.write_text(json.dumps(add_obj, indent=2), encoding="utf-8")

        except Exception as e:
            error_text = str(e)

        record = {
            "file_size_bytes": file_size,
            "file_size_label": size_label(file_size),
            "rep": rep,
            "cid": cid,
            "add_ok": add_ok,
            "cat_ok": cat_ok,
            "hash_consistent": hash_consistent,
            "add_latency_ms": add_latency_ms,
            "cat_latency_ms": cat_latency_ms,
            "write_throughput_mbps": write_throughput_mbps,
            "read_throughput_mbps": read_throughput_mbps,
            "local_hash": local_hash,
            "retrieved_hash": cat_hash,
            "error": error_text
        }
        records.append(record)

    add_vals = [r["add_latency_ms"] for r in records if r["add_latency_ms"] is not None]
    cat_vals = [r["cat_latency_ms"] for r in records if r["cat_latency_ms"] is not None]
    write_vals = [r["write_throughput_mbps"] for r in records if r["write_throughput_mbps"] is not None]
    read_vals = [r["read_throughput_mbps"] for r in records if r["read_throughput_mbps"] is not None]

    retrieval_success_rate = round(sum(1 for r in records if r["cat_ok"]) / len(records), 4)
    add_success_rate = round(sum(1 for r in records if r["add_ok"]) / len(records), 4)
    hash_consistency_rate = round(sum(1 for r in records if r["hash_consistent"]) / len(records), 4)

    return {
        "file_size_bytes": file_size,
        "file_size_label": size_label(file_size),
        "n_runs": len(records),
        "add_success_rate": add_success_rate,
        "retrieval_success_rate": retrieval_success_rate,
        "hash_consistency_rate": hash_consistency_rate,
        "add_latency_ms": stats(add_vals),
        "cat_latency_ms": stats(cat_vals),
        "write_throughput_mbps": stats(write_vals),
        "read_throughput_mbps": stats(read_vals),
        "records": records
    }

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--ipfs-api", default="http://ipfs-node-1:5001/api/v0")
    parser.add_argument("--repetitions", type=int, default=5)
    parser.add_argument(
        "--sizes",
        default="1024,10240,102400,262144,524288,1048576,2097152,5242880,10485760"
    )
    parser.add_argument("--output-root", default=str(Path.home() / "secdt-phase10"))
    args = parser.parse_args()

    sizes = [int(x.strip()) for x in args.sizes.split(",") if x.strip()]
    ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    runset_id = f"phase10_ipfs_filesize_{ts}"
    run_dir = Path(args.output_root) / runset_id
    run_dir.mkdir(parents=True, exist_ok=True)

    all_cases = []
    all_raw = []

    for sz in sizes:
        case_dir = run_dir / f"size_{size_label(sz)}"
        case_dir.mkdir(parents=True, exist_ok=True)
        result = run_case(args.ipfs_api, case_dir, sz, args.repetitions)
        case_summary = dict(result)
        case_summary.pop("records", None)
        (case_dir / "case_summary.json").write_text(json.dumps(case_summary, indent=2), encoding="utf-8")
        all_cases.append(case_summary)
        all_raw.extend(result["records"])

    raw_jsonl = run_dir / "phase10_ipfs_filesize_raw.jsonl"
    with raw_jsonl.open("w", encoding="utf-8") as f:
        for row in all_raw:
            f.write(json.dumps(row, separators=(",", ":")) + "\n")

    summary = {
        "phase": "phase10_ipfs_filesize",
        "runset_id": runset_id,
        "ipfs_api": args.ipfs_api,
        "repetitions_per_size": args.repetitions,
        "sizes_bytes": sizes,
        "cases": all_cases
    }

    summary_json = run_dir / "phase10_ipfs_filesize_summary.json"
    summary_json.write_text(json.dumps(summary, indent=2), encoding="utf-8")

    csv_file = run_dir / "phase10_ipfs_filesize_summary.csv"
    with csv_file.open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow([
            "file_size_label",
            "file_size_bytes",
            "n_runs",
            "add_success_rate",
            "retrieval_success_rate",
            "hash_consistency_rate",
            "add_mean_ms",
            "add_median_ms",
            "add_p95_ms",
            "add_p99_ms",
            "cat_mean_ms",
            "cat_median_ms",
            "cat_p95_ms",
            "cat_p99_ms",
            "write_mean_mbps",
            "write_p95_mbps",
            "read_mean_mbps",
            "read_p95_mbps"
        ])
        for c in all_cases:
            writer.writerow([
                c["file_size_label"],
                c["file_size_bytes"],
                c["n_runs"],
                c["add_success_rate"],
                c["retrieval_success_rate"],
                c["hash_consistency_rate"],
                c["add_latency_ms"]["mean"],
                c["add_latency_ms"]["median"],
                c["add_latency_ms"]["p95"],
                c["add_latency_ms"]["p99"],
                c["cat_latency_ms"]["mean"],
                c["cat_latency_ms"]["median"],
                c["cat_latency_ms"]["p95"],
                c["cat_latency_ms"]["p99"],
                c["write_throughput_mbps"]["mean"],
                c["write_throughput_mbps"]["p95"],
                c["read_throughput_mbps"]["mean"],
                c["read_throughput_mbps"]["p95"]
            ])

    print(json.dumps({
        "runset_dir": str(run_dir),
        "summary_json": str(summary_json),
        "summary_csv": str(csv_file),
        "raw_jsonl": str(raw_jsonl)
    }, indent=2))

if __name__ == "__main__":
    main()
