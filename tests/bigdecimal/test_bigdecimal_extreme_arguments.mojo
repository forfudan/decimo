"""
Arguments at the far ends of what a `BigDecimal` holds.

A `BigDecimal` reaches an exponent of `10^18`, and two of the functions here
used to meet such an argument badly rather than answer it. The arctangent
formed the reciprocal and fed it to its series, whose terms are that
reciprocal cubed and fifthed: lining scales of three and five quintillion
against the sum exhausted memory, for an argument whose answer is a right
angle. The three reducing functions asked for as many digits of pi as the
argument has, and nothing would ever finish that, so they did not stop.

Both now behave the way the binary layer does: the arctangent answers, and
the reduction refuses in one line rather than being discovered as a hang.
"""

from std import testing
from std.testing import assert_equal, assert_raises, assert_true

from decimo.bigdecimal.arithmetics import multiply, subtract
from decimo.bigdecimal.bigdecimal import BDec
from decimo.bigdecimal.constants import pi
from decimo.bigdecimal.trigonometric import arctan, cos, sin, tan
from decimo.biguint.biguint import BigUInt
from decimo.rounding_mode import RoundingMode


def _ten_to(power: Int, negative: Bool = False) -> BDec:
    """`10^power`, built from its parts.

    Args:
        power: The power of ten, which may be far past what digits could
            spell out.
        negative: Whether to answer with the minus sign.

    Returns:
        The value, whose coefficient is one and whose scale carries the
        whole of it.
    """
    return BDec(BigUInt.one(), -power, negative)


def test_the_arctangent_of_a_colossal_argument_is_a_right_angle() raises:
    """An argument three quintillion digits long, answered rather than aborted.

    `arctan(x)` falls short of a right angle by `1/x`, which here is below
    every digit anyone could ask for, so every rounding mode answers what it
    would answer for `pi/2` itself -- the value is strictly between the
    representable value below `pi/2` and `pi/2`, and so is `pi/2`. A negative
    argument answers the mirror of that, the arctangent being odd.
    """
    for power in [
        3_000_000_000_000_000_000,
        1_000_000_000_000_000_000,
        1_000_000_000,
    ]:
        for precision in [20, 40]:
            var right_angle = multiply(pi(precision + 20), BDec("0.5"))
            for mode in [
                RoundingMode.ROUND_HALF_EVEN,
                RoundingMode.ROUND_DOWN,
                RoundingMode.ROUND_UP,
            ]:
                for negative in [False, True]:
                    var expected = right_angle.copy()
                    expected.sign = negative
                    expected.round_to_precision_inplace(
                        precision,
                        mode,
                        remove_extra_digit_due_to_rounding=True,
                        fill_zeros_to_precision=False,
                    )
                    assert_equal(
                        String(
                            _ten_to(power, negative).arctan(precision, mode)
                        ),
                        String(expected),
                        (
                            "arctan of ten to the "
                            + String(power)
                            + (" negated" if negative else "")
                            + " at "
                            + String(precision)
                            + " digits"
                        ),
                    )


def test_the_arctangent_adds_up_across_its_saturation() raises:
    """Either side of where the series stops being asked.

    The series is skipped once the reciprocal falls below the last place, and
    the line that decides it has to be in the right place: too early and a
    reciprocal that still shows in the digits is thrown away.

    `arctan(x) + arctan(1/x)` is a right angle for any positive `x`, and the
    reciprocal's arctangent is taken by the series whatever the large one
    does, so the sum catches a line drawn too early -- at `10^16` with twenty
    digits asked for, saturating would lose a reciprocal that belongs in the
    sixteenth.
    """
    for precision in [20, 30]:
        var wide = precision + 15
        var right_angle = multiply(pi(wide + 10), BDec("0.5"))
        for power in [
            precision - 8,
            precision - 4,
            precision,
            precision + 1,
            precision + 8,
            precision + 40,
        ]:
            var large = arctan(_ten_to(power), wide)
            var small = arctan(_ten_to(-power), wide)
            var drift = subtract(large.add(small), right_angle)
            assert_true(
                drift.coefficient.is_zero()
                or Int(drift.adjusted()) <= -precision - 2,
                (
                    "arctan of ten to the "
                    + String(power)
                    + " and of its reciprocal add to "
                    + String(drift)
                    + " away from a right angle"
                ),
            )


def test_an_argument_too_far_to_reduce_is_refused() raises:
    """The three reducing functions say so rather than running for ever.

    Reducing modulo `2pi` spends a digit of pi for every digit of the
    argument above the point, so an argument of `10^(3*10^18)` asks for more
    of the constant than any precision holds.
    """
    var huge = _ten_to(3_000_000_000_000_000_000)
    with assert_raises(contains="more digits of pi"):
        _ = sin(huge, 20)
    with assert_raises(contains="more digits of pi"):
        _ = cos(huge, 20)
    with assert_raises(contains="more digits of pi"):
        _ = tan(huge, 20)


def test_an_argument_that_can_be_reduced_is_not_refused() raises:
    """The bound refuses the impossible and nothing else.

    A hundred digits of reduction is ordinary work, and `sin(10^100)` has an
    answer: the square of it and the square of the cosine add to one.
    """
    var large = _ten_to(100)
    var sined = sin(large, 30)
    var cosed = cos(large, 30)
    var total = multiply(sined, sined).add(multiply(cosed, cosed))
    var drift = subtract(total, BDec("1"))
    assert_true(
        drift.coefficient.is_zero() or Int(drift.adjusted()) <= -25,
        "the squares of the sine and cosine of ten to the hundred add to "
        + String(total),
    )


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
