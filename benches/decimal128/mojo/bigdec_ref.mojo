# Cross-language Decimal128 benchmark — high-precision reference oracle.
#
# Uses `decimo.BigDecimal` at extra working precision (default 40 digits)
# to compute ln/log10/exp, then rounds to 28 significant digits (the
# Decimal128 width) so the result string can be compared apples-to-apples
# against decimo / rust / .NET in the aggregated report.
#
# Writes the same CSV schema as bench.mojo (timestamp,language,op,
# case_name,result,ns_per_iter) with `language=bigdec` and
# `ns_per_iter=` left empty (this is a correctness reference, not a
# perf measurement).
#
# Usage:
#   pixi run --manifest-path ../../../pixi.toml mojo run \
#       -I ../../../src --debug-level=line-tables -D ASSERT=none \
#       ./bigdec_ref.mojo --op ln --cases-dir ../cases --logs-dir ../logs

from decimo import BigDecimal
from decimo import Decimal128
import decimo.bigdecimal.exponential as bdexp
from decimo.tests import load_bench_cases
from std.python import Python
from std.sys import argv as sys_argv


def _now_stamp() raises -> String:
    var dt = Python.import_module("datetime")
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


def _pad(s: String, width: Int) -> String:
    if len(s) >= width:
        return s
    var out = s
    var pad = width - len(s)
    for _ in range(pad):
        out += " "
    return out


# Round a BigDecimal to the Decimal128 storage grid (≤ 96-bit
# coefficient, scale ≤ 28) using banker's rounding, and return its
# canonical Decimal128 string.
#
# Previously this was ~80 lines of hand-written significant-digit
# rounding, coefficient-bound checks, and exact-integer collapsing.
# `Decimal128.from_decimal()` now performs all of this in one call by
# routing through `from_string()` (which applies `ROUND_HALF_EVEN` via
# `round_coefficient`, calls `fit_to_max_coefficient` to honour the
# 29-digit cap, and emits Decimal128's natural string form).
def _round_and_str(v: BigDecimal) raises -> String:
    return String(Decimal128.from_decimal(v))


def _ref_result(
    op: String, a_str: String, work_precision: Int
) raises -> String:
    var a = BigDecimal.from_string(a_str)
    if op == "ln":
        var r = bdexp.ln(a, work_precision)
        return _round_and_str(r)
    elif op == "log10":
        var r = bdexp.log10(a, work_precision)
        return _round_and_str(r)
    elif op == "exp":
        var r = bdexp.exp(a, work_precision)
        return _round_and_str(r)
    raise Error("bigdec_ref only supports ln, log10, exp (got '" + op + "')")


def main() raises:
    var argv = sys_argv()
    var op = String("ln")
    var cases_dir = String("../cases")
    var logs_dir = String("../logs")
    var work_precision = 40

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
        elif arg == "--work-precision":
            work_precision = Int(String(argv[i + 1]))
            i += 2
        else:
            i += 1

    var toml_path = cases_dir + "/" + op + ".toml"
    var cases = load_bench_cases(toml_path)

    var os_mod = Python.import_module("os")
    if not os_mod.path.exists(logs_dir):
        os_mod.makedirs(logs_dir)
    var ts = _now_stamp()
    var log_path = logs_dir + "/bigdec_" + op + "_" + ts + ".csv"
    var py = Python.import_module("builtins")
    var log = py.open(log_path, "w")
    log.write("timestamp,language,op,case_name,result,ns_per_iter\n")

    print(
        "# decimo.BigDecimal",
        op,
        "(work=",
        work_precision,
        ", quantised onto Decimal128 grid via from_decimal())",
    )
    print(_pad("case", 40), "result")
    for ref bc in cases:
        var result = _ref_result(op, bc.a, work_precision)
        print(_pad(bc.name, 40), result)
        log.write(
            ts
            + ",bigdec,"
            + op
            + ","
            + _csv_quote(bc.name)
            + ","
            + _csv_quote(result)
            + ",\n"
        )
    log.flush()
    log.close()
    print("wrote", log_path)
