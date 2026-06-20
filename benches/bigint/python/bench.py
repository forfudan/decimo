#!/usr/bin/env python3
"""Cross-language BigInt benchmark — Python (int) side.

Reads cases/<op>.toml, expands `{C,N}` patterns, auto-tunes iteration count
to ~50ms per case, and emits one CSV per case to logs/python_<op>_<ts>.csv:

    timestamp,language,op,case_name,result,ns_per_iter

Python's arbitrary-precision `int` is the **oracle**: the aggregator marks
the `match` column as OK iff every other language's result string equals
Python's. BigInt arithmetic is exact, so there is no precision parameter.

Usage:
    python3 bench.py --op multiply --cases-dir ../cases --logs-dir ../logs
"""

from __future__ import annotations

import argparse
import csv
import math
import os
import re
import sys
import time
from datetime import datetime, timezone

try:
    import tomllib  # py 3.11+
except ImportError:
    import tomli as tomllib  # type: ignore

# BigInt cases reach tens of thousands of decimal digits; lift CPython's
# int<->str conversion guard (default 4300) so from_string / to_string work.
sys.set_int_max_str_digits(10_000_000)

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


def make_kernel(op: str, a: str, b: str):
    """Return (display_result_str, kernel_callable_no_args)."""
    da = int(a)
    # `b` is the second operand (add/multiply/floor_divide) or the small
    # integer exponent / shift count (power/shift). Unary ops ignore it.
    db = int(b) if b not in ("", None) else 0

    if op == "add":
        return str(da + db), (lambda: da + db)
    if op == "multiply":
        return str(da * db), (lambda: da * db)
    if op == "floor_divide":
        return str(da // db), (lambda: da // db)
    if op == "power":
        return str(da**db), (lambda: da**db)
    if op == "shift":
        return str(da << db), (lambda: da << db)
    if op == "sqrt":
        return str(math.isqrt(da)), (lambda: math.isqrt(da))
    if op == "from_string":
        return str(int(a)), (lambda: int(a))
    if op == "to_string":
        return str(da), (lambda: str(da))
    raise ValueError(f"unknown op: {op}")


# ----- timing -----------------------------------------------------------

TARGET_NS = 50_000_000
MIN_RES_NS = 100_000  # 100µs floor per rep for resolution
MAX_WALL_NS = 500_000_000  # 500ms total wall per case


def bench_kernel(kernel, iter_hint: int) -> float:
    """Return best-of-N ns/iter, auto-tuned.

    Mirrors the Mojo harness: target ~50ms per rep, a 100µs resolution
    floor so cheap ops do not collapse to 0 ns/iter, and an adaptive
    `reps` (3 -> 1) bounding wall time per case at ~500ms.
    """
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
    args = ap.parse_args()

    toml_path = os.path.join(args.cases_dir, f"{args.op}.toml")
    with open(toml_path, "rb") as f:
        doc = tomllib.load(f)
    cfg = doc.get("config", {})
    iter_hint = int(cfg.get("iterations", 1000))
    cases = doc.get("cases", [])

    os.makedirs(args.logs_dir, exist_ok=True)
    ts = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    log_path = os.path.join(args.logs_dir, f"python_{args.op}_{ts}.csv")
    print(f"# python int {args.op} (hint={iter_hint})")
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
            ]
        )
        for c in cases:
            name = c["name"]
            a = expand(c["a"])
            b = expand(c.get("b", "")) if c.get("b") not in (None, "") else ""
            try:
                result, kernel = make_kernel(args.op, a, b)
                per_ns = bench_kernel(kernel, iter_hint)
            except Exception as exc:
                result = f"ERR: {exc.__class__.__name__}: {exc}"
                per_ns = 0.0
            short = result if len(result) <= 34 else result[:34]
            print(f"{name:<44}{short:<36}{per_ns:.2f}")
            w.writerow([ts, "python", args.op, name, result, f"{per_ns:.4f}"])
    print(f"wrote {log_path}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
