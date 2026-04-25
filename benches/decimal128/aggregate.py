#!/usr/bin/env python3
"""Aggregate per-language CSV bench logs into a side-by-side markdown report.

Reads logs/{lang}_{op}_{ts}.csv files (latest per (lang, op) wins), joins on
case_name, and emits:

    1. Cross-op overview    (rows = ops, columns = languages, median ns/iter)
    2. Per-op detail tables (rows = test cases, columns = languages)
    3. Result-equivalence summary (per-op match rate)

Output goes to <reports-dir>/dec128_report_{ts}.md by default.

Usage:
    python3 aggregate.py --logs-dir logs --reports-dir reports \\
                         --ops add multiply ...
"""

from __future__ import annotations

import argparse
import csv
import glob
import os
import platform
import shutil
import statistics
import subprocess
import sys
from datetime import datetime


def latest_log(logs_dir: str, lang: str, op: str) -> str | None:
    matches = sorted(glob.glob(os.path.join(logs_dir, f"{lang}_{op}_*.csv")))
    return matches[-1] if matches else None


def load(path: str) -> list[dict[str, str]]:
    with open(path, newline="") as f:
        return list(csv.DictReader(f))


def fmt_num(s: str | float | None) -> str:
    if s is None:
        return "-"
    try:
        return f"{float(s):,.2f}"
    except (TypeError, ValueError):
        return str(s)


def fmt_ratio(num, den) -> str:
    try:
        n, d = float(num), float(den)
        if d == 0:
            return "-"
        return f"{n / d:,.1f}x"
    except (TypeError, ValueError):
        return "-"


def median_ns(rows: list[dict[str, str]]) -> float | None:
    vals: list[float] = []
    for r in rows:
        try:
            vals.append(float(r["ns_per_iter"]))
        except (KeyError, ValueError):
            pass
    return statistics.median(vals) if vals else None


def _run(cmd: list[str]) -> str:
    """Run a command, return first non-empty stdout line, or '' on failure."""
    try:
        out = subprocess.run(
            cmd, capture_output=True, text=True, timeout=5, check=False
        ).stdout.strip()
        return out.splitlines()[0].strip() if out else ""
    except (FileNotFoundError, subprocess.TimeoutExpired, OSError):
        return ""


def collect_env_info() -> list[tuple[str, str]]:
    """Best-effort system + toolchain info for the report header."""
    info: list[tuple[str, str]] = []

    # OS / kernel / arch
    info.append(("OS", f"{platform.system()} {platform.release()}"))
    info.append(("Arch", platform.machine()))

    # CPU
    cpu = ""
    if platform.system() == "Darwin":
        cpu = _run(["sysctl", "-n", "machdep.cpu.brand_string"])
    elif platform.system() == "Linux":
        try:
            with open("/proc/cpuinfo") as f:
                for line in f:
                    if line.startswith("model name"):
                        cpu = line.split(":", 1)[1].strip()
                        break
        except OSError:
            pass
    if cpu:
        info.append(("CPU", cpu))

    # Mojo
    mojo_v = ""
    if shutil.which("pixi"):
        mojo_v = _run(["pixi", "run", "mojo", "--version"])
    if not mojo_v and shutil.which("mojo"):
        mojo_v = _run(["mojo", "--version"])
    if mojo_v:
        info.append(("Mojo", mojo_v))

    # Rust
    if shutil.which("rustc"):
        rust_v = _run(["rustc", "--version"])
        if rust_v:
            info.append(("Rust", rust_v))

    # .NET (used by both csharp and vbnet harnesses)
    dotnet = shutil.which("dotnet") or "/opt/homebrew/opt/dotnet/bin/dotnet"
    if os.path.exists(dotnet):
        dn = _run([dotnet, "--version"])
        if dn:
            info.append((".NET SDK", dn))

    # Python (running aggregate.py itself)
    info.append(("Python", platform.python_version()))

    return info


def _is_numeric_col(values: list[str]) -> bool:
    """Heuristic: column is numeric if every non-empty value parses as float
    (after stripping trailing 'x' and ',' from formatted ratios/medians)."""
    seen = False
    for v in values:
        if v in ("", "-"):
            continue
        seen = True
        s = v.rstrip("x").replace(",", "")
        try:
            float(s)
        except ValueError:
            return False
    return seen


def render_aligned_table(header: list[str], rows: list[list[str]]) -> list[str]:
    """Pad markdown table cells to uniform width per column for readability."""
    cols = len(header)
    widths = [len(h) for h in header]
    for r in rows:
        for i in range(cols):
            if i < len(r) and len(r[i]) > widths[i]:
                widths[i] = len(r[i])

    aligns = [
        "right" if _is_numeric_col([r[i] for r in rows if i < len(r)]) else "left"
        for i in range(cols)
    ]

    def pad(cell: str, w: int, align: str) -> str:
        return cell.rjust(w) if align == "right" else cell.ljust(w)

    out: list[str] = []
    out.append(
        "| "
        + " | ".join(pad(header[i], widths[i], aligns[i]) for i in range(cols))
        + " |"
    )
    sep_cells = []
    for i in range(cols):
        if aligns[i] == "right":
            sep_cells.append("-" * (widths[i] - 1) + ":")
        else:
            sep_cells.append("-" * widths[i])
    out.append("| " + " | ".join(sep_cells) + " |")
    for r in rows:
        cells = []
        for i in range(cols):
            v = r[i] if i < len(r) else ""
            cells.append(pad(v, widths[i], aligns[i]))
        out.append("| " + " | ".join(cells) + " |")
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--logs-dir", default="logs")
    ap.add_argument(
        "--reports-dir",
        default="reports",
        help="Where to write the timestamped markdown report.",
    )
    ap.add_argument("--ops", nargs="+", required=True)
    ap.add_argument("--langs", nargs="+", default=["mojo", "rust", "csharp", "vbnet"])
    ap.add_argument(
        "--out",
        default=None,
        help="Override report path (default: <reports-dir>/dec128_report_<ts>.md)",
    )
    args = ap.parse_args()

    os.makedirs(args.reports_dir, exist_ok=True)
    # Filename uses compact UTC timestamp (matches the per-lang CSV log naming
    # convention used by all four harnesses); header shows a human-readable
    # local time with explicit UTC offset, e.g. "2026-04-21 14:26:06 (UTC+0100)".
    from datetime import timezone

    ts = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    now_local = datetime.now().astimezone()
    offset = now_local.strftime("%z")  # e.g. "+0100" or "-0500"
    # Convert to ISO 8601 extended form: "+0100" -> "UTC+01:00".
    if len(offset) == 5:
        offset_str = f"UTC{offset[:3]}:{offset[3:]}"
    else:
        offset_str = "UTC"
    header_ts = f"{now_local.strftime('%Y-%m-%d %H:%M:%S')} ({offset_str})"
    out_path = args.out or os.path.join(args.reports_dir, f"dec128_report_{ts}.md")

    lang_label = {
        "mojo": "decimo",
        "rust": "rust",
        "csharp": "csharp",
        "vbnet": "vbnet",
        "bigdec": "bigdec(d128)",
    }

    lines: list[str] = [
        "# Decimal128 cross-language benchmark report",
        "",
        f"- Generated: {header_ts}",
        f"- Languages: {', '.join(lang_label.get(lang, lang) for lang in args.langs)}",
        f"- Ops: {', '.join(args.ops)}",
        "",
        "All times are **ns / iter** (lower = faster). The `match` column flags",
        "cases where languages disagreed on the result string.",
        "",
        "## 0. System & toolchain",
        "",
        "```txt",
    ]
    for k, v in collect_env_info():
        lines.append(f"{(k + ':').ljust(16)}{v}")
    lines.append("```")
    lines.append("")

    # Load: per_op[op][lang][case_name] -> row_dict
    per_op: dict[str, dict[str, dict[str, dict[str, str]]]] = {}
    case_orders: dict[str, list[str]] = {}
    for op in args.ops:
        per_op[op] = {}
        case_orders[op] = []
        for lang in args.langs:
            log = latest_log(args.logs_dir, lang, op)
            if not log:
                continue
            d: dict[str, dict[str, str]] = {}
            for r in load(log):
                if r["case_name"] not in case_orders[op]:
                    case_orders[op].append(r["case_name"])
                d[r["case_name"]] = r
            per_op[op][lang] = d

    # ----- Section 1 -----
    lines.append("## 1. Cross-op overview (median ns / iter per case)")
    lines.append("")
    overview_header = ["op", "cases"]
    for lang in args.langs:
        overview_header.append(f"{lang_label.get(lang, lang)} median")
    # `bigdec` is the high-precision oracle for ln/log10/exp; it has no
    # ns/iter timings (correctness-only), so it is excluded from the
    # ratio columns and from any timing-median column when its value is
    # blank.
    ratio_pairs = (
        [lang for lang in args.langs if lang not in ("mojo", "bigdec")]
        if "mojo" in args.langs
        else []
    )
    ratio_short = {"rust": "rs", "csharp": "cs", "vbnet": "vb"}
    for lang in ratio_pairs:
        overview_header.append(f"dm/{ratio_short.get(lang, lang)}")
    overview_rows: list[list[str]] = []
    for op in args.ops:
        row = [op, str(len(case_orders[op]))]
        meds: dict[str, float | None] = {}
        for lang in args.langs:
            rows = list(per_op[op].get(lang, {}).values())
            m = median_ns(rows)
            meds[lang] = m
            row.append(fmt_num(m))
        for lang in ratio_pairs:
            row.append(fmt_ratio(meds.get("mojo"), meds.get(lang)))
        overview_rows.append(row)
    lines.extend(render_aligned_table(overview_header, overview_rows))
    lines.append("")

    # ----- Section 2 -----
    lines.append("## 2. Per-op detail (rows = test cases, columns = languages)")
    lines.append("")
    lines.append(
        "Each op is split into **two tables**: one for results (correctness) "
        "and one for timings (performance + ratio)."
    )
    lines.append("")
    for op in args.ops:
        if not per_op[op]:
            lines.append(f"### {op}\n\n_no logs found_\n")
            continue
        lines.append(f"### {op}")
        lines.append("")
        present_langs = [lang for lang in args.langs if lang in per_op[op]]
        present_ratio_pairs = [
            lang for lang in ratio_pairs if lang in per_op[op] and "mojo" in per_op[op]
        ]

        # Pre-compute per-case match flag and per-language records.
        case_records: list[tuple[str, bool, dict[str, dict[str, str]]]] = []
        for case in case_orders[op]:
            recs = {
                lang: per_op[op].get(lang, {}).get(case, {}) for lang in present_langs
            }
            results = {lang: recs[lang].get("result") for lang in present_langs}
            distinct = {r for r in results.values() if r is not None}
            is_match = len(distinct) <= 1
            case_records.append((case, is_match, recs))

        # ---- Table 2a: results ----
        lines.append(f"#### {op} — results")
        lines.append("")
        res_header = ["case", "match"] + [
            lang_label.get(lang, lang) for lang in present_langs
        ]
        res_body: list[list[str]] = []
        for case, is_match, recs in case_records:
            row = [case, "OK" if is_match else "DIFF"]
            for lang in present_langs:
                res = recs[lang].get("result", "-")
                if is_match:
                    row.append("-")
                else:
                    row.append(res if len(res) <= 56 else res[:53] + "...")
            res_body.append(row)
        lines.extend(render_aligned_table(res_header, res_body))
        lines.append("")

        # ---- Table 2b: timings + ratios ----
        lines.append(f"#### {op} — timings (ns/iter)")
        lines.append("")
        time_header = ["case", "match"] + [
            lang_label.get(lang, lang) for lang in present_langs
        ]
        for lang in present_ratio_pairs:
            time_header.append(f"dm/{ratio_short.get(lang, lang)}")
        time_body: list[list[str]] = []
        for case, is_match, recs in case_records:
            row = [case, "OK" if is_match else "DIFF"]
            for lang in present_langs:
                row.append(fmt_num(recs[lang].get("ns_per_iter")))
            for lang in present_ratio_pairs:
                m = recs.get("mojo", {}).get("ns_per_iter")
                r = recs.get(lang, {}).get("ns_per_iter")
                row.append(fmt_ratio(m, r))
            time_body.append(row)
        lines.extend(render_aligned_table(time_header, time_body))
        lines.append("")

    # ----- Section 3 -----
    lines.append("## 3. Result-equivalence summary (across all languages)")
    lines.append("")
    eq_header = ["op", "total", "matched", "mismatched"]
    eq_rows: list[list[str]] = []
    for op in args.ops:
        total = len(case_orders[op])
        matched = 0
        for case in case_orders[op]:
            results = {
                lang: per_op[op].get(lang, {}).get(case, {}).get("result")
                for lang in args.langs
            }
            if len({r for r in results.values() if r is not None}) <= 1:
                matched += 1
        eq_rows.append([op, str(total), str(matched), str(total - matched)])
    lines.extend(render_aligned_table(eq_header, eq_rows))

    report = "\n".join(lines) + "\n"
    sys.stdout.write(report)
    with open(out_path, "w") as f:
        f.write(report)
    print(f"\n>>> Wrote {out_path}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
