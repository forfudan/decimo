# ===----------------------------------------------------------------------=== #
# Test BigInt special functions (factorial)
# ===----------------------------------------------------------------------=== #

from std import testing
from decimo.bigint.bigint import BigInt
from decimo.bigint.arithmetics import multiply_by_word_inplace
from decimo.bigint.special import product_range


def test_factorial_basic() raises:
    """Tests factorial of small non-negative integers."""
    testing.assert_equal(String(BigInt(0).factorial()), "1")
    testing.assert_equal(String(BigInt(1).factorial()), "1")
    testing.assert_equal(String(BigInt(2).factorial()), "2")
    testing.assert_equal(String(BigInt(5).factorial()), "120")
    testing.assert_equal(String(BigInt(10).factorial()), "3628800")
    testing.assert_equal(String(BigInt(20).factorial()), "2432902008176640000")


def test_factorial_large() raises:
    """Tests factorial that exceeds 64-bit range."""
    testing.assert_equal(
        String(BigInt(25).factorial()), "15511210043330985984000000"
    )


def test_factorial_crosses_leaf_cutoff() raises:
    """Tests factorial large enough to exercise the binary-split branch."""
    # 40 > the 32-factor leaf cutoff, so this splits and recombines.
    testing.assert_equal(
        String(BigInt(40).factorial()),
        "815915283247897734345611269596115894272000000000",
    )


def test_factorial_negative_raises() raises:
    """Tests that a negative argument raises."""
    var raised = False
    try:
        _ = BigInt(-1).factorial()
    except:
        raised = True
    testing.assert_true(raised, "factorial of a negative value should raise")


def test_factorial_too_large_raises() raises:
    """Tests that an argument above the cap raises."""
    var raised = False
    try:
        _ = BigInt(2_000_000).factorial()  # above the 10^6 cap
    except:
        raised = True
    testing.assert_true(raised, "factorial above the cap should raise")


def test_permutation() raises:
    """Tests permutation P(n, k)."""
    testing.assert_equal(String(BigInt(10).permutation(3)), "720")
    testing.assert_equal(String(BigInt(5).permutation(5)), "120")  # P(n,n)=n!
    testing.assert_equal(String(BigInt(5).permutation(0)), "1")
    testing.assert_equal(String(BigInt(5).permutation(7)), "0")  # k > n
    testing.assert_equal(String(BigInt(100).permutation(2)), "9900")


def test_permutation_negative_k_raises() raises:
    """Tests that a negative k raises."""
    var raised = False
    try:
        _ = BigInt(5).permutation(-1)
    except:
        raised = True
    testing.assert_true(raised, "permutation with negative k should raise")


def test_permutation_large_n() raises:
    """Tests permutation with a large n that still fits in one word."""
    # n = 70000, k = 2 -> 70000 * 69999.
    testing.assert_equal(String(BigInt(70000).permutation(2)), "4899930000")


def test_permutation_n_too_large_raises() raises:
    """Tests that an n too large to be an `Int` raises."""
    var raised = False
    try:
        _ = BigInt("9223372036854775808").permutation(2)  # 2^63
    except:
        raised = True
    testing.assert_true(raised, "permutation with n > 2^63 - 1 should raise")


def test_multiply_by_word_inplace_zero_and_one() raises:
    """Tests that word == 1 is a no-op; word == 0 yields a canonical zero."""
    var x = BigInt(12345)
    multiply_by_word_inplace(x, 1)
    testing.assert_equal(String(x), "12345")
    multiply_by_word_inplace(x, 0)
    testing.assert_equal(String(x), "0")
    # Zero times any word stays zero.
    multiply_by_word_inplace(x, 7)
    testing.assert_equal(String(x), "0")


def test_multiply_by_word_inplace_preserves_sign() raises:
    """The sign is preserved when scaling a negative value."""
    var x = BigInt(-6)
    multiply_by_word_inplace(x, 7)
    testing.assert_equal(String(x), "-42")


def test_product_range_out_of_bounds_raises() raises:
    """Tests that product_range rejects out-of-range bounds."""
    var raised = False
    try:
        _ = product_range(1, 4_294_967_296)  # far more than 10^6 factors
    except:
        raised = True
    testing.assert_true(raised, "product_range over 10^6 factors should raise")
    raised = False
    try:
        _ = product_range(-1, 5)
    except:
        raised = True
    testing.assert_true(raised, "product_range low < 0 should raise")


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
