#!/usr/bin/env python3
"""Aggregate per-language CSV bench logs into a side-by-side markdown report.

Languages: mojo (decimo.BigInt, system under test), python (int, oracle),
rust (num-bigint, compiled peer).

BigInt is exact, so there is NO precision dimension. Log filenames look
like `<lang>_<op>_<ts>.csv`; the report shows one timings table per op.

The `match py` column is **OK** iff `decimo` and Python agree on the result
value. Integers have a single canonical decimal form, so this is exact
string equality (with a numeric fallback). DIFF cases are expanded inside
collapsible `<details>` blocks listing every language's full result.
"""

from __future__ import annotations

import argparse
import csv
import glob

# Result strings can run into tens of thousands of characters (e.g.
# 50000-digit from_string cases). Raise the CSV field limit accordingly.
csv.field_size_limit(10_000_000)
import os
import platform
import re
import shutil
import statistics
import subprocess
import sys
from datetime import datetime, timezone

LANGS_DEFAULT = ["mojo", "python", "rust"]
LANG_LABEL = {"mojo": "decimo", "python": "python", "rust": "rust"}

# Maximum width for case names rendered in markdown tables. Long names are
# truncated with an ellipsis to keep tables readable; the full name is still
# shown verbatim inside `DIFF` blocks.
DISPLAY_NAME_MAX = 48


def _short_name(name: str) -> str:
    if len(name) <= DISPLAY_NAME_MAX:
        return name
    return name[: DISPLAY_NAME_MAX - 1] + "…"  # ellipsis


def _values_equal(a: str, b: str) -> bool:
    """Compare two integer result strings as values.

    Falls back to string equality if either side cannot be parsed as an
    integer (e.g. an ``ERR: ...`` marker).
    """
    if a == b:
        return True
    try:
        return int(a) == int(b)
    except (TypeError, ValueError):
        return False


LOG_RE = re.compile(r"^(?P<lang>[a-z]+)_(?P<op>[a-z_]+)_(?P<ts>\d{8}_\d{6})\.csv$")


def discover_logs(logs_dir: str) -> dict[tuple[str, str], str]:
    latest: dict[tuple[str, str], tuple[str, str]] = {}
    for path in glob.glob(os.path.join(logs_dir, "*.csv")):
        m = LOG_RE.match(os.path.basename(path))
        if not m:
            continue
        key = (m.group("lang"), m.group("op"))
        ts = m.group("ts")
        if key not in latest or ts > latest[key][1]:
            latest[key] = (path, ts)
    return {k: v[0] for k, v in latest.items()}


def load(path: str) -> list[dict[str, str]]:
    with open(path, newline="") as f:
        return list(csv.DictReader(f))


def fmt_num(s) -> str:
    if s is None or s == "":
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
        return f"{n / d:,.2f}x"
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
    try:
        out = subprocess.run(
            cmd, capture_output=True, text=True, timeout=5, check=False
        ).stdout.strip()
        return out.splitlines()[0].strip() if out else ""
    except (FileNotFoundError, subprocess.TimeoutExpired, OSError):
        return ""


def collect_env_info() -> list[tuple[str, str]]:
    info: list[tuple[str, str]] = [
        ("OS", f"{platform.system()} {platform.release()}"),
        ("Arch", platform.machine()),
    ]
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
    if shutil.which("pixi"):
        v = _run(["pixi", "run", "mojo", "--version"])
        if v:
            info.append(("Mojo", v))
    info.append(("Python", platform.python_version()))
    rustc = _run(["rustc", "--version"])
    if rustc:
        info.append(("Rust", rustc))
    return info


def _is_numeric_col(values: list[str]) -> bool:
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


# Threshold above which a DIFF result is considered "long" and worth
# folding the shared head / tail. 200 chars is roughly two lines on a
# typical viewer, so anything past that benefits from folding.
_FOLD_LONG_THRESHOLD = 200
_FOLD_MIN_RUN = 40
_FOLD_KEEP_EDGE = 8


def _fold_diff_results(results: list[str | None]) -> list[str | None]:
    """Fold long DIFF result strings around the diverging region.

    Given N result strings (some may be ``None`` for missing rows), find
    the longest common prefix and longest common suffix shared by ALL
    non-None results. If both are long enough, replace those runs with
    ``(K same chars)`` markers, keeping a few boundary chars verbatim.
    """
    real = [r for r in results if r is not None]
    if not real:
        return results
    if max(len(r) for r in real) < _FOLD_LONG_THRESHOLD:
        return results
    prefix_len = 0
    min_len = min(len(r) for r in real)
    while prefix_len < min_len and all(
        r[prefix_len] == real[0][prefix_len] for r in real
    ):
        prefix_len += 1
    suffix_len = 0
    while suffix_len < min_len - prefix_len and all(
        r[-1 - suffix_len] == real[0][-1 - suffix_len] for r in real
    ):
        suffix_len += 1

    fold_prefix = prefix_len >= _FOLD_MIN_RUN
    fold_suffix = suffix_len >= _FOLD_MIN_RUN
    if not fold_prefix and not fold_suffix:
        return results

    out: list[str | None] = []
    for r in results:
        if r is None:
            out.append(None)
            continue
        head_keep = _FOLD_KEEP_EDGE if fold_prefix else 0
        tail_keep = _FOLD_KEEP_EDGE if fold_suffix else 0
        head_keep = min(head_keep, prefix_len)
        tail_keep = min(tail_keep, suffix_len)
        head_fold = prefix_len - head_keep
        tail_fold = suffix_len - tail_keep
        middle_start = prefix_len
        middle_end = len(r) - suffix_len
        parts: list[str] = []
        if fold_prefix:
            parts.append(f"({head_fold} same chars)...")
            parts.append(r[prefix_len - head_keep : prefix_len])
        else:
            parts.append(r[:prefix_len])
        parts.append(r[middle_start:middle_end])
        if fold_suffix:
            parts.append(r[len(r) - suffix_len : len(r) - suffix_len + tail_keep])
            parts.append(f"...({tail_fold} same chars)")
        else:
            parts.append(r[len(r) - suffix_len :])
        out.append("".join(parts))
    return out


def render_aligned_table(header: list[str], rows: list[list[str]]) -> list[str]:
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
    sep = []
    for i in range(cols):
        sep.append(
            "-" * (widths[i] - 1) + ":" if aligns[i] == "right" else "-" * widths[i]
        )
    out.append("| " + " | ".join(sep) + " |")
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
    ap.add_argument("--reports-dir", default="reports")
    ap.add_argument("--ops", nargs="+", required=True)
    ap.add_argument("--langs", nargs="+", default=LANGS_DEFAULT)
    ap.add_argument("--out", default=None)
    args = ap.parse_args()

    os.makedirs(args.reports_dir, exist_ok=True)
    ts = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    now_local = datetime.now().astimezone()
    offset = now_local.strftime("%z")
    offset_str = f"UTC{offset[:3]}:{offset[3:]}" if len(offset) == 5 else "UTC"
    header_ts = f"{now_local.strftime('%Y-%m-%d %H:%M:%S')} ({offset_str})"
    out_path = args.out or os.path.join(args.reports_dir, f"bigint_report_utc_{ts}.md")

    log_index = discover_logs(args.logs_dir)
    # records[op][lang][case_name] -> row dict
    records: dict[str, dict[str, dict[str, dict[str, str]]]] = {}
    case_orders: dict[str, list[str]] = {}
    for op in args.ops:
        records[op] = {}
        case_orders[op] = []
        for lang in args.langs:
            path = log_index.get((lang, op))
            if not path:
                continue
            d: dict[str, dict[str, str]] = {}
            for r in load(path):
                if r["case_name"] not in case_orders[op]:
                    case_orders[op].append(r["case_name"])
                d[r["case_name"]] = r
            records[op][lang] = d

    ratio_pairs = [l for l in args.langs if l != "mojo"]
    ratio_short = {"python": "py", "rust": "rs"}

    lines: list[str] = [
        "# BigInt cross-language benchmark report",
        "",
        f"- Generated: {header_ts}",
        f"- Languages: {', '.join(LANG_LABEL.get(l, l) for l in args.langs)}",
        f"- Ops: {', '.join(args.ops)}",
        "- **Time unit: nanoseconds per iteration (ns/iter)** — lower is faster.",
        "",
        "All timing columns (`decimo`, `python`, `rust`) are **ns / iter**.",
        "Each per-op timings table has a single correctness column,",
        "`match py` (vs Python `int`), comparing integer values. A case is",
        "listed in the `DIFF` block if `decimo` disagrees with the Python",
        "oracle.",
        "",
        f"Ratio columns: `dm/{ratio_short.get('python')}` = decimo ÷ python, "
        f"`dm/{ratio_short.get('rust')}` = decimo ÷ rust "
        "(**< 1.00 means decimo is faster**).",
        "",
        "## 0. System & toolchain",
        "",
        "```txt",
    ]
    for k, v in collect_env_info():
        lines.append(f"{(k + ':').ljust(16)}{v}")
    lines.append("```")
    lines.append("")

    # ----- Section 1: cross-op overview -----
    lines.append("## 1. Cross-op overview")
    lines.append("")
    overview_header = ["op", "cases"]
    for lang in args.langs:
        overview_header.append(LANG_LABEL.get(lang, lang))
    for lang in ratio_pairs:
        overview_header.append(f"dm/{ratio_short.get(lang, lang)}")
    overview_rows: list[list[str]] = []
    for op in args.ops:
        row = [op, str(len(case_orders[op]))]
        meds: dict[str, float | None] = {}
        for lang in args.langs:
            rows = list(records[op].get(lang, {}).values())
            m = median_ns(rows)
            meds[lang] = m
            row.append(fmt_num(m))
        for lang in ratio_pairs:
            row.append(fmt_ratio(meds.get("mojo"), meds.get(lang)))
        overview_rows.append(row)
    lines.extend(render_aligned_table(overview_header, overview_rows))
    lines.append("")

    # ----- Section 2: per-op detail -----
    lines.append("## 2. Per-op detail")
    lines.append("")
    for op in args.ops:
        lines.append(f"### {op}")
        lines.append("")
        per_lang = records[op]
        if not per_lang:
            lines.append("_no logs found_\n")
            continue
        present_langs = [lang for lang in args.langs if lang in per_lang]
        present_ratio_pairs = [
            lang for lang in ratio_pairs if lang in per_lang and "mojo" in per_lang
        ]

        case_records: list[tuple[str, bool, dict[str, dict[str, str]]]] = []
        for case in case_orders[op]:
            recs = {
                lang: per_lang.get(lang, {}).get(case, {}) for lang in present_langs
            }
            mojo_val = recs.get("mojo", {}).get("result")
            py_val = recs.get("python", {}).get("result")
            if mojo_val is None or py_val is None:
                py_match = False
            else:
                py_match = _values_equal(mojo_val, py_val)
            case_records.append((case, py_match, recs))

        time_header = ["case", "match py"] + [
            LANG_LABEL.get(l, l) for l in present_langs
        ]
        for lang in present_ratio_pairs:
            time_header.append(f"dm/{ratio_short.get(lang, lang)}")
        time_body: list[list[str]] = []
        for case, py_match, recs in case_records:
            py_cell = "OK" if py_match else "DIFF"
            row = [_short_name(case), py_cell]
            for lang in present_langs:
                row.append(
                    fmt_num(recs[lang].get("ns_per_iter") if recs[lang] else None)
                )
            for lang in present_ratio_pairs:
                m = recs.get("mojo", {}).get("ns_per_iter")
                r = recs.get(lang, {}).get("ns_per_iter")
                row.append(fmt_ratio(m, r))
            time_body.append(row)
        lines.extend(render_aligned_table(time_header, time_body))
        lines.append("")

        # A case is shown in the DIFF block iff decimo disagrees with the
        # Python oracle.
        diffs = [t for t in case_records if not t[1]]
        if diffs:
            lines.append(
                f"<details><summary>{len(diffs)} DIFF case(s) at "
                f"<code>{op}</code> — click to expand</summary>"
            )
            lines.append("")
            for case, _py_match, recs in diffs:
                lines.append(f"**{case}**")
                lines.append("")
                pairs: list[tuple[str, str | None]] = []
                for lang in args.langs:
                    rec = recs.get(lang, {}) if lang in present_langs else {}
                    r = rec.get("result") if rec else None
                    pairs.append((LANG_LABEL.get(lang, lang), r))
                folded = _fold_diff_results([p[1] for p in pairs])
                lines.append("```")
                for (label, _), shown in zip(pairs, folded):
                    if shown is None:
                        lines.append(f"{label}: (no row)")
                    else:
                        lines.append(f"{label}: {shown}")
                lines.append("```")
                lines.append("")
            lines.append("</details>")
            lines.append("")

    # ----- Section 3: agreement summary -----
    lines.append("## 3. decimo-vs-python agreement summary")
    lines.append("")
    eq_header = ["op", "total", "matched", "mismatched", "match %"]
    eq_rows: list[list[str]] = []
    for op in args.ops:
        total = len(case_orders[op])
        matched = 0
        for case in case_orders[op]:
            per_lang = records[op]
            mojo_val = per_lang.get("mojo", {}).get(case, {}).get("result")
            py_val = per_lang.get("python", {}).get(case, {}).get("result")
            if (
                mojo_val is not None
                and py_val is not None
                and _values_equal(mojo_val, py_val)
            ):
                matched += 1
        pct = f"{(100.0 * matched / total):.1f}%" if total else "-"
        eq_rows.append([op, str(total), str(matched), str(total - matched), pct])
    lines.extend(render_aligned_table(eq_header, eq_rows))

    report = "\n".join(lines) + "\n"
    sys.stdout.write(report)
    with open(out_path, "w") as f:
        f.write(report)
    print(f"\n>>> Wrote {out_path}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
