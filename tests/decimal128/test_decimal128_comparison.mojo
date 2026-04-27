"""
Test Decimal128 comparison operations including:

1. equality / inequality (function-based and operator-based)
2. greater / greater_equal / less / less_equal
3. zero comparison edge cases
4. edge cases (transitivity, precision)
5. exact comparison with trailing zeros
6. min / max / clamp
"""

from std import testing

from decimo import Dec128
from decimo import Decimal128
from decimo.decimal128.comparison import (
    greater,
    greater_equal,
    less,
    less_equal,
    equal,
    not_equal,
    max,
    min,
    clamp,
)


def test_equality() raises:
    """Test equality comparisons."""
    testing.assert_true(equal(Decimal128(12345, 2), Decimal128(12345, 2)))
    testing.assert_true(equal(Dec128("123.450"), Decimal128(12345, 2)))
    testing.assert_false(equal(Decimal128(12345, 2), Dec128("123.46")))
    testing.assert_true(equal(Dec128(0), Dec128("0.00")))
    testing.assert_true(equal(Dec128(0), Dec128("-0")))
    testing.assert_false(equal(Decimal128(12345, 2), Dec128("-123.45")))


def test_inequality() raises:
    """Test inequality comparisons."""
    testing.assert_false(not_equal(Decimal128(12345, 2), Decimal128(12345, 2)))
    testing.assert_false(not_equal(Decimal128(123450, 3), Decimal128(12345, 2)))
    testing.assert_true(not_equal(Decimal128(12345, 2), Decimal128(12346, 2)))
    testing.assert_true(not_equal(Decimal128(12345, 2), Decimal128(-12345, 2)))


def test_greater() raises:
    """Test greater-than comparisons."""
    testing.assert_true(greater(Decimal128(12346, 2), Decimal128(12345, 2)))
    testing.assert_false(greater(Decimal128(12345, 2), Decimal128(12346, 2)))
    testing.assert_false(greater(Decimal128(12345, 2), Decimal128(12345, 2)))
    testing.assert_true(greater(Decimal128(12345, 2), Decimal128(-12345, 2)))
    testing.assert_false(greater(Decimal128(-12345, 2), Decimal128(12345, 2)))
    testing.assert_true(greater(Dec128("-123.45"), Dec128("-123.46")))
    testing.assert_false(greater(Dec128(0), Decimal128(12345, 2)))
    testing.assert_true(greater(Dec128(0), Dec128("-123.45")))
    testing.assert_true(greater(Dec128("123.5"), Decimal128(12345, 2)))


def test_greater_equal() raises:
    """Test greater-or-equal comparisons."""
    testing.assert_true(greater_equal(Dec128("123.46"), Decimal128(12345, 2)))
    testing.assert_true(
        greater_equal(Decimal128(12345, 2), Decimal128(12345, 2))
    )
    testing.assert_true(greater_equal(Decimal128(12345, 2), Dec128("-123.45")))
    testing.assert_true(greater_equal(Dec128("123.450"), Decimal128(12345, 2)))
    testing.assert_false(greater_equal(Decimal128(12345, 2), Dec128("123.46")))


def test_less() raises:
    """Test less-than comparisons."""
    testing.assert_true(less(Decimal128(12345, 2), Dec128("123.46")))
    testing.assert_false(less(Decimal128(12345, 2), Decimal128(12345, 2)))
    testing.assert_true(less(Dec128("-123.45"), Decimal128(12345, 2)))
    testing.assert_true(less(Dec128("-123.46"), Dec128("-123.45")))
    testing.assert_true(less(Dec128(0), Decimal128(12345, 2)))


def test_less_equal() raises:
    """Test less-or-equal comparisons."""
    testing.assert_true(less_equal(Decimal128(12345, 2), Dec128("123.46")))
    testing.assert_true(less_equal(Decimal128(12345, 2), Decimal128(12345, 2)))
    testing.assert_true(less_equal(Dec128("-123.45"), Decimal128(12345, 2)))
    testing.assert_true(less_equal(Dec128("123.450"), Decimal128(12345, 2)))
    testing.assert_false(less_equal(Dec128("123.46"), Decimal128(12345, 2)))


def test_zero_comparison() raises:
    """Test zero comparison edge cases."""
    var zero = Dec128(0)
    var pos = Dec128("0.0000000000000000001")
    var neg = Dec128("-0.0000000000000000001")
    var zero_scale = Dec128("0.00000")
    var neg_zero = Dec128("-0")

    # Zero vs small positive
    testing.assert_false(greater(zero, pos))
    testing.assert_true(less(zero, pos))
    testing.assert_false(equal(zero, pos))

    # Zero vs small negative
    testing.assert_true(greater(zero, neg))
    testing.assert_false(less(zero, neg))
    testing.assert_false(equal(zero, neg))

    # Different zeros
    testing.assert_true(equal(zero, zero_scale))
    testing.assert_true(greater_equal(zero, zero_scale))
    testing.assert_true(less_equal(zero, zero_scale))

    # Negative zero
    testing.assert_true(equal(zero, neg_zero))
    testing.assert_true(greater_equal(zero, neg_zero))
    testing.assert_true(less_equal(zero, neg_zero))


def test_edge_cases() raises:
    """Test comparison edge cases."""
    # Very close values
    testing.assert_true(
        greater(
            Dec128("1.000000000000000000000000001"),
            Dec128("1.000000000000000000000000000"),
        )
    )

    # Very large values
    testing.assert_true(
        greater(
            Dec128("79228162514264337593543950335"),
            Dec128("79228162514264337593543950334"),
        )
    )

    # Very small neg vs very small pos
    testing.assert_true(
        less(Dec128("-0." + "0" * 27 + "1"), Dec128("0." + "0" * 27 + "1"))
    )

    # Transitivity
    testing.assert_true(greater(Dec128(1000), Dec128("0.001")))
    testing.assert_true(greater(Dec128("0.001"), Dec128("-0.001")))
    testing.assert_true(greater(Dec128("-0.001"), Dec128(-1000)))
    testing.assert_true(greater(Dec128(1000), Dec128(-1000)))

    # Max scale-difference boundary in the fractional branch.
    # Equal integer parts (both 0), scales differing by 28: this exercises
    # the worst-case `10**scale_diff` factor inside `compare_absolute`.
    # 0.0000000000000000000000000001 (scale 28) vs 0.1 (scale 1)
    testing.assert_true(
        less(
            Dec128("0." + "0" * 27 + "1"),
            Dec128("0.1"),
        )
    )
    # Same, equality with trailing-zero expansion across max scale_diff
    testing.assert_true(
        equal(
            Dec128("0.1"),
            Dec128("0.1" + "0" * 27),
        )
    )
    # Differ only in the 28th fractional digit (max scale_diff path)
    testing.assert_true(
        greater(
            Dec128("0.1" + "0" * 26 + "1"),
            Dec128("0.1"),
        )
    )


def test_exact_comparison() raises:
    """Test exact comparison with precision and trailing zeros."""
    # Zeros with different scales
    testing.assert_true(equal(Dec128(0), Dec128("0.0")))
    testing.assert_true(equal(Dec128(0), Dec128("0.00000")))
    testing.assert_true(equal(Dec128("0.0"), Dec128("0.00000")))

    # Equal values with trailing zeros
    testing.assert_true(equal(Dec128("123.400"), Dec128("123.4")))
    testing.assert_true(equal(Dec128("123.4"), Dec128("123.40000")))
    testing.assert_true(equal(Dec128("123.400"), Dec128("123.40000")))

    # Close but different
    testing.assert_false(equal(Dec128("1.2"), Dec128("1.20000001")))
    testing.assert_true(less(Dec128("1.2"), Dec128("1.20000001")))


def test_comparison_operators() raises:
    """Test comparison operator overloads."""
    var a = Decimal128(12345, 2)  # 123.45
    var b = Dec128("67.89")
    var c = Decimal128(12345, 2)
    var d = Dec128("123.450")
    var e = Dec128("-50.0")
    var f = Dec128(0)
    var g = Dec128("-0.0")

    # Greater than
    testing.assert_true(a > b)
    testing.assert_false(b > a)
    testing.assert_false(a > c)
    testing.assert_true(a > e)
    testing.assert_true(a > f)
    testing.assert_true(f > e)

    # Less than
    testing.assert_false(a < b)
    testing.assert_true(b < a)
    testing.assert_false(a < c)
    testing.assert_false(a < d)
    testing.assert_true(e < a)
    testing.assert_true(e < f)
    testing.assert_true(f < a)

    # Greater or equal
    testing.assert_true(a >= b)
    testing.assert_false(b >= a)
    testing.assert_true(a >= c)
    testing.assert_true(a >= d)
    testing.assert_true(f >= g)

    # Less or equal
    testing.assert_false(a <= b)
    testing.assert_true(b <= a)
    testing.assert_true(a <= c)
    testing.assert_true(a <= d)
    testing.assert_true(g <= f)

    # Equality / inequality
    testing.assert_false(a == b)
    testing.assert_true(a == c)
    testing.assert_true(a == d)
    testing.assert_true(f == g)
    testing.assert_true(a != b)
    testing.assert_false(a != c)
    testing.assert_false(f != g)


# ===----------------------------------------------------------------------=== #
# min / max / clamp
# ===----------------------------------------------------------------------=== #


def test_max() raises:
    """Test max() returns the larger of two values; equal values return `a`."""
    var a = Dec128("1.5")
    var b = Dec128("2.25")
    testing.assert_equal(String(max(a, b)), "2.25")
    testing.assert_equal(String(max(b, a)), "2.25")
    testing.assert_equal(String(a.max(b)), "2.25")
    # negatives
    testing.assert_equal(String(max(Dec128("-3"), Dec128("-7"))), "-3")
    # equal values: returns first arg, preserving its scale
    testing.assert_equal(String(max(Dec128("1.0"), Dec128("1.00"))), "1.0")
    testing.assert_equal(String(max(Dec128("1.00"), Dec128("1.0"))), "1.00")


def test_min() raises:
    """Test min() returns the smaller of two values; equal values return `a`."""
    var a = Dec128("1.5")
    var b = Dec128("2.25")
    testing.assert_equal(String(min(a, b)), "1.5")
    testing.assert_equal(String(min(b, a)), "1.5")
    testing.assert_equal(String(b.min(a)), "1.5")
    testing.assert_equal(String(min(Dec128("-3"), Dec128("-7"))), "-7")
    # equal values: returns first arg
    testing.assert_equal(String(min(Dec128("1.0"), Dec128("1.00"))), "1.0")


def test_min_max_zero() raises:
    """Test min/max with zeros of different scales and signs."""
    testing.assert_equal(String(max(Dec128("0"), Dec128("0.00"))), "0")
    testing.assert_equal(String(min(Dec128("-0"), Dec128("0"))), "-0")


def test_clamp_in_range() raises:
    """Test clamp() returns x unchanged when lower <= x <= upper."""
    var lo = Dec128("0")
    var hi = Dec128("10")
    var x = Dec128("3.14")
    testing.assert_equal(String(clamp(x, lo, hi)), "3.14")
    testing.assert_equal(String(x.clamp(lo, hi)), "3.14")


def test_clamp_below() raises:
    """Test clamp() returns lower when x < lower."""
    var lo = Dec128("0")
    var hi = Dec128("10")
    testing.assert_equal(String(clamp(Dec128("-5"), lo, hi)), "0")


def test_clamp_above() raises:
    """Test clamp() returns upper when x > upper."""
    var lo = Dec128("0")
    var hi = Dec128("10")
    testing.assert_equal(String(clamp(Dec128("99"), lo, hi)), "10")


def test_clamp_at_boundary() raises:
    """Test clamp() at exact boundary values."""
    var lo = Dec128("-1.5")
    var hi = Dec128("1.5")
    testing.assert_equal(String(clamp(lo, lo, hi)), "-1.5")
    testing.assert_equal(String(clamp(hi, lo, hi)), "1.5")


def test_clamp_invalid_bounds() raises:
    """Test clamp() raises when lower > upper."""
    var raised = False
    try:
        _ = clamp(Dec128("5"), Dec128("10"), Dec128("0"))
    except:
        raised = True
    testing.assert_true(raised, "clamp must raise when lower > upper")


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
