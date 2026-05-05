# Cross-language Decimal128 benchmark — Mojo (decimo) side.
#
# Reads cases/<op>.toml (shared with the Rust side), expands `{C,N}` repeat
# patterns via `decimo.tests.expand_value`, runs `iterations` of each case,
# and emits one CSV record per case to stdout AND to `logs/mojo_<op>_<ts>.csv`.
# Schema (mirrors rust/src/main.rs):
#
#     timestamp,language,op,case_name,result,ns_per_iter
#
# Usage:  pixi run mojo run -I ../../../src --debug-level=line-tables \
#             -D ASSERT=none ./bench.mojo --op add
#
# Available ops: add, subtract, multiply, divide, comparison, from_string,
#                to_string.

from decimo import Decimal128
from decimo.tests import BenchCase, load_bench_cases, load_bench_iterations
from std.benchmark import black_box, keep
from std.python import Python, PythonObject
from std.sys import argv as sys_argv
from std.time import perf_counter_ns


def _now_stamp() raises -> String:
    var dt = Python.import_module("datetime")
    # Use UTC to match the rust/csharp/vbnet harnesses, so log filenames are
    # comparable across machines/timezones and "latest log" selection is stable.
    var now = dt.datetime.now(dt.timezone.utc)
    return String(now.strftime("%Y%m%d_%H%M%S"))


def _csv_quote(s: String) -> String:
    var needs_quote = False
    for ch in s.codepoint_slices():
        if ch == "," or ch == '"' or ch == "\n" or ch == "\r":
            needs_quote = True
            break
    if not needs_quote:
        return s
    var out = String('"')
    for ch in s.codepoint_slices():
        if ch == '"':
            out += '""'
        else:
            out += String(ch)
    out += '"'
    return out


def _bench_one[
    Body: fn(a: Decimal128, b: Decimal128) raises capturing[_] -> UInt64,
](a: Decimal128, b: Decimal128, iters: Int) raises -> Float64:
    """Run `Body(a, b)` once per inner iter; best-of-5; returns ns/op.

    Defeats compiler precomputation of cheap kernels (notably `comparison`,
    whose result on fixed `(a, b)` is loop-invariant and would otherwise be
    constant-folded to a near-zero timing) by:

    1. Wrapping the operands with `black_box` so the optimiser cannot
       hoist `Body(a, b)` out of the loop -- each iteration must reload.
    2. Passing the result through `keep` so the call cannot be deleted as
       dead code.
    3. XOR-folding the result into a sink that also incorporates the loop
       index, ensuring an observable side-effect that depends on `i`.
    """
    comptime REPS = 5
    var best: Int = 0x7FFF_FFFF_FFFF_FFFF
    var sink: UInt64 = 0
    for _ in range(REPS):
        var t0 = perf_counter_ns()
        for i in range(iters):
            var r = Body(black_box(a), black_box(b))
            keep(r)
            sink = sink ^ r ^ UInt64(i)
        var dt = Int(perf_counter_ns() - t0)
        if dt < best:
            best = dt
    keep(sink)
    return Float64(best) / Float64(iters)


def _bench_str(a_str: String, iters: Int) raises -> Float64:
    """from_string microbench — re-parses the string each iter."""
    comptime REPS = 5
    var best: Int = 0x7FFF_FFFF_FFFF_FFFF
    var sink: UInt64 = 0
    for _ in range(REPS):
        var t0 = perf_counter_ns()
        for _ in range(iters):
            var d = Decimal128(a_str)
            sink += UInt64(d.coefficient() & 0xFFFF_FFFF_FFFF_FFFF)
        var dt = Int(perf_counter_ns() - t0)
        if dt < best:
            best = dt
    _ = sink
    return Float64(best) / Float64(iters)


def _bench_to_str(d: Decimal128, iters: Int) raises -> Float64:
    comptime REPS = 5
    var best: Int = 0x7FFF_FFFF_FFFF_FFFF
    var sink: UInt64 = 0
    for _ in range(REPS):
        var t0 = perf_counter_ns()
        for _ in range(iters):
            sink += UInt64(len(String(d)))
        var dt = Int(perf_counter_ns() - t0)
        if dt < best:
            best = dt
    _ = sink
    return Float64(best) / Float64(iters)


def _result_for(
    op: String, a: Decimal128, b: Decimal128, c: Decimal128
) raises -> String:
    if op == "add":
        return String(a + b)
    elif op == "subtract":
        return String(a - b)
    elif op == "multiply":
        return String(a * b)
    elif op == "divide":
        return String(a / b)
    elif op == "comparison":
        if a < b:
            return String("-1")
        if a > b:
            return String("1")
        return String("0")
    elif op == "from_string":
        return String(a)
    elif op == "to_string":
        return String(a)
    elif op == "ln":
        return String(a.ln())
    elif op == "log10":
        return String(a.log10())
    elif op == "exp":
        return String(a.exp())
    elif op == "fma":
        return String(a.fma(b, c))
    raise Error("unknown op: " + op)


def _run_case(
    op: String,
    bc: BenchCase,
    iters: Int,
) raises -> Tuple[String, Float64]:
    var a = Decimal128(bc.a)
    var b = Decimal128(bc.b) if bc.b != "" else Decimal128.ZERO()
    var c = Decimal128(bc.c) if bc.c != "" else Decimal128.ZERO()
    var result = _result_for(op, a, b, c)

    var per: Float64
    if op == "add":

        @parameter
        def _f_add(x: Decimal128, y: Decimal128) raises -> UInt64:
            return UInt64((x + y).coefficient() & 0xFFFF_FFFF_FFFF_FFFF)

        per = _bench_one[_f_add](a, b, iters)
    elif op == "subtract":

        @parameter
        def _f_sub(x: Decimal128, y: Decimal128) raises -> UInt64:
            return UInt64((x - y).coefficient() & 0xFFFF_FFFF_FFFF_FFFF)

        per = _bench_one[_f_sub](a, b, iters)
    elif op == "multiply":

        @parameter
        def _f_mul(x: Decimal128, y: Decimal128) raises -> UInt64:
            return UInt64((x * y).coefficient() & 0xFFFF_FFFF_FFFF_FFFF)

        per = _bench_one[_f_mul](a, b, iters)
    elif op == "divide":

        @parameter
        def _f_div(x: Decimal128, y: Decimal128) raises -> UInt64:
            return UInt64((x / y).coefficient() & 0xFFFF_FFFF_FFFF_FFFF)

        per = _bench_one[_f_div](a, b, iters)
    elif op == "comparison":

        @parameter
        def _f_cmp(x: Decimal128, y: Decimal128) raises -> UInt64:
            return UInt64(1) if x < y else UInt64(0)

        per = _bench_one[_f_cmp](a, b, iters)
    elif op == "from_string":
        per = _bench_str(bc.a, iters)
    elif op == "to_string":
        per = _bench_to_str(a, iters)
    elif op == "ln":

        @parameter
        def _f_ln(x: Decimal128, y: Decimal128) raises -> UInt64:
            return UInt64(x.ln().coefficient() & 0xFFFF_FFFF_FFFF_FFFF)

        per = _bench_one[_f_ln](a, b, iters)
    elif op == "log10":

        @parameter
        def _f_log10(x: Decimal128, y: Decimal128) raises -> UInt64:
            return UInt64(x.log10().coefficient() & 0xFFFF_FFFF_FFFF_FFFF)

        per = _bench_one[_f_log10](a, b, iters)
    elif op == "exp":

        @parameter
        def _f_exp(x: Decimal128, y: Decimal128) raises -> UInt64:
            return UInt64(x.exp().coefficient() & 0xFFFF_FFFF_FFFF_FFFF)

        per = _bench_one[_f_exp](a, b, iters)
    elif op == "fma":
        # Capture the third operand `c` so the kernel runs the true
        # ternary fused multiply-add per iteration.
        @parameter
        def _f_fma(x: Decimal128, y: Decimal128) raises -> UInt64:
            return UInt64(x.fma(y, c).coefficient() & 0xFFFF_FFFF_FFFF_FFFF)

        per = _bench_one[_f_fma](a, b, iters)
    else:
        raise Error("unknown op: " + op)

    return Tuple[String, Float64](result, per)


def _pad(s: String, width: Int) -> String:
    if len(s) >= width:
        return s
    var out = s
    var pad = width - len(s)
    for _ in range(pad):
        out += " "
    return out


def main() raises:
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
    var iters = load_bench_iterations(toml_path)
    var cases = load_bench_cases(toml_path)

    var os_mod = Python.import_module("os")
    if not os_mod.path.exists(logs_dir):
        os_mod.makedirs(logs_dir)
    var ts = _now_stamp()
    var log_path = logs_dir + "/mojo_" + op + "_" + ts + ".csv"
    var py = Python.import_module("builtins")
    var log = py.open(log_path, "w")
    log.write("timestamp,language,op,case_name,result,ns_per_iter\n")

    print("# decimo.Decimal128", op, "(iters=", iters, ")")
    print(_pad("case", 40), _pad("result", 32), "ns/iter")
    for ref bc in cases:
        var pair = _run_case(op, bc, iters)
        var result = pair[0]
        var per = pair[1]
        var result_short = result if len(result) <= 30 else String(
            result[byte=0:30]
        )
        print(_pad(bc.name, 40), _pad(result_short, 32), per)
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
