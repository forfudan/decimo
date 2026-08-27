"""Times decimo for `docs/benchmarks.md`. Emits JSON on stdout.

Reports the minimum over several rounds rather than the mean: noise on a
latency benchmark is one-sided, so the minimum is the stable estimator. The
operands and precisions match `bench_libmpdec.c` and `bench_python.py`.

    pixi run mojo run -I src -D ASSERT=none benches/doc/bench_decimo.mojo
"""

from std.time import perf_counter_ns

from decimo.bigdecimal.bigdecimal import BigDecimal
from decimo.bigdecimal import arithmetics as bd_arithmetics
from decimo.bigdecimal import rounding as bd_rounding
from decimo.bigdecimal import constants as bd_constants
from decimo.bigdecimal import exponential as bd_exponential
from decimo.bigint.bigint import BigInt
from decimo.bigint import exponential as bigint_exponential
from decimo.rounding_mode import RoundingMode

comptime ROUNDS = 7


def format_number(value: Float64) -> String:
    """Three decimal places, without pulling in a formatting library."""
    var scaled = Int(value * 1000.0 + 0.5)
    var whole = scaled // 1000
    var fraction = scaled % 1000
    var fraction_text = String(fraction)
    while fraction_text.byte_length() < 3:
        fraction_text = "0" + fraction_text
    return String(whole) + "." + fraction_text


def build_digits(count: Int, seed: Int) -> String:
    """A `count`-digit decimal string. Same sequence as the other benchmarks."""
    var out = String("")
    var state = seed
    var step = 31 if seed == 7 else 37
    var offset = 17 if seed == 7 else 11
    for _ in range(count):
        state = (state * step + offset) % 9
        out += String(state + 1)
    return out^


def main() raises -> None:
    var sink = 0
    print("{")
    print('  "library": "decimo",')

    # --- BigDecimal, operand width paired with the working precision ---
    var widths = [9, 1000, 100000, 1000000]
    var precisions = [28, 1000, 100000, 1000000]
    var iterations = [200000, 20000, 20, 2]
    var round_counts = [ROUNDS, ROUNDS, 3, 3]

    print('  "bigdecimal": {')
    for k in range(len(widths)):
        var width = widths[k]
        var precision = precisions[k]
        var iters = iterations[k]
        var rounds = round_counts[k]
        var text_x = build_digits(width, 7)
        var text_y = build_digits(width, 3)
        var x = BigDecimal(text_x)
        var y = BigDecimal(text_y)
        # Round away the low half of the operand. A fixed ten decimal places
        # would be a no-op on a million-digit integer.
        var round_to = -(width // 2)

        var best_add = 1.0e30
        var best_subtract = 1.0e30
        var best_multiply = 1.0e30
        var best_divide = 1.0e30
        var best_round = 1.0e30
        var best_parse = 1.0e30

        for _ in range(rounds):
            var t0 = perf_counter_ns()
            for _ in range(iters):
                sink += Int(bd_arithmetics.add(x, y, precision).sign)
            var t1 = perf_counter_ns()
            best_add = min(best_add, Float64(Int(t1 - t0)) / Float64(iters))

            t0 = perf_counter_ns()
            for _ in range(iters):
                sink += Int(bd_arithmetics.subtract(x, y, precision).sign)
            t1 = perf_counter_ns()
            best_subtract = min(
                best_subtract, Float64(Int(t1 - t0)) / Float64(iters)
            )

            t0 = perf_counter_ns()
            for _ in range(iters):
                sink += Int(bd_arithmetics.multiply(x, y, precision).sign)
            t1 = perf_counter_ns()
            best_multiply = min(
                best_multiply, Float64(Int(t1 - t0)) / Float64(iters)
            )

            t0 = perf_counter_ns()
            for _ in range(iters):
                sink += Int(bd_arithmetics.true_divide(x, y, precision).sign)
            t1 = perf_counter_ns()
            best_divide = min(
                best_divide, Float64(Int(t1 - t0)) / Float64(iters)
            )

            t0 = perf_counter_ns()
            for _ in range(iters):
                sink += Int(
                    bd_rounding.round(
                        x, round_to, RoundingMode.ROUND_HALF_EVEN
                    ).sign
                )
            t1 = perf_counter_ns()
            best_round = min(best_round, Float64(Int(t1 - t0)) / Float64(iters))

            t0 = perf_counter_ns()
            for _ in range(iters):
                sink += Int(BigDecimal(text_x).sign)
            t1 = perf_counter_ns()
            best_parse = min(best_parse, Float64(Int(t1 - t0)) / Float64(iters))

        var comma = "," if k < len(widths) - 1 else ""
        print(
            '    "'
            + String(width)
            + ":"
            + String(precision)
            + '": {"add": '
            + format_number(best_add)
            + ', "subtract": '
            + format_number(best_subtract)
            + ', "multiply": '
            + format_number(best_multiply)
            + ', "divide": '
            + format_number(best_divide)
            + ', "round": '
            + format_number(best_round)
            + ', "from_string": '
            + format_number(best_parse)
            + "}"
            + comma
        )
    print("  },")

    # --- In place. Measured but not rendered; feeds internal_notes. ---
    var small_a = BigDecimal("12345.6789")
    var small_b = BigDecimal("9876.54321")
    var best_add_inplace = 1.0e30
    var best_subtract_inplace = 1.0e30
    var best_multiply_inplace = 1.0e30
    for _ in range(ROUNDS):
        var accumulator = BigDecimal("12345.6789")
        var t0 = perf_counter_ns()
        for _ in range(200000):
            bd_arithmetics.add_inplace(accumulator, small_b, 28)
        var t1 = perf_counter_ns()
        best_add_inplace = min(
            best_add_inplace, Float64(Int(t1 - t0)) / 200000.0
        )
        sink += Int(accumulator.sign)

        var accumulator2 = BigDecimal("12345.6789")
        t0 = perf_counter_ns()
        for _ in range(200000):
            bd_arithmetics.subtract_inplace(accumulator2, small_b, 28)
        t1 = perf_counter_ns()
        best_subtract_inplace = min(
            best_subtract_inplace, Float64(Int(t1 - t0)) / 200000.0
        )
        sink += Int(accumulator2.sign)

        var accumulator3 = BigDecimal("1.0000001")
        t0 = perf_counter_ns()
        for _ in range(200000):
            bd_arithmetics.multiply_inplace(accumulator3, small_a, 28)
        t1 = perf_counter_ns()
        best_multiply_inplace = min(
            best_multiply_inplace, Float64(Int(t1 - t0)) / 200000.0
        )
        sink += Int(accumulator3.sign)

    print('  "bigdecimal_inplace": {')
    print('    "add": ' + format_number(best_add_inplace) + ",")
    print('    "subtract": ' + format_number(best_subtract_inplace) + ",")
    print('    "multiply": ' + format_number(best_multiply_inplace))
    print("  },")

    # --- sqrt, exp, ln, power ---
    var higher_precisions = [28, 100, 1000, 10000]
    var higher_iterations = [20000, 5000, 200, 1]
    var higher_rounds = [ROUNDS, ROUNDS, 3, 1]
    var base = BigDecimal("2.3456789")
    var exponent = BigDecimal("1.5")

    print('  "higher": {')
    for k in range(len(higher_precisions)):
        var precision = higher_precisions[k]
        var iters = higher_iterations[k]
        var rounds = higher_rounds[k]
        var best_sqrt = 1.0e30
        var best_exp = 1.0e30
        var best_ln = 1.0e30
        var best_power = 1.0e30
        for _ in range(rounds):
            var t0 = perf_counter_ns()
            for _ in range(iters):
                sink += Int(bd_exponential.sqrt(base, precision).sign)
            var t1 = perf_counter_ns()
            best_sqrt = min(best_sqrt, Float64(Int(t1 - t0)) / Float64(iters))

            t0 = perf_counter_ns()
            for _ in range(iters):
                sink += Int(bd_exponential.exp(base, precision).sign)
            t1 = perf_counter_ns()
            best_exp = min(best_exp, Float64(Int(t1 - t0)) / Float64(iters))

            t0 = perf_counter_ns()
            for _ in range(iters):
                sink += Int(bd_exponential.ln(base, precision).sign)
            t1 = perf_counter_ns()
            best_ln = min(best_ln, Float64(Int(t1 - t0)) / Float64(iters))

            t0 = perf_counter_ns()
            for _ in range(iters):
                sink += Int(
                    bd_exponential.power(base, exponent, precision).sign
                )
            t1 = perf_counter_ns()
            best_power = min(best_power, Float64(Int(t1 - t0)) / Float64(iters))

        var comma = "," if k < len(higher_precisions) - 1 else ""
        print(
            '    "'
            + String(precision)
            + '": {"sqrt": '
            + format_number(best_sqrt)
            + ', "exp": '
            + format_number(best_exp)
            + ', "ln": '
            + format_number(best_ln)
            + ', "power": '
            + format_number(best_power)
            + "}"
            + comma
        )
    print("  },")

    # --- BigInt against GMP and CPython's int ---
    #
    # The sink reads a word of the result, not its sign. Every operand here is
    # non-negative, so the sign is a constant the optimizer can see through,
    # and once `sqrt`'s correcting walks were provably terminating it deleted
    # the whole call: the two-word case read 1.75 ns instead of 9.5.
    var integer_widths = [10, 100, 1000, 10000, 100000, 1000000]
    var integer_iterations = [200000, 20000, 5000, 200, 20, 2]
    var integer_rounds = [ROUNDS, ROUNDS, ROUNDS, 5, 3, 3]

    print('  "bigint": {')
    for k in range(len(integer_widths)):
        var width = integer_widths[k]
        var iters = integer_iterations[k]
        var rounds = integer_rounds[k]
        var x = BigInt(build_digits(width, 7))
        var y = BigInt(build_digits(width, 3))
        # A 2n-by-n division. Dividing two operands of the same width gives a
        # one-word quotient and measures nothing.
        var wide = x * y

        var best_add = 1.0e30
        var best_multiply = 1.0e30
        var best_divide = 1.0e30
        var best_sqrt = 1.0e30
        for _ in range(rounds):
            var t0 = perf_counter_ns()
            for _ in range(iters):
                sink += Int((x + y).words[0])
            var t1 = perf_counter_ns()
            best_add = min(best_add, Float64(Int(t1 - t0)) / Float64(iters))

            t0 = perf_counter_ns()
            for _ in range(iters):
                sink += Int((x * y).words[0])
            t1 = perf_counter_ns()
            best_multiply = min(
                best_multiply, Float64(Int(t1 - t0)) / Float64(iters)
            )

            t0 = perf_counter_ns()
            for _ in range(iters):
                sink += Int((wide // y).words[0])
            t1 = perf_counter_ns()
            best_divide = min(
                best_divide, Float64(Int(t1 - t0)) / Float64(iters)
            )

            t0 = perf_counter_ns()
            for _ in range(iters):
                sink += Int(bigint_exponential.sqrt(x).words[0])
            t1 = perf_counter_ns()
            best_sqrt = min(best_sqrt, Float64(Int(t1 - t0)) / Float64(iters))

        var comma = "," if k < len(integer_widths) - 1 else ""
        print(
            '    "'
            + String(width)
            + '": {"add": '
            + format_number(best_add)
            + ', "multiply": '
            + format_number(best_multiply)
            + ', "floor_divide": '
            + format_number(best_divide)
            + ', "sqrt": '
            + format_number(best_sqrt)
            + "}"
            + comma
        )
    print("  },")

    # A digest of a 1000-digit product, so the generator can confirm that
    # decimo and libmpdec computed the same number rather than assuming it.
    var digest_product = bd_arithmetics.multiply(
        BigDecimal(build_digits(1000, 7)), BigDecimal(build_digits(1000, 3)), 0
    )
    var digest_text = String(digest_product)
    print(
        '  "sweep_digest": {"digits": '
        + String(digest_text.byte_length())
        + ', "tail": "'
        + String(digest_text[byte = digest_text.byte_length() - 24 :])
        + '"},'
    )

    # --- pi ---
    var pi_precisions = [100, 1000, 10000, 100000, 1000000]
    print('  "pi_digits_100": "' + String(bd_constants.pi(100)) + '",')
    print('  "pi": {')
    for k in range(len(pi_precisions)):
        var precision = pi_precisions[k]
        var reps = 1
        if precision <= 1000:
            reps = 200
        elif precision <= 10000:
            reps = 20
        elif precision <= 100000:
            reps = 3
        var best_pi = 1.0e30
        var rounds = 3 if precision >= 100000 else ROUNDS
        for _ in range(rounds):
            var t0 = perf_counter_ns()
            for _ in range(reps):
                # The decimal string is part of the measurement, as it is for
                # mpmath and MPFR. decimo is already base-10 internally, so
                # this step is cheap for it, but that is to be measured rather
                # than assumed.
                sink += String(bd_constants.pi(precision)).byte_length()
            var t1 = perf_counter_ns()
            best_pi = min(best_pi, Float64(Int(t1 - t0)) / Float64(reps))
        var comma = "," if k < len(pi_precisions) - 1 else ""
        print(
            '    "' + String(precision) + '": ' + format_number(best_pi) + comma
        )
    print("  }")
    print("}")

    if sink == -987654321:
        print("unreachable")
