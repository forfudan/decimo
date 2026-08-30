"""
Test BigInt true in-place arithmetic operations: +=, -=, *=.

These tests verify that the in-place operators produce correct results
identical to the non-in-place operators, but mutate self.words directly
instead of creating a new BigInt.
"""

from std import testing

from decimo.bigint.bigint import BigInt


# ===----------------------------------------------------------------------=== #
# Test: __iadd__ (+=) with BigInt
# ===----------------------------------------------------------------------=== #


def test_iadd_basic() raises:
    """Basic iadd: positive + positive."""
    var x = BigInt(100)
    x += BigInt(23)
    testing.assert_equal(String(x), "123")


def test_iadd_zero_lhs() raises:
    """Iadd: 0 += other."""
    var x = BigInt(0)
    x += BigInt(42)
    testing.assert_equal(String(x), "42")


def test_iadd_zero_rhs() raises:
    """Iadd: x += 0 is no-op."""
    var x = BigInt(42)
    x += BigInt(0)
    testing.assert_equal(String(x), "42")


def test_iadd_both_zero() raises:
    """Iadd: 0 += 0 = 0."""
    var x = BigInt(0)
    x += BigInt(0)
    testing.assert_equal(String(x), "0")


def test_iadd_negative_result() raises:
    """Iadd with negative result: positive + negative where |neg| > |pos|."""
    var x = BigInt(10)
    x += BigInt(-30)
    testing.assert_equal(String(x), "-20")


def test_iadd_cancel_to_zero() raises:
    """Iadd: x + (-x) = 0."""
    var x = BigInt(42)
    x += BigInt(-42)
    testing.assert_equal(String(x), "0")


def test_iadd_both_negative() raises:
    """Iadd: negative + negative."""
    var x = BigInt(-10)
    x += BigInt(-20)
    testing.assert_equal(String(x), "-30")


def test_iadd_neg_plus_pos() raises:
    """Iadd: negative + positive where |pos| > |neg|."""
    var x = BigInt(-10)
    x += BigInt(30)
    testing.assert_equal(String(x), "20")


def test_iadd_carry_propagation() raises:
    """Iadd with carry: (2^32 - 1) + 1 = 2^32."""
    var x = BigInt("4294967295")
    x += BigInt(1)
    testing.assert_equal(String(x), "4294967296")


def test_iadd_large_values() raises:
    """Iadd with large multi-word values."""
    var x = BigInt("999999999999999999999999999999")
    x += BigInt(1)
    testing.assert_equal(String(x), "1000000000000000000000000000000")

    var y = BigInt("123456789012345678901234567890")
    y += BigInt("876543210987654321098765432110")
    testing.assert_equal(String(y), "1000000000000000000000000000000")


def test_iadd_matches_add() raises:
    """Iadd produces same result as add for various values."""

    def _check(a: String, b: String) raises:
        var expected = String(BigInt(a) + BigInt(b))
        var x = BigInt(a)
        x += BigInt(b)
        testing.assert_equal(String(x), expected)

    _check("0", "0")
    _check("1", "0")
    _check("0", "-1")
    _check("123", "456")
    _check("-123", "456")
    _check("123", "-456")
    _check("-123", "-456")
    _check("999999999999999999", "1")
    _check("-1000000000000000000", "999999999999999999")


# ===----------------------------------------------------------------------=== #
# Test: __iadd__ (+=) with Int
# ===----------------------------------------------------------------------=== #


def test_iadd_int_basic() raises:
    """Iadd with Int: positive + positive."""
    var x = BigInt(100)
    x += 23
    testing.assert_equal(String(x), "123")


def test_iadd_int_zero() raises:
    """Iadd with Int: x += 0 is no-op."""
    var x = BigInt(42)
    x += 0
    testing.assert_equal(String(x), "42")

    var y = BigInt(0)
    y += 42
    testing.assert_equal(String(y), "42")


def test_iadd_int_negative() raises:
    """Iadd with Int: adding negative Int."""
    var x = BigInt(10)
    x += -30
    testing.assert_equal(String(x), "-20")

    var y = BigInt(-10)
    y += 5
    testing.assert_equal(String(y), "-5")


def test_iadd_int_cancel() raises:
    """Iadd with Int: cancellation to zero."""
    var x = BigInt(42)
    x += -42
    testing.assert_equal(String(x), "0")

    var y = BigInt(-42)
    y += 42
    testing.assert_equal(String(y), "0")


def test_iadd_int_large_base() raises:
    """Iadd with Int: large BigInt + small Int."""
    var x = BigInt("999999999999999999999999999999")
    x += 1
    testing.assert_equal(String(x), "1000000000000000000000000000000")


def test_iadd_int_accumulator_loop() raises:
    """Iadd Int in a loop: simulate accumulator pattern."""
    var sum = BigInt(0)
    for i in range(1, 101):
        sum += i
    # Sum of 1..100 = 5050
    testing.assert_equal(String(sum), "5050")


# ===----------------------------------------------------------------------=== #
# Test: __isub__ (-=) with BigInt
# ===----------------------------------------------------------------------=== #


def test_isub_basic() raises:
    """Basic isub: positive - positive."""
    var x = BigInt(100)
    x -= BigInt(23)
    testing.assert_equal(String(x), "77")


def test_isub_zero_rhs() raises:
    """Isub: x -= 0 is no-op."""
    var x = BigInt(42)
    x -= BigInt(0)
    testing.assert_equal(String(x), "42")


def test_isub_zero_lhs() raises:
    """Isub: 0 -= other = -other."""
    var x = BigInt(0)
    x -= BigInt(42)
    testing.assert_equal(String(x), "-42")

    var y = BigInt(0)
    y -= BigInt(-42)
    testing.assert_equal(String(y), "42")


def test_isub_cancel_to_zero() raises:
    """Isub: x - x = 0."""
    var x = BigInt(42)
    x -= BigInt(42)
    testing.assert_equal(String(x), "0")


def test_isub_negative_result() raises:
    """Isub: positive - larger positive = negative."""
    var x = BigInt(10)
    x -= BigInt(30)
    testing.assert_equal(String(x), "-20")


def test_isub_both_negative() raises:
    """Isub: negative - negative."""
    # -10 - (-30) = -10 + 30 = 20
    var x = BigInt(-10)
    x -= BigInt(-30)
    testing.assert_equal(String(x), "20")

    # -30 - (-10) = -30 + 10 = -20
    var y = BigInt(-30)
    y -= BigInt(-10)
    testing.assert_equal(String(y), "-20")


def test_isub_borrow_propagation() raises:
    """Isub with borrow: 2^32 - 1 = 2^32 - 1."""
    var x = BigInt("4294967296")
    x -= BigInt(1)
    testing.assert_equal(String(x), "4294967295")


def test_isub_large_values() raises:
    """Isub with large multi-word values."""
    var x = BigInt("1000000000000000000000000000000")
    x -= BigInt(1)
    testing.assert_equal(String(x), "999999999999999999999999999999")


def test_isub_matches_sub() raises:
    """Isub produces same result as subtract for various values."""

    def _check(a: String, b: String) raises:
        var expected = String(BigInt(a) - BigInt(b))
        var x = BigInt(a)
        x -= BigInt(b)
        testing.assert_equal(String(x), expected)

    _check("0", "0")
    _check("1", "0")
    _check("0", "-1")
    _check("123", "456")
    _check("-123", "456")
    _check("123", "-456")
    _check("-123", "-456")
    _check("1000000000000000000", "1")
    _check("-1000000000000000000", "999999999999999999")


# ===----------------------------------------------------------------------=== #
# Test: __imul__ (*=) with BigInt
# ===----------------------------------------------------------------------=== #


def test_imul_basic() raises:
    """Basic imul: positive * positive."""
    var x = BigInt(12)
    x *= BigInt(10)
    testing.assert_equal(String(x), "120")


def test_imul_zero_lhs() raises:
    """Imul: 0 *= other = 0."""
    var x = BigInt(0)
    x *= BigInt(42)
    testing.assert_equal(String(x), "0")


def test_imul_zero_rhs() raises:
    """Imul: x *= 0 = 0."""
    var x = BigInt(42)
    x *= BigInt(0)
    testing.assert_equal(String(x), "0")


def test_imul_one() raises:
    """Imul: x *= 1 is no-op."""
    var x = BigInt(42)
    x *= BigInt(1)
    testing.assert_equal(String(x), "42")


def test_imul_minus_one() raises:
    """Imul: x *= -1 negates."""
    var x = BigInt(42)
    x *= BigInt(-1)
    testing.assert_equal(String(x), "-42")

    var y = BigInt(-42)
    y *= BigInt(-1)
    testing.assert_equal(String(y), "42")


def test_imul_sign_combinations() raises:
    """Imul: all sign combinations."""
    # pos * pos = pos
    var a = BigInt(7)
    a *= BigInt(6)
    testing.assert_equal(String(a), "42")

    # pos * neg = neg
    var b = BigInt(7)
    b *= BigInt(-6)
    testing.assert_equal(String(b), "-42")

    # neg * pos = neg
    var c = BigInt(-7)
    c *= BigInt(6)
    testing.assert_equal(String(c), "-42")

    # neg * neg = pos
    var d = BigInt(-7)
    d *= BigInt(-6)
    testing.assert_equal(String(d), "42")


def test_imul_carry_propagation() raises:
    """Imul with carry: (2^32 - 1) * (2^32 - 1)."""
    var x = BigInt("4294967295")
    x *= BigInt("4294967295")
    testing.assert_equal(String(x), "18446744065119617025")


def test_imul_large_values() raises:
    """Imul with large multi-word values."""
    var x = BigInt("123456789012345678901234567890")
    x *= BigInt("2")
    testing.assert_equal(String(x), "246913578024691357802469135780")


def test_imul_matches_mul() raises:
    """Imul produces same result as multiply for various values."""

    def _check(a: String, b: String) raises:
        var expected = String(BigInt(a) * BigInt(b))
        var x = BigInt(a)
        x *= BigInt(b)
        testing.assert_equal(String(x), expected)

    _check("0", "0")
    _check("1", "0")
    _check("0", "-1")
    _check("123", "456")
    _check("-123", "456")
    _check("123", "-456")
    _check("-123", "-456")
    _check("999999999", "999999999")
    _check("123456789012345678901234567890", "987654321098765432109876543210")


# ===----------------------------------------------------------------------=== #
# Test: chained in-place operations
# ===----------------------------------------------------------------------=== #


def test_chained_iadd() raises:
    """Multiple iadd operations in sequence."""
    var x = BigInt(0)
    x += BigInt(10)
    x += BigInt(20)
    x += BigInt(30)
    testing.assert_equal(String(x), "60")


def test_chained_isub() raises:
    """Multiple isub operations in sequence."""
    var x = BigInt(100)
    x -= BigInt(10)
    x -= BigInt(20)
    x -= BigInt(30)
    testing.assert_equal(String(x), "40")


def test_chained_imul() raises:
    """Multiple imul operations: factorial-like."""
    var x = BigInt(1)
    x *= BigInt(2)
    x *= BigInt(3)
    x *= BigInt(4)
    x *= BigInt(5)
    testing.assert_equal(String(x), "120")


def test_mixed_inplace() raises:
    """Mixed in-place operations."""
    var x = BigInt(10)
    x += BigInt(5)  # 15
    x *= BigInt(4)  # 60
    x -= BigInt(10)  # 50
    x += BigInt(-50)  # 0
    testing.assert_equal(String(x), "0")


def test_iadd_int_accumulator_vs_direct() raises:
    """Int iadd accumulator gives same result as direct computation."""
    # Compute 1 + 2 + ... + 1000 via iadd
    var sum_iadd = BigInt(0)
    for i in range(1, 1001):
        sum_iadd += i
    # n*(n+1)/2 = 500500
    testing.assert_equal(String(sum_iadd), "500500")


def test_imul_factorial_20() raises:
    """Compute 20! via repeated imul."""
    var factorial = BigInt(1)
    for i in range(2, 21):
        factorial *= BigInt(i)
    # 20! = 2432902008176640000
    testing.assert_equal(String(factorial), "2432902008176640000")


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
