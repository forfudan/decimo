"""
Test BigInt comparison and utility methods: compare, compare_magnitudes,
is_one_or_minus_one, and __iadd__(Int).
"""

from std import testing

from decimo.bigint.bigint import BigInt


# ===----------------------------------------------------------------------=== #
# Test: is_one_or_minus_one
# ===----------------------------------------------------------------------=== #


def test_is_one_or_minus_one() raises:
    """Test is_one_or_minus_one method."""
    testing.assert_true(BigInt(1).is_one_or_minus_one(), "1 is ±1")
    testing.assert_true(BigInt(-1).is_one_or_minus_one(), "-1 is ±1")
    testing.assert_true(not BigInt(0).is_one_or_minus_one(), "0 is not ±1")
    testing.assert_true(not BigInt(2).is_one_or_minus_one(), "2 is not ±1")
    testing.assert_true(not BigInt(-2).is_one_or_minus_one(), "-2 is not ±1")


# ===----------------------------------------------------------------------=== #
# Test: compare / compare_magnitudes instance methods
# ===----------------------------------------------------------------------=== #


def test_compare_instance_method() raises:
    """Test compare() instance method."""
    testing.assert_equal(BigInt(5).compare(BigInt(3)), Int8(1))
    testing.assert_equal(BigInt(3).compare(BigInt(5)), Int8(-1))
    testing.assert_equal(BigInt(5).compare(BigInt(5)), Int8(0))
    testing.assert_equal(BigInt(-5).compare(BigInt(3)), Int8(-1))
    testing.assert_equal(BigInt(3).compare(BigInt(-5)), Int8(1))
    testing.assert_equal(BigInt(0).compare(BigInt(0)), Int8(0))


def test_compare_magnitudes_instance_method() raises:
    """Test compare_magnitudes() instance method."""
    testing.assert_equal(BigInt(5).compare_magnitudes(BigInt(3)), Int8(1))
    testing.assert_equal(BigInt(3).compare_magnitudes(BigInt(5)), Int8(-1))
    testing.assert_equal(BigInt(5).compare_magnitudes(BigInt(5)), Int8(0))

    # Magnitude comparison ignores sign
    testing.assert_equal(BigInt(-5).compare_magnitudes(BigInt(3)), Int8(1))
    testing.assert_equal(BigInt(-5).compare_magnitudes(BigInt(-3)), Int8(1))
    testing.assert_equal(BigInt(-5).compare_magnitudes(BigInt(-5)), Int8(0))


# ===----------------------------------------------------------------------=== #
# Test: __iadd__(Int)
# ===----------------------------------------------------------------------=== #


def test_iadd_int() raises:
    """Test optimized += with Int."""
    var x = BigInt(100)
    x += 1
    testing.assert_equal(String(x), "101")

    x += -1
    testing.assert_equal(String(x), "100")

    x += 0
    testing.assert_equal(String(x), "100")

    x += 999
    testing.assert_equal(String(x), "1099")


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
