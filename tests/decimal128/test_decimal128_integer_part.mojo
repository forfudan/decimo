"""
Tests for Decimal128 integer-part / fractional-part / sign helpers:
trunc(), floor(), ceil(), fract(), signum(), unpack().
"""

from std import testing

from decimo import Dec128


# ===----------------------------------------------------------------------=== #
# trunc()
# ===----------------------------------------------------------------------=== #


def test_trunc_positive_fraction() raises:
    testing.assert_equal(String(Dec128("3.7").trunc()), "3", "trunc(3.7)")
    testing.assert_equal(String(Dec128("3.999").trunc()), "3", "trunc(3.999)")
    testing.assert_equal(
        String(Dec128("0.999999999").trunc()), "0", "trunc(0.999999999)"
    )


def test_trunc_negative_fraction() raises:
    """Truncation rounds toward zero, NOT toward -inf. The sign is preserved
    even when the magnitude rounds to zero (signed-zero semantics, IEEE 754
    / IBM GDA)."""
    testing.assert_equal(String(Dec128("-3.7").trunc()), "-3", "trunc(-3.7)")
    testing.assert_equal(
        String(Dec128("-3.999").trunc()), "-3", "trunc(-3.999)"
    )
    testing.assert_equal(
        String(Dec128("-0.5").trunc()), "-0", "trunc(-0.5) -> -0 (signed)"
    )


def test_trunc_already_integer() raises:
    testing.assert_equal(String(Dec128("3").trunc()), "3", "trunc(3)")
    # Trailing zeros after the decimal point are still an integer numerically;
    # the result has scale 0.
    testing.assert_equal(String(Dec128("3.0").trunc()), "3", "trunc(3.0)")
    testing.assert_equal(String(Dec128("100").trunc()), "100", "trunc(100)")


def test_trunc_zero() raises:
    testing.assert_equal(String(Dec128("0").trunc()), "0", "trunc(0)")
    testing.assert_equal(String(Dec128("0.000").trunc()), "0", "trunc(0.000)")
    testing.assert_equal(String(Dec128("-0.5").trunc()), "-0", "trunc(-0.5)")


def test_trunc_large_value() raises:
    # MAX coefficient has 29 digits: 79228162514264337593543950335.
    # Take MAX-1 followed by .5 — trunc just drops the .5.
    var v = Dec128("79228162514264337593543950334.5")
    testing.assert_equal(
        String(v.trunc()),
        "79228162514264337593543950334",
        "trunc near max: drops .5",
    )


# ===----------------------------------------------------------------------=== #
# floor()
# ===----------------------------------------------------------------------=== #


def test_floor_positive() raises:
    testing.assert_equal(String(Dec128("3.7").floor()), "3", "floor(3.7)")
    testing.assert_equal(String(Dec128("3.0").floor()), "3", "floor(3.0)")
    testing.assert_equal(String(Dec128("3").floor()), "3", "floor(3)")


def test_floor_negative() raises:
    """Floor rounds toward -inf, so negative non-integers round AWAY from zero.
    """
    testing.assert_equal(String(Dec128("-3.2").floor()), "-4", "floor(-3.2)")
    testing.assert_equal(String(Dec128("-3.7").floor()), "-4", "floor(-3.7)")
    testing.assert_equal(
        String(Dec128("-0.001").floor()), "-1", "floor(-0.001)"
    )
    testing.assert_equal(String(Dec128("-3.0").floor()), "-3", "floor(-3.0)")


def test_floor_zero() raises:
    testing.assert_equal(String(Dec128("0").floor()), "0", "floor(0)")


# ===----------------------------------------------------------------------=== #
# ceil()
# ===----------------------------------------------------------------------=== #


def test_ceil_positive() raises:
    testing.assert_equal(String(Dec128("3.2").ceil()), "4", "ceil(3.2)")
    testing.assert_equal(String(Dec128("3.7").ceil()), "4", "ceil(3.7)")
    testing.assert_equal(String(Dec128("0.001").ceil()), "1", "ceil(0.001)")
    testing.assert_equal(String(Dec128("3.0").ceil()), "3", "ceil(3.0)")


def test_ceil_negative() raises:
    """Ceil rounds toward +inf, so negative non-integers round TOWARD zero.
    The sign of zero is preserved when the magnitude rounds to zero."""
    testing.assert_equal(String(Dec128("-3.7").ceil()), "-3", "ceil(-3.7)")
    testing.assert_equal(String(Dec128("-3.2").ceil()), "-3", "ceil(-3.2)")
    testing.assert_equal(String(Dec128("-0.5").ceil()), "-0", "ceil(-0.5)")


def test_ceil_zero() raises:
    testing.assert_equal(String(Dec128("0").ceil()), "0", "ceil(0)")


# ===----------------------------------------------------------------------=== #
# fract() — fractional part: self - self.trunc()
# ===----------------------------------------------------------------------=== #


def test_fract_positive() raises:
    testing.assert_equal(String(Dec128("3.75").fract()), "0.75", "fract(3.75)")
    testing.assert_equal(
        String(Dec128("0.123").fract()), "0.123", "fract(0.123)"
    )


def test_fract_negative() raises:
    """Fract preserves the sign of the input."""
    testing.assert_equal(
        String(Dec128("-3.75").fract()), "-0.75", "fract(-3.75)"
    )
    testing.assert_equal(
        String(Dec128("-0.123").fract()), "-0.123", "fract(-0.123)"
    )


def test_fract_integer() raises:
    """Fract of an integer is zero — but with the original scale preserved."""
    testing.assert_equal(String(Dec128("3").fract()), "0", "fract(3)")
    testing.assert_equal(
        String(Dec128("3.000").fract()), "0.000", "fract(3.000)"
    )
    testing.assert_equal(String(Dec128("-3").fract()), "0", "fract(-3)")


def test_fract_round_trip() raises:
    """Trunc(x) + fract(x) == x for every x."""
    var samples = [
        String("3.75"),
        String("-3.75"),
        String("0.123456789012345678901234567"),
        String("-0.123456789012345678901234567"),
        String("100"),
        String("0"),
        String("1.5"),
        String("-0.5"),
    ]
    for s in samples:
        var x = Dec128(s)
        var sum = x.trunc() + x.fract()
        testing.assert_equal(
            String(sum), s, "trunc + fract round-trip for " + s
        )


# ===----------------------------------------------------------------------=== #
# signum()
# ===----------------------------------------------------------------------=== #


def test_signum_positive() raises:
    testing.assert_equal(String(Dec128("3.7").signum()), "1", "signum(3.7)")
    testing.assert_equal(String(Dec128("0.001").signum()), "1", "signum(0.001)")
    testing.assert_equal(
        String(Dec128("79228162514264337593543950335").signum()),
        "1",
        "signum(MAX)",
    )


def test_signum_negative() raises:
    testing.assert_equal(String(Dec128("-3.7").signum()), "-1", "signum(-3.7)")
    testing.assert_equal(
        String(Dec128("-0.001").signum()), "-1", "signum(-0.001)"
    )


def test_signum_zero() raises:
    """All zero-valued Decimal128 forms (with any scale, any sign bit) signum to 0.
    """
    testing.assert_equal(String(Dec128("0").signum()), "0", "signum(0)")
    testing.assert_equal(String(Dec128("0.000").signum()), "0", "signum(0.000)")
    testing.assert_equal(String(Dec128("-0").signum()), "0", "signum(-0)")
    testing.assert_equal(
        String(Dec128("-0.000").signum()), "0", "signum(-0.000)"
    )


# ===----------------------------------------------------------------------=== #
# unpack() — (low, mid, high, scale, sign)
# ===----------------------------------------------------------------------=== #


def test_unpack_simple() raises:
    """123.45 → coefficient = 12345, scale = 2, sign = False."""
    var parts = Dec128("123.45").unpack()
    testing.assert_equal(Int(parts[0]), 12345, "low")
    testing.assert_equal(Int(parts[1]), 0, "mid")
    testing.assert_equal(Int(parts[2]), 0, "high")
    testing.assert_equal(Int(parts[3]), 2, "scale")
    testing.assert_equal(parts[4], False, "sign (positive)")


def test_unpack_negative() raises:
    """Negative numbers set the sign bit; the coefficient is unsigned."""
    var parts = Dec128("-123.45").unpack()
    testing.assert_equal(Int(parts[0]), 12345, "low")
    testing.assert_equal(Int(parts[1]), 0, "mid")
    testing.assert_equal(Int(parts[2]), 0, "high")
    testing.assert_equal(Int(parts[3]), 2, "scale")
    testing.assert_equal(parts[4], True, "sign (negative)")


def test_unpack_zero() raises:
    """Zero unpacks to all-zero coefficient; scale is preserved."""
    var parts = Dec128("0").unpack()
    testing.assert_equal(Int(parts[0]), 0, "low")
    testing.assert_equal(Int(parts[1]), 0, "mid")
    testing.assert_equal(Int(parts[2]), 0, "high")
    testing.assert_equal(Int(parts[3]), 0, "scale")
    testing.assert_equal(parts[4], False, "sign")

    var parts2 = Dec128("0.000").unpack()
    testing.assert_equal(Int(parts2[3]), 3, "scale of 0.000 is preserved")


def test_unpack_max_scale() raises:
    """A value with max scale (28) round-trips through unpack."""
    var v = Dec128("0." + "0" * 27 + "1")  # 1e-28
    var parts = v.unpack()
    testing.assert_equal(Int(parts[0]), 1, "low")
    testing.assert_equal(Int(parts[3]), 28, "scale (max)")
    testing.assert_equal(parts[4], False, "sign")


def test_unpack_high_word_used() raises:
    """A value larger than 2^64 uses the `high` word."""
    # 2^64 = 18446744073709551616
    var parts = Dec128("18446744073709551616").unpack()
    testing.assert_equal(Int(parts[0]), 0, "low (= 2^64 mod 2^32 = 0)")
    testing.assert_equal(Int(parts[1]), 0, "mid (= 2^64 mod 2^64 / 2^32 = 0)")
    testing.assert_equal(Int(parts[2]), 1, "high (= 2^64 / 2^64 = 1)")
    testing.assert_equal(Int(parts[3]), 0, "scale")
    testing.assert_equal(parts[4], False, "sign")


def test_unpack_negative_zero_preserves_sign() raises:
    """`Dec128("-0")` and `Dec128("-0.000")` retain `sign == True` and
    preserve scale through `unpack()`. Regression test for IEEE 754 /
    IBM GDA signed-zero semantics (PR #227 review)."""
    var parts = Dec128("-0").unpack()
    testing.assert_equal(Int(parts[0]), 0, "low")
    testing.assert_equal(Int(parts[1]), 0, "mid")
    testing.assert_equal(Int(parts[2]), 0, "high")
    testing.assert_equal(Int(parts[3]), 0, "scale of -0 is 0")
    testing.assert_equal(parts[4], True, "sign of -0 is negative")

    var parts2 = Dec128("-0.000").unpack()
    testing.assert_equal(Int(parts2[0]), 0, "low")
    testing.assert_equal(Int(parts2[1]), 0, "mid")
    testing.assert_equal(Int(parts2[2]), 0, "high")
    testing.assert_equal(Int(parts2[3]), 3, "scale of -0.000 is preserved")
    testing.assert_equal(parts2[4], True, "sign of -0.000 is negative")


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
