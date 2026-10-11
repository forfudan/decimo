"""
Checks `arcsin`, `arccos` and `arctan2` against identities and their edges.

The table in `test_bigdecimal_trigonometric.mojo` pins the values it lists at
fifty digits against mpmath. What a table cannot see is a function that is
self-consistently wrong, so the checks here tie the three to each other and to
the functions they invert, and then look at the places where the kernels take a
different branch: the ends of `[-1, 1]`, the axes, and the arguments just
inside them.

`a - b` and `a + b` on `BigDecimal` round to the default precision of 28, so a
check on a 50-digit result uses the exact forms from `arithmetics` or unary
minus. Measuring the operator instead of the function is the trap here.
"""

from std import testing
from std.testing import assert_equal, assert_true

from decimo.bigdecimal.arithmetics import add, multiply, subtract
from decimo.bigdecimal.bigdecimal import BDec
from decimo.bigdecimal.constants import pi
from decimo.bigdecimal.trigonometric import (
    _arccosine_in_binary,
    _arcsine_in_binary,
    _arctangent_in_binary,
    arccos,
    arccos_rounded,
    arcsin,
    arcsin_rounded,
    arctan,
    arctan2,
    arctan2_rounded,
    cos,
    sin,
)
from decimo.biguint.biguint import BigUInt
from decimo.rounding_mode import RoundingMode

comptime WIDTH = 50
"""Digits the identities are checked at."""

comptime TOLERANCE = "1E-46"
"""What an identity may be off by at `WIDTH`.

Each side of an identity is a chain of two or three rounded operations, so the
last few digits belong to the arithmetic rather than to the function. Four
digits of room, which is far tighter than a wrong branch would be.
"""


def assert_close(expected: BDec, got: BDec, msg: String) raises:
    """Fails unless the two agree to within `TOLERANCE`."""
    var residual = abs(subtract(expected, got))
    assert_true(
        residual <= BDec(TOLERANCE),
        msg + ": expected " + String(expected) + ", got " + String(got),
    )


def sample_arguments() raises -> List[BDec]:
    """Arguments inside `[-1, 1]`, including both ends and just inside them."""
    return [
        BDec("0"),
        BDec("0.0000000000000000000001"),
        BDec("0.1"),
        BDec("0.25"),
        BDec("0.5"),
        BDec("0.75"),
        BDec("0.9"),
        BDec("0.99"),
        BDec("0.9999999"),
        BDec("0.99999999999999999999"),
        BDec("1"),
        BDec("-0.1"),
        BDec("-0.5"),
        BDec("-0.9"),
        BDec("-0.9999999"),
        BDec("-1"),
    ]


def test_arcsin_plus_arccos_is_a_right_angle() raises:
    """`arcsin(x) + arccos(x) = π/2` everywhere on `[-1, 1]`."""
    var half_pi = pi(WIDTH + 2).true_divide(BDec("2"), precision=WIDTH + 2)
    for x in sample_arguments():
        assert_close(
            half_pi,
            add(arcsin(x, WIDTH), arccos(x, WIDTH)),
            "arcsin + arccos at " + String(x),
        )


def test_sine_of_arcsine_returns_the_argument() raises:
    """`sin(arcsin(x)) = x`, which ties `arcsin` to the function it inverts."""
    for x in sample_arguments():
        assert_close(
            x, sin(arcsin(x, WIDTH), WIDTH), "sin(arcsin) at " + String(x)
        )


def test_cosine_of_arccosine_returns_the_argument() raises:
    """`cos(arccos(x)) = x`."""
    for x in sample_arguments():
        assert_close(
            x, cos(arccos(x, WIDTH), WIDTH), "cos(arccos) at " + String(x)
        )


def test_arcsine_is_odd() raises:
    """`arcsin(-x) = -arcsin(x)`, which the kernel gets from the quotient."""
    for x in sample_arguments():
        assert_close(
            -arcsin(x, WIDTH),
            arcsin(-x, WIDTH),
            "arcsin oddness at " + String(x),
        )


def test_arccosine_reflects_about_a_right_angle() raises:
    """`arccos(-x) = π - arccos(x)`, the one symmetry its identity hides."""
    var whole_pi = pi(WIDTH + 2)
    for x in sample_arguments():
        assert_close(
            subtract(whole_pi, arccos(x, WIDTH)),
            arccos(-x, WIDTH),
            "arccos reflection at " + String(x),
        )


def test_arctan2_matches_arctan_right_of_the_y_axis() raises:
    """With `x > 0` the quadrant is the one `arctan(y / x)` already gives."""
    var abscissas = [BDec("0.5"), BDec("1"), BDec("3")]
    var ordinates = [
        BDec("-4"),
        BDec("-0.5"),
        BDec("0"),
        BDec("0.25"),
        BDec("7"),
    ]
    for x in abscissas:
        for y in ordinates:
            assert_close(
                arctan(y.true_divide(x, precision=WIDTH + 2), WIDTH),
                arctan2(y, x, WIDTH),
                "arctan2 against arctan at " + String(y) + ", " + String(x),
            )


def test_arctan2_on_the_axes() raises:
    """The four axis directions are exactly the multiples of a right angle."""
    var whole_pi = pi(WIDTH + 2)
    var half_pi = whole_pi.true_divide(BDec("2"), precision=WIDTH + 2)

    assert_close(
        BDec("0"), arctan2(BDec("0"), BDec("2"), WIDTH), "positive x-axis"
    )
    assert_close(
        whole_pi, arctan2(BDec("0"), BDec("-2"), WIDTH), "negative x-axis"
    )
    assert_close(
        half_pi, arctan2(BDec("3"), BDec("0"), WIDTH), "positive y-axis"
    )
    assert_close(
        -half_pi, arctan2(BDec("-3"), BDec("0"), WIDTH), "negative y-axis"
    )


def test_arctan2_of_the_origin_is_zero() raises:
    """The origin carries no angle; zero is what `math.atan2` answers too."""
    assert_equal(String(arctan2(BDec("0"), BDec("0"), WIDTH)), "0")


def test_arctan2_crosses_the_negative_x_axis_continuously() raises:
    """Just above and just below the cut differ by a whole turn, not a jump.

    The branch that adds π for a negative abscissa chooses its side by the
    ordinate's sign, so the two sides of the cut are the test of that choice.
    """
    var tiny = BDec("0.0000000000000000000001")
    var above = arctan2(tiny, BDec("-1"), WIDTH)
    var below = arctan2(-tiny, BDec("-1"), WIDTH)
    # The angle at `(-1, ±tiny)` is a half turn short of the cut by `tiny`
    # itself, since `arctan(tiny) = tiny` to well past fifty digits.
    var just_short = subtract(pi(WIDTH + 2), tiny)
    assert_close(just_short, above, "just above the cut is just under π")
    assert_close(-just_short, below, "just below the cut is just over -π")
    assert_true(above > BDec("0"), "above the cut the angle is positive")
    assert_true(below < BDec("0"), "below the cut the angle is negative")


def test_the_ends_of_the_domain() raises:
    """`±1` take their own branch in both kernels, so they are pinned here."""
    var whole_pi = pi(WIDTH + 2)
    var half_pi = whole_pi.true_divide(BDec("2"), precision=WIDTH + 2)

    assert_close(half_pi, arcsin(BDec("1"), WIDTH), "arcsin(1)")
    assert_close(-half_pi, arcsin(BDec("-1"), WIDTH), "arcsin(-1)")
    assert_equal(String(arccos(BDec("1"), WIDTH)), "0")
    assert_close(whole_pi, arccos(BDec("-1"), WIDTH), "arccos(-1)")
    assert_equal(String(arcsin(BDec("0"), WIDTH)), "0")


def test_outside_the_domain_raises() raises:
    """Anything past `±1` has no real arcsine or arccosine."""
    var outside = [
        BDec("1.0000000000000000000001"),
        BDec("-1.0000000000000000000001"),
        BDec("2"),
        BDec("-2"),
        BDec("1E20"),
    ]
    for x in outside:
        var raised = False
        try:
            _ = arcsin(x, WIDTH)
        except:
            raised = True
        assert_true(raised, "arcsin accepted " + String(x))

        raised = False
        try:
            _ = arccos(x, WIDTH)
        except:
            raised = True
        assert_true(raised, "arccos accepted " + String(x))


def test_rounding_modes_are_carried_through() raises:
    """Each mode decides the last digit, and the modes disagree where it does.

    The expected values are mpmath at sixty digits, rounded once by CPython's
    `decimal` in each mode.
    """
    # arcsin(0.3) = 0.304692654015397507972003...
    var x = BDec("0.3")
    assert_equal(
        String(arcsin_rounded(x, 9, RoundingMode.ROUND_HALF_EVEN)),
        "0.304692654",
    )
    assert_equal(
        String(arcsin_rounded(x, 9, RoundingMode.ROUND_DOWN)), "0.304692654"
    )
    assert_equal(
        String(arcsin_rounded(x, 9, RoundingMode.ROUND_UP)), "0.304692655"
    )
    assert_equal(
        String(arcsin_rounded(x, 9, RoundingMode.ROUND_CEILING)), "0.304692655"
    )
    assert_equal(
        String(arcsin_rounded(x, 9, RoundingMode.ROUND_FLOOR)), "0.304692654"
    )

    # arccos(0.3) = 1.266103672779499111259319...
    assert_equal(
        String(arccos_rounded(x, 9, RoundingMode.ROUND_HALF_EVEN)), "1.26610367"
    )
    assert_equal(
        String(arccos_rounded(x, 9, RoundingMode.ROUND_UP)), "1.26610368"
    )
    assert_equal(
        String(arccos_rounded(x, 9, RoundingMode.ROUND_FLOOR)), "1.26610367"
    )

    # arctan2(2, -3) = 2.553590050042225687217032...
    var y = BDec("2")
    var left = BDec("-3")
    assert_equal(
        String(arctan2_rounded(y, left, 9, RoundingMode.ROUND_HALF_EVEN)),
        "2.55359005",
    )
    assert_equal(
        String(arctan2_rounded(y, left, 9, RoundingMode.ROUND_UP)), "2.55359006"
    )
    assert_equal(
        String(arctan2_rounded(y, left, 9, RoundingMode.ROUND_FLOOR)),
        "2.55359005",
    )


# ===----------------------------------------------------------------------=== #
# The route through the binary layer
# ===----------------------------------------------------------------------=== #
#
# Above a couple of dozen digits these three convert their argument to a
# `BigFloat`, evaluate there and convert back, because the decimal series is
# quadratic in the digits: the arccosine took five seconds at nine hundred
# digits and now takes two tenths of a millisecond. The deciding loop settles
# the last digit either way, so the answers are the same -- which is what
# these check, the series being the second implementation.


def _subjects() -> List[String]:
    """Arguments that reach every branch of the choice.

    Returns:
        Ordinary values, both ends of the domain, and arguments a hair from
        one, where the two inverse functions turn the argument's own error
        into a larger one.
    """
    return [
        String("0.6180339887498948482045868343656381"),
        String("-0.5"),
        String("0.1"),
        String("1e-40"),
        String("0.9999999999999999999"),
        String("-0.9999999999999999999"),
        String(
            "0.999999999999999999999999999999999999999999999999999999999999"
        ),
    ]


def test_both_routes_to_the_inverse_functions_agree() raises:
    """The decimal series and the binary route, kernel against kernel.

    Each promises to be within a few units of the last place of the width it
    is asked for, so the two agree to a handful of units at that width. They
    share nothing: one sums a series in base-10^18 words, the other converts,
    reduces the argument, sums a different series in base-2^64 words, and
    converts back.
    """
    for width in [30, 45]:
        for text in _subjects():
            var x = BDec(text)
            for which in range(3):
                var series: BDec
                var binary: BDec
                var name: String
                if which == 0:
                    series = arctan(x, width)
                    binary = _arctangent_in_binary(x, width)
                    name = "arctan"
                elif which == 1:
                    series = arcsin(x, width)
                    binary = _arcsine_in_binary(x, width)
                    name = "arcsin"
                else:
                    series = arccos(x, width)
                    binary = _arccosine_in_binary(x, width)
                    name = "arccos"
                var gap = subtract(series, binary)
                assert_true(
                    gap.coefficient.is_zero()
                    or Int(gap.adjusted())
                    <= Int(series.adjusted()) - width + 2,
                    (
                        "the two routes to "
                        + name
                        + "("
                        + text
                        + ") at "
                        + String(width)
                        + " digits differ by "
                        + String(gap)
                    ),
                )


def test_the_identities_hold_where_the_binary_route_is_taken() raises:
    """The three functions, end to end, at a precision past the floor.

    `arcsin(x) + arccos(x)` is a right angle, and the sine of an arcsine is
    the argument it was given. Both go through the public entry points, so
    this is the route a caller takes.
    """
    for precision in [30, 60]:
        var right_angle = multiply(
            pi(precision + 10), BDec("0.5")
        ).round_to_precision(precision - 2)
        for text in _subjects():
            var x = BDec(text)
            var total = add(
                x.arcsin(precision, RoundingMode.ROUND_HALF_EVEN),
                x.arccos(precision, RoundingMode.ROUND_HALF_EVEN),
            ).round_to_precision(precision - 2)
            assert_equal(
                String(total.round_to_precision(precision - 2)),
                String(right_angle.round_to_precision(precision - 2)),
                (
                    "arcsin plus arccos at "
                    + String(precision)
                    + " digits for "
                    + text
                ),
            )
            var back = sin(
                x.arcsin(precision + 10, RoundingMode.ROUND_HALF_EVEN),
                precision + 10,
            )
            var drift = subtract(back, x)
            assert_true(
                drift.coefficient.is_zero()
                or Int(drift.adjusted()) <= Int(x.adjusted()) - precision + 4,
                (
                    "the sine of the arcsine at "
                    + String(precision)
                    + " digits for "
                    + text
                    + " came back "
                    + String(drift)
                    + " away"
                ),
            )


def test_the_arctangent_of_a_huge_argument_is_a_right_angle() raises:
    """An argument far past where the answer stops moving.

    `arctan(10^1000000)` is a right angle to every digit anyone will ask for,
    and the argument is one the binary layer can still hold -- a million
    decimal places is three and a third million bits. So this goes the binary
    way, conversion and all, and has to come back with the same right angle
    the decimal series gives.
    """
    var huge = BDec(BigUInt.one(), -1_000_000, False)
    var right_angle = multiply(pi(60), BDec("0.5")).round_to_precision(40)
    assert_equal(
        String(
            huge.arctan(50, RoundingMode.ROUND_HALF_EVEN).round_to_precision(40)
        ),
        String(right_angle),
        "the arctangent of ten to the million",
    )


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
