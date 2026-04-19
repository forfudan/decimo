# ===----------------------------------------------------------------------=== #
# Test Rational basic functionality
# ===----------------------------------------------------------------------=== #

from std import testing
from std.testing import assert_true
from decimo.rational.rational import Rational
from decimo.bigint.bigint import BigInt


# ===----------------------------------------------------------------------=== #
# Construction
# ===----------------------------------------------------------------------=== #


def test_from_int() raises:
    """Test construction from Int."""
    var r = Rational(0)
    assert_true(r.is_zero(), "Rational(0) should be zero")
    assert_true(
        String(r) == "0", "Rational(0) should be '0', got: " + String(r)
    )

    var one = Rational(1)
    assert_true(
        String(one) == "1", "Rational(1) should be '1', got: " + String(one)
    )

    var neg = Rational(-5)
    assert_true(
        String(neg) == "-5", "Rational(-5) should be '-5', got: " + String(neg)
    )
    assert_true(neg.is_negative(), "-5 should be negative")

    print("  PASS: from_int")


def test_from_bigint() raises:
    """Test construction from BigInt (denominator = 1)."""
    var r = Rational(BigInt(42))
    assert_true(r.is_integer(), "Should be an integer")
    assert_true(String(r) == "42", "Rational(BigInt(42)) should be '42'")

    var neg = Rational(BigInt(-100))
    assert_true(
        String(neg) == "-100", "Rational(BigInt(-100)) should be '-100'"
    )

    print("  PASS: from_bigint")


def test_from_two_ints() raises:
    """Test construction from numerator and denominator."""
    var r = Rational(BigInt(3), BigInt(7))
    assert_true(String(r) == "3/7", "3/7 should be '3/7', got: " + String(r))

    # Auto-normalization
    var r2 = Rational(BigInt(6), BigInt(14))
    assert_true(
        String(r2) == "3/7",
        "6/14 should normalize to '3/7', got: " + String(r2),
    )

    # Negative denominator => sign moves to numerator
    var r3 = Rational(BigInt(3), BigInt(-7))
    assert_true(
        String(r3) == "-3/7",
        "3/(-7) should normalize to '-3/7', got: " + String(r3),
    )

    # Both negative => positive
    var r4 = Rational(BigInt(-6), BigInt(-14))
    assert_true(
        String(r4) == "3/7",
        "(-6)/(-14) should normalize to '3/7', got: " + String(r4),
    )

    # Zero numerator
    var r5 = Rational(BigInt(0), BigInt(999))
    assert_true(r5.is_zero(), "0/999 should be zero")
    assert_true(String(r5) == "0", "0/999 should be '0'")

    print("  PASS: from_two_ints")


def test_zero_denominator_raises() raises:
    """Test that zero denominator raises an error."""
    var raised = False
    try:
        var _r = Rational(BigInt(1), BigInt(0))
    except:
        raised = True
    assert_true(raised, "Zero denominator should raise")

    print("  PASS: zero_denominator_raises")


# ===----------------------------------------------------------------------=== #
# String / repr
# ===----------------------------------------------------------------------=== #


def test_str_and_repr() raises:
    """Test __str__ and __repr__."""
    var r = Rational(BigInt(3), BigInt(7))
    assert_true(String(r) == "3/7", "__str__ should be '3/7'")
    assert_true(
        r.__repr__() == "Rational(3, 7)",
        "__repr__ should be 'Rational(3, 7)', got: " + r.__repr__(),
    )

    var integer = Rational(5)
    assert_true(String(integer) == "5", "integer __str__ should be '5'")
    assert_true(
        integer.__repr__() == "Rational(5, 1)",
        "integer __repr__ should be 'Rational(5, 1)', got: "
        + integer.__repr__(),
    )

    print("  PASS: str_and_repr")


# ===----------------------------------------------------------------------=== #
# Comparison
# ===----------------------------------------------------------------------=== #


def test_equality() raises:
    """Test == and !=."""
    var a = Rational(BigInt(1), BigInt(2))
    var b = Rational(BigInt(2), BigInt(4))
    assert_true(a == b, "1/2 should equal 2/4")

    var c = Rational(BigInt(1), BigInt(3))
    assert_true(a != c, "1/2 should not equal 1/3")

    var d = Rational(0)
    var e = Rational(BigInt(0), BigInt(100))
    assert_true(d == e, "0 should equal 0/100")

    print("  PASS: equality")


def test_ordering() raises:
    """Test <, <=, >, >=."""
    var half = Rational(BigInt(1), BigInt(2))
    var third = Rational(BigInt(1), BigInt(3))
    var one = Rational(1)

    assert_true(third < half, "1/3 < 1/2")
    assert_true(half > third, "1/2 > 1/3")
    assert_true(third <= half, "1/3 <= 1/2")
    assert_true(half >= third, "1/2 >= 1/3")
    assert_true(half <= half, "1/2 <= 1/2")
    assert_true(half >= half, "1/2 >= 1/2")
    assert_true(half < one, "1/2 < 1")
    assert_true(one > half, "1 > 1/2")

    # Negative numbers
    var neg_half = Rational(BigInt(-1), BigInt(2))
    assert_true(neg_half < half, "-1/2 < 1/2")
    assert_true(neg_half < Rational(0), "-1/2 < 0")

    print("  PASS: ordering")


# ===----------------------------------------------------------------------=== #
# Unary operators
# ===----------------------------------------------------------------------=== #


def test_neg() raises:
    """Test negation."""
    var half = Rational(BigInt(1), BigInt(2))
    var neg_half = -half
    assert_true(
        String(neg_half) == "-1/2",
        "-1/2 should be '-1/2', got: " + String(neg_half),
    )

    var neg_neg = -neg_half
    assert_true(neg_neg == half, "--1/2 should equal 1/2")

    var zero = Rational(0)
    var neg_zero = -zero
    assert_true(neg_zero.is_zero(), "-0 should be zero")
    assert_true(String(neg_zero) == "0", "-0 should be '0'")

    print("  PASS: neg")


def test_abs() raises:
    """Test absolute value."""
    var neg = Rational(BigInt(-3), BigInt(7))
    var pos = abs(neg)
    assert_true(
        String(pos) == "3/7",
        "abs(-3/7) should be '3/7', got: " + String(pos),
    )

    var already_pos = Rational(BigInt(3), BigInt(7))
    assert_true(
        abs(already_pos) == already_pos, "abs of positive should be same"
    )

    print("  PASS: abs")


# ===----------------------------------------------------------------------=== #
# Arithmetic
# ===----------------------------------------------------------------------=== #


def test_add() raises:
    """Test addition."""
    var a = Rational(BigInt(1), BigInt(2))
    var b = Rational(BigInt(1), BigInt(3))
    var result = a + b
    assert_true(
        String(result) == "5/6",
        "1/2 + 1/3 should be '5/6', got: " + String(result),
    )

    # Adding to zero
    var zero = Rational(0)
    assert_true(a + zero == a, "x + 0 should be x")

    # Adding negatives
    var c = Rational(BigInt(-1), BigInt(6))
    var result2 = a + c
    assert_true(
        String(result2) == "1/3",
        "1/2 + (-1/6) should be '1/3', got: " + String(result2),
    )

    # Same denominator
    var d = Rational(BigInt(2), BigInt(5))
    var e = Rational(BigInt(1), BigInt(5))
    var result3 = d + e
    assert_true(
        String(result3) == "3/5",
        "2/5 + 1/5 should be '3/5', got: " + String(result3),
    )

    print("  PASS: add")


def test_sub() raises:
    """Test subtraction."""
    var a = Rational(BigInt(1), BigInt(2))
    var b = Rational(BigInt(1), BigInt(3))
    var result = a - b
    assert_true(
        String(result) == "1/6",
        "1/2 - 1/3 should be '1/6', got: " + String(result),
    )

    # Self subtraction = zero
    var result2 = a - a
    assert_true(result2.is_zero(), "x - x should be zero")

    print("  PASS: sub")


def test_mul() raises:
    """Test multiplication."""
    var a = Rational(BigInt(2), BigInt(3))
    var b = Rational(BigInt(3), BigInt(5))
    var result = a * b
    assert_true(
        String(result) == "2/5",
        "2/3 * 3/5 should be '2/5', got: " + String(result),
    )

    # Multiply by zero
    var zero = Rational(0)
    var result2 = a * zero
    assert_true(result2.is_zero(), "x * 0 should be zero")

    # Multiply by one
    var one = Rational(1)
    assert_true(a * one == a, "x * 1 should be x")

    # Multiply negatives
    var neg = Rational(BigInt(-1), BigInt(2))
    var result3 = neg * neg
    assert_true(
        String(result3) == "1/4",
        "(-1/2) * (-1/2) should be '1/4', got: " + String(result3),
    )

    print("  PASS: mul")


def test_truediv() raises:
    """Test true division."""
    var a = Rational(BigInt(2), BigInt(3))
    var b = Rational(BigInt(4), BigInt(5))
    var result = a / b
    assert_true(
        String(result) == "5/6",
        "2/3 / 4/5 should be '5/6', got: " + String(result),
    )

    # Division by one
    var one = Rational(1)
    assert_true(a / one == a, "x / 1 should be x")

    # Division by self
    var result2 = a / a
    assert_true(
        String(result2) == "1",
        "x / x should be '1', got: " + String(result2),
    )

    print("  PASS: truediv")


def test_truediv_by_zero_raises() raises:
    """Test that division by zero raises."""
    var a = Rational(BigInt(1), BigInt(2))
    var zero = Rational(0)
    var raised = False
    try:
        var _r = a / zero
    except:
        raised = True
    assert_true(raised, "Division by zero should raise")

    print("  PASS: truediv_by_zero_raises")


# ===----------------------------------------------------------------------=== #
# Query methods
# ===----------------------------------------------------------------------=== #


def test_query_methods() raises:
    """Test is_zero, is_integer, is_positive, is_negative, sign."""
    var zero = Rational(0)
    assert_true(zero.is_zero(), "0 should be zero")
    assert_true(zero.is_integer(), "0 should be integer")
    assert_true(not zero.is_positive(), "0 should not be positive")
    assert_true(not zero.is_negative(), "0 should not be negative")
    assert_true(zero.sign() == 0, "sign(0) should be 0")

    var pos = Rational(BigInt(3), BigInt(7))
    assert_true(not pos.is_zero(), "3/7 should not be zero")
    assert_true(not pos.is_integer(), "3/7 should not be integer")
    assert_true(pos.is_positive(), "3/7 should be positive")
    assert_true(pos.sign() == 1, "sign(3/7) should be 1")

    var neg = Rational(BigInt(-5), BigInt(3))
    assert_true(neg.is_negative(), "-5/3 should be negative")
    assert_true(neg.sign() == -1, "sign(-5/3) should be -1")

    var integer = Rational(42)
    assert_true(integer.is_integer(), "42 should be integer")

    print("  PASS: query_methods")


# ===----------------------------------------------------------------------=== #
# Reciprocal
# ===----------------------------------------------------------------------=== #


def test_reciprocal() raises:
    """Test reciprocal."""
    var r = Rational(BigInt(3), BigInt(7))
    var recip = r.reciprocal()
    assert_true(
        String(recip) == "7/3",
        "reciprocal of 3/7 should be '7/3', got: " + String(recip),
    )

    # Reciprocal of negative
    var neg = Rational(BigInt(-2), BigInt(5))
    var neg_recip = neg.reciprocal()
    assert_true(
        String(neg_recip) == "-5/2",
        "reciprocal of -2/5 should be '-5/2', got: " + String(neg_recip),
    )

    # Reciprocal of 1
    var one = Rational(1)
    var one_recip = one.reciprocal()
    assert_true(
        String(one_recip) == "1",
        "reciprocal of 1 should be '1', got: " + String(one_recip),
    )

    # Reciprocal of zero raises
    var zero = Rational(0)
    var raised = False
    try:
        var _r = zero.reciprocal()
    except:
        raised = True
    assert_true(raised, "reciprocal of zero should raise")

    print("  PASS: reciprocal")


# ===----------------------------------------------------------------------=== #
# Normalization edge cases
# ===----------------------------------------------------------------------=== #


def test_normalization() raises:
    """Test that normalization always produces lowest terms."""
    # Large common factor
    var r = Rational(BigInt(100), BigInt(200))
    assert_true(
        String(r) == "1/2",
        "100/200 should normalize to '1/2', got: " + String(r),
    )

    # Prime numerator and denominator
    var r2 = Rational(BigInt(7), BigInt(13))
    assert_true(
        String(r2) == "7/13",
        "7/13 should stay '7/13', got: " + String(r2),
    )

    # Large GCD
    var r3 = Rational(BigInt(12345), BigInt(67890))
    # gcd(12345, 67890) = 3*5 = 15
    # 12345/15 = 823, 67890/15 = 4526
    assert_true(
        String(r3) == "823/4526",
        "12345/67890 should normalize to '823/4526', got: " + String(r3),
    )

    print("  PASS: normalization")


# ===----------------------------------------------------------------------=== #
# Constants
# ===----------------------------------------------------------------------=== #


def test_constants() raises:
    """Test predefined constants."""
    var zero = Rational.zero()
    assert_true(zero.is_zero(), "ZERO should be zero")

    var one = Rational.one()
    assert_true(String(one) == "1", "ONE should be '1'")

    var two = Rational.two()
    assert_true(String(two) == "2", "TWO should be '2'")

    var minus_one = Rational.minus_one()
    assert_true(String(minus_one) == "-1", "MINUS_ONE should be '-1'")
    assert_true(minus_one.is_negative(), "MINUS_ONE should be negative")

    var half = Rational.one_half()
    assert_true(String(half) == "1/2", "ONE_HALF should be '1/2'")

    var third = Rational.one_third()
    assert_true(String(third) == "1/3", "ONE_THIRD should be '1/3'")

    print("  PASS: constants")


# ===----------------------------------------------------------------------=== #
# Main
# ===----------------------------------------------------------------------=== #


def main() raises:
    print("Testing Rational basic functionality...")
    test_from_int()
    test_from_bigint()
    test_from_two_ints()
    test_zero_denominator_raises()
    test_str_and_repr()
    test_equality()
    test_ordering()
    test_neg()
    test_abs()
    test_add()
    test_sub()
    test_mul()
    test_truediv()
    test_truediv_by_zero_raises()
    test_query_methods()
    test_reciprocal()
    test_normalization()
    test_constants()
    print("All Rational basic tests passed!")
