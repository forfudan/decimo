"""
Tests the decimal transcendentals that are worked out in the binary layer.

Above a few dozen digits `ln`, `log10`, `exp`, `expm1`, `log1p` and the
general `power` convert their argument to a `BigFloat`, evaluate there, and
convert back, because a binary multiplication moves machine words where a
decimal one moves base-10^18 words. `sin`, `cos` and `tan` do the same at
every precision, the reduction by `pi/2` being the cost there rather than the
series. The decimal series stay for shorter requests, for arguments outside
the binary exponent range, for an argument too small to need reducing, and as
the second implementation these tests compare against.

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
from decimo.bigdecimal.trigonometric import (
    _cosine_in_binary,
    _sine_in_binary,
    _tangent_in_binary,
    cos,
    sin,
    tan,
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


def _angles() -> List[String]:
    """Angles that reach every branch of the circular choice.

    Returns:
        The texts: an argument too small to reduce, one just the other side
        of `pi/4`, the two signs, a large magnitude, and three that sit a
        hair from a multiple of `pi/2`, where the answer begins with a run of
        zeros the reduction had to find and lose.
    """
    return [
        String("0.5"),
        String("-0.5"),
        String("0.8"),
        String("1.2"),
        String("100"),
        String("-100"),
        String("1e20"),
        String("1e-20"),
        # pi/2, pi and 2 pi to 34 digits: the sine or the cosine of these is
        # about 1e-35, so the reduction gives up its first thirty-five digits
        # and the width has to grow to cover them.
        String("1.570796326794896619231321691639751"),
        String("3.141592653589793238462643383279503"),
        String("6.283185307179586476925286766559006"),
    ]


def _routes_agree(
    series: BigDecimal, binary: BigDecimal, width: Int, what: String
) raises:
    """Checks two kernels of the same function against each other.

    Args:
        series: What the decimal series returned.
        binary: What the binary route returned.
        width: The digits both were asked for.
        what: The name and argument, for the message.

    Raises:
        AssertionError: If the two differ by more than a few units of the
            last place of `width`.
    """
    var gap = series.subtract(binary)
    assert_true(
        gap.coefficient.is_zero()
        or Int(gap.adjusted()) <= Int(series.adjusted()) - width + 2,
        (
            "the two routes to "
            + what
            + " at "
            + String(width)
            + " digits differ by "
            + String(gap)
        ),
    )


def test_both_routes_to_the_sine_agree() raises:
    """The decimal series and the binary route, kernel against kernel.

    They share no code: one reduces and sums in base-10^18 words, the other
    converts, reduces and sums in base-2^64 words, and converts back. Each
    promises `TRIG_SLACK` units of the last place of the width it is asked
    for, so they agree to a handful of units there.
    """
    for width in [28, 45, 150, 400]:
        for text in _angles():
            var x = BigDecimal(text)
            _routes_agree(
                sin(x, width),
                _sine_in_binary(x, width),
                width,
                "sin(" + text + ")",
            )


def test_both_routes_to_the_cosine_agree() raises:
    """As the sine, and the cosine is the one that cancels at `pi/2`."""
    for width in [28, 45, 150, 400]:
        for text in _angles():
            var x = BigDecimal(text)
            _routes_agree(
                cos(x, width),
                _cosine_in_binary(x, width),
                width,
                "cos(" + text + ")",
            )


def test_both_routes_to_the_tangent_agree() raises:
    """As the sine, and the tangent is the one that also runs off.

    Near `pi/2` the answer is enormous rather than tiny, which is the other
    branch of the width the binary route asks for: an answer of size `t`
    amplifies the argument's own error by `t` there, where a small answer
    amplifies it by `1/t`.
    """
    for width in [28, 45, 150, 400]:
        for text in _angles():
            var x = BigDecimal(text)
            _routes_agree(
                tan(x, width),
                _tangent_in_binary(x, width),
                width,
                "tan(" + text + ")",
            )


def test_a_small_angle_is_left_to_the_series() raises:
    """Below about `pi/4` the sine does not go to binary, and still answers.

    The dispatch is on the argument, not only on the precision, so this pins
    that the answer does not depend on which side of the bound an argument
    falls: the sine of `0.785` and of `0.786` are both right, though they
    take different routes.
    """
    for text in [String("0.785"), String("0.786")]:
        var x = BigDecimal(text)
        for width in [28, 200]:
            _routes_agree(
                sin(x, width),
                _sine_in_binary(x, width),
                width,
                "sin(" + text + ")",
            )


def test_an_angle_past_the_binary_range_is_refused_as_before() raises:
    """An exponent no `BigFloat` holds takes the decimal way, and is refused.

    `sin` has refused an argument this large since the reduction learned to
    check its own width: reducing `10^(3*10^18)` by `pi/2` would need more
    digits of pi than a precision may be. The binary route must not change
    that answer, and the way it does not is by declining to take such an
    argument at all.
    """
    var huge = BigDecimal(BigUInt.one(), -3_000_000_000_000_000_000, False)
    var refused = False
    try:
        var _answer = huge.sin(60, RoundingMode.ROUND_HALF_EVEN)
    except:
        refused = True
    assert_true(
        refused, "the sine of ten to the three quintillion must be refused"
    )


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
