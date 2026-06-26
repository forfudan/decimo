# ===----------------------------------------------------------------------=== #
# Test BigDecimal special functions (factorial)
# ===----------------------------------------------------------------------=== #

from std import testing
from decimo.bigdecimal.bigdecimal import BigDecimal


def test_factorial_exact() raises:
    """Test exact factorial (precision == 0)."""
    testing.assert_equal(String(BigDecimal(0).factorial()), "1")
    testing.assert_equal(String(BigDecimal(1).factorial()), "1")
    testing.assert_equal(String(BigDecimal(5).factorial()), "120")
    testing.assert_equal(String(BigDecimal(10).factorial()), "3628800")
    testing.assert_equal(
        String(BigDecimal(30).factorial()),
        "265252859812191058636308480000000",
    )


def test_factorial_integer_with_scale() raises:
    """Test that an integer value written with a fractional part (e.g.
    "5.00") is accepted."""
    testing.assert_equal(String(BigDecimal("5.00").factorial()), "120")


def test_factorial_rounded() raises:
    """Test the rounded mode returns `precision` significant digits."""
    testing.assert_equal(
        String(BigDecimal(30).factorial(10)), "2.652528598E+32"
    )


def test_factorial_non_integer_raises() raises:
    """Test that a non-integer argument raises."""
    var raised = False
    try:
        _ = BigDecimal("5.5").factorial()
    except:
        raised = True
    testing.assert_true(raised, "factorial of a non-integer should raise")


def test_factorial_negative_raises() raises:
    """Test that a negative argument raises."""
    var raised = False
    try:
        _ = BigDecimal(-1).factorial()
    except:
        raised = True
    testing.assert_true(raised, "factorial of a negative value should raise")


def test_factorial_too_large_raises() raises:
    """Test that an argument above the cap raises."""
    var raised = False
    try:
        _ = BigDecimal(2_000_000).factorial()  # above the 10^6 cap
    except:
        raised = True
    testing.assert_true(raised, "factorial above the cap should raise")


def test_permutation() raises:
    """Test permutation P(n, k) exact."""
    testing.assert_equal(String(BigDecimal(10).permutation(3)), "720")
    testing.assert_equal(String(BigDecimal(5).permutation(0)), "1")
    testing.assert_equal(String(BigDecimal(5).permutation(7)), "0")  # k > n


def test_permutation_rounded() raises:
    """Test permutation rounded mode."""
    testing.assert_equal(String(BigDecimal(10).permutation(3, 2)), "7.2E+2")


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
