#!/usr/bin/env python3
"""Cross-language BigDecimal benchmark — Python (decimal.Decimal) side.

Reads cases/<op>.toml, expands `{C,N}` patterns, auto-tunes iteration count
to ~50ms per case, and emits one CSV per case to logs/python_<op>_<ts>.csv:

    timestamp,language,op,case_name,result,ns_per_iter

Python's decimal.Decimal is the **oracle**: the aggregator marks the `match`
column as OK iff every other language's result is numerically equal to
Python's, so formatting-only differences such as trailing zeros do not
count as DIFFs.

Usage:
    python3 bench.py --op multiply --cases-dir ../cases --logs-dir ../logs
"""

from __future__ import annotations

import argparse
import csv
import decimal
import os
import re
import sys
import time
from datetime import datetime, timezone

try:
    import tomllib  # py 3.11+
except ImportError:
    import tomli as tomllib  # type: ignore


PATTERN_RE = re.compile(r"\{([^{}]*),(\d+)\}")


def expand(s: str) -> str:
    """Expand `{C,N}` repeat patterns. Last comma wins (matches Mojo)."""
    out = []
    i = 0
    while i < len(s):
        if s[i] == "{":
            close = s.find("}", i + 1)
            if close < 0:
                out.append(s[i])
                i += 1
                continue
            inner = s[i + 1 : close]
            comma = inner.rfind(",")
            if comma < 0:
                out.append(s[i : close + 1])
                i = close + 1
                continue
            payload = inner[:comma]
            try:
                n = int(inner[comma + 1 :])
            except ValueError:
                out.append(s[i : close + 1])
                i = close + 1
                continue
            out.append(payload * n)
            i = close + 1
        else:
            out.append(s[i])
            i += 1
    return "".join(out)


# ----- per-op kernels ---------------------------------------------------


def _round_args(b: str):
    ndigits_str, mode = b.split("|", 1)
    py_mode = {
        "ROUND_DOWN": decimal.ROUND_DOWN,
        "ROUND_UP": decimal.ROUND_UP,
        "ROUND_HALF_UP": decimal.ROUND_HALF_UP,
        "ROUND_HALF_DOWN": decimal.ROUND_HALF_DOWN,
        "ROUND_HALF_EVEN": decimal.ROUND_HALF_EVEN,
        "ROUND_CEILING": decimal.ROUND_CEILING,
        "ROUND_FLOOR": decimal.ROUND_FLOOR,
    }[mode]
    return int(ndigits_str), py_mode


def _fmt(d) -> str:
    """Format a Decimal as fixed-point (no scientific notation).

    For non-Decimal values (e.g. comparison int, str), fall back to str().
    Important: do NOT apply `+d`. The arithmetic ops (`a+b`, `a*b`, ...)
    already round their result to the active context precision; calling
    `+d` afterwards is at best idempotent for arithmetic ops but adds an
    unwanted rounding pass for `from_string`/`to_string` (where the
    timed kernel deliberately preserves the input digits). Keeping the
    display path rounding-free keeps the displayed result aligned with
    what the kernel actually computed.
    """
    if isinstance(d, decimal.Decimal):
        return format(d, "f")
    return str(d)


def make_kernel(op: str, a: str, b: str, precision: int):
    """Return (display_result_str, kernel_callable_no_args, supported_bool)."""
    decimal.getcontext().prec = precision
    da = decimal.Decimal(a)
    # `b` for the `round` op encodes "ndigits|MODE" (not a Decimal).
    if op == "round" or b in ("", None):
        db = decimal.Decimal(0)
    else:
        db = decimal.Decimal(b)

    if op == "add":
        return _fmt(da + db), (lambda: da + db), True
    if op == "subtract":
        return _fmt(da - db), (lambda: da - db), True
    if op == "multiply":
        return _fmt(da * db), (lambda: da * db), True
    if op == "divide":
        return _fmt(da / db), (lambda: da / db), True
    if op == "comparison":
        cmp = -1 if da < db else (1 if da > db else 0)
        return str(cmp), (lambda: -1 if da < db else (1 if da > db else 0)), True
    if op == "from_string":
        # Parsing is precision-insensitive: do not apply current-context
        # rounding. The kernel times exactly the parse path.
        return _fmt(decimal.Decimal(a)), (lambda: decimal.Decimal(a)), True
    if op == "to_string":
        return _fmt(da), (lambda: format(da, "f")), True
    if op == "sqrt":
        return _fmt(da.sqrt()), (lambda: da.sqrt()), True
    if op == "exp":
        return _fmt(da.exp()), (lambda: da.exp()), True
    if op == "ln":
        return _fmt(da.ln()), (lambda: da.ln()), True
    if op == "root":
        # Python decimal has no nth root; emulate via x**(1/n) for the
        # *result* (oracle) but mark as supported. n is bc.b.
        n = decimal.Decimal(b)
        recip = decimal.Decimal(1) / n
        result = da**recip
        return _fmt(result), (lambda: da**recip), True
    if op == "round":
        ndigits, py_mode = _round_args(b)
        decimal.getcontext().rounding = py_mode
        # Python's Decimal.__round__(n) uses current context rounding mode.
        return _fmt(round(da, ndigits)), (lambda: round(da, ndigits)), True
    raise ValueError(f"unknown op: {op}")


# ----- timing -----------------------------------------------------------

TARGET_NS = 50_000_000
MIN_RES_NS = 100_000  # 100µs floor per rep for resolution
MAX_WALL_NS = 500_000_000  # 500ms total wall per case


def bench_kernel(kernel, iter_hint: int, precision: int = 100) -> float:
    """Return best-of-N ns/iter, auto-tuned.

    Strategy:
      - Target ~50 ms per rep (TARGET_NS).
      - Resolution floor: ensure each rep takes ≥100 µs so cheap ops do not
        collapse to 0 ns/iter at high precision.
      - Adaptive `reps`: shrink from 3 → 1 for very-slow ops to bound wall
        time per case at ~500 ms.
    `precision` is currently informational; iter scaling derives from the
    measured per-iter cost rather than precision directly.
    """
    del precision  # not used: cal_ns drives the choice
    # calibrate
    t0 = time.perf_counter_ns()
    r = kernel()
    cal = time.perf_counter_ns() - t0
    if cal <= 0:
        cal = 1
    n = TARGET_NS // cal
    n_min_res = MIN_RES_NS // cal
    if n < n_min_res:
        n = n_min_res
    if n < 3:
        n = 3
    if n > iter_hint:
        n = iter_hint
    if n < 1:
        n = 1
    iters = int(n)
    per_rep = iters * cal
    reps = 3
    if per_rep > 0:
        reps = max(1, min(3, MAX_WALL_NS // per_rep))
    best = 1 << 62
    for _ in range(int(reps)):
        t0 = time.perf_counter_ns()
        for _ in range(iters):
            r = kernel()
        dt = time.perf_counter_ns() - t0
        if dt < best:
            best = dt
    _ = r
    return best / iters


# ----- main -------------------------------------------------------------


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--op", required=True)
    ap.add_argument("--cases-dir", default="../cases")
    ap.add_argument("--logs-dir", default="../logs")
    ap.add_argument(
        "--precision",
        type=int,
        default=None,
        help="Override precision from cases TOML.",
    )
    args = ap.parse_args()

    toml_path = os.path.join(args.cases_dir, f"{args.op}.toml")
    with open(toml_path, "rb") as f:
        doc = tomllib.load(f)
    cfg = doc.get("config", {})
    iter_hint = int(cfg.get("iterations", 1000))
    precision = (
        int(args.precision)
        if args.precision is not None
        else int(cfg.get("precision", 28))
    )
    cases = doc.get("cases", [])

    os.makedirs(args.logs_dir, exist_ok=True)
    ts = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    log_path = os.path.join(args.logs_dir, f"python_{args.op}_p{precision}_{ts}.csv")
    print(f"# python decimal.Decimal {args.op} (prec={precision}, hint={iter_hint})")
    print(f"{'case':<44}{'result':<36}ns/iter")
    with open(log_path, "w", newline="") as fout:
        w = csv.writer(fout, lineterminator="\n")
        w.writerow(
            [
                "timestamp",
                "language",
                "op",
                "case_name",
                "result",
                "ns_per_iter",
                "precision",
            ]
        )
        for c in cases:
            name = c["name"]
            a = expand(c["a"])
            b = expand(c.get("b", "")) if c.get("b") not in (None, "") else ""
            try:
                result, kernel, _ = make_kernel(args.op, a, b, precision)
                per_ns = bench_kernel(kernel, iter_hint, precision)
            except Exception as exc:
                result = f"ERR: {exc.__class__.__name__}: {exc}"
                per_ns = 0.0
            short = result if len(result) <= 34 else result[:34]
            print(f"{name:<44}{short:<36}{per_ns:.2f}")
            w.writerow(
                [ts, "python", args.op, name, result, f"{per_ns:.4f}", str(precision)]
            )
    print(f"wrote {log_path}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
