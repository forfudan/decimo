"""
Tests the four integer operations that decimo had the neighbours of.

`factorial` and `permutation` were there without `binomial`; `BigDecimal` and
`Decimal128` had an nth root while the integer types had only `sqrt`;
`BigUInt` had `ceil_divide` and `BigInt` did not; and the Karatsuba square
root carried its remainder without anything exposing it.

The expected values come from CPython: `math.comb`, `math.isqrt`, and
`-(-a // b)` for the ceiling quotient, which is the identity the
implementation uses as well -- so the cases that matter here are the ones
where signs disagree, since that is what the identity is for.
"""

from std import testing
from std.testing import assert_equal, assert_true

from decimo.bigint.bigint import BigInt
from decimo.bigint.exponential import root as bigint_root, sqrt_rem
from decimo.bigint.special import binomial
from decimo.biguint.biguint import BigUInt
from decimo.biguint.exponential import root as biguint_root


def test_binomial_against_cpython() raises:
    """`math.comb` for the same pairs."""
    var pairs = [
        (5, 2),
        (10, 5),
        (52, 5),
        (60, 30),
        (100, 0),
        (100, 100),
        (1000, 999),
    ]
    var expected = [
        "10",
        "252",
        "2598960",
        "118264581564861424",
        "1",
        "1",
        "1000",
    ]
    for i in range(len(pairs)):
        assert_equal(
            binomial(BigInt(pairs[i][0]), pairs[i][1]),
            BigInt(expected[i]),
            "C(" + String(pairs[i][0]) + ", " + String(pairs[i][1]) + ")",
        )

    # Past the range of any fixed-width integer.
    assert_equal(
        binomial(BigInt(200), 100),
        BigInt("90548514656103281165404177077484163874504589675413336841320"),
        "C(200, 100)",
    )


def test_binomial_is_symmetric() raises:
    """`C(n, k) = C(n, n - k)`, which is also how the big `k` is made cheap."""
    for n in [10, 52, 200]:
        for k in [0, 1, 3, n // 2]:
            assert_equal(
                binomial(BigInt(n), k),
                binomial(BigInt(n), n - k),
                "C(" + String(n) + ", " + String(k) + ") symmetry",
            )


def test_binomial_edges_and_refusals() raises:
    """`k > n` is zero, as `math.comb` has it; negatives have no answer."""
    assert_equal(binomial(BigInt(3), 5), BigInt.zero(), "k past n")
    assert_equal(binomial(BigInt(0), 0), BigInt.one(), "C(0, 0)")

    var raised = False
    try:
        _ = binomial(BigInt(-5), 2)
    except:
        raised = True
    assert_true(raised, "a negative n was accepted")

    raised = False
    try:
        _ = binomial(BigInt(5), -2)
    except:
        raised = True
    assert_true(raised, "a negative k was accepted")


def test_binomial_agrees_with_permutation() raises:
    """`C(n, k) * k! = P(n, k)`, the two counts the library now both have."""
    for nk in [(10, 3), (20, 7), (52, 5)]:
        var combinations = binomial(BigInt(nk[0]), nk[1])
        var orderings = BigInt(nk[1]).factorial()
        assert_equal(
            combinations * orderings,
            BigInt(nk[0]).permutation(nk[1]),
            "C * k! at " + String(nk[0]) + ", " + String(nk[1]),
        )


def test_ceil_divide_where_the_signs_disagree() raises:
    """Rounding up is not truncation, and the two differ by sign, not value."""
    var cases = [
        ("7", "2", "4"),
        ("-7", "2", "-3"),
        ("7", "-2", "-3"),
        ("-7", "-2", "4"),
        ("6", "3", "2"),
        ("-6", "3", "-2"),
        ("1", "1000", "1"),
        ("-1", "1000", "0"),
    ]
    for item in cases:
        assert_equal(
            BigInt(item[0]).ceil_divide(BigInt(item[1])),
            BigInt(item[2]),
            "ceil(" + item[0] + " / " + item[1] + ")",
        )


def test_ceil_divide_is_the_floor_quotient_or_one_past_it() raises:
    """The quotient is the floor one, plus one exactly when it divided short."""
    for a in [BigInt("17"), BigInt("-17"), BigInt("1000000000000000000001")]:
        for b in [BigInt("3"), BigInt("-3"), BigInt("17")]:
            var floor_quotient = a // b
            var ceiling = a.ceil_divide(b)
            var exact = (floor_quotient * b) == a
            if exact:
                assert_equal(
                    ceiling, floor_quotient, "exact division at " + String(a)
                )
            else:
                assert_equal(
                    ceiling,
                    floor_quotient + BigInt.one(),
                    "inexact division at " + String(a) + " / " + String(b),
                )


def test_ceil_divide_by_zero_raises() raises:
    var raised = False
    try:
        _ = BigInt(7).ceil_divide(BigInt.zero())
    except:
        raised = True
    assert_true(raised, "a zero divisor was accepted")


def test_sqrt_rem_reconstructs_its_argument() raises:
    """`s * s + r == x` and `r <= 2 * s`, which is what the pair promises."""
    var values = [
        BigInt("0"),
        BigInt("1"),
        BigInt("2"),
        BigInt("10"),
        BigInt("99"),
        BigInt("100"),
        BigInt("12345678901234567890"),
        BigInt("9" * 60),
    ]
    for x in values:
        var pair = x.sqrt_rem()
        var s = pair[0].copy()
        var r = pair[1].copy()
        assert_equal(s * s + r, x, "reconstruction at " + String(x))
        assert_true(r >= BigInt.zero(), "a negative remainder at " + String(x))
        assert_true(
            r <= s * BigInt(2), "the remainder exceeds 2s at " + String(x)
        )
        assert_equal(s, x.isqrt(), "the root disagrees with isqrt()")


def test_sqrt_rem_above_the_karatsuba_cutoff() raises:
    """Inputs past `CUTOFF_SQRT_BASE`, including unnormalized ones.

    The square root's Karatsuba recursion wants an even word count and a top
    word of at least `2^62`, and `sqrt()` is where that normalization
    happens. An earlier version of `sqrt_rem()` reached past it into
    `_sqrtrem()` with the raw magnitude: 68 of the 348 values swept here came
    back with a root and a remainder that did not reconstruct their argument.
    The shapes with a deliberately small top word are the ones that caught
    it.
    """
    for words in range(33, 64):
        var bits = words * 64
        var normalized_top = BigInt(2).power(bits - 1)
        var small_top = BigInt(2).power(bits - 63)
        var candidates = [
            normalized_top.copy(),
            normalized_top + BigInt.one(),
            small_top.copy(),
            small_top + BigInt.one(),
            small_top * BigInt(3),
            small_top - BigInt.one(),
        ]
        for x in candidates:
            var pair = x.sqrt_rem()
            var s = pair[0].copy()
            var r = pair[1].copy()
            assert_equal(
                s * s + r, x, "reconstruction at " + String(words) + " words"
            )
            assert_true(
                r <= s * BigInt(2),
                "the remainder exceeds 2s at " + String(words) + " words",
            )


def test_root_of_a_degree_past_the_value() raises:
    """A degree larger than the value's size answers one, and cheaply.

    `BigUInt.power()` refuses an exponent of a billion or more, and
    `digits + n` overflows for an `n` near `Int.MAX`, so a degree that large
    has to be answered before either is reached. The answer is one: `2^n`
    exceeds the value, so even two is too large a root.
    """
    assert_equal(String(BigUInt(2).root(1_000_000_001)), "1", "degree 1e9+1")
    assert_equal(String(BigUInt(2).root(Int.MAX)), "1", "degree Int.MAX")
    assert_equal(
        String(BigUInt("1" + "0" * 30).root(Int.MAX)),
        "1",
        "a thirty-digit value at degree Int.MAX",
    )
    assert_equal(String(BigUInt(0).root(Int.MAX)), "0", "zero stays zero")
    assert_equal(
        BigInt(-2).root(1_000_000_001),
        BigInt("-1"),
        "the sign survives the shortcut",
    )

    # The shortcut must not fire where the answer is still two.
    var power_of_two = BigUInt(2).power(100)
    assert_equal(
        String(power_of_two.root(100)), "2", "the exact hundredth root"
    )
    assert_equal(String(power_of_two.root(101)), "1", "one degree past it")


def test_sqrt_rem_against_cpython() raises:
    """`math.isqrt` and the remainder it leaves."""
    assert_equal(String(BigInt("10").sqrt_rem()[0]), "3", "isqrt(10)")
    assert_equal(String(BigInt("10").sqrt_rem()[1]), "1", "rem(10)")
    assert_equal(
        String(BigInt("12345678901234567890").sqrt_rem()[0]),
        "3513641828",
        "isqrt of a twenty-digit value",
    )
    assert_equal(
        String(BigInt("12345678901234567890").sqrt_rem()[1]),
        "5763386306",
        "its remainder",
    )


def test_sqrt_rem_of_a_negative_raises() raises:
    var raised = False
    try:
        _ = BigInt(-1).sqrt_rem()
    except:
        raised = True
    assert_true(raised, "a negative value was accepted")


def test_root_truncates_toward_zero() raises:
    """An integral root truncates, and a negative one truncates toward zero."""
    var cases = [
        ("1000", 3, "10"),
        ("1001", 3, "10"),
        ("999", 3, "9"),
        ("10", 2, "3"),
        ("1024", 10, "2"),
        ("255", 8, "1"),
        ("256", 8, "2"),
        ("0", 5, "0"),
        ("1", 7, "1"),
        ("-8", 3, "-2"),
        ("-9", 3, "-2"),
        ("-1000", 3, "-10"),
    ]
    for item in cases:
        assert_equal(
            BigInt(item[0]).root(item[1]),
            BigInt(item[2]),
            "root(" + item[0] + ", " + String(item[1]) + ")",
        )


def test_root_brackets_the_answer() raises:
    """`s^n <= x < (s+1)^n`, checked rather than compared to a table."""
    var values = [
        BigUInt("2"),
        BigUInt("63"),
        BigUInt("64"),
        BigUInt("65"),
        BigUInt("1000000007"),
        BigUInt("12345678901234567890123456789"),
        BigUInt("9" * 80),
    ]
    for x in values:
        for n in [2, 3, 5, 7, 13]:
            var s = biguint_root(x, n)
            assert_true(
                s.power(n) <= x,
                "the root is too large at "
                + String(x)
                + " degree "
                + String(n),
            )
            assert_true(
                (s + BigUInt.one()).power(n) > x,
                "the root is too small at "
                + String(x)
                + " degree "
                + String(n),
            )


def test_root_agrees_with_the_square_root_at_degree_two() raises:
    """Degree two is `isqrt`, by a different route."""
    for x in [
        BigInt("2"),
        BigInt("10"),
        BigInt("10000"),
        BigInt("12345678901234567890"),
    ]:
        assert_equal(x.root(2), x.isqrt(), "degree two at " + String(x))


def test_root_of_degree_one_is_the_value() raises:
    for x in [BigInt("0"), BigInt("7"), BigInt("-7")]:
        assert_equal(x.root(1), x, "degree one at " + String(x))


def test_root_refusals() raises:
    """A non-positive degree has no meaning; an even root of a negative is
    not real."""
    for n in [0, -1, -3]:
        var raised = False
        try:
            _ = BigInt(8).root(n)
        except:
            raised = True
        assert_true(raised, "degree " + String(n) + " was accepted")

    for n in [2, 4, 10]:
        var raised = False
        try:
            _ = BigInt(-8).root(n)
        except:
            raised = True
        assert_true(
            raised, "an even root of a negative was accepted at " + String(n)
        )


def test_biguint_root_matches_bigint_root() raises:
    """The signed root is the unsigned one with the sign put back."""
    for v in ["0", "1", "1000", "12345678901234567890123456789"]:
        for n in [2, 3, 5]:
            assert_equal(
                String(biguint_root(BigUInt(v), n)),
                String(bigint_root(BigInt(v), n)),
                "root(" + v + ", " + String(n) + ")",
            )


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
