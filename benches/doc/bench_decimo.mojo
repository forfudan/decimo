"""Times decimo for `docs/benchmarks.md`. Emits JSON on stdout.

Reports the minimum over several rounds rather than the mean: noise on a
latency benchmark is one-sided, so the minimum is the stable estimator. The
operand sets match `bench_libmpdec.c` and `bench_cpython.py` exactly.

    pixi run mojo run -I src -D ASSERT=none benches/doc/bench_decimo.mojo
"""

from std.time import perf_counter_ns

from decimo.bigdecimal.bigdecimal import BigDecimal
from decimo.bigdecimal import arithmetics as bd_arithmetics
from decimo.bigdecimal import rounding as bd_rounding
from decimo.bigdecimal import constants as bd_constants
from decimo.bigint.bigint import BigInt
from decimo.rounding_mode import RoundingMode

comptime ROUNDS = 7
comptime ITERS = 200000


def _num(value: Float64) -> String:
    """Three decimal places, without pulling in a formatting library."""
    var scaled = Int(value * 1000.0 + 0.5)
    var whole = scaled // 1000
    var frac = scaled % 1000
    var frac_text = String(frac)
    while frac_text.byte_length() < 3:
        frac_text = "0" + frac_text
    return String(whole) + "." + frac_text


def _digits(count: Int) -> String:
    """A `count`-digit decimal string, deterministic across runs."""
    var out = String("")
    var state = 7
    for _ in range(count):
        state = (state * 31 + 17) % 9
        out += String(state + 1)
    return out^


def main() raises -> None:
    var sink = 0
    print("{")
    print('  "library": "decimo",')
    print('  "rounds": ' + String(ROUNDS) + ",")
    print('  "iterations": ' + String(ITERS) + ",")

    # --- BigDecimal, small operands, precision 28 (matches libmpdec) ---
    var a = BigDecimal("12345.6789")
    var b = BigDecimal("9876.54321")
    var wide = BigDecimal("1234.56789012345678901234567890")

    var best_add = 1.0e30
    var best_sub = 1.0e30
    var best_mul = 1.0e30
    var best_div = 1.0e30
    var best_round = 1.0e30
    var best_str = 1.0e30

    for _ in range(ROUNDS):
        var t0 = perf_counter_ns()
        for _ in range(ITERS):
            sink += Int(bd_arithmetics.add(a, b, 28).sign)
        var t1 = perf_counter_ns()
        best_add = min(best_add, Float64(Int(t1 - t0)) / Float64(ITERS))

        t0 = perf_counter_ns()
        for _ in range(ITERS):
            sink += Int(bd_arithmetics.subtract(a, b, 28).sign)
        t1 = perf_counter_ns()
        best_sub = min(best_sub, Float64(Int(t1 - t0)) / Float64(ITERS))

        t0 = perf_counter_ns()
        for _ in range(ITERS):
            sink += Int(bd_arithmetics.multiply(a, b, 28).sign)
        t1 = perf_counter_ns()
        best_mul = min(best_mul, Float64(Int(t1 - t0)) / Float64(ITERS))

        t0 = perf_counter_ns()
        for _ in range(ITERS):
            sink += Int(bd_arithmetics.true_divide(a, b, 28).sign)
        t1 = perf_counter_ns()
        best_div = min(best_div, Float64(Int(t1 - t0)) / Float64(ITERS))

        t0 = perf_counter_ns()
        for _ in range(ITERS):
            sink += Int(
                bd_rounding.round(wide, 10, RoundingMode.ROUND_HALF_EVEN).sign
            )
        t1 = perf_counter_ns()
        best_round = min(best_round, Float64(Int(t1 - t0)) / Float64(ITERS))

        t0 = perf_counter_ns()
        for _ in range(ITERS):
            sink += Int(BigDecimal("12345.6789").sign)
        t1 = perf_counter_ns()
        best_str = min(best_str, Float64(Int(t1 - t0)) / Float64(ITERS))

    print('  "bigdecimal": {')
    print('    "add": ' + _num(best_add) + ",")
    print('    "subtract": ' + _num(best_sub) + ",")
    print('    "multiply": ' + _num(best_mul) + ",")
    print('    "divide": ' + _num(best_div) + ",")
    print('    "round": ' + _num(best_round) + ",")
    print('    "from_string": ' + _num(best_str))
    print("  },")

    # --- BigInt against CPython's int, at matched decimal widths ---
    var sizes = [100, 1000, 10000, 100000]
    print('  "bigint": {')
    for si in range(len(sizes)):
        var n_digits = sizes[si]
        var x = BigInt(_digits(n_digits))
        var y = BigInt(_digits(n_digits - 1))
        var reps = max(3, 20000000 // (n_digits * 4))

        var t_add = 1.0e30
        var t_mul = 1.0e30
        for _ in range(ROUNDS):
            var t0 = perf_counter_ns()
            for _ in range(reps):
                sink += Int((x + y).sign)
            var t1 = perf_counter_ns()
            t_add = min(t_add, Float64(Int(t1 - t0)) / Float64(reps))

            t0 = perf_counter_ns()
            for _ in range(reps):
                sink += Int((x * y).sign)
            t1 = perf_counter_ns()
            t_mul = min(t_mul, Float64(Int(t1 - t0)) / Float64(reps))

        var comma = "," if si < len(sizes) - 1 else ""
        print(
            '    "'
            + String(n_digits)
            + '": {"add": '
            + _num(t_add)
            + ', "multiply": '
            + _num(t_mul)
            + "}"
            + comma
        )
    print("  },")

    # --- pi ---
    var precisions = [100, 1000, 10000, 100000, 1000000]
    print('  "pi_digits_100": "' + String(bd_constants.pi(100)) + '",')
    print('  "pi": {')
    for pi_index in range(len(precisions)):
        var precision = precisions[pi_index]
        var pi_reps = 1
        if precision <= 1000:
            pi_reps = 200
        elif precision <= 10000:
            pi_reps = 20
        elif precision <= 100000:
            pi_reps = 3
        var best_pi = 1.0e30
        var pi_rounds = 3 if precision >= 100000 else ROUNDS
        for _ in range(pi_rounds):
            var t0 = perf_counter_ns()
            for _ in range(pi_reps):
                # The decimal string is part of the measurement, as it is
                # for mpmath and MPFR. Leaving it out would compare decimo's
                # computation against their computation *plus* a base
                # conversion, which is not the same question. decimo is
                # already base-10 internally, so this step is cheap for it --
                # but that is an advantage to be measured, not assumed.
                sink += String(bd_constants.pi(precision)).byte_length()
            var t1 = perf_counter_ns()
            best_pi = min(best_pi, Float64(Int(t1 - t0)) / Float64(pi_reps))
        var comma2 = "," if pi_index < len(precisions) - 1 else ""
        print('    "' + String(precision) + '": ' + _num(best_pi) + comma2)
    print("  }")
    print("}")

    if sink == -987654321:
        print("unreachable")
