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
import decimo.bigdecimal.exponential as bdexp
from decimo.rounding_mode import RoundingMode
from decimo.tests import BenchCase, load_bench_cases
from std.python import Python
from std.sys import argv as sys_argv


fn _now_stamp() raises -> String:
    var dt = Python.import_module("datetime")
    var now = dt.datetime.now(dt.timezone.utc)
    return String(now.strftime("%Y%m%d_%H%M%S"))


fn _csv_quote(s: String) -> String:
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


fn _pad(s: String, width: Int) -> String:
    if len(s) >= width:
        return s
    var out = s
    var pad = width - len(s)
    for _ in range(pad):
        out += " "
    return out


fn _strip_trailing_zeros(s: String) -> String:
    # Strip trailing zeros after the decimal point so the ref result is
    # easy to eyeball next to the Decimal128 / rust_decimal column.
    # Leaves integer values ("0", "1") and scientific notation untouched.
    if "." not in s or "e" in s or "E" in s:
        return s
    var end = len(s)
    while end > 0 and s[byte = end - 1 : end] == "0":
        end -= 1
    if end > 0 and s[byte = end - 1 : end] == ".":
        end -= 1
    return String(s[byte=0:end])


# Decimal128's coefficient is a 96-bit unsigned integer:
#   MAX_AS_UINT128 = 2**96 - 1 = 79228162514264337593543950335  (29 digits)
# So a value can be stored at 29 significant digits iff its normalized
# coefficient is <= MAX. Otherwise it falls back to 28 digits.
comptime _DEC128_MAX_COEF = String("79228162514264337593543950335")


# Extract the digit-only coefficient string from a BigDecimal's textual
# form: drop sign, decimal point, and any leading zeros (sub-1 values).
# Stops at the first 'e'/'E' so scientific-notation tails don't leak in.
fn _coefficient_digits(s: String) -> String:
    var out = String("")
    var seen_nonzero = False
    for ch in s.codepoint_slices():
        if ch == "-" or ch == "+" or ch == ".":
            continue
        if ch == "e" or ch == "E":
            break
        if not seen_nonzero:
            if ch == "0":
                continue
            seen_nonzero = True
        out += String(ch)
    return out


fn _fits_in_dec128(s: String) -> Bool:
    var coef = _coefficient_digits(s)
    if len(coef) < 29:
        return True
    if len(coef) > 29:
        return False
    # Same-length 29-digit comparison is well-defined as a string compare.
    return coef <= _DEC128_MAX_COEF


# Round a BigDecimal using Decimal128's variable-precision policy: try
# 29 significant digits first; if the resulting coefficient overflows
# 2**96-1 then fall back to 28. `fill_zeros_to_precision=True` ensures
# the result *always* shows the full target precision (so a trailing
# significant zero doesn't make the column look like it has one fewer
# digit than Decimal128 would actually store).
fn _round_and_str(mut v: BigDecimal) raises -> String:
    v.round_to_precision(
        29,
        RoundingMode.ROUND_HALF_EVEN,
        remove_extra_digit_due_to_rounding=False,
        fill_zeros_to_precision=True,
    )
    var s = String(v)
    if not _fits_in_dec128(s):
        v.round_to_precision(
            28,
            RoundingMode.ROUND_HALF_EVEN,
            remove_extra_digit_due_to_rounding=False,
            fill_zeros_to_precision=True,
        )
        s = String(v)
    return _collapse_exact_integer(s)


# If the rounded value is an exact integer (all post-decimal digits are
# zero, or the value is the textual zero "0E-N"), collapse to compact
# integer form so the oracle column matches Decimal128's natural output
# for cases like log10(100) -> 2 instead of "2.0000000000000000000000000000".
fn _collapse_exact_integer(s: String) -> String:
    # Find dot and 'E' positions.
    var dot = -1
    var e_pos = -1
    for i in range(len(s)):
        var ch = s[byte = i : i + 1]
        if ch == ".":
            dot = i
        elif ch == "e" or ch == "E":
            e_pos = i
            break
    # Case 1: "0E-28" or "-0E-28" -> "0".
    if e_pos >= 0 and dot < 0:
        var mantissa = String(s[byte=0:e_pos])
        var all_zero = True
        for ch in mantissa.codepoint_slices():
            if String(ch) != "0" and String(ch) != "-" and String(ch) != "+":
                all_zero = False
                break
        if all_zero:
            return String("0")
        return s
    # Case 2: "N.000...0" -> "N" (only if no exponent and post-dot all zero).
    if dot >= 0 and e_pos < 0:
        var post = String(s[byte = dot + 1 : len(s)])
        var all_zero = True
        for ch in post.codepoint_slices():
            if String(ch) != "0":
                all_zero = False
                break
        if all_zero:
            return String(s[byte=0:dot])
    return s


fn _ref_result(op: String, a_str: String, work_precision: Int) raises -> String:
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


fn main() raises:
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
        ", target=29-then-28 [Decimal128 policy])",
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
