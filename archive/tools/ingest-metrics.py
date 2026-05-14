#!/usr/bin/env python3
"""Normalize infra metrics exports into LaTeX-ready tables."""

from __future__ import annotations

import argparse
import csv
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, Iterable, List, Tuple


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Prepare normalized metrics files for LaTeX charts."
    )
    parser.add_argument(
        "--metrics-dir",
        required=True,
        help="Path to metrics export directory (contains index.json and query files).",
    )
    parser.add_argument(
        "--output-dir",
        default=None,
        help="Output directory (default: archive/generated/metrics).",
    )
    return parser.parse_args()


def escape_tex(value: str) -> str:
    replacements = {
        "\\": r"\textbackslash{}",
        "&": r"\&",
        "%": r"\%",
        "$": r"\$",
        "#": r"\#",
        "_": r"\_",
        "{": r"\{",
        "}": r"\}",
        "~": r"\textasciitilde{}",
        "^": r"\textasciicircum{}",
    }
    return "".join(replacements.get(ch, ch) for ch in value)


def read_index(metrics_dir: Path) -> dict:
    index_path = metrics_dir / "index.json"
    if not index_path.exists():
        raise FileNotFoundError(f"index.json not found in {metrics_dir}")
    with index_path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def build_export_map(index: dict) -> Dict[str, dict]:
    exports = index.get("exports", [])
    result: Dict[str, dict] = {}
    for entry in exports:
        name = entry.get("name")
        if isinstance(name, str) and name:
            result[name] = entry
    return result


def epoch_to_iso(ts: float) -> str:
    return datetime.fromtimestamp(ts, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def parse_float(value: object) -> float | None:
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def load_series_from_csv(path: Path) -> List[Tuple[float, float]]:
    if not path.exists():
        return []
    points: List[Tuple[float, float]] = []
    with path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            ts = parse_float(row.get("timestamp"))
            value = parse_float(row.get("value"))
            if ts is None or value is None:
                continue
            points.append((ts, value))
    return points


def load_series_from_raw(path: Path) -> List[Tuple[float, float]]:
    if not path.exists():
        return []
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return []
    points: List[Tuple[float, float]] = []
    results = payload.get("data", {}).get("result", [])
    if not isinstance(results, list):
        return []
    for result in results:
        values = result.get("values", [])
        if not isinstance(values, list):
            continue
        for point in values:
            if not isinstance(point, list) or len(point) < 2:
                continue
            ts = parse_float(point[0])
            value = parse_float(point[1])
            if ts is None or value is None:
                continue
            points.append((ts, value))
    return points


def load_query_points(metrics_dir: Path, export_entry: dict | None) -> List[Tuple[float, float]]:
    if not export_entry:
        return []
    csv_path = export_entry.get("csv")
    raw_path = export_entry.get("raw")
    points: List[Tuple[float, float]] = []
    if isinstance(csv_path, str):
        points = load_series_from_csv(metrics_dir / Path(csv_path).name)
        if not points:
            points = load_series_from_csv(Path(csv_path))
    if points:
        return points
    if isinstance(raw_path, str):
        points = load_series_from_raw(metrics_dir / Path(raw_path).name)
        if not points:
            points = load_series_from_raw(Path(raw_path))
    return points


def aggregate_sum(points: Iterable[Tuple[float, float]]) -> Dict[float, float]:
    agg: Dict[float, float] = {}
    for ts, value in points:
        agg[ts] = agg.get(ts, 0.0) + value
    return agg


def write_tsv(path: Path, headers: List[str], rows: List[List[object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle, delimiter="\t")
        writer.writerow(headers)
        writer.writerows(rows)


def rows_from_single_series(series: Dict[float, float]) -> List[List[object]]:
    rows: List[List[object]] = []
    for ts in sorted(series.keys()):
        rows.append([epoch_to_iso(ts), f"{ts:.3f}", f"{series[ts]:.6f}"])
    return rows


def rows_from_dual_series(left: Dict[float, float], right: Dict[float, float]) -> List[List[object]]:
    rows: List[List[object]] = []
    for ts in sorted(set(left.keys()) | set(right.keys())):
        rows.append(
            [
                epoch_to_iso(ts),
                f"{ts:.3f}",
                f"{left.get(ts, 0.0):.6f}",
                f"{right.get(ts, 0.0):.6f}",
            ]
        )
    return rows


def write_scenario_tex(index: dict, output_dir: Path) -> None:
    scenario = str(index.get("scenario", "unknown"))
    timestamp = str(index.get("timestamp", "unknown"))
    params = index.get("parameters", {}) if isinstance(index.get("parameters"), dict) else {}
    start = str(params.get("start", "unknown"))
    end = str(params.get("end", "unknown"))
    step = str(params.get("step", "unknown"))
    missing = index.get("missing_queries", [])
    missing_count = len(missing) if isinstance(missing, list) else 0
    exports = index.get("exports", [])
    exports_count = len(exports) if isinstance(exports, list) else 0

    lines = [
        "% Generated by archive/tools/ingest-metrics.py",
        rf"\newcommand{{\MetricsScenario}}{{{escape_tex(scenario)}}}",
        rf"\newcommand{{\MetricsTimestamp}}{{{escape_tex(timestamp)}}}",
        rf"\newcommand{{\MetricsWindowStart}}{{{escape_tex(start)}}}",
        rf"\newcommand{{\MetricsWindowEnd}}{{{escape_tex(end)}}}",
        rf"\newcommand{{\MetricsStep}}{{{escape_tex(step)}}}",
        rf"\newcommand{{\MetricsExportsCount}}{{{exports_count}}}",
        rf"\newcommand{{\MetricsMissingCount}}{{{missing_count}}}",
        "",
    ]
    (output_dir / "scenario.tex").write_text("\n".join(lines), encoding="utf-8")


def main() -> int:
    args = parse_args()
    repo_root = Path(__file__).resolve().parents[2]
    metrics_dir = Path(args.metrics_dir).expanduser().resolve()
    output_dir = (
        Path(args.output_dir).expanduser().resolve()
        if args.output_dir
        else (repo_root / "archive" / "generated" / "metrics")
    )

    output_dir.mkdir(parents=True, exist_ok=True)

    index = read_index(metrics_dir)
    export_map = build_export_map(index)

    request_rate = aggregate_sum(load_query_points(metrics_dir, export_map.get("request_rate_total")))
    error_rate = aggregate_sum(load_query_points(metrics_dir, export_map.get("error_rate_5xx")))
    latency_p95 = aggregate_sum(load_query_points(metrics_dir, export_map.get("latency_p95_seconds")))
    latency_p99 = aggregate_sum(load_query_points(metrics_dir, export_map.get("latency_p99_seconds")))
    prod_count = aggregate_sum(load_query_points(metrics_dir, export_map.get("prod_request_count")))
    shadow_count = aggregate_sum(load_query_points(metrics_dir, export_map.get("shadow_request_count")))
    pod_cpu = aggregate_sum(load_query_points(metrics_dir, export_map.get("pod_cpu_usage_rate")))
    pod_mem = aggregate_sum(load_query_points(metrics_dir, export_map.get("pod_memory_working_set_bytes")))

    write_scenario_tex(index, output_dir)

    if request_rate:
        write_tsv(
            output_dir / "request_rate.tsv",
            ["ts_iso", "timestamp_epoch", "value_rps"],
            rows_from_single_series(request_rate),
        )
    if error_rate:
        error_rate_pct = {ts: value * 100.0 for ts, value in error_rate.items()}
        write_tsv(
            output_dir / "error_rate.tsv",
            ["ts_iso", "timestamp_epoch", "value_percent"],
            rows_from_single_series(error_rate_pct),
        )
    if latency_p95 or latency_p99:
        write_tsv(
            output_dir / "latency_p95_p99.tsv",
            ["ts_iso", "timestamp_epoch", "p95_seconds", "p99_seconds"],
            rows_from_dual_series(latency_p95, latency_p99),
        )
    if prod_count or shadow_count:
        write_tsv(
            output_dir / "prod_shadow_counts.tsv",
            ["ts_iso", "timestamp_epoch", "prod_requests", "shadow_requests"],
            rows_from_dual_series(prod_count, shadow_count),
        )
    if pod_cpu:
        write_tsv(
            output_dir / "pod_cpu_usage.tsv",
            ["ts_iso", "timestamp_epoch", "cpu_cores"],
            rows_from_single_series(pod_cpu),
        )
    if pod_mem:
        pod_mem_mib = {ts: value / (1024.0 * 1024.0) for ts, value in pod_mem.items()}
        write_tsv(
            output_dir / "pod_memory_usage.tsv",
            ["ts_iso", "timestamp_epoch", "memory_mib"],
            rows_from_single_series(pod_mem_mib),
        )

    print(f"Prepared metrics for LaTeX in: {output_dir}")
    print("Generated: scenario.tex and available normalized TSV files")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
