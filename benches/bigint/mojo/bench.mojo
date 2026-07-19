# Cross-language BigInt benchmark — Mojo (decimo.BigInt) side.
#
# Reads cases/<op>.toml (shared across languages), expands {C,N} repeat
# patterns, auto-tunes iteration count to ~50ms per case, and emits one CSV
# record per case to logs/mojo_<op>_<ts>.csv. Schema (mirrors decimal128/):
#
#     timestamp,language,op,case_name,result,ns_per_iter
#
# Unlike the BigDecimal harness there is NO precision parameter: BigInt
# arithmetic is always exact.
#
# Usage:
#   pixi run mojo run -I ../../../src --debug-level=line-tables -D ASSERT=none \
#       ./bench.mojo --op multiply --cases-dir ../cases --logs-dir ../logs
#
# Available ops: add, multiply, floor_divide, power, shift, sqrt,
#                from_string, to_string.

from decimo.bigint.bigint import BigInt
import decimo.bigint.arithmetics
import decimo.bigint.exponential
from decimo.tests import (
    BenchCase,
    load_bench_cases,
    load_bench_iterations,
)
from std.benchmark import keep
from std.python import Python
from std.sys import argv as sys_argv
from std.time import perf_counter_ns


def _now_stamp() raises -> String:
    var dt = Python.import_module("datetime")
    var now = dt.datetime.now(dt.timezone.utc)
    return String(now.strftime("%Y%m%d_%H%M%S"))


def _csv_quote(s: String) -> String:
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


def _result_for(
    op: String,
    imm a: BigInt,
    imm b: BigInt,
    a_str: String,
    b_int: Int,
) raises -> String:
    """Display path: produce the result string ONCE per case.

    Never call this inside a timing loop — use `_time_kernel` instead.
    """
    if op == "add":
        return String(a + b)
    if op == "multiply":
        return String(a * b)
    if op == "floor_divide":
        return String(a // b)
    if op == "power":
        return String(a**b_int)
    if op == "shift":
        return String(a << b_int)
    if op == "sqrt":
        return String(a.sqrt())
    if op == "from_string":
        return String(BigInt(a_str))
    if op == "to_string":
        return String(a)
    raise Error("unknown op: " + op)


def _time_kernel(
    op: String,
    imm a: BigInt,
    imm b: BigInt,
    a_str: String,
    b_int: Int,
) raises:
    """Pure-numeric kernel for the timing loop.

    Performs the same work as `_result_for` but renders to a String only
    for the `to_string` / `from_string` ops (where parsing / rendering IS
    the operation under measurement). For every other op it uses
    `keep(...)` on a small derivative of the result (`len(words)`,
    `sign`) to prevent dead-code elimination while keeping the keep cost
    negligible versus the op.

    Operands `a` / `b` are taken as `imm` (borrowed) so no per-iter
    deep copy of the heap-backed word list occurs.
    """
    if op == "add":
        var r = a + b
        keep(len(r.words))
        keep(r.sign)
        return
    if op == "multiply":
        var r = a * b
        keep(len(r.words))
        keep(r.sign)
        return
    if op == "floor_divide":
        var r = a // b
        keep(len(r.words))
        keep(r.sign)
        return
    if op == "power":
        var r = a**b_int
        keep(len(r.words))
        keep(r.sign)
        return
    if op == "shift":
        var r = a << b_int
        keep(len(r.words))
        keep(r.sign)
        return
    if op == "sqrt":
        var r = a.sqrt()
        keep(len(r.words))
        keep(r.sign)
        return
    if op == "from_string":
        var v = BigInt(a_str)
        keep(len(v.words))
        keep(v.sign)
        return
    if op == "to_string":
        var s = String(a)
        keep(s.byte_length())
        return
    raise Error("unknown op: " + op)


# Auto-tune iters: target ~50ms per timed run.
# Includes a resolution floor (≥100µs total per rep) so cheap ops don't
# collapse to <1 timer-tick and report 0 ns/iter. Returns (iters, reps):
# reps shrinks to 1 for very-slow ops to bound wall time per case at ~500ms.
def _tune_iters(initial_ns: UInt, hint_iters: Int) -> Tuple[Int, Int]:
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


def _bench_case(
    op: String,
    bc: BenchCase,
    iter_hint: Int,
) raises -> Tuple[String, Float64]:
    """Compute result + best-of-N ns/iter (auto-tuned)."""
    # Build operands once.
    var a = BigInt(bc.a)

    # `b` handling per op:
    #   - power / shift: b encodes the (small) integer exponent / shift count
    #   - sqrt / from_string / to_string: unary, no b
    #   - add / multiply / floor_divide: b is the second BigInt operand
    var b: BigInt
    var b_int: Int = 0
    if op == "power" or op == "shift":
        b = BigInt.from_int(0)
        b_int = Int(BigInt(bc.b))
    elif op == "sqrt" or op == "from_string" or op == "to_string" or bc.b == "":
        b = BigInt.from_int(0)
    else:
        b = BigInt(bc.b)

    # Compute the displayed `result` ONCE per case (outside any timing loop).
    var result = _result_for(op, a, b, bc.a, b_int)

    # Calibration: time 1 rep to estimate per-iter cost.
    var cal_iters: Int = 1
    var t0 = perf_counter_ns()
    for _ in range(cal_iters):
        _time_kernel(op, a, b, bc.a, b_int)
    var cal_ns = UInt(perf_counter_ns() - t0)
    var tuned = _tune_iters(cal_ns, iter_hint)
    var iters = tuned[0]
    var reps = tuned[1]

    # Best-of-N timing (N = reps, adaptive).
    var best: Int = 0x7FFF_FFFF_FFFF_FFFF
    for _ in range(reps):
        var t1 = perf_counter_ns()
        for _ in range(iters):
            _time_kernel(op, a, b, bc.a, b_int)
        var dt = Int(perf_counter_ns() - t1)
        if dt < best:
            best = dt
    return Tuple[String, Float64](result, Float64(best) / Float64(iters))


def _pad(s: String, w: Int) -> String:
    if s.byte_length() >= w:
        return s
    var out = s
    for _ in range(w - s.byte_length()):
        out += " "
    return out


def main() raises:
    var pysys = Python.import_module("sys")
    pysys.set_int_max_str_digits(10000000)

    var argv = sys_argv()
    var op = String("add")
    var cases_dir = String("../cases")
    var logs_dir = String("../logs")
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
        else:
            i += 1

    var toml_path = cases_dir + "/" + op + ".toml"
    var iter_hint = load_bench_iterations(toml_path)
    var cases = load_bench_cases(toml_path)

    var os_mod = Python.import_module("os")
    if not os_mod.path.exists(logs_dir):
        os_mod.makedirs(logs_dir)
    var ts = _now_stamp()
    var log_path = logs_dir + "/mojo_" + op + "_" + ts + ".csv"
    var py = Python.import_module("builtins")
    var log = py.open(log_path, "w")
    log.write("timestamp,language,op,case_name,result,ns_per_iter\n")

    print("# decimo.BigInt", op, "(hint=", iter_hint, ")")
    print(_pad("case", 44), _pad("result", 36), "ns/iter")
    for ref bc in cases:
        var pair = _bench_case(op, bc, iter_hint)
        var result = pair[0]
        var per = pair[1]
        var rs = result if result.byte_length() <= 34 else String(
            result[byte=0:34]
        )
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
            + "\n"
        )
    log.flush()
    log.close()
    print("wrote", log_path)
