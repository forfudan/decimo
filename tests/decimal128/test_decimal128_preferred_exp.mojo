"""
Regression tests pinning the IEEE 754-2008 / IBM General Decimal Arithmetic
"preferred exponent" semantics for multiply and divide.

Background (see docs/plans/decimal128_enhancement.md §6):

The cross-language harness flags trailing-zero / scale-string differences
between decimo's Decimal128 and `rust_decimal` on a handful of cases. On
every disputed case decimo, C# (`System.Decimal`) and VB.NET
(`System.Decimal`) AGREE, against `rust_decimal`. decimo follows IEEE
754-2008 §3.3 and the IBM General Decimal Arithmetic spec §4.1 — the
"preferred exponent" rules — matching the .NET BCL. `rust_decimal` is
the lone outlier.

These tests pin the canonical decimo output so that any regression
toward rust_decimal's behaviour is caught immediately.
"""

from std import testing

from decimo import Dec128


# ===----------------------------------------------------------------------=== #
# multiply: 123.45 * 0
#
# Per IEEE 754-2008, the ideal exponent of `multiply(a, b)` is
# `exp(a) + exp(b)`. For `123.45 * 0`:
#   exp(123.45) = -2,  exp(0) = 0  →  ideal exponent = -2.
# Therefore the canonical result is `0.00`, NOT `0`.
#
# decimo + .NET: `0.00`   (correct)
# rust_decimal:  `0`      (drops the scale)
# ===----------------------------------------------------------------------=== #


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
    # exp(1.234567) = -6, so ideal exp(1.234567 * 0) = -6
    var result = Dec128("1.234567") * Dec128("0")
    testing.assert_equal(
        String(result),
        "0.000000",
        "1.234567 * 0 should be '0.000000'",
    )

    # exp(0.0) = -1, exp(0.000) = -3, ideal sum = -4
    var result2 = Dec128("0.0") * Dec128("0.000")
    testing.assert_equal(
        String(result2),
        "0.0000",
        "0.0 * 0.000 should be '0.0000'",
    )


def test_multiply_zero_by_integer() raises:
    """0 * anything-with-positive-exponent stays at '0' (ideal exp = 0+0)."""
    var result = Dec128("0") * Dec128("123")
    testing.assert_equal(String(result), "0", "0 * 123 should be '0'")


# ===----------------------------------------------------------------------=== #
# divide: 10.5 / 2.5
#
# Ideal exponent of divide is `exp(a) - exp(b)`. For `10.5 / 2.5`:
#   exp(10.5) = -1, exp(2.5) = -1  →  ideal exponent = 0.
# The exact result `4.2` (at exp -1) is preferred over `4.20` (at exp -2)
# because exp -1 is the largest exponent that still represents the exact
# quotient.
#
# decimo + .NET: `4.2`
# rust_decimal:  `4.20`
# ===----------------------------------------------------------------------=== #


def test_divide_preferred_exponent_exact() raises:
    """10.5 / 2.5 must be '4.2' (NOT '4.20')."""
    var result = Dec128("10.5") / Dec128("2.5")
    testing.assert_equal(
        String(result),
        "4.2",
        "10.5 / 2.5 should be '4.2' (largest exp giving exact quotient)",
    )


def test_divide_preferred_exponent_negative() raises:
    """123.45 / -2 must be '-61.725' (exact) — exp -3 is required for exactness.

    Ideal exp = exp(123.45) - exp(-2) = -2 - 0 = -2. But the exact result
    `-61.725` requires exp -3, so we MUST go below the ideal. The choice is
    `-61.725` (exact at exp -3), not `-61.7250` (exact at exp -4).
    """
    var result = Dec128("123.45") / Dec128("-2")
    testing.assert_equal(
        String(result),
        "-61.725",
        "123.45 / -2 should be '-61.725' (smallest |exp| giving exactness)",
    )


def test_divide_exact_integer_quotient() raises:
    """10 / 2 should be '5' (ideal exp = 0; exact at exp 0)."""
    var result = Dec128("10") / Dec128("2")
    testing.assert_equal(String(result), "5", "10 / 2 should be '5'")


def test_divide_above_ideal_exponent() raises:
    """When the exact quotient has fewer fractional digits than the ideal
    exponent suggests, drop trailing zeros down to the ideal."""
    # exp(6.0) = -1, exp(2) = 0, ideal exp = -1. Quotient is 3, exact at
    # exp 0. The canonical form is `3.0` (matching ideal exp -1) since
    # we MUST hit at least the ideal, but we never go above it.
    var result = Dec128("6.0") / Dec128("2")
    testing.assert_equal(
        String(result),
        "3.0",
        "6.0 / 2 should hit ideal exponent -1 → '3.0'",
    )


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
