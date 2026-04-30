#!/usr/bin/env python3
"""Aggregate per-language CSV bench logs into a side-by-side markdown report.

Languages: mojo (decimo, system under test), python (oracle), rust (bigdecimal
crate, performance reference).

Multi-precision aware: log filenames look like `<lang>_<op>_p<prec>_<ts>.csv`.
The report shows **one timings table per (op, precision)**; cross-op overview
lists each (op, precision) pair as a row; agreement summary is per
(op, precision).

The `match` column is **OK** iff `decimo` and Python agree on the result
string (Python's `decimal.Decimal` is the oracle). DIFF cases are expanded
inside collapsible `<details>` blocks listing every language's full result.
"""

from __future__ import annotations

import argparse
import csv
import decimal
import glob

# Result strings can run into the hundreds of thousands of characters at
# high precision (e.g. p=100000). Raise the CSV field limit accordingly.
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
LANG_LABEL = {"mojo": "decimo", "python": "python", "rust": "rust BD"}

# Maximum width for case names rendered in markdown tables. Long names are
# truncated with an ellipsis to keep tables readable; the full name is still
# shown verbatim inside `DIFF` blocks.
DISPLAY_NAME_MAX = 48


def _short_name(name: str) -> str:
    if len(name) <= DISPLAY_NAME_MAX:
        return name
    return name[: DISPLAY_NAME_MAX - 1] + "\u2026"  # ellipsis


def _values_equal(a: str, b: str) -> bool:
    """Compare two result strings as numeric values when possible.

    Two decimal strings that differ only in trailing-zero precision (e.g.
    ``"1.290"`` vs ``"1.29"``) represent the same numeric value and should
    be reported as matching. Falls back to string equality if either side
    cannot be parsed as a Decimal (e.g. boolean comparison results).
    """
    if a == b:
        return True
    try:
        # Use a context with very high precision so the comparison itself
        # never rounds away meaningful digits.
        ctx = decimal.Context(prec=200000)
        with decimal.localcontext(ctx):
            return decimal.Decimal(a) == decimal.Decimal(b)
    except (decimal.InvalidOperation, ValueError):
        return False


LOG_RE = re.compile(
    r"^(?P<lang>[a-z]+)_(?P<op>[a-z_]+)_p(?P<prec>\d+)_(?P<ts>\d{8}_\d{6})\.csv$"
)


def discover_logs(logs_dir: str) -> dict[tuple[str, str, int], str]:
    latest: dict[tuple[str, str, int], tuple[str, str]] = {}
    for path in glob.glob(os.path.join(logs_dir, "*.csv")):
        m = LOG_RE.match(os.path.basename(path))
        if not m:
            continue
        key = (m.group("lang"), m.group("op"), int(m.group("prec")))
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
    if shutil.which("rustc"):
        v = _run(["rustc", "--version"])
        if v:
            info.append(("Rust", v))
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
    ap.add_argument("--ops", nargs="+")
    ap.add_argument("--precisions", nargs="+", type=int)
    ap.add_argument(
        "--combos",
        nargs="+",
        help="List of op:prec combinations to report. Overrides cross-product of --ops x --precisions.",
    )
    ap.add_argument("--langs", nargs="+", default=LANGS_DEFAULT)
    ap.add_argument("--out", default=None)
    args = ap.parse_args()

    # Build the set of (op, prec) combinations to report.
    op_precs: dict[str, list[int]] = {}
    if args.combos:
        for c in args.combos:
            op, _, prec = c.partition(":")
            op_precs.setdefault(op, []).append(int(prec))
        for op in op_precs:
            seen: set[int] = set()
            op_precs[op] = [p for p in op_precs[op] if not (p in seen or seen.add(p))]
        args.ops = list(op_precs.keys())
        args.precisions = sorted({p for ps in op_precs.values() for p in ps})
    else:
        if not args.ops or not args.precisions:
            ap.error(
                "--ops and --precisions are required when --combos is not provided"
            )
        for op in args.ops:
            op_precs[op] = list(args.precisions)

    os.makedirs(args.reports_dir, exist_ok=True)
    ts = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    now_local = datetime.now().astimezone()
    offset = now_local.strftime("%z")
    offset_str = f"UTC{offset[:3]}:{offset[3:]}" if len(offset) == 5 else "UTC"
    header_ts = f"{now_local.strftime('%Y-%m-%d %H:%M:%S')} ({offset_str})"
    out_path = args.out or os.path.join(args.reports_dir, f"bigdec_report_{ts}.md")

    log_index = discover_logs(args.logs_dir)
    records: dict[str, dict[int, dict[str, dict[str, dict[str, str]]]]] = {}
    case_orders: dict[tuple[str, int], list[str]] = {}
    for op in args.ops:
        records[op] = {}
        for prec in op_precs[op]:
            records[op][prec] = {}
            case_orders[(op, prec)] = []
            for lang in args.langs:
                path = log_index.get((lang, op, prec))
                if not path:
                    continue
                d: dict[str, dict[str, str]] = {}
                for r in load(path):
                    if r["case_name"] not in case_orders[(op, prec)]:
                        case_orders[(op, prec)].append(r["case_name"])
                    d[r["case_name"]] = r
                records[op][prec][lang] = d

    lines: list[str] = [
        "# BigDecimal cross-language benchmark report",
        "",
        f"- Generated: {header_ts}",
        f"- Languages: {', '.join(LANG_LABEL.get(l, l) for l in args.langs)}",
        f"- Ops: {', '.join(args.ops)}",
        f"- Precisions: {', '.join(str(p) for p in args.precisions)}",
        "- **Time unit: nanoseconds per iteration (ns/iter)** \u2014 lower is faster.",
        "",
        "All timing columns (`decimo`, `python`, `rust BD`) are **ns / iter**.",
        "Each per-op timings table has two correctness columns:",
        "`match py` (vs Python `decimal.Decimal`) and `match rs` (vs the",
        "Rust `bigdecimal` crate). Both compare values numerically at very",
        "high precision \u2014 trailing-zero differences are not flagged. A",
        "case is listed in the `DIFF` block if `decimo` disagrees with",
        "*either* oracle. `match rs` is `-` for ops the Rust crate does",
        "not implement (`exp`, `ln`, `root`, `round`).",
        "",
        "> **Note on `root` op.** Python's nth-root is emulated via",
        "> `da ** (Decimal(1)/n)`, where `1/n` is itself rounded to the",
        "> working precision. This makes Python an *imperfect* oracle for",
        "> `root`: a small number of last-digit differences vs `decimo` are",
        "> expected and not bugs. Negative-base nth roots additionally",
        "> raise `InvalidOperation` in Python's `decimal` module.",
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
    overview_header = ["op", "precision", "cases"]
    for lang in args.langs:
        overview_header.append(LANG_LABEL.get(lang, lang))
    ratio_pairs = [l for l in args.langs if l != "mojo"]
    ratio_short = {"python": "py", "rust": "rs"}
    for lang in ratio_pairs:
        overview_header.append(f"dm/{ratio_short.get(lang, lang)}")
    overview_rows: list[list[str]] = []
    for op in args.ops:
        for prec in op_precs[op]:
            row = [op, str(prec), str(len(case_orders[(op, prec)]))]
            meds: dict[str, float | None] = {}
            for lang in args.langs:
                rows = list(records[op][prec].get(lang, {}).values())
                m = median_ns(rows)
                meds[lang] = m
                row.append(fmt_num(m))
            for lang in ratio_pairs:
                row.append(fmt_ratio(meds.get("mojo"), meds.get(lang)))
            overview_rows.append(row)
    lines.extend(render_aligned_table(overview_header, overview_rows))
    lines.append("")

    # ----- Section 2: per-(op,precision) detail -----
    lines.append("## 2. Per-op detail (one timings table per precision)")
    lines.append("")
    for op in args.ops:
        lines.append(f"### {op}")
        lines.append("")
        for prec in op_precs[op]:
            per_lang = records[op][prec]
            if not per_lang:
                lines.append(f"#### precision = {prec}\n\n_no logs found_\n")
                continue
            lines.append(f"#### precision = {prec}")
            lines.append("")
            present_langs = [lang for lang in args.langs if lang in per_lang]
            present_ratio_pairs = [
                lang for lang in ratio_pairs if lang in per_lang and "mojo" in per_lang
            ]

            case_records: list[tuple[str, bool, bool, dict[str, dict[str, str]]]] = []
            for case in case_orders[(op, prec)]:
                recs = {
                    lang: per_lang.get(lang, {}).get(case, {}) for lang in present_langs
                }
                mojo_val = recs.get("mojo", {}).get("result")
                py_val = recs.get("python", {}).get("result")
                rs_val = recs.get("rust", {}).get("result")
                # Match against Python (oracle).
                if mojo_val is None or py_val is None:
                    py_match = False
                else:
                    py_match = _values_equal(mojo_val, py_val)
                # Match against Rust. If Rust didn't run this op (skip / no
                # row), treat as N/A — render as "-" and don't count it as
                # a DIFF for the purposes of opening a details block.
                if mojo_val is None or rs_val is None:
                    rs_match = None  # type: ignore[assignment]
                else:
                    rs_match = _values_equal(mojo_val, rs_val)
                case_records.append((case, py_match, rs_match, recs))  # type: ignore[arg-type]

            time_header = ["case", "match py", "match rs"] + [
                LANG_LABEL.get(l, l) for l in present_langs
            ]
            for lang in present_ratio_pairs:
                time_header.append(f"dm/{ratio_short.get(lang, lang)}")
            time_body: list[list[str]] = []
            for case, py_match, rs_match, recs in case_records:
                py_cell = "OK" if py_match else "DIFF"
                if rs_match is None:
                    rs_cell = "-"
                else:
                    rs_cell = "OK" if rs_match else "DIFF"
                row = [_short_name(case), py_cell, rs_cell]
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

            # A case is shown in the DIFF block iff decimo disagrees with
            # *any* available oracle (Python or Rust). N/A on Rust does
            # not trigger a DIFF on its own.
            diffs = [
                t
                for t in case_records
                if (not t[1]) or (t[2] is False)  # py_match False or rs_match False
            ]
            if diffs:
                lines.append(
                    f"<details><summary>{len(diffs)} DIFF case(s) at "
                    f"<code>{op}</code> / prec={prec} \u2014 click to expand</summary>"
                )
                lines.append("")
                for case, _py_match, _rs_match, recs in diffs:
                    lines.append(f"**{case}**")
                    lines.append("")
                    lines.append("| language | result |")
                    lines.append("| --- | --- |")
                    for lang in args.langs:
                        rec = recs.get(lang, {}) if lang in present_langs else {}
                        r = rec.get("result") if rec else None
                        if r is None:
                            cell = "_(no row)_"
                        else:
                            cell = "`" + r.replace("|", "\\|") + "`"
                        lines.append(f"| {LANG_LABEL.get(lang, lang)} | {cell} |")
                    lines.append("")
                lines.append("</details>")
                lines.append("")

    # ----- Section 3 -----
    lines.append("## 3. decimo-vs-python agreement summary")
    lines.append("")
    eq_header = ["op", "precision", "total", "matched", "mismatched", "match %"]
    eq_rows: list[list[str]] = []
    for op in args.ops:
        for prec in op_precs[op]:
            total = len(case_orders[(op, prec)])
            matched = 0
            for case in case_orders[(op, prec)]:
                per_lang = records[op][prec]
                mojo_val = per_lang.get("mojo", {}).get(case, {}).get("result")
                py_val = per_lang.get("python", {}).get(case, {}).get("result")
                if (
                    mojo_val is not None
                    and py_val is not None
                    and _values_equal(mojo_val, py_val)
                ):
                    matched += 1
            pct = f"{(100.0 * matched / total):.1f}%" if total else "-"
            eq_rows.append(
                [op, str(prec), str(total), str(matched), str(total - matched), pct]
            )
    lines.extend(render_aligned_table(eq_header, eq_rows))

    report = "\n".join(lines) + "\n"
    sys.stdout.write(report)
    with open(out_path, "w") as f:
        f.write(report)
    print(f"\n>>> Wrote {out_path}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
