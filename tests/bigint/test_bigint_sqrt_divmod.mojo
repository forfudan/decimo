"""
Test BigInt sqrt and divmod operations: sqrt, isqrt, __divmod__
with positive, negative, mixed-sign, and consistency checks.
"""

from std import testing
from decimo.bigint.bigint import BigInt
import decimo.bigint.exponential as bigint_exponential


# ===----------------------------------------------------------------------=== #
# Test: sqrt / isqrt
# ===----------------------------------------------------------------------=== #


def test_sqrt_perfect_squares() raises:
    """Test sqrt with perfect squares."""
    testing.assert_equal(String(BigInt(0).sqrt()), "0")
    testing.assert_equal(String(BigInt(1).sqrt()), "1")
    testing.assert_equal(String(BigInt(4).sqrt()), "2")
    testing.assert_equal(String(BigInt(9).sqrt()), "3")
    testing.assert_equal(String(BigInt(16).sqrt()), "4")
    testing.assert_equal(String(BigInt(25).sqrt()), "5")
    testing.assert_equal(String(BigInt(100).sqrt()), "10")
    testing.assert_equal(String(BigInt(10000).sqrt()), "100")
    testing.assert_equal(String(BigInt(1000000).sqrt()), "1000")


def test_sqrt_non_perfect() raises:
    """Test sqrt with non-perfect squares (floor)."""
    # sqrt(2) = 1
    testing.assert_equal(String(BigInt(2).sqrt()), "1")

    # sqrt(3) = 1
    testing.assert_equal(String(BigInt(3).sqrt()), "1")

    # sqrt(5) = 2
    testing.assert_equal(String(BigInt(5).sqrt()), "2")

    # sqrt(8) = 2
    testing.assert_equal(String(BigInt(8).sqrt()), "2")

    # sqrt(99) = 9
    testing.assert_equal(String(BigInt(99).sqrt()), "9")

    # sqrt(101) = 10
    testing.assert_equal(String(BigInt(101).sqrt()), "10")


def test_sqrt_large() raises:
    """Test sqrt with large perfect squares."""
    # 10^20 → sqrt = 10^10 = 10000000000
    var x = BigInt(10) ** 20
    testing.assert_equal(String(x.sqrt()), "10000000000")

    # (2^50)^2 = 2^100 → sqrt = 2^50 = 1125899906842624
    var big_sq = BigInt(2) ** 100
    testing.assert_equal(String(big_sq.sqrt()), "1125899906842624")

    # Verify: sqrt * sqrt <= x < (sqrt+1)^2
    var n = BigInt("99999999999999999999999999999")  # 29 digits
    var s = n.sqrt()
    var s_sq = s * s
    var s1_sq = (s + BigInt(1)) * (s + BigInt(1))
    testing.assert_true(s_sq <= n, "sqrt^2 <= n")
    testing.assert_true(s1_sq > n, "(sqrt+1)^2 > n")


def test_sqrt_at_the_top_of_a_word() raises:
    """Values whose root is the largest that fits its word.

    `(root + 1) * (root + 1)` overflows there, and the correcting walk used
    to read the wrapped value as small, step up, and never stop. These all
    hung rather than answering.
    """
    testing.assert_equal(String(BigInt(4294967295).sqrt()), "65535")
    testing.assert_equal(String(BigInt(4294836225).sqrt()), "65535")
    testing.assert_equal(String(BigInt(4294836224).sqrt()), "65534")
    testing.assert_equal(
        String(BigInt("18446744073709551615").sqrt()), "4294967295"
    )
    testing.assert_equal(
        String(BigInt("18446744065119617025").sqrt()), "4294967295"
    )
    testing.assert_equal(
        String(BigInt("18446744065119617024").sqrt()), "4294967294"
    )


def test_sqrt_matches_its_definition_across_sizes() raises:
    """`s * s <= n < (s + 1)^2`, on both sides of both cutoffs.

    Powers of two and their neighbours, because they are where a word count
    turns odd and where the normalizing shift has the least to do. 4200 bits
    is well past `CUTOFF_SQRT_RECURSIVE`, so this covers the recursion too.
    """
    for bit in range(1, 4200, 7):
        for delta in range(-1, 2):
            var n = (BigInt(1) << bit) + BigInt(delta)
            if n.is_zero() or n.is_negative():
                continue
            var s = n.sqrt()
            testing.assert_true(s * s <= n, "s*s <= n at 2^" + String(bit))
            var next = s + BigInt(1)
            testing.assert_true(
                next * next > n, "(s+1)^2 > n at 2^" + String(bit)
            )


def test_sqrt_negative_raises() raises:
    """Test that sqrt of negative number raises."""
    var raised = False
    try:
        _ = BigInt(-4).sqrt()
    except:
        raised = True
    testing.assert_true(raised, "sqrt(-4) should raise")


def test_isqrt_equals_sqrt() raises:
    """Test that isqrt and sqrt produce the same result."""
    testing.assert_equal(String(BigInt(49).isqrt()), String(BigInt(49).sqrt()))
    testing.assert_equal(String(BigInt(50).isqrt()), String(BigInt(50).sqrt()))


# ===----------------------------------------------------------------------=== #
# Test: __divmod__
# ===----------------------------------------------------------------------=== #


def test_divmod_basic() raises:
    """Test divmod with positive numbers."""
    var result = BigInt(7).__divmod__(BigInt(3))
    testing.assert_equal(String(result[0]), "2", "7 divmod 3: q")
    testing.assert_equal(String(result[1]), "1", "7 divmod 3: r")

    result = BigInt(10).__divmod__(BigInt(5))
    testing.assert_equal(String(result[0]), "2", "10 divmod 5: q")
    testing.assert_equal(String(result[1]), "0", "10 divmod 5: r")

    result = BigInt(0).__divmod__(BigInt(5))
    testing.assert_equal(String(result[0]), "0", "0 divmod 5: q")
    testing.assert_equal(String(result[1]), "0", "0 divmod 5: r")


def test_divmod_mixed_sign() raises:
    """Test divmod with mixed signs (floor semantics)."""
    # Python: divmod(7, -3) = (-3, -2) since 7 = (-3)*(-3) + (-2)
    var result = BigInt(7).__divmod__(BigInt(-3))
    testing.assert_equal(String(result[0]), "-3", "7 divmod -3: q")
    testing.assert_equal(String(result[1]), "-2", "7 divmod -3: r")

    # Python: divmod(-7, 3) = (-3, 2) since -7 = (-3)*3 + 2
    result = BigInt(-7).__divmod__(BigInt(3))
    testing.assert_equal(String(result[0]), "-3", "-7 divmod 3: q")
    testing.assert_equal(String(result[1]), "2", "-7 divmod 3: r")

    # Python: divmod(-7, -3) = (2, -1) since -7 = 2*(-3) + (-1)
    result = BigInt(-7).__divmod__(BigInt(-3))
    testing.assert_equal(String(result[0]), "2", "-7 divmod -3: q")
    testing.assert_equal(String(result[1]), "-1", "-7 divmod -3: r")


def test_divmod_consistency() raises:
    """Test that divmod(a, b) satisfies a = q * b + r."""

    def _check_divmod(a_val: Int, b_val: Int) raises:
        var a = BigInt(a_val)
        var b = BigInt(b_val)
        var result = a.__divmod__(b)
        var q = result[0].copy()
        var r = result[1].copy()
        var reconstructed = q * b + r
        testing.assert_equal(
            String(reconstructed),
            String(a),
            "divmod consistency: " + String(a_val) + " divmod " + String(b_val),
        )

    _check_divmod(17, 5)
    _check_divmod(-17, 5)
    _check_divmod(17, -5)
    _check_divmod(-17, -5)
    _check_divmod(100, 7)
    _check_divmod(-100, 7)


def test_divmod_by_zero_raises() raises:
    """Test divmod by zero raises."""
    var raised = False
    try:
        _ = BigInt(42).__divmod__(BigInt(0))
    except:
        raised = True
    testing.assert_true(raised, "divmod by zero should raise")


# ===----------------------------------------------------------------------=== #
# Test: reciprocal_sqrt_fixed_point
# ===----------------------------------------------------------------------=== #


def _assert_reciprocal_sqrt_fixed_point(
    x: UInt64, fractional_bits: Int, tolerance: Int
) raises:
    """Brackets `r` against the exact `floor(2^fractional_bits / sqrt(x))`.

    `r` is the exact value when `r^2 * x <= 2^(2f) < (r + 1)^2 * x`. Widening
    that by `tolerance` on each side gives a check that needs no reference
    value and no reference implementation: it asserts exactly the contract the
    function documents, and it is not satisfied by any wrong answer.
    """
    var r = bigint_exponential.reciprocal_sqrt_fixed_point(x, fractional_bits)
    var bx = BigInt(String(x))
    var square = BigInt.one() << (2 * fractional_bits)
    var label = (
        " for x=" + String(x) + ", fractional_bits=" + String(fractional_bits)
    )

    var low = r - BigInt(tolerance)
    if low.sign:
        low = BigInt.zero()
    testing.assert_true(
        low * low * bx <= square,
        "reciprocal_sqrt_fixed_point() is more than "
        + String(tolerance)
        + " ulp high"
        + label,
    )

    var high = r + BigInt(tolerance + 1)
    testing.assert_true(
        high * high * bx > square,
        "reciprocal_sqrt_fixed_point() is more than "
        + String(tolerance)
        + " ulp low"
        + label,
    )


def test_reciprocal_sqrt_fixed_point_brackets_the_exact_value() raises:
    """`2^f / sqrt(x)` is within a few ulp of the true value, at every size.

    The word-sized `x` values span the whole `UInt64` range, including both
    perfect squares (exact answers, where an off-by-one is easiest to make)
    and values above `2^53`, which no longer round-trip through the `Float64`
    seed. The `fractional_bits` values cross the point where the Newton schedule
    starts running at all (`fractional_bits <= 44 + ceil(bits(x) / 2)` returns
    the seed directly) and then several doublings past it.
    """
    var xs = [
        UInt64(1),
        UInt64(2),
        UInt64(3),
        UInt64(4),
        UInt64(10005),
        UInt64(999999937),
        UInt64(1) << 40,
        UInt64(9223372036854775807),
        UInt64(0) - UInt64(1),
    ]
    var fractional_bits = [0, 1, 30, 64, 128, 200, 256, 501, 1000, 3000]

    for i in range(len(xs)):
        for j in range(len(fractional_bits)):
            _assert_reciprocal_sqrt_fixed_point(xs[i], fractional_bits[j], 4)


def test_reciprocal_sqrt_fixed_point_exact_powers_of_four() raises:
    """`x = 4^k` makes `2^f / sqrt(x)` an exact power of two."""
    testing.assert_equal(
        String(bigint_exponential.reciprocal_sqrt_fixed_point(UInt64(1), 64)),
        String(BigInt.one() << 64),
    )
    testing.assert_equal(
        String(bigint_exponential.reciprocal_sqrt_fixed_point(UInt64(4), 300)),
        String(BigInt.one() << 299),
    )
    testing.assert_equal(
        String(
            bigint_exponential.reciprocal_sqrt_fixed_point(
                UInt64(1) << 40, 1000
            )
        ),
        String(BigInt.one() << 980),
    )


def test_reciprocal_sqrt_fixed_point_rejects_bad_arguments() raises:
    """Zero and a negative width raise rather than returning nonsense."""
    var raised = False
    try:
        _ = bigint_exponential.reciprocal_sqrt_fixed_point(UInt64(0), 64)
    except:
        raised = True
    testing.assert_true(raised, "x = 0 should raise")

    raised = False
    try:
        _ = bigint_exponential.reciprocal_sqrt_fixed_point(UInt64(10005), -1)
    except:
        raised = True
    testing.assert_true(raised, "negative fractional_bits should raise")


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
