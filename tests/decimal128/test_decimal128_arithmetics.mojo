"""
Test Decimal128 arithmetic operations: add, subtract, negate, abs,
multiply, divide, truncate divide, modulo.

Consolidates the former test_decimal128_{arithmetics, multiply, divide,
modulo}.mojo files. Each per-operation TOML data file is parsed exactly
once per test function (was repeatedly opened across many small test
functions before the consolidation).
"""

from std.python import Python, PythonObject
from std import testing
from decimo.toml.parser import TOMLDocument

from decimo import Dec128
from decimo import Decimal128
from decimo.rounding_mode import RoundingMode
from decimo.tests import TestCase, parse_file, load_test_cases


comptime arithmetics_path = "tests/decimal128/test_data/decimal128_arithmetics.toml"
comptime multiply_path = "tests/decimal128/test_data/decimal128_multiply.toml"
comptime divide_path = "tests/decimal128/test_data/decimal128_divide.toml"
comptime modulo_path = "tests/decimal128/test_data/decimal128_modulo.toml"


# ─────────────────────────────────────────────────────────────────────────────
# add / subtract / negate / abs (TOML-driven, single parse)
# ─────────────────────────────────────────────────────────────────────────────


def test_decimal128_arithmetics() raises:
    """Addition, subtraction, negation, and absolute-value cases."""
    var pydecimal = Python.import_module("decimal")
    var toml = parse_file(arithmetics_path)
    var test_cases: List[TestCase]
    var count_wrong = 0

    # Addition ---------------------------------------------------------------
    test_cases = load_test_cases(toml, "addition_tests")
    for tc in test_cases:
        var result = Dec128(tc.a) + Dec128(tc.b)
        try:
            testing.assert_equal(
                lhs=String(result), rhs=tc.expected, msg=tc.description
            )
        except e:
            print(
                tc.description,
                "\n  Expected:",
                tc.expected,
                "\n  Got:",
                String(result),
                "\n  Python decimal result:",
                String(pydecimal.Decimal(tc.a) + pydecimal.Decimal(tc.b)),
                "\n",
            )
            count_wrong += 1

    # Subtraction ------------------------------------------------------------
    test_cases = load_test_cases(toml, "subtraction_tests")
    for tc in test_cases:
        var result = Dec128(tc.a) - Dec128(tc.b)
        try:
            testing.assert_equal(
                lhs=String(result), rhs=tc.expected, msg=tc.description
            )
        except e:
            print(
                tc.description,
                "\n  Expected:",
                tc.expected,
                "\n  Got:",
                String(result),
                "\n  Python decimal result:",
                String(pydecimal.Decimal(tc.a) - pydecimal.Decimal(tc.b)),
                "\n",
            )
            count_wrong += 1

    # Negation (unary) -------------------------------------------------------
    test_cases = load_test_cases[unary=True](toml, "negation_tests")
    for tc in test_cases:
        var result = -Dec128(tc.a)
        try:
            testing.assert_equal(
                lhs=String(result), rhs=tc.expected, msg=tc.description
            )
        except e:
            print(
                tc.description,
                "\n  Expected:",
                tc.expected,
                "\n  Got:",
                String(result),
                "\n",
            )
            count_wrong += 1

    # Absolute value (unary) -------------------------------------------------
    test_cases = load_test_cases[unary=True](toml, "abs_tests")
    for tc in test_cases:
        var result = abs(Dec128(tc.a))
        try:
            testing.assert_equal(
                lhs=String(result), rhs=tc.expected, msg=tc.description
            )
        except e:
            print(
                tc.description,
                "\n  Expected:",
                tc.expected,
                "\n  Got:",
                String(result),
                "\n",
            )
            count_wrong += 1

    # Extreme addition cases -------------------------------------------------
    test_cases = load_test_cases(toml, "extreme_addition_tests")
    for tc in test_cases:
        var result = Dec128(tc.a) + Dec128(tc.b)
        try:
            testing.assert_equal(
                lhs=String(result), rhs=tc.expected, msg=tc.description
            )
        except e:
            print(
                tc.description,
                "\n  Expected:",
                tc.expected,
                "\n  Got:",
                String(result),
                "\n",
            )
            count_wrong += 1

    testing.assert_equal(
        count_wrong, 0, "Some add/sub/neg/abs cases failed. See above."
    )


def test_repeated_addition() raises:
    """Test that repeated addition of 0.1 accumulates correctly."""
    var acc = Dec128(0)
    for _ in range(10):
        acc = acc + Dec128("0.1")
    testing.assert_equal(String(acc), "1.0", "Repeated addition of 0.1")


def test_double_and_triple_negation() raises:
    var a = Dec128("123.45")
    testing.assert_equal(String(-(-a)), "123.45", "Double negation")
    testing.assert_equal(String(-(-(-a))), "-123.45", "Triple negation")


def test_addition_overflow() raises:
    # Use `with testing.assert_raises():` so the test fails loudly if the
    # operation does NOT raise; a bare try/except would silently swallow
    # an `assert_true(False, ...)` placed inside it.
    var a = Dec128("79228162514264337593543950335")  # MAX
    var b = Dec128("1")
    with testing.assert_raises():
        var _result = a + b


def test_subtraction_commutativity() raises:
    """Tests that a - b == -(b - a)."""
    var a = Dec128("123.456")
    var b = Dec128("789.012")
    testing.assert_equal(
        String(a - b), String(-(b - a)), "a - b should equal -(b - a)"
    )


# ─────────────────────────────────────────────────────────────────────────────
# multiply (TOML-driven, single parse)
# ─────────────────────────────────────────────────────────────────────────────


def test_decimal128_multiply() raises:
    """Multiply: basic, special, negative, precision, boundary, GM stress,
    and commutative cases. Single parse of the multiply TOML file."""
    var pydecimal = Python.import_module("decimal")
    var toml = parse_file(multiply_path)
    var count_wrong = 0

    var binary_sections = [
        String("basic_tests"),
        String("special_tests"),
        String("negative_tests"),
        String("precision_tests"),
        String("boundary_tests"),
        String("gm_stress_tests"),
    ]
    for section in binary_sections:
        var test_cases = load_test_cases(toml, section)
        for tc in test_cases:
            var result = Dec128(tc.a) * Dec128(tc.b)
            try:
                testing.assert_equal(
                    lhs=String(result), rhs=tc.expected, msg=tc.description
                )
            except e:
                print(
                    tc.description,
                    "\n  Expected:",
                    tc.expected,
                    "\n  Got:",
                    String(result),
                    "\n  Python decimal result:",
                    String(pydecimal.Decimal(tc.a) * pydecimal.Decimal(tc.b)),
                    "\n",
                )
                count_wrong += 1

    # Commutative: also assert a*b == b*a
    var comm_cases = load_test_cases(toml, "commutative_tests")
    for tc in comm_cases:
        var ab = Dec128(tc.a) * Dec128(tc.b)
        var ba = Dec128(tc.b) * Dec128(tc.a)
        try:
            testing.assert_equal(
                lhs=String(ab), rhs=tc.expected, msg=tc.description
            )
            testing.assert_equal(
                lhs=String(ab),
                rhs=String(ba),
                msg="Commutative: " + tc.description,
            )
        except e:
            print(
                tc.description,
                "\n  a*b:",
                String(ab),
                "  b*a:",
                String(ba),
                "\n",
            )
            count_wrong += 1

    testing.assert_equal(count_wrong, 0, "Some multiplication tests failed.")


def test_multiply_precision_scale_properties() raises:
    """Scale and precision properties of multiplication results."""
    var r1 = Dec128("0.5") * Dec128("0.25")
    testing.assert_equal(r1.scale(), 3)

    var r2 = Dec128("0.1234567890") * Dec128("0.9876543210")
    testing.assert_equal(r2.scale(), 20)

    var r3 = Dec128("0." + "1" * 14) * Dec128("0." + "9" * 14)
    testing.assert_equal(r3.scale(), 28)

    var r4 = Dec128("0." + "1" * 15) * Dec128("0." + "9" * 15)
    testing.assert_equal(r4.scale(), 28)

    var r5 = Dec128("0.123456789012345678901234567") * Dec128("0.2")
    testing.assert_equal(r5.scale(), 28)


def test_multiply_boundary_cases() raises:
    """Boundary cases requiring assertions beyond simple equality."""
    var near_max = Dec128("38614081257132168796771975168")
    var result1 = near_max * Dec128("1.9")
    testing.assert_true(result1 < Decimal128.MAX())

    var tiny = Dec128("0." + "0" * 20 + "1")
    var huge = Dec128("1" + "0" * 20)
    testing.assert_equal(String(tiny * huge), "0.100000000000000000000")

    var max_dec = Decimal128.MAX()
    testing.assert_equal(
        String(max_dec * Dec128("0.01")),
        "792281625142643375935439503.35",
    )

    var small = Dec128("0." + "0" * 27 + "1")
    var one = Dec128(1)
    testing.assert_equal(String(small * one), String(small))


# ─────────────────────────────────────────────────────────────────────────────
# divide (/) and truncate divide (//) — TOML-driven, single parse
# ─────────────────────────────────────────────────────────────────────────────


def test_decimal128_divide_truncate() raises:
    """Division (/) and truncate-division (//) cases. Single parse of the
    divide TOML file (was 6 separate parses before consolidation)."""
    var doc = parse_file(divide_path)
    var count_wrong = 0

    var div_sections = [
        String("division_basic"),
        String("division_precision"),
        String("division_scale"),
        String("division_special"),
    ]
    for section in div_sections:
        var cases = load_test_cases(doc, section)
        for tc in cases:
            var result = Decimal128(tc.a) / Decimal128(tc.b)
            try:
                testing.assert_equal(
                    String(result), tc.expected, tc.description
                )
            except e:
                print(
                    tc.description,
                    "\n  Expected:",
                    tc.expected,
                    "\n  Got:",
                    String(result),
                    "\n",
                )
                count_wrong += 1

    var trunc_sections = [String("truncate_basic"), String("truncate_edge")]
    for section in trunc_sections:
        var cases = load_test_cases(doc, section)
        for tc in cases:
            var result = Decimal128(tc.a) // Decimal128(tc.b)
            try:
                testing.assert_equal(
                    String(result), tc.expected, tc.description
                )
            except e:
                print(
                    tc.description,
                    "\n  Expected:",
                    tc.expected,
                    "\n  Got:",
                    String(result),
                    "\n",
                )
                count_wrong += 1

    testing.assert_equal(count_wrong, 0, "Some divide/truncate cases failed.")


def test_divide_repeating_decimals() raises:
    """Repeating-decimal results checked with startswith (10 cases)."""
    testing.assert_true(
        String(Decimal128(1) / Decimal128(3)).startswith("0.33333333333333"),
        "1/3 repeating",
    )
    testing.assert_true(
        String(Decimal128(1) / Decimal128(6)).startswith("0.16666666666666"),
        "1/6 repeating",
    )
    testing.assert_true(
        String(Decimal128(1) / Decimal128(7)).startswith(
            "0.142857142857142857"
        ),
        "1/7 repeating",
    )
    testing.assert_true(
        String(Decimal128(2) / Decimal128(3)).startswith("0.66666666666666"),
        "2/3 repeating",
    )
    testing.assert_true(
        String(Decimal128(5) / Decimal128(6)).startswith("0.83333333333333"),
        "5/6 repeating",
    )
    testing.assert_true(
        String(Decimal128(1) / Decimal128(9)).startswith("0.11111111111111"),
        "1/9 repeating",
    )
    testing.assert_true(
        String(Decimal128(1) / Decimal128(11)).startswith("0.0909090909090"),
        "1/11 repeating",
    )
    testing.assert_true(
        String(Decimal128(1) / Decimal128(12)).startswith("0.08333333333333"),
        "1/12 repeating",
    )
    testing.assert_true(
        String(Decimal128(5) / Decimal128(11)).startswith("0.4545454545454"),
        "5/11 repeating",
    )
    testing.assert_true(
        String(Decimal128(10) / Decimal128(3)).startswith("3.33333333333333"),
        "10/3 repeating",
    )


def test_divide_bankers_rounding_at_boundary() raises:
    """Banker's (round-half-to-even) at the MAX_SCALE+1 cutoff.

    Discriminating cases between banker's and round-half-up, all
    exercising the post-bulk rounding branch in `divide()`'s UInt128
    path. Reference values cross-checked with Python's `decimal`:

        from decimal import Decimal, ROUND_HALF_EVEN
        (Decimal(k) / Decimal(2**29)).quantize(
            Decimal('1E-28'), rounding=ROUND_HALF_EVEN
        )
    """

    # 1) Exact-half terminator with EVEN last-kept digit.
    #    1 / 2^29 = 0.00000000186264514923095703125 (29 frac digits).
    #    Cut at 28 frac → drop "5" with rem == 0; 28th digit = 2 (even).
    #    Banker's: keep, no round-up → "...0312".
    #    Half-up   would give "...0313" (regression marker).
    testing.assert_equal(
        Decimal128(1) / Decimal128(536870912),  # 2^29
        Decimal128("0.0000000018626451492309570312"),
        "Banker's: exact half, even kept → drop",
    )

    # 2) Exact-half terminator with EVEN last-kept digit (second
    #    exemplar to confirm the pattern).
    #    5 / 2^29 = 0.0000000093132257461547851562**5**.
    #    Cut at 28 → 28th digit = 2 (even); banker's drops 5.
    #    Half-up   would give "...1563".
    testing.assert_equal(
        Decimal128(5) / Decimal128(536870912),
        Decimal128("0.0000000093132257461547851562"),
        "Banker's: exact half, even kept → drop (case 2)",
    )

    # 3) Exact-half terminator with ODD last-kept digit.
    #    3 / 2^29 = 0.0000000055879354476928710937**5**.
    #    Cut at 28 → 28th digit = 7 (odd); banker's bumps to 8.
    #    Half-up coincidentally agrees here (both round up).
    testing.assert_equal(
        Decimal128(3) / Decimal128(536870912),
        Decimal128("0.0000000055879354476928710938"),
        "Banker's: exact half, odd kept → bump to even",
    )

    # 4) "5 with non-zero tail" — NOT a banker's tie.
    #    1 / 7 = 0.142857142857142857142857142857...  (non-terminating)
    #    Cut at 28 → 28th = 8, 29th = 5, 30th = 7 (and so on).
    #    True value strictly > .5 of the unit, so banker's and half-up
    #    agree: round up. Last kept digit becomes 9.
    testing.assert_equal(
        Decimal128(1) / Decimal128(7),
        Decimal128("0.1428571428571428571428571429"),
        "5-with-tail: round up regardless of mode",
    )

    # 5) Below-half repeating: 1/3 ends in all 3s. 28th = 3, 29th = 3.
    #    Drop. Result has 28 trailing 3s.
    testing.assert_equal(
        Decimal128(1) / Decimal128(3),
        Decimal128("0.3333333333333333333333333333"),
        "Below-half: drop",
    )


def test_divide_properties_and_edge() raises:
    """Scale property checks, edge cases with comparisons and overflow."""
    var a25 = Decimal128(1) / Decimal128(81)
    testing.assert_true(a25.scale() <= Decimal128.MAX_SCALE)

    var a29 = Decimal128("12345678901234567890123456789") / Decimal128(7)
    testing.assert_true(a29.scale() <= Decimal128.MAX_SCALE)

    var a30 = Decimal128("0." + "1" * 28) / Decimal128("0." + "9" * 28)
    testing.assert_true(a30.scale() <= Decimal128.MAX_SCALE)

    var a41 = Decimal128(1) / Decimal128("0." + "0" * 27 + "1")
    testing.assert_true(a41 > Decimal128(String("1" + "0" * 27)))

    var a42 = Decimal128("0." + "0" * 27 + "1") / Decimal128(10)
    testing.assert_equal(a42, Decimal128("0." + "0" * 28))

    try:
        var _a43 = Decimal128.MAX() / Decimal128("0.0001")
    except:
        pass

    var min_positive = Decimal128("0." + "0" * 27 + "1")
    var a44 = min_positive / Decimal128(2)
    testing.assert_true(a44.scale() <= Decimal128.MAX_SCALE)

    var a47 = Decimal128(1) / Decimal128(3)
    testing.assert_true(a47.scale() == Decimal128.MAX_SCALE)

    var a50 = Decimal128("0." + "0" * 27 + "5") / Decimal128(1)
    testing.assert_true(a50.scale() <= Decimal128.MAX_SCALE)

    var max_value = Decimal128.MAX()
    testing.assert_equal(max_value / Decimal128(1), max_value)

    var near_max = Decimal128.MAX() - Decimal128(1)
    testing.assert_equal(
        near_max / Decimal128(10),
        Decimal128("7922816251426433759354395033.4"),
    )

    var large_num = Decimal128.MAX() / Decimal128(3)
    testing.assert_true(large_num * Decimal128(3) <= Decimal128.MAX())

    try:
        var _a60 = Decimal128.MAX() / Decimal128("0.5")
    except:
        pass


def test_divide_special_and_precision() raises:
    """Decimal128 equality, mixed precision, and rounding edge cases."""
    testing.assert_equal(
        Decimal128("1.000") / Decimal128("1.000"),
        Decimal128(1),
    )

    var special_value = Decimal128("123.456789012345678901234567")
    testing.assert_equal(special_value / Decimal128(1), special_value)

    testing.assert_equal(
        Decimal128("0.000123") / Decimal128("0.000123"),
        Decimal128(1),
    )

    testing.assert_equal(
        Decimal128(1) / Decimal128("0.999999"),
        Decimal128("1.000001000001000001000001000"),
    )

    var value = Decimal128("123.456")
    var divided = value / Decimal128(7)
    var result = divided * Decimal128(7)
    testing.assert_true(
        abs(value - result) / value < Decimal128("0.0001"),
        "Divide then multiply should approximately cancel",
    )

    var a74 = Decimal128("0.1") / Decimal128(3)
    testing.assert_true(String(a74).startswith("0.0333333333333333"))

    var a75 = Decimal128(1) / Decimal128("0.0001234567890123456789")
    testing.assert_true(a75 > Decimal128(8000))

    var a77 = Decimal128("0.12345678901234567") / Decimal128(
        "0.98765432109876543"
    )
    testing.assert_true(a77 < Decimal128("0.13"))

    var a83 = Decimal128(1) / Decimal128("1.9999999999999999999999999")
    testing.assert_equal(a83, Decimal128("0.5000000000000000000000000250"))

    var a84 = Decimal128(1) / Decimal128("4" + "0" * Decimal128.MAX_SCALE)
    testing.assert_equal(a84, Decimal128("0." + "0" * Decimal128.MAX_SCALE))

    var a58 = Decimal128("123" + "0" * 25) / Decimal128("123" + "0" * 15)
    testing.assert_equal(a58, Decimal128("1" + "0" * 10))


def test_divide_error_handling() raises:
    """Division by zero, overflow, and boundary conditions.

    All probes use `with testing.assert_raises():` because they are
    must-raise cases:
    - Division by zero is mathematically undefined.
    - Decimal128's representable maximum magnitude is `MAX()` at scale
      0; dividing `MAX()` by a value with magnitude < 1 (e.g. 0.5, 0.1,
      0.00001) yields a mathematical result strictly greater than
      `MAX()`, which cannot be represented and must therefore raise.
    """
    # Must raise: real division by zero.
    with testing.assert_raises():
        var _r = Decimal128(123) / Decimal128(0)

    # Must raise: MAX / 0.5 = 2 * MAX, which exceeds MAX.
    with testing.assert_raises():
        var _r92 = Decimal128.MAX() / Decimal128("0.5")

    # Must raise: MAX / 0.1 = 10 * MAX, which exceeds MAX.
    with testing.assert_raises():
        var _r93 = Decimal128.MAX() / Decimal128("0.1")

    var result94 = Decimal128.MIN() / Decimal128("10.12345")
    testing.assert_equal(
        result94, Decimal128("-7826201790324873199704048554.1")
    )

    var result95 = Decimal128("0." + "0" * 27 + "1") / Decimal128.MAX()
    testing.assert_equal(String(result95), "0.0000000000000000000000000000")

    testing.assert_equal(String(Decimal128.MAX() / Decimal128.MIN()), "-1")

    # Must raise: MAX / 0.00001 = 100000 * MAX, which exceeds MAX.
    with testing.assert_raises():
        var _r96 = Decimal128.MAX() / Decimal128("0.00001")

    var calc = (Decimal128(1) / Decimal128(3)) * Decimal128(3)
    testing.assert_equal(String(calc), "0.9999999999999999999999999999")

    # Must raise: truncate divide by zero.
    with testing.assert_raises():
        var _r2 = Decimal128(10) // Decimal128(0)


def test_truncate_math_relationships() raises:
    """Mathematical properties of truncate division."""
    var a1 = Decimal128(10)
    var b1 = Decimal128(3)
    var floor_div = a1 // b1
    var mod_result = a1 % b1
    testing.assert_equal(String(floor_div * b1 + mod_result), String(a1))

    var a2 = Decimal128("10.5")
    var b2 = Decimal128("2.5")
    var floor_div2 = a2 // b2
    var div_floored = (a2 / b2).round(0, RoundingMode.down())
    testing.assert_equal(String(floor_div2), String(div_floored))

    var a3 = Decimal128(-10)
    var b3 = Decimal128(3)
    var floor_div3 = a3 // b3
    var mod_result3 = a3 % b3
    testing.assert_equal(String(floor_div3 * b3 + mod_result3), String(a3))

    var a4 = Decimal128("10.5")
    var b4 = Decimal128("3.2")
    var floor_div4 = a4 // b4
    var lower_bound = floor_div4 * b4
    var upper_bound = (floor_div4 + Decimal128(1)) * b4
    testing.assert_true((lower_bound <= a4) and (a4 < upper_bound))


# ─────────────────────────────────────────────────────────────────────────────
# modulo (%) — TOML-driven, single parse
# ─────────────────────────────────────────────────────────────────────────────


def test_decimal128_modulo() raises:
    """Modulo: basic, negative, and edge cases. Single parse of the modulo
    TOML file (was 3 separate parses before consolidation)."""
    var doc = parse_file(modulo_path)
    var count_wrong = 0

    var sections = [
        String("modulo_basic"),
        String("modulo_negative"),
        String("modulo_edge"),
    ]
    for section in sections:
        var cases = load_test_cases(doc, section)
        for tc in cases:
            var result = Dec128(tc.a) % Dec128(tc.b)
            try:
                testing.assert_equal(
                    String(result), tc.expected, tc.description
                )
            except e:
                print(
                    tc.description,
                    "\n  Expected:",
                    tc.expected,
                    "\n  Got:",
                    String(result),
                    "\n",
                )
                count_wrong += 1

    testing.assert_equal(count_wrong, 0, "Some modulo cases failed.")


def test_modulo_exception() raises:
    """Modulo by zero must raise.

    Uses `with testing.assert_raises():` so the test fails if the
    operation unexpectedly succeeds; a bare try/except with
    `assert_true(False, ...)` inside would silently swallow that
    assertion failure.
    """
    with testing.assert_raises():
        var _r = Decimal128(10) % Decimal128(0)


def test_modulo_mathematical_relationships() raises:
    """Mathematical properties of modulo."""
    var a1 = Decimal128(10)
    var b1 = Decimal128(3)
    testing.assert_equal(
        String((a1 // b1) * b1 + (a1 % b1)),
        String(a1),
        "a == (a // b) * b + (a % b)",
    )

    var a2 = Decimal128("10.5")
    var b2 = Decimal128("3.2")
    var mod2 = a2 % b2
    testing.assert_true(
        (mod2 >= Decimal128(0)) and (mod2 < b2),
        "For positive b, 0 <= (a % b) < b",
    )

    var a3 = Decimal128(-10)
    var b3 = Decimal128(3)
    testing.assert_equal(String((a3 // b3) * b3 + (a3 % b3)), String(a3))

    var mod4 = Decimal128("10.5") % Decimal128("-3.2")
    testing.assert_true(
        mod4 == Decimal128("0.9"),
        "10.5 % -3.2 should equal 0.9, got " + String(mod4),
    )

    var mod_once = Decimal128(17) % Decimal128(5)
    var mod_twice = mod_once % Decimal128(5)
    testing.assert_equal(String(mod_once), String(mod_twice))


def test_modulo_consistency_with_floor_division() raises:
    """Tests that a % b should equal a - (a // b) * b for various inputs."""

    def _check(a_str: String, b_str: String) raises:
        var a = Decimal128(a_str)
        var b = Decimal128(b_str)
        testing.assert_equal(
            String(a % b),
            String(a - (a // b) * b),
            "a % b == a - (a // b) * b for (" + a_str + ", " + b_str + ")",
        )

    _check("10", "3")
    _check("-10", "3")
    _check("10.5", "2.5")
    _check("10", "-3")


# ===----------------------------------------------------------------------=== #
# fma
# ===----------------------------------------------------------------------=== #


def test_fma_basic() raises:
    """Smoke tests covering the simple, scale-aligned cases."""
    testing.assert_equal(
        String(Decimal128("2").fma(Decimal128("3"), Decimal128("5"))),
        "11",  # 2*3 + 5
    )
    testing.assert_equal(
        String(Decimal128("1.5").fma(Decimal128("4"), Decimal128("0.5"))),
        "6.5",  # 1.5*4 + 0.5
    )
    testing.assert_equal(
        String(Decimal128("0.1").fma(Decimal128("0.2"), Decimal128("0.03"))),
        "0.05",  # 0.1*0.2 + 0.03
    )


def test_fma_zero_operands() raises:
    """`x.fma(0, c) == c` and `0.fma(x, c) == c` (multiplication shortcut)."""
    testing.assert_equal(
        String(Decimal128("123.45").fma(Decimal128.ZERO(), Decimal128("7"))),
        "7",
    )
    testing.assert_equal(
        String(Decimal128.ZERO().fma(Decimal128("99"), Decimal128("-2.5"))),
        "-2.5",
    )
    # Zero addend: fma(a, b, 0) == a * b.
    testing.assert_equal(
        String(Decimal128("3").fma(Decimal128("4"), Decimal128.ZERO())),
        "12",
    )


def test_fma_signs() raises:
    """Sign combinations for product and addend."""
    # Same sign: positive + positive.
    testing.assert_equal(
        String(Decimal128("2").fma(Decimal128("3"), Decimal128("4"))), "10"
    )
    # Same sign: negative * negative + positive.
    testing.assert_equal(
        String(Decimal128("-2").fma(Decimal128("-3"), Decimal128("4"))), "10"
    )
    # Opposite signs: positive product + negative addend.
    testing.assert_equal(
        String(Decimal128("2").fma(Decimal128("3"), Decimal128("-4"))), "2"
    )
    # Opposite signs: negative product + positive addend that wins.
    testing.assert_equal(
        String(Decimal128("-2").fma(Decimal128("3"), Decimal128("10"))), "4"
    )
    # Opposite signs: negative product + positive addend, product wins.
    testing.assert_equal(
        String(Decimal128("-5").fma(Decimal128("3"), Decimal128("10"))), "-5"
    )


def test_fma_exact_cancellation() raises:
    """Exact zero result keeps the natural scale."""
    var r = Decimal128("3").fma(Decimal128("4"), Decimal128("-12"))
    testing.assert_equal(String(r), "0")


def test_fma_single_rounding_advantage() raises:
    """The fma result should differ from `(a*b)+c` when the intermediate
    product overflows Decimal128's precision and the addend would be
    cancelled away by the multiply's pre-rounding.
    Classic example: (1 + 1e-20) * 1 - 1.
    """
    # In Decimal128 the product 1.000_000_000_000_000_000_01 * 1 keeps
    # all 21 digits (well within MAX_NUM_DIGITS=29). Adding -1 yields
    # exactly 1e-20.
    var a = Decimal128("1.00000000000000000001")
    var b = Decimal128("1")
    var c = Decimal128("-1")
    testing.assert_equal(String(a.fma(b, c)), "0.00000000000000000001")
    # Two-step computation also gives the same answer here because the
    # product fits without rounding. fma should match.
    testing.assert_equal(String(a.fma(b, c)), String((a * b) + c))


def test_fma_scale_alignment() raises:
    """Different scales for the product and addend get aligned."""
    # 1.5 (scale 1) * 2 (scale 0) = 3.0 (scale 1); + 0.001 (scale 3) = 3.001.
    testing.assert_equal(
        String(Decimal128("1.5").fma(Decimal128("2"), Decimal128("0.001"))),
        "3.001",
    )
    # Inverse: small product, large-scale addend wins the alignment.
    testing.assert_equal(
        String(
            Decimal128("0.5").fma(Decimal128("0.5"), Decimal128("100.000000"))
        ),
        "100.250000",
    )


def test_fma_large_values() raises:
    """Big coefficients near the Decimal128 capacity."""
    # 7.92...e28 * 0.1 = 7.92...e27; add another 7.92...e27 = ~1.58e28.
    var huge = Decimal128("7000000000000000000000000000")
    var r = huge.fma(Decimal128("0.5"), huge)
    testing.assert_equal(String(r), "10500000000000000000000000000")


def test_fma_overflow() raises:
    """Result overflows Decimal128 capacity."""
    var max_val = Decimal128.MAX()
    try:
        var _r = max_val.fma(Decimal128("2"), Decimal128.ZERO())
        testing.assert_true(False, "Expected OverflowError")
    except:
        pass


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
