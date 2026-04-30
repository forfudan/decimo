# Cross-language BigDecimal benchmark — Mojo (decimo.BigDecimal) side.
#
# Reads cases/<op>.toml (shared across languages), expands {C,N} repeat
# patterns, auto-tunes iteration count to ~50ms per case, and emits one CSV
# record per case to logs/mojo_<op>_<ts>.csv. Schema (mirrors decimal128/):
#
#     timestamp,language,op,case_name,result,ns_per_iter
#
# Usage:
#   pixi run mojo run -I ../../../src --debug-level=line-tables -D ASSERT=none \
#       ./bench.mojo --op multiply --cases-dir ../cases --logs-dir ../logs
#
# Available ops: add, subtract, multiply, divide, comparison,
#                from_string, to_string, sqrt, exp, ln, root, round.

from decimo import BigDecimal
from decimo.bigdecimal.arithmetics import true_divide
from decimo.bigdecimal.exponential import sqrt as bd_sqrt
from decimo.bigdecimal.exponential import exp as bd_exp
from decimo.bigdecimal.exponential import ln as bd_ln
from decimo.bigdecimal.exponential import root as bd_root
from decimo.bigdecimal.rounding import round as bd_round
from decimo.bigdecimal.rounding import round_to_precision
from decimo.rounding_mode import RoundingMode
from decimo.tests import (
    BenchCase,
    load_bench_cases,
    load_bench_iterations,
    load_bench_precision,
)
from std.benchmark import keep
from std.python import Python
from std.sys import argv as sys_argv
from std.time import perf_counter_ns


fn _now_stamp() raises -> String:
    var dt = Python.import_module("datetime")
    var now = dt.datetime.now(dt.timezone.utc)
    return String(now.strftime("%Y%m%d_%H%M%S"))


fn _csv_quote(s: String) -> String:
    var needs = False
    for ch in s.codepoint_slices():
        if ch == "," or ch == '"' or ch == "\n" or ch == "\r":
            needs = True
            break
    if not needs:
        return s
    var out = String('"')
    for ch in s.codepoint_slices():
        if ch == '"':
            out += '""'
        else:
            out += String(ch)
    out += '"'
    return out


fn _parse_round_param(b: String) raises -> Tuple[Int, RoundingMode]:
    """Decode "ndigits|MODE" into (ndigits, RoundingMode)."""
    var idx = b.find("|")
    if idx < 0:
        raise Error("round case missing '|' in b field: " + b)
    var ndigits = atol(String(b[byte=0:idx]))
    var mode_str = String(b[byte = idx + 1 : len(b)])
    if mode_str == "ROUND_DOWN":
        return Tuple[Int, RoundingMode](ndigits, RoundingMode.ROUND_DOWN)
    if mode_str == "ROUND_UP":
        return Tuple[Int, RoundingMode](ndigits, RoundingMode.ROUND_UP)
    if mode_str == "ROUND_HALF_UP":
        return Tuple[Int, RoundingMode](ndigits, RoundingMode.ROUND_HALF_UP)
    if mode_str == "ROUND_HALF_DOWN":
        return Tuple[Int, RoundingMode](ndigits, RoundingMode.ROUND_HALF_DOWN)
    if mode_str == "ROUND_HALF_EVEN":
        return Tuple[Int, RoundingMode](ndigits, RoundingMode.ROUND_HALF_EVEN)
    if mode_str == "ROUND_CEILING":
        return Tuple[Int, RoundingMode](ndigits, RoundingMode.ROUND_CEILING)
    if mode_str == "ROUND_FLOOR":
        return Tuple[Int, RoundingMode](ndigits, RoundingMode.ROUND_FLOOR)
    raise Error("unknown rounding mode: " + mode_str)


fn _cmp_3way(a: BigDecimal, b: BigDecimal) raises -> String:
    """Stable, cross-language 3-way comparison: returns "-1", "0", or "1"."""
    if a < b:
        return String("-1")
    if a > b:
        return String("1")
    return String("0")


fn _round_to_prec(var v: BigDecimal, precision: Int) raises -> BigDecimal:
    """Round `v` to `precision` significant digits (HALF_EVEN), in-place."""
    round_to_precision(
        v,
        precision,
        RoundingMode.ROUND_HALF_EVEN,
        remove_extra_digit_due_to_rounding=False,
        fill_zeros_to_precision=False,
    )
    return v^


fn _emit(v: BigDecimal) raises -> String:
    """Render a BigDecimal in fixed-point (no scientific notation).

    Works around a corner case in `BigDecimal.to_string(force_plain=True)`
    where negative-scale numbers (e.g. `1686 × 10**2`) lose the trailing
    magnitude zeros (would render "1686" instead of "168600"). We append
    those zeros explicitly here so the output is comparable to Python's
    `format(decimal.Decimal, 'f')` and Rust's `to_plain_string()`.
    """
    var s = v.to_string(force_plain=True)
    if v.scale < 0:
        var pad = -v.scale
        for _ in range(pad):
            s += "0"
    return s^


fn _result_for(
    op: String,
    a: BigDecimal,
    b: BigDecimal,
    a_str: String,
    b_str: String,
    precision: Int,
) raises -> String:
    if op == "add":
        return _emit(_round_to_prec(a + b, precision))
    if op == "subtract":
        return _emit(_round_to_prec(a - b, precision))
    if op == "multiply":
        return _emit(_round_to_prec(a * b, precision))
    if op == "divide":
        return _emit(true_divide(a, b, precision))
    if op == "comparison":
        return _cmp_3way(a, b)
    if op == "from_string":
        return _emit(_round_to_prec(BigDecimal(a_str), precision))
    if op == "to_string":
        return _emit(_round_to_prec(a.copy(), precision))
    if op == "sqrt":
        return _emit(bd_sqrt(a, precision))
    if op == "exp":
        return _emit(bd_exp(a, precision))
    if op == "ln":
        return _emit(bd_ln(a, precision))
    if op == "root":
        return _emit(bd_root(a, b, precision))
    if op == "round":
        var pr = _parse_round_param(b_str)
        return _emit(bd_round(a, pr[0], pr[1]))
    raise Error("unknown op: " + op)


# Auto-tune iters: target ~50ms per timed run.
# Includes a resolution floor (≥100µs total per rep) so cheap ops at high
# precision don't collapse to <1 timer-tick and report 0 ns/iter.
# Returns (iters, reps): reps shrinks to 1 for very-slow ops to bound wall
# time per case at ~500ms.
fn _tune_iters(initial_ns: UInt, hint_iters: Int) -> Tuple[Int, Int]:
    comptime TARGET_NS: UInt = 50_000_000  # 50ms per rep target
    comptime MIN_RES_NS: UInt = 100_000  # 100µs floor for resolution
    comptime MAX_WALL_NS: UInt = 500_000_000  # 500ms total per case
    var cal = initial_ns if initial_ns > 0 else UInt(1)
    var n = Int(TARGET_NS // cal)
    var n_min_res = Int(MIN_RES_NS // cal)
    if n < n_min_res:
        n = n_min_res
    if n < 3:
        n = 3
    if n > hint_iters:
        n = hint_iters
    if n < 1:
        n = 1
    var per_rep = UInt(n) * cal
    var reps = 3
    if per_rep > 0:
        var r = Int(MAX_WALL_NS // per_rep)
        if r < 1:
            r = 1
        if r > 3:
            r = 3
        reps = r
    return Tuple[Int, Int](n, reps)


fn _bench_case(
    op: String,
    bc: BenchCase,
    iter_hint: Int,
    precision: Int,
) raises -> Tuple[String, Float64]:
    """Compute result + best-of-3 ns/iter (auto-tuned)."""
    # Build operands once.
    var a: BigDecimal
    var b: BigDecimal
    a = BigDecimal(bc.a)
    # `b` operand handling per op:
    #   - round:        b field encodes "ndigits|MODE"  (no arithmetic operand)
    #   - from_string / to_string: unary
    #   - comparison:   b is the second operand
    #   - arithmetic / sqrt / exp / ln: as-is (sqrt/exp/ln are unary)
    #   - root:         b is the root index n
    if op == "round" or op == "from_string" or op == "to_string":
        b = BigDecimal.from_int(0)
    elif bc.b == "":
        b = BigDecimal.from_int(0)
    else:
        b = BigDecimal(bc.b)

    var result = _result_for(op, a, b, bc.a, bc.b, precision)

    # Calibration: time `cal_iters` reps to estimate per-iter cost.
    var cal_iters: Int = 1
    var t0 = perf_counter_ns()
    for _ in range(cal_iters):
        var r = _result_for(op, a, b, bc.a, bc.b, precision)
        keep(len(r))
    var cal_ns = UInt(perf_counter_ns() - t0)
    var tuned = _tune_iters(cal_ns, iter_hint)
    var iters = tuned[0]
    var reps = tuned[1]

    # Best-of-N timing (N = reps, adaptive).
    var best: Int = 0x7FFF_FFFF_FFFF_FFFF
    for _ in range(reps):
        var t1 = perf_counter_ns()
        for _ in range(iters):
            var r = _result_for(op, a, b, bc.a, bc.b, precision)
            keep(len(r))
        var dt = Int(perf_counter_ns() - t1)
        if dt < best:
            best = dt
    return Tuple[String, Float64](result, Float64(best) / Float64(iters))


fn _pad(s: String, w: Int) -> String:
    if len(s) >= w:
        return s
    var out = s
    for _ in range(w - len(s)):
        out += " "
    return out


fn main() raises:
    var argv = sys_argv()
    var op = String("add")
    var cases_dir = String("../cases")
    var logs_dir = String("../logs")
    var precision_override: Int = -1
    var i = 1
    while i < len(argv):
        var arg = String(argv[i])
        if arg == "--op":
            op = String(argv[i + 1])
            i += 2
        elif arg == "--cases-dir":
            cases_dir = String(argv[i + 1])
            i += 2
        elif arg == "--logs-dir":
            logs_dir = String(argv[i + 1])
            i += 2
        elif arg == "--precision":
            precision_override = atol(String(argv[i + 1]))
            i += 2
        else:
            i += 1

    var toml_path = cases_dir + "/" + op + ".toml"
    var iter_hint = load_bench_iterations(toml_path)
    var precision = (
        precision_override if precision_override
        > 0 else load_bench_precision(toml_path)
    )
    var cases = load_bench_cases(toml_path)

    var os_mod = Python.import_module("os")
    if not os_mod.path.exists(logs_dir):
        os_mod.makedirs(logs_dir)
    var ts = _now_stamp()
    var log_path = (
        logs_dir + "/mojo_" + op + "_p" + String(precision) + "_" + ts + ".csv"
    )
    var py = Python.import_module("builtins")
    var log = py.open(log_path, "w")
    log.write("timestamp,language,op,case_name,result,ns_per_iter,precision\n")

    print(
        "# decimo.BigDecimal",
        op,
        "(prec=",
        precision,
        ", hint=",
        iter_hint,
        ")",
    )
    print(_pad("case", 44), _pad("result", 36), "ns/iter")
    for ref bc in cases:
        var pair = _bench_case(op, bc, iter_hint, precision)
        var result = pair[0]
        var per = pair[1]
        var rs = result if len(result) <= 34 else String(result[byte=0:34])
        print(_pad(bc.name, 44), _pad(rs, 36), per)
        log.write(
            ts
            + ",mojo,"
            + op
            + ","
            + _csv_quote(bc.name)
            + ","
            + _csv_quote(result)
            + ","
            + String(per)
            + ","
            + String(precision)
            + "\n"
        )
    log.flush()
    log.close()
    print("wrote", log_path)
