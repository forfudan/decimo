"""
Rounding that is decided rather than assumed, for `exp`, `ln` and `log10`.

Each of these three arguments puts a rounding boundary inside the interval
the kernel's error bound allows at the first width tried, so the answer
cannot be settled on the first pass and the loop has to widen. They are the
shape that a fixed number of guard digits gets wrong: the digits just past
the cut are `000` or `999`, and which way the value rounds depends on what
comes after them.

The expected values were computed by CPython's `decimal` at fifty digits and
rounded once.
"""

from std import testing
from std.testing import assert_equal

from decimo.bigdecimal.bigdecimal import BDec
from decimo.bigdecimal.exponential import exp_rounded, ln_rounded, log10_rounded
from decimo.bigdecimal.trigonometric import (
    sin_rounded,
    cos_rounded,
    tan_rounded,
)
from decimo.rounding_mode import RoundingMode


def test_ln_where_the_tail_is_zeros() raises:
    # ln(664.247984247) = 6.4986555500052845...
    var x = BDec("664.247984247")
    assert_equal(
        String(ln_rounded(x, 9, RoundingMode.ROUND_HALF_EVEN)), "6.49865555"
    )
    assert_equal(
        String(ln_rounded(x, 9, RoundingMode.ROUND_DOWN)), "6.49865555"
    )
    assert_equal(String(ln_rounded(x, 9, RoundingMode.ROUND_UP)), "6.49865556")
    assert_equal(
        String(ln_rounded(x, 9, RoundingMode.ROUND_CEILING)), "6.49865556"
    )
    assert_equal(
        String(ln_rounded(x, 9, RoundingMode.ROUND_FLOOR)), "6.49865555"
    )


def test_exp_where_the_tail_is_zeros() raises:
    # exp(167.83767867) = 7.7799660500089087...E+72
    var x = BDec("167.837678670")
    assert_equal(
        String(exp_rounded(x, 9, RoundingMode.ROUND_HALF_EVEN)),
        "7.77996605E+72",
    )
    assert_equal(
        String(exp_rounded(x, 9, RoundingMode.ROUND_UP)), "7.77996606E+72"
    )
    assert_equal(
        String(exp_rounded(x, 9, RoundingMode.ROUND_DOWN)), "7.77996605E+72"
    )


def test_log10_where_the_tail_is_nines() raises:
    # log10(132.960671561) = 2.1237231999907277...
    var x = BDec("132.960671561")
    assert_equal(
        String(log10_rounded(x, 9, RoundingMode.ROUND_HALF_EVEN)), "2.12372320"
    )
    assert_equal(
        String(log10_rounded(x, 9, RoundingMode.ROUND_DOWN)), "2.12372319"
    )
    assert_equal(
        String(log10_rounded(x, 9, RoundingMode.ROUND_FLOOR)), "2.12372319"
    )
    assert_equal(
        String(log10_rounded(x, 9, RoundingMode.ROUND_CEILING)), "2.12372320"
    )


def test_the_rational_points_are_answered_not_looped() raises:
    # The loop would never settle on these, since the true value sits exactly
    # on a boundary. Each function answers them before entering it.
    for mode in [
        RoundingMode.ROUND_HALF_EVEN,
        RoundingMode.ROUND_UP,
        RoundingMode.ROUND_DOWN,
        RoundingMode.ROUND_CEILING,
        RoundingMode.ROUND_FLOOR,
    ]:
        assert_equal(String(exp_rounded(BDec("0"), 9, mode)), "1")
        assert_equal(String(ln_rounded(BDec("1"), 9, mode)), "0")
        assert_equal(String(log10_rounded(BDec("1000"), 9, mode)), "3")
        assert_equal(String(log10_rounded(BDec("0.001"), 9, mode)), "-3")


def test_the_trigonometric_functions_decide_too() raises:
    # sin(1.5) = 0.997494986604..., cos(1.5) = 0.0707372016677...,
    # tan(1.5) = 14.1014199472..., from the same independent computation.
    var x = BDec("1.5")
    assert_equal(
        String(sin_rounded(x, 9, RoundingMode.ROUND_DOWN)), "0.997494986"
    )
    assert_equal(
        String(sin_rounded(x, 9, RoundingMode.ROUND_UP)), "0.997494987"
    )
    assert_equal(
        String(sin_rounded(x, 9, RoundingMode.ROUND_HALF_EVEN)), "0.997494987"
    )
    assert_equal(
        String(cos_rounded(x, 9, RoundingMode.ROUND_DOWN)), "0.0707372016"
    )
    assert_equal(
        String(cos_rounded(x, 9, RoundingMode.ROUND_UP)), "0.0707372017"
    )
    assert_equal(
        String(tan_rounded(x, 9, RoundingMode.ROUND_DOWN)), "14.1014199"
    )
    assert_equal(String(tan_rounded(x, 9, RoundingMode.ROUND_UP)), "14.1014200")

    # A large argument reduces first and still decides its last digit.
    assert_equal(
        String(sin_rounded(BDec("1E+150"), 9, RoundingMode.ROUND_HALF_EVEN)),
        "-0.950743877",
    )

    # Zero is exact in all three, and the loop could not settle on it.
    for mode in [RoundingMode.ROUND_UP, RoundingMode.ROUND_FLOOR]:
        assert_equal(String(sin_rounded(BDec("0"), 9, mode)), "0")
        assert_equal(String(cos_rounded(BDec("0"), 9, mode)), "1")
        assert_equal(String(tan_rounded(BDec("0"), 9, mode)), "0")


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
