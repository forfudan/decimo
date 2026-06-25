# ===----------------------------------------------------------------------=== #
# Test BigInt special functions (factorial)
# ===----------------------------------------------------------------------=== #

from std import testing
from decimo.bigint.bigint import BigInt


def test_factorial_basic() raises:
    """Test factorial of small non-negative integers."""
    testing.assert_equal(String(BigInt(0).factorial()), "1")
    testing.assert_equal(String(BigInt(1).factorial()), "1")
    testing.assert_equal(String(BigInt(2).factorial()), "2")
    testing.assert_equal(String(BigInt(5).factorial()), "120")
    testing.assert_equal(String(BigInt(10).factorial()), "3628800")
    testing.assert_equal(String(BigInt(20).factorial()), "2432902008176640000")


def test_factorial_large() raises:
    """Test factorial that exceeds 64-bit range."""
    testing.assert_equal(
        String(BigInt(25).factorial()), "15511210043330985984000000"
    )


def test_factorial_negative_raises() raises:
    """Test that a negative argument raises."""
    var raised = False
    try:
        _ = BigInt(-1).factorial()
    except:
        raised = True
    testing.assert_true(raised, "factorial of a negative value should raise")


def test_factorial_too_large_raises() raises:
    """Test that an argument above the cap raises."""
    var raised = False
    try:
        _ = BigInt(2_000_000).factorial()  # above the 10^6 cap
    except:
        raised = True
    testing.assert_true(raised, "factorial above the cap should raise")


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
