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


def test_factorial_crosses_leaf_cutoff() raises:
    """Test factorial large enough to exercise the binary-split branch."""
    # 40 > the 32-factor leaf cutoff, so this splits and recombines.
    testing.assert_equal(
        String(BigInt(40).factorial()),
        "815915283247897734345611269596115894272000000000",
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


def test_permutation() raises:
    """Test permutation P(n, k)."""
    testing.assert_equal(String(BigInt(10).permutation(3)), "720")
    testing.assert_equal(String(BigInt(5).permutation(5)), "120")  # P(n,n)=n!
    testing.assert_equal(String(BigInt(5).permutation(0)), "1")
    testing.assert_equal(String(BigInt(5).permutation(7)), "0")  # k > n
    testing.assert_equal(String(BigInt(100).permutation(2)), "9900")


def test_permutation_negative_k_raises() raises:
    """Test that a negative k raises."""
    var raised = False
    try:
        _ = BigInt(5).permutation(-1)
    except:
        raised = True
    testing.assert_true(raised, "permutation with negative k should raise")


def test_permutation_large_n() raises:
    """Test permutation with a large n that still fits in one word."""
    # n = 70000 (< 2^32), k = 2 -> 70000 * 69999.
    testing.assert_equal(String(BigInt(70000).permutation(2)), "4899930000")


def test_permutation_n_too_large_raises() raises:
    """Test that an n above 2^32 - 1 raises."""
    var raised = False
    try:
        _ = BigInt(4_294_967_296).permutation(2)  # 2^32, above WORD_MAX
    except:
        raised = True
    testing.assert_true(raised, "permutation with n > 2^32 - 1 should raise")


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
