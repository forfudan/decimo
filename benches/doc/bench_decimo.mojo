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
from decimo.bigdecimal import exponential as bd_exponential
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


def _digits_seeded(count: Int, seed: Int) -> String:
    """A `count`-digit decimal string; same sequence as `bench_libmpdec.c`."""
    var out = String("")
    var state = seed
    var step = 31 if seed == 7 else 37
    var offset = 17 if seed == 7 else 11
    for _ in range(count):
        state = (state * step + offset) % 9
        out += String(state + 1)
    return out^


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

    # In-place forms, the fair counterpart to libmpdec writing into an `mpd_t`
    # allocated once. Comparing the out-of-place calls above against that would
    # be comparing two different operations.
    var best_add_inplace = 1.0e30
    var best_sub_inplace = 1.0e30
    var best_mul_inplace = 1.0e30
    for _ in range(ROUNDS):
        var acc = BigDecimal("12345.6789")
        var t0 = perf_counter_ns()
        for _ in range(ITERS):
            bd_arithmetics.add_inplace(acc, b, 28)
        var t1 = perf_counter_ns()
        best_add_inplace = min(
            best_add_inplace, Float64(Int(t1 - t0)) / Float64(ITERS)
        )
        sink += Int(acc.sign)

        var acc2 = BigDecimal("12345.6789")
        t0 = perf_counter_ns()
        for _ in range(ITERS):
            bd_arithmetics.subtract_inplace(acc2, b, 28)
        t1 = perf_counter_ns()
        best_sub_inplace = min(
            best_sub_inplace, Float64(Int(t1 - t0)) / Float64(ITERS)
        )
        sink += Int(acc2.sign)

        var acc3 = BigDecimal("1.0000001")
        t0 = perf_counter_ns()
        for _ in range(ITERS):
            bd_arithmetics.multiply_inplace(acc3, a, 28)
        t1 = perf_counter_ns()
        best_mul_inplace = min(
            best_mul_inplace, Float64(Int(t1 - t0)) / Float64(ITERS)
        )
        sink += Int(acc3.sign)

    print('  "bigdecimal_inplace": {')
    print('    "add": ' + _num(best_add_inplace) + ",")
    print('    "subtract": ' + _num(best_sub_inplace) + ",")
    print('    "multiply": ' + _num(best_mul_inplace))
    print("  },")

    print('  "bigdecimal": {')
    print('    "add": ' + _num(best_add) + ",")
    print('    "subtract": ' + _num(best_sub) + ",")
    print('    "multiply": ' + _num(best_mul) + ",")
    print('    "divide": ' + _num(best_div) + ",")
    print('    "round": ' + _num(best_round) + ",")
    print('    "from_string": ' + _num(best_str))
    print("  },")

    # --- Operand-size sweep, matching bench_libmpdec.c ---
    # One base-10^9 word says nothing about how either library scales, and both
    # switch to a transform for large operands, so this is where the crossover
    # shows up. Exact arithmetic (precision 0), except division, which needs a
    # finite target.
    var widths = [9, 100, 1000, 10000, 100000]
    print('  "sweep": {')
    for wi in range(len(widths)):
        var width = widths[wi]
        var sx = BigDecimal(_digits_seeded(width, 7))
        var sy = BigDecimal(_digits_seeded(width, 3))
        var iters = max(3, 2000000 // width)
        var sweep_rounds = 3 if width >= 10000 else ROUNDS

        var w_add = 1.0e30
        var w_mul = 1.0e30
        var w_div = 1.0e30
        for _ in range(sweep_rounds):
            var t0 = perf_counter_ns()
            for _ in range(iters):
                sink += Int(bd_arithmetics.add(sx, sy, 0).sign)
            var t1 = perf_counter_ns()
            w_add = min(w_add, Float64(Int(t1 - t0)) / Float64(iters))

            t0 = perf_counter_ns()
            for _ in range(iters):
                sink += Int(bd_arithmetics.multiply(sx, sy, 0).sign)
            t1 = perf_counter_ns()
            w_mul = min(w_mul, Float64(Int(t1 - t0)) / Float64(iters))

            t0 = perf_counter_ns()
            for _ in range(iters):
                sink += Int(bd_arithmetics.true_divide(sx, sy, width + 8).sign)
            t1 = perf_counter_ns()
            w_div = min(w_div, Float64(Int(t1 - t0)) / Float64(iters))

        var sweep_comma = "," if wi < len(widths) - 1 else ""
        print(
            '    "'
            + String(width)
            + '": {"add": '
            + _num(w_add)
            + ', "multiply": '
            + _num(w_mul)
            + ', "divide": '
            + _num(w_div)
            + "}"
            + sweep_comma
        )
    print("  },")

    # --- Higher-level operations, matching bench_libmpdec.c ---
    # Fixed set chosen before the results were seen: sqrt, exp, ln, power.
    var precs = [28, 100, 1000]
    var hx = BigDecimal("2.3456789")
    var hy = BigDecimal("1.5")
    print('  "higher": {')
    for hi in range(len(precs)):
        var prec = precs[hi]
        var hit = 200 if prec >= 1000 else (5000 if prec >= 100 else 20000)
        var hrounds = 3 if prec >= 1000 else ROUNDS
        var h_sqrt = 1.0e30
        var h_exp = 1.0e30
        var h_ln = 1.0e30
        var h_pow = 1.0e30
        for _ in range(hrounds):
            var t0 = perf_counter_ns()
            for _ in range(hit):
                sink += Int(bd_exponential.sqrt(hx, prec).sign)
            var t1 = perf_counter_ns()
            h_sqrt = min(h_sqrt, Float64(Int(t1 - t0)) / Float64(hit))

            t0 = perf_counter_ns()
            for _ in range(hit):
                sink += Int(bd_exponential.exp(hx, prec).sign)
            t1 = perf_counter_ns()
            h_exp = min(h_exp, Float64(Int(t1 - t0)) / Float64(hit))

            t0 = perf_counter_ns()
            for _ in range(hit):
                sink += Int(bd_exponential.ln(hx, prec).sign)
            t1 = perf_counter_ns()
            h_ln = min(h_ln, Float64(Int(t1 - t0)) / Float64(hit))

            t0 = perf_counter_ns()
            for _ in range(hit):
                sink += Int(bd_exponential.power(hx, hy, prec).sign)
            t1 = perf_counter_ns()
            h_pow = min(h_pow, Float64(Int(t1 - t0)) / Float64(hit))

        var hcomma = "," if hi < len(precs) - 1 else ""
        print(
            '    "'
            + String(prec)
            + '": {"sqrt": '
            + _num(h_sqrt)
            + ', "exp": '
            + _num(h_exp)
            + ', "ln": '
            + _num(h_ln)
            + ', "power": '
            + _num(h_pow)
            + "}"
            + hcomma
        )
    print("  },")

    # A digest of the sweep's 1000-digit product, so the generator can confirm
    # that decimo and libmpdec computed the same number. Without it, "exact
    # arithmetic on both sides" is an assumption rather than a check.
    var digest_product = bd_arithmetics.multiply(
        BigDecimal(_digits_seeded(1000, 7)),
        BigDecimal(_digits_seeded(1000, 3)),
        0,
    )
    var digest_text = String(digest_product)
    print(
        '  "sweep_digest": {"digits": '
        + String(digest_text.byte_length())
        + ', "tail": "'
        + String(digest_text[byte = digest_text.byte_length() - 24 :])
        + '"},'
    )

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
