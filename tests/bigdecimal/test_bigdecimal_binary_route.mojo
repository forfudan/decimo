"""
Tests the decimal transcendentals that are worked out in the binary layer.

Above a few dozen digits `ln`, `log10`, `exp`, `expm1`, `log1p` and the
general `power` convert their argument to a `BigFloat`, evaluate there, and
convert back, because a binary multiplication moves machine words where a
decimal one moves base-10^18 words. The decimal series stay for shorter
requests, for arguments outside the binary exponent range, and as the second
implementation these tests compare against.

Two things are checked here: the two routes against each other, which is two
independent implementations of the same function, and the argument that must
not take the binary route at all, its exponent being past what a `BigFloat`
holds. The answers themselves are checked against CPython in
`test_bigdecimal_exponential.mojo`, which already pays for the Python
interpreter this one would otherwise start a second time.
"""

from std import testing
from std.testing import assert_equal, assert_true

from decimo.bigdecimal.bigdecimal import BigDecimal
from decimo.bigdecimal.exponential import (
    _exponential_in_binary,
    _logarithm_in_binary,
    ln,
)
from decimo.biguint.biguint import BigUInt
from decimo.rounding_mode import RoundingMode


def _arguments() -> List[String]:
    """Arguments that reach every branch of the choice.

    Returns:
        The texts, from ordinary values through the two ends of the exponent
        range to arguments a hair from one, where the logarithm's answer is
        as small as the distance.
    """
    return [
        String("3.14159265358979323846264338327950288"),
        String("2"),
        String("0.1"),
        String("123456789.987654321"),
        String("1e50"),
        String("1e-50"),
        String("1.0000000000000000001"),
        String("0.9999999999999999999"),
        String(
            "1.000000000000000000000000000000000000000000000000000000000001"
        ),
        String(
            "0.999999999999999999999999999999999999999999999999999999999999"
        ),
    ]


def test_both_routes_to_the_logarithm_agree() raises:
    """The decimal series and the binary route, kernel against kernel.

    Each promises to be within a few units of the last place of the width it
    is asked for, so they agree to a handful of units at that width. They
    share no code: one sums a series in base-10^18 words, the other converts,
    sums a different series in base-2^64 words, and converts back.
    """
    for width in [45, 60, 150, 400]:
        for text in _arguments():
            var x = BigDecimal(text)
            var series = ln(x, width)
            var binary = _logarithm_in_binary(x, width)
            var gap = series.subtract(binary)
            # The two answers carry `width` digits each, so a gap of a few
            # units of the last place sits at least `width - 2` digits below
            # the leading one. Anything above that is a disagreement.
            assert_true(
                gap.coefficient.is_zero()
                or Int(gap.adjusted()) <= Int(series.adjusted()) - width + 2,
                (
                    "the two routes to ln("
                    + text
                    + ") at "
                    + String(width)
                    + " digits differ by "
                    + String(gap)
                ),
            )


def test_an_argument_past_the_binary_range_still_answers() raises:
    """A decimal exponent no `BigFloat` can hold goes the decimal way.

    A `BigDecimal` reaches `10^(10^18)` where a `BigFloat` stops at `2^63`,
    which is `10^(2.8 * 10^18)`. An argument past that has no binary form, so
    the series answers it, and the answer is still the logarithm: `ln(10^n)`
    is `n ln 10`.
    """
    # Sixty digits, which is past the floor, so the choice is the range's to
    # make and not the precision's.
    var huge = BigDecimal(BigUInt.one(), -3_000_000_000_000_000_000, False)
    var answer = huge.ln(60, RoundingMode.ROUND_HALF_EVEN)
    var ten = BigDecimal(BigUInt(10), 0, False)
    var expected = ten.ln(80, RoundingMode.ROUND_HALF_EVEN).multiply(
        BigDecimal(BigUInt(3_000_000_000_000_000_000), 0, False)
    )
    assert_equal(
        String(answer.round_to_precision(30)),
        String(expected.round_to_precision(30)),
        "ln of ten to the three quintillion",
    )


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
