"""
Tests for Decimal128 integer-part / fractional-part / sign helpers and
the IEEE 754 / IBM GDA "preferred exponent" semantics for multiply and
divide.

Consolidates test_decimal128_{integer_part, preferred_exp}.mojo.
Neither file uses TOML.
"""

from std import testing

from decimo import Dec128


# ─────────────────────────────────────────────────────────────────────────────
# trunc()
# ─────────────────────────────────────────────────────────────────────────────


def test_trunc_positive_fraction() raises:
    testing.assert_equal(String(Dec128("3.7").trunc()), "3", "trunc(3.7)")
    testing.assert_equal(String(Dec128("3.999").trunc()), "3", "trunc(3.999)")
    testing.assert_equal(
        String(Dec128("0.999999999").trunc()), "0", "trunc(0.999999999)"
    )


def test_trunc_negative_fraction() raises:
    """Truncation rounds toward zero, NOT toward -inf."""
    testing.assert_equal(String(Dec128("-3.7").trunc()), "-3", "trunc(-3.7)")
    testing.assert_equal(
        String(Dec128("-3.999").trunc()), "-3", "trunc(-3.999)"
    )
    testing.assert_equal(
        String(Dec128("-0.5").trunc()), "-0", "trunc(-0.5) -> -0 (signed)"
    )


def test_trunc_already_integer() raises:
    testing.assert_equal(String(Dec128("3").trunc()), "3", "trunc(3)")
    testing.assert_equal(String(Dec128("3.0").trunc()), "3", "trunc(3.0)")
    testing.assert_equal(String(Dec128("100").trunc()), "100", "trunc(100)")


def test_trunc_zero() raises:
    testing.assert_equal(String(Dec128("0").trunc()), "0", "trunc(0)")
    testing.assert_equal(String(Dec128("0.000").trunc()), "0", "trunc(0.000)")
    testing.assert_equal(String(Dec128("-0.5").trunc()), "-0", "trunc(-0.5)")


def test_trunc_large_value() raises:
    var v = Dec128("79228162514264337593543950334.5")
    testing.assert_equal(
        String(v.trunc()),
        "79228162514264337593543950334",
        "trunc near max: drops .5",
    )


# ─────────────────────────────────────────────────────────────────────────────
# floor()
# ─────────────────────────────────────────────────────────────────────────────


def test_floor_positive() raises:
    testing.assert_equal(String(Dec128("3.7").floor()), "3")
    testing.assert_equal(String(Dec128("3.0").floor()), "3")
    testing.assert_equal(String(Dec128("3").floor()), "3")


def test_floor_negative() raises:
    testing.assert_equal(String(Dec128("-3.2").floor()), "-4")
    testing.assert_equal(String(Dec128("-3.7").floor()), "-4")
    testing.assert_equal(String(Dec128("-0.001").floor()), "-1")
    testing.assert_equal(String(Dec128("-3.0").floor()), "-3")


def test_floor_zero() raises:
    testing.assert_equal(String(Dec128("0").floor()), "0")


# ─────────────────────────────────────────────────────────────────────────────
# ceil()
# ─────────────────────────────────────────────────────────────────────────────


def test_ceil_positive() raises:
    testing.assert_equal(String(Dec128("3.2").ceil()), "4")
    testing.assert_equal(String(Dec128("3.7").ceil()), "4")
    testing.assert_equal(String(Dec128("0.001").ceil()), "1")
    testing.assert_equal(String(Dec128("3.0").ceil()), "3")


def test_ceil_negative() raises:
    testing.assert_equal(String(Dec128("-3.7").ceil()), "-3")
    testing.assert_equal(String(Dec128("-3.2").ceil()), "-3")
    testing.assert_equal(String(Dec128("-0.5").ceil()), "-0")


def test_ceil_zero() raises:
    testing.assert_equal(String(Dec128("0").ceil()), "0")


# ─────────────────────────────────────────────────────────────────────────────
# fract() — fractional part: self - self.trunc()
# ─────────────────────────────────────────────────────────────────────────────


def test_fract_positive() raises:
    testing.assert_equal(String(Dec128("3.75").fract()), "0.75")
    testing.assert_equal(String(Dec128("0.123").fract()), "0.123")


def test_fract_negative() raises:
    """Fract preserves the sign of the input."""
    testing.assert_equal(String(Dec128("-3.75").fract()), "-0.75")
    testing.assert_equal(String(Dec128("-0.123").fract()), "-0.123")


def test_fract_integer() raises:
    """Fract of an integer is zero — but with the original scale preserved."""
    testing.assert_equal(String(Dec128("3").fract()), "0")
    testing.assert_equal(String(Dec128("3.000").fract()), "0.000")
    testing.assert_equal(String(Dec128("-3").fract()), "0")


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


# ─────────────────────────────────────────────────────────────────────────────
# signum()
# ─────────────────────────────────────────────────────────────────────────────


def test_signum_positive() raises:
    testing.assert_equal(String(Dec128("3.7").signum()), "1")
    testing.assert_equal(String(Dec128("0.001").signum()), "1")
    testing.assert_equal(
        String(Dec128("79228162514264337593543950335").signum()), "1"
    )


def test_signum_negative() raises:
    testing.assert_equal(String(Dec128("-3.7").signum()), "-1")
    testing.assert_equal(String(Dec128("-0.001").signum()), "-1")


def test_signum_zero() raises:
    testing.assert_equal(String(Dec128("0").signum()), "0")
    testing.assert_equal(String(Dec128("0.000").signum()), "0")
    testing.assert_equal(String(Dec128("-0").signum()), "0")
    testing.assert_equal(String(Dec128("-0.000").signum()), "0")


# ─────────────────────────────────────────────────────────────────────────────
# unpack() — (low, mid, high, scale, sign)
# ─────────────────────────────────────────────────────────────────────────────


def test_unpack_simple() raises:
    var parts = Dec128("123.45").unpack()
    testing.assert_equal(Int(parts[0]), 12345, "low")
    testing.assert_equal(Int(parts[1]), 0, "mid")
    testing.assert_equal(Int(parts[2]), 0, "high")
    testing.assert_equal(Int(parts[3]), 2, "scale")
    testing.assert_equal(parts[4], False, "sign (positive)")


def test_unpack_negative() raises:
    var parts = Dec128("-123.45").unpack()
    testing.assert_equal(Int(parts[0]), 12345, "low")
    testing.assert_equal(Int(parts[1]), 0, "mid")
    testing.assert_equal(Int(parts[2]), 0, "high")
    testing.assert_equal(Int(parts[3]), 2, "scale")
    testing.assert_equal(parts[4], True, "sign (negative)")


def test_unpack_zero() raises:
    var parts = Dec128("0").unpack()
    testing.assert_equal(Int(parts[0]), 0, "low")
    testing.assert_equal(Int(parts[1]), 0, "mid")
    testing.assert_equal(Int(parts[2]), 0, "high")
    testing.assert_equal(Int(parts[3]), 0, "scale")
    testing.assert_equal(parts[4], False, "sign")

    var parts2 = Dec128("0.000").unpack()
    testing.assert_equal(Int(parts2[3]), 3, "scale of 0.000 is preserved")


def test_unpack_max_scale() raises:
    var v = Dec128("0." + "0" * 27 + "1")  # 1e-28
    var parts = v.unpack()
    testing.assert_equal(Int(parts[0]), 1, "low")
    testing.assert_equal(Int(parts[3]), 28, "scale (max)")
    testing.assert_equal(parts[4], False, "sign")


def test_unpack_high_word_used() raises:
    var parts = Dec128("18446744073709551616").unpack()
    testing.assert_equal(Int(parts[0]), 0, "low")
    testing.assert_equal(Int(parts[1]), 0, "mid")
    testing.assert_equal(Int(parts[2]), 1, "high")
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


# ─────────────────────────────────────────────────────────────────────────────
# Preferred-exponent semantics for multiply and divide (IEEE 754-2008 §3.3 /
# IBM GDA §4.1). Pinned to catch regressions toward `rust_decimal` behaviour.
# ─────────────────────────────────────────────────────────────────────────────


def test_multiply_by_zero_preserves_scale() raises:
    """123.45 * 0 must be '0.00' (preferred exponent = -2)."""
    var result = Dec128("123.45") * Dec128("0")
    testing.assert_equal(
        String(result),
        "0.00",
        "123.45 * 0 should preserve scale -2 per IEEE 754 §3.3",
    )


def test_multiply_by_zero_negative_exponent() raises:
    """Multiplying any value by zero adopts the sum of exponents."""
    var result = Dec128("1.234567") * Dec128("0")
    testing.assert_equal(String(result), "0.000000")

    var result2 = Dec128("0.0") * Dec128("0.000")
    testing.assert_equal(String(result2), "0.0000")


def test_multiply_zero_by_integer() raises:
    """0 * anything-with-positive-exponent stays at '0' (ideal exp = 0+0)."""
    var result = Dec128("0") * Dec128("123")
    testing.assert_equal(String(result), "0")


def test_divide_preferred_exponent_exact() raises:
    """10.5 / 2.5 must be '4.2' (NOT '4.20')."""
    var result = Dec128("10.5") / Dec128("2.5")
    testing.assert_equal(
        String(result),
        "4.2",
        "10.5 / 2.5 should be '4.2' (largest exp giving exact quotient)",
    )


def test_divide_preferred_exponent_negative() raises:
    """123.45 / -2 must be '-61.725' (exact at exp -3, smallest |exp|)."""
    var result = Dec128("123.45") / Dec128("-2")
    testing.assert_equal(String(result), "-61.725")


def test_divide_exact_integer_quotient() raises:
    """10 / 2 should be '5'."""
    var result = Dec128("10") / Dec128("2")
    testing.assert_equal(String(result), "5")


def test_divide_above_ideal_exponent() raises:
    """6.0 / 2 should hit ideal exponent -1 → '3.0'."""
    var result = Dec128("6.0") / Dec128("2")
    testing.assert_equal(String(result), "3.0")


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
