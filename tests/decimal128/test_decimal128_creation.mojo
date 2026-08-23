"""
Test Decimal128 creation: from_string, from_int, from_float, and the
5-arg component constructor.

Consolidates the former test_decimal128_{from_string, from_int,
from_float}.mojo files. Each TOML data file is parsed exactly once per
test function (was repeatedly opened across many small test functions
before the consolidation). from_float has no TOML data file because all
of its checks are startswith-style.
"""

from std import testing
from decimo.toml.parser import TOMLDocument

from decimo import Dec128
from decimo import Decimal128
from decimo import BigDecimal
from decimo.tests import TestCase, parse_file, load_test_cases


comptime from_string_path = (
    "tests/decimal128/test_data/decimal128_from_string.toml"
)
comptime from_int_path = "tests/decimal128/test_data/decimal128_from_int.toml"


# ─────────────────────────────────────────────────────────────────────────────
# from_string (TOML-driven, single parse)
# ─────────────────────────────────────────────────────────────────────────────


def test_decimal128_from_string() raises:
    """Run all from_string TOML sections in a single parse."""
    var toml = parse_file(from_string_path)
    var count_wrong = 0

    var sections = [
        String("basic_integer_tests"),
        String("basic_decimal_tests"),
        String("negative_tests"),
        String("zero_variant_tests"),
        String("scientific_notation_tests"),
        String("formatting_variant_tests"),
        String("special_character_tests"),
        String("boundary_tests"),
        String("special_case_tests"),
    ]
    for section in sections:
        var test_cases = load_test_cases[unary=True](toml, section)
        for tc in test_cases:
            var result = Dec128.from_string(tc.a)
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

    testing.assert_equal(count_wrong, 0, "Some from_string test cases failed.")


def test_from_string_high_precision_truncation() raises:
    var long_decimal = Dec128.from_string(
        "0.11111111111111111111111111111111111"
    )
    testing.assert_true(String(long_decimal).startswith("0.11111111111"))


def test_from_string_boundary_large_scale() raises:
    var large = Dec128.from_string("9999999999999999999999999999.5")
    testing.assert_equal(String(large), "10000000000000000000000000000")


def test_from_string_invalid_inputs() raises:
    """Invalid input strings that should raise exceptions."""
    var caught = False
    try:
        var _empty = Dec128.from_string("")
        testing.assert_true(False, "Empty string should raise")
    except:
        caught = True
    testing.assert_true(caught)

    caught = False
    try:
        var _non_numeric = Dec128.from_string("abc")
        testing.assert_true(False, "Non-numeric string should raise")
    except:
        caught = True
    testing.assert_true(caught)

    caught = False
    try:
        var _multi_points = Dec128.from_string("1.2.3")
        testing.assert_true(False, "Multiple decimal points should raise")
    except:
        caught = True
    testing.assert_true(caught)

    caught = False
    try:
        var _invalid_exp = Dec128.from_string("1.23e")
        testing.assert_true(False, "Invalid scientific notation should raise")
    except:
        caught = True
    testing.assert_true(caught)

    caught = False
    try:
        var _mixed = Dec128.from_string("123a456")
        testing.assert_true(False, "Mixed digits/characters should raise")
    except:
        caught = True
    testing.assert_true(caught)

    caught = False
    try:
        var _space = Dec128.from_string("1 234")
        testing.assert_true(False, "Space in integer should raise")
    except:
        caught = True
    testing.assert_true(caught)


# Regression tests for PR #224 (exponent-overflow handling).
def test_from_string_e29_overflows() raises:
    with testing.assert_raises():
        _ = Dec128.from_string("1e29")


def test_from_string_e30_to_e57_overflow() raises:
    for e in range(30, 58):
        var s = "1e" + String(e)
        with testing.assert_raises():
            _ = Dec128.from_string(s)


def test_from_string_parser_off_by_one_e58_e589() raises:
    with testing.assert_raises():
        _ = Dec128.from_string("1e58")
    with testing.assert_raises():
        _ = Dec128.from_string("1e589")
    with testing.assert_raises():
        _ = Dec128.from_string("1e1000000")


def test_from_string_neg_exponent_off_by_one() raises:
    var d = Dec128.from_string("1e-58")
    testing.assert_true(d == Dec128(0), "1e-58 should round to 0 at MAX_SCALE")


def test_from_string_scale_compensates_exponent() raises:
    var d = Dec128.from_string("0.000000000000000000000000000001e29")
    testing.assert_true(d == Dec128.from_string("0.1"))


def test_from_string_valid_e28_boundary() raises:
    var d = Dec128.from_string("1e28")
    testing.assert_true(
        d == Dec128.from_string("10000000000000000000000000000")
    )


# ─────────────────────────────────────────────────────────────────────────────
# from_int (TOML-driven, single parse) + 5-arg component constructor
# ─────────────────────────────────────────────────────────────────────────────


def test_decimal128_from_int() raises:
    """Run all from_int TOML sections in a single parse."""
    var toml = parse_file(from_int_path)
    var count_wrong = 0

    var unary_sections = [
        String("basic_integer_tests"),
        String("large_integer_tests"),
    ]
    for section in unary_sections:
        var cases = load_test_cases[unary=True](toml, section)
        for tc in cases:
            var result = Dec128.from_int(Int(tc.a))
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

    # from_int with scale: a=integer, b=scale
    var scale_cases = load_test_cases(toml, "from_int_with_scale_tests")
    for tc in scale_cases:
        var result = Dec128.from_int(Int(tc.a), UInt32(Int(tc.b)))
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

    testing.assert_equal(count_wrong, 0, "Some from_int test cases failed.")


def test_from_int_operations() raises:
    """Arithmetic operations using from_int results."""
    testing.assert_equal(
        String(Dec128.from_int(100) + Dec128.from_int(50)), "150"
    )
    testing.assert_equal(
        String(Dec128.from_int(100) - Dec128.from_int(30)), "70"
    )
    testing.assert_equal(
        String(Dec128.from_int(25) * Dec128.from_int(4)), "100"
    )
    testing.assert_equal(
        String(Dec128.from_int(100) / Dec128.from_int(5)), "20"
    )
    testing.assert_equal(String(Dec128.from_int(10) * Dec128("3.5")), "35.0")
    testing.assert_equal(String(Dec128.from_int(10) + Dec128.from_int(5)), "15")


def test_from_int_comparison() raises:
    """Comparison operations using from_int results."""
    testing.assert_true(Dec128.from_int(100) == Dec128.from_int(100))
    testing.assert_true(Dec128.from_int(123) == Dec128("123"))
    testing.assert_true(Dec128.from_int(50) < Dec128.from_int(100))
    testing.assert_true(Dec128.from_int(200) > Dec128.from_int(100))
    testing.assert_true(Dec128.from_int(-500) == Dec128("-500"))


def test_from_int_properties() raises:
    """Properties of from_int results."""
    testing.assert_false(Dec128.from_int(100).is_negative())
    testing.assert_true(Dec128.from_int(-100).is_negative())
    testing.assert_equal(Dec128.from_int(123).scale(), 0)
    testing.assert_true(Dec128.from_int(42).is_integer())
    testing.assert_equal(Dec128.from_int(9876).coefficient(), UInt128(9876))


def test_from_int_edge_cases() raises:
    """Edge cases for from_int."""
    testing.assert_equal(String(Dec128.from_int(0)), "0")

    var neg_zero = -0
    var dec_neg_zero = Dec128.from_int(neg_zero)
    testing.assert_false(
        dec_neg_zero.is_negative() and dec_neg_zero.is_zero(),
        "Negative zero should not preserve negative sign",
    )

    var int64_min = Dec128.from_int(-9223372036854775807 - 1)
    testing.assert_equal(String(int64_min), "-9223372036854775808")

    testing.assert_true(Dec128.from_int(12345) == Dec128("12345"))
    testing.assert_equal(String(Dec128.from_int(10**9)), "1000000000")


def test_from_int_with_scale_advanced() raises:
    """Inline checks for from_int with scale."""
    testing.assert_equal(Dec128.from_int(123, 2).scale(), 2)
    testing.assert_equal(Dec128.from_int(-456, 3).scale(), 3)
    testing.assert_equal(Dec128.from_int(0, 4).scale(), 4)
    testing.assert_equal(Dec128.from_int(1, 25).scale(), 25)
    testing.assert_equal(
        Dec128.from_int(1, UInt32(Decimal128.MAX_SCALE)).scale(),
        Decimal128.MAX_SCALE,
    )

    var a7 = Dec128.from_int(10, 1)
    var b7 = Dec128.from_int(3, 2)
    testing.assert_equal(String(a7 / b7), "33.333333333333333333333333333")

    testing.assert_true(
        Dec128.from_int(123, 0) != Dec128.from_int(123, 2),
        "from_int(123, 0) != from_int(123, 2)",
    )


def test_decimal128_from_components() raises:
    """5-argument component constructor."""
    testing.assert_equal(String(Decimal128(0, 0, 0, 0, False)), "0")
    testing.assert_equal(String(Decimal128(1, 0, 0, 0, False)), "1")
    testing.assert_equal(String(Decimal128(1, 0, 0, 0, True)), "-1")
    testing.assert_equal(String(Decimal128(12345, 0, 0, 2, False)), "123.45")
    testing.assert_equal(String(Decimal128(12345, 0, 0, 2, True)), "-123.45")

    var large = Decimal128(0xFFFFFFFF, 5, 0, 0, False)
    var expected_large = Decimal128(String(0xFFFFFFFF + 5 * 4294967296))
    testing.assert_equal(String(large), String(expected_large))

    var high_scale = Decimal128(123, 0, 0, 10, False)
    testing.assert_equal(high_scale.scale(), 10)
    testing.assert_equal(String(high_scale), "0.0000000123")

    testing.assert_equal(
        String(Decimal128(123, 0, 0, 10, True)), "-0.0000000123"
    )

    testing.assert_false(Decimal128(0, 0, 0, 0, False).is_negative())
    testing.assert_false(Decimal128(1, 0, 0, 0, False).is_negative())
    testing.assert_true(Decimal128(1, 0, 0, 0, True).is_negative())

    testing.assert_equal(
        String(Decimal128(0, 0, 3, 0, False)), "55340232221128654848"
    )

    testing.assert_equal(Decimal128(123, 0, 0, 28, False).scale(), 28)

    try:
        var _overflow_scale = Decimal128(123, 0, 0, 100, False)
    except:
        pass


# ─────────────────────────────────────────────────────────────────────────────
# from_float (no TOML; all checks are startswith-style)
# ─────────────────────────────────────────────────────────────────────────────


def test_from_float_simple_integers() raises:
    testing.assert_equal(String(Dec128.from_float(0.0)), "0")
    testing.assert_equal(String(Dec128.from_float(1.0)), "1")
    testing.assert_equal(String(Dec128.from_float(10.0)), "10")
    testing.assert_equal(String(Dec128.from_float(100.0)), "100")
    testing.assert_equal(String(Dec128.from_float(1000.0)), "1000")


def test_from_float_simple_decimals() raises:
    testing.assert_equal(String(Dec128.from_float(0.5)), "0.5")
    testing.assert_equal(String(Dec128.from_float(0.25)), "0.25")
    testing.assert_equal(String(Dec128.from_float(1.5)), "1.5")
    testing.assert_true(String(Dec128.from_float(3.14)).startswith("3.14"))
    testing.assert_true(String(Dec128.from_float(2.71828)).startswith("2.7182"))


def test_from_float_negative_numbers() raises:
    testing.assert_equal(String(Dec128.from_float(-1.0)), "-1")
    testing.assert_equal(String(Dec128.from_float(-0.5)), "-0.5")
    testing.assert_true(
        String(Dec128.from_float(-123.456)).startswith("-123.45")
    )
    testing.assert_equal(String(Dec128.from_float(-0.0)), "0")
    testing.assert_true(
        String(Dec128.from_float(-999.999)).startswith("-999.99")
    )


def test_from_float_very_large_numbers() raises:
    testing.assert_equal(String(Dec128.from_float(1e10)), "10000000000")
    testing.assert_equal(String(Dec128.from_float(1e15)), "1000000000000000")
    testing.assert_equal(
        String(Dec128.from_float(9007199254740991.0)), "9007199254740991"
    )
    testing.assert_equal(
        String(Dec128.from_float(1e20)), "100000000000000000000"
    )
    testing.assert_true(
        String(Dec128.from_float(1.23456789e15)).startswith("1234567890000000")
    )


def test_from_float_very_small_numbers() raises:
    testing.assert_true(
        String(Dec128.from_float(1e-10)).startswith("0.00000000")
    )
    testing.assert_true(
        String(Dec128.from_float(1e-15)).startswith("0.000000000000001")
    )
    testing.assert_true(
        String(Dec128.from_float(1.234e-10)).startswith("0.0000000001")
    )
    testing.assert_true(
        String(Dec128.from_float(1e-20)).startswith("0.00000000000000000001")
    )
    testing.assert_true(String(Dec128.from_float(1e-310)).startswith("0."))


def test_from_float_binary_to_decimal_conversion() raises:
    testing.assert_true(String(Dec128.from_float(0.1)).startswith("0.1"))
    testing.assert_true(String(Dec128.from_float(0.2)).startswith("0.2"))
    testing.assert_true(String(Dec128.from_float(0.3)).startswith("0.3"))
    testing.assert_true(String(Dec128.from_float(0.1 + 0.2)).startswith("0.3"))
    testing.assert_true(String(Dec128.from_float(0.1)).startswith("0.1"))


def test_from_float_rounding_behavior() raises:
    testing.assert_true(
        String(Dec128.from_float(3.141592653589793)).startswith(
            "3.14159265358979"
        )
    )
    testing.assert_true(
        String(Dec128.from_float(1.0 / 3.0)).startswith("0.33333333")
    )
    testing.assert_true(
        String(Dec128.from_float(2.0 / 3.0)).startswith("0.66666666")
    )
    testing.assert_true(
        String(Dec128.from_float(123.456)).startswith("123.456")
    )
    testing.assert_true(
        String(Dec128.from_float(9.9999999999999999)).startswith("10")
    )


def test_from_float_special_values() raises:
    testing.assert_equal(String(Dec128.from_float(0.0)), "0")
    testing.assert_true(
        String(Dec128.from_float(2.220446049250313e-16)).startswith(
            "0.000000000000000"
        )
    )
    testing.assert_equal(String(Dec128.from_float(1024.0)), "1024")
    testing.assert_equal(String(Dec128.from_float(0.125)), "0.125")
    testing.assert_true(String(Dec128.from_float(9.9999)).startswith("9.9999"))


def test_from_float_scientific_notation() raises:
    testing.assert_equal(String(Dec128.from_float(1.23e5)), "123000")
    testing.assert_true(
        String(Dec128.from_float(4.56e-3)).startswith("0.00456")
    )
    testing.assert_equal(
        String(Dec128.from_float(1.0e20)), "100000000000000000000"
    )
    testing.assert_true(
        String(Dec128.from_float(1.0e-10)).startswith("0.00000000")
    )
    testing.assert_true(String(Dec128.from_float(5e20)).startswith("5"))


def test_from_float_boundary_cases() raises:
    testing.assert_equal(String(Dec128.from_float(1000.0)), "1000")
    testing.assert_equal(
        String(Dec128.from_float(9007199254740990.0)), "9007199254740990"
    )
    testing.assert_true(
        String(Dec128.from_float(9007199254740994.0)).startswith(
            "9007199254740"
        )
    )
    testing.assert_true(String(Dec128.from_float(123.000000)).startswith("123"))
    testing.assert_equal(String(Dec128.from_float(0.125)), "0.125")


def test_from_decimal_round_trip() raises:
    """Values whose canonical form already fits in Decimal128 should
    round-trip through `from_decimal()` byte-for-byte."""
    testing.assert_equal(String(Dec128.from_decimal(BigDecimal("0"))), "0")
    testing.assert_equal(String(Dec128.from_decimal(BigDecimal("1"))), "1")
    testing.assert_equal(String(Dec128.from_decimal(BigDecimal("-1"))), "-1")
    testing.assert_equal(
        String(Dec128.from_decimal(BigDecimal("3.14"))), "3.14"
    )
    testing.assert_equal(
        String(Dec128.from_decimal(BigDecimal("-3.14"))), "-3.14"
    )
    testing.assert_equal(String(Dec128.from_decimal(BigDecimal("0.1"))), "0.1")
    testing.assert_equal(
        String(
            Dec128.from_decimal(BigDecimal("1.2345678901234567890123456789"))
        ),
        "1.2345678901234567890123456789",
    )
    testing.assert_equal(
        String(Dec128.from_decimal(BigDecimal("9999999999999999999999999999"))),
        "9999999999999999999999999999",
    )


def test_from_decimal_banker_rounding() raises:
    """High-precision BigDecimal values should be quantised to 28 dp
    using banker's rounding (`ROUND_HALF_EVEN`)."""
    # 35 fractional digits → must round to 28.
    var pi35 = BigDecimal("3.14159265358979323846264338327950288")
    testing.assert_equal(
        String(Dec128.from_decimal(pi35)),
        "3.1415926535897932384626433833",
    )
    # Exact half, last kept digit even (2) → stays 2 (ROUND_HALF_EVEN).
    var half_even = BigDecimal("0.12345678901234567890123456785")
    testing.assert_equal(
        String(Dec128.from_decimal(half_even)),
        "0.1234567890123456789012345678",
    )
    # Exact half, last kept digit odd (3) → rounds up to 4.
    var half_up = BigDecimal("0.12345678901234567890123456735")
    testing.assert_equal(
        String(Dec128.from_decimal(half_up)),
        "0.1234567890123456789012345674",
    )


def test_from_decimal_overflow() raises:
    """Values whose integral part overflows the 96-bit coefficient
    must raise `OverflowError`. We assert on the error message
    substring (`"overflow"` from `OverflowError.__str__`) rather than a
    bare `try/except` so the test fails loudly if `from_decimal()` raises
    a different error type — e.g. a regression in `to_string(force_plain
    =True)` previously returned `"1"` for `BigDecimal("1e40")`, which
    `from_string()` happily parsed without raising at all.
    """
    var huge = BigDecimal("1e40")
    with testing.assert_raises(contains="Cannot fit Decimal128 coefficient"):
        var _d = Dec128.from_decimal(huge)


# ─────────────────────────────────────────────────────────────────────────────
# from_integral_scalar / from_float_scalar (parametric on dtype)
# ─────────────────────────────────────────────────────────────────────────────


def test_from_integral_scalar_widths() raises:
    """Every integral width lands on the same value as `from_int` would."""
    testing.assert_equal(
        String(Decimal128.from_integral_scalar(Int8(-123))), "-123"
    )
    testing.assert_equal(
        String(Decimal128.from_integral_scalar(Int8.MIN)), "-128"
    )
    testing.assert_equal(
        String(Decimal128.from_integral_scalar(UInt8.MAX)), "255"
    )
    testing.assert_equal(String(Decimal128.from_integral_scalar(Int32(0))), "0")
    testing.assert_equal(
        String(Decimal128.from_integral_scalar(Int64.MIN)),
        "-9223372036854775808",
    )
    testing.assert_equal(
        String(Decimal128.from_integral_scalar(UInt64.MAX)),
        "18446744073709551615",
    )


def test_from_integral_scalar_wide_types() raises:
    """128- and 256-bit scalars are the only ones that can overflow."""
    # The largest coefficient Decimal128 can hold, exactly.
    testing.assert_equal(
        String(Decimal128.from_integral_scalar(Decimal128.MAX_AS_UINT128)),
        "79228162514264337593543950335",
    )
    testing.assert_equal(
        String(Decimal128.from_integral_scalar(Decimal128.MAX_AS_INT128)),
        "79228162514264337593543950335",
    )
    testing.assert_equal(
        String(Decimal128.from_integral_scalar(-Decimal128.MAX_AS_INT128)),
        "-79228162514264337593543950335",
    )
    testing.assert_equal(
        String(Decimal128.from_integral_scalar(Int128(-7))), "-7"
    )

    # One past the top overflows, in both directions.
    with testing.assert_raises():
        var _a = Decimal128.from_integral_scalar(
            Decimal128.MAX_AS_UINT128 + UInt128(1)
        )
    with testing.assert_raises():
        var _b = Decimal128.from_integral_scalar(
            -Decimal128.MAX_AS_INT256 - Int256(1)
        )
    # Int256.MIN has no positive counterpart; it must be rejected, not negated.
    with testing.assert_raises():
        var _c = Decimal128.from_integral_scalar(Int256.MIN)


def test_from_float_scalar_narrower_types() raises:
    """Narrower binary formats widen to Float64 exactly."""
    # 0.5 and -2.5 are exact in every one of these formats.
    testing.assert_equal(
        String(Decimal128.from_float_scalar(Float16(0.5))), "0.5"
    )
    testing.assert_equal(
        String(Decimal128.from_float_scalar(BFloat16(0.5))), "0.5"
    )
    testing.assert_equal(
        String(Decimal128.from_float_scalar(Float32(0.5))), "0.5"
    )
    testing.assert_equal(
        String(Decimal128.from_float_scalar(Float64(0.5))), "0.5"
    )
    testing.assert_equal(
        String(Decimal128.from_float_scalar(Float16(-2.5))), "-2.5"
    )
    testing.assert_equal(
        String(Decimal128.from_float_scalar(Float32(-2.5))), "-2.5"
    )

    # Float16(0.1) is 819/8192 = 0.0999755859375, and that is what we get -
    # not the 0.1 the literal was written as.
    testing.assert_equal(
        String(Decimal128.from_float_scalar(Float16(0.1))), "0.0999755859375"
    )


def test_from_float_is_a_forwarding_alias() raises:
    """The deprecated `from_float` still agrees with `from_float_scalar`."""
    testing.assert_equal(
        String(Decimal128.from_float(Float64(3.25))),
        String(Decimal128.from_float_scalar(Float64(3.25))),
    )
    testing.assert_equal(
        String(Decimal128.from_float(Float64(-0.125))),
        String(Decimal128.from_float_scalar(Float32(-0.125))),
    )


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
