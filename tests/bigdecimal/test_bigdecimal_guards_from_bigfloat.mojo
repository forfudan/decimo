"""
Answers that BigDecimal reached only through a loop that could not settle.

Each of these has a guard in BigFloat that the decimal layer never got. The
answer is exactly a value the destination holds, or a hair from one, and the
deciding loop cannot settle on either: the directed modes raised, or, for
`hypot` with a far smaller leg, the sum of squares ran out of memory. Each
case is pinned in every mode that tells the two sides apart.
"""

from std import testing
from std.testing import assert_equal

from decimo.bigdecimal.bigdecimal import BDec
from decimo.rounding_mode import RoundingMode


comptime DOWN = RoundingMode.ROUND_DOWN
comptime UP = RoundingMode.ROUND_UP
comptime FLOOR = RoundingMode.ROUND_FLOOR
comptime CEILING = RoundingMode.ROUND_CEILING
comptime HALF_EVEN = RoundingMode.ROUND_HALF_EVEN

comptime ONE = "1.000000000000000000000000000"
comptime ONE_UP = "1.000000000000000000000000001"
comptime BELOW_ONE = "0.9999999999999999999999999999"


def test_a_power_of_one_or_a_power_of_ten() raises:
    """Exact answers past the nine places the exact search looks at."""
    assert_equal(String(BDec(1).power(28, DOWN, exponent=BDec("1E-10"))), ONE)
    assert_equal(String(BDec(1).power(28, UP, exponent=BDec("1E-10"))), ONE)
    assert_equal(
        String(BDec("1E+1024").power(28, DOWN, exponent=BDec("0.0009765625"))),
        "10.00000000000000000000000000",
    )
    assert_equal(
        String(BDec("1E-1024").power(28, UP, exponent=BDec("0.0009765625"))),
        "0.1000000000000000000000000000",
    )
    assert_equal(
        String(BDec("0.01").power(28, CEILING, exponent=BDec("0.5"))),
        "0.1000000000000000000000000000",
    )


def test_a_power_a_hair_from_one() raises:
    """An exponent too small for `y ln(x)` to reach the last place."""
    var two = BDec(2)
    var half = BDec("0.5")
    var tiny = BDec("1E-500")
    assert_equal(String(two.power(28, DOWN, exponent=tiny)), ONE)
    assert_equal(String(two.power(28, UP, exponent=tiny)), ONE_UP)
    assert_equal(String(two.power(28, DOWN, exponent=-tiny)), BELOW_ONE)
    assert_equal(String(two.power(28, UP, exponent=-tiny)), ONE)
    assert_equal(String(half.power(28, FLOOR, exponent=tiny)), BELOW_ONE)
    assert_equal(String(half.power(28, CEILING, exponent=tiny)), ONE)
    assert_equal(String(BDec("1E+300").power(28, UP, exponent=tiny)), ONE_UP)


def test_the_operator_rounds_like_the_method() raises:
    """`**` gives what `power()` gives, which it did not in the last digit."""
    for item in [
        ("2", "10000000000"),
        ("2", "1000000000000000.5"),
        ("1", "0.5"),
        ("4", "0.5"),
        ("7", "31"),
        ("3.7", "-2.25"),
    ]:
        var base = BDec(item[0])
        var exponent = BDec(item[1])
        assert_equal(
            String(base**exponent),
            String(base.power(28, HALF_EVEN, exponent=exponent)),
            item[0] + " ** " + item[1],
        )
    var x = BDec(3)
    x **= BDec(4)
    assert_equal(String(x), "81")


def test_expm1_far_below_nought() raises:
    """Minus one plus a value below a guard unit of it."""
    for x in [BDec(-1000), BDec(-75), BDec("-1E+20")]:
        assert_equal(String(x.expm1(28, DOWN)), "-" + BELOW_ONE)
        assert_equal(String(x.expm1(28, CEILING)), "-" + BELOW_ONE)
        assert_equal(String(x.expm1(28, UP)), "-" + ONE)
        assert_equal(String(x.expm1(28, FLOOR)), "-" + ONE)
        assert_equal(String(x.expm1(28, HALF_EVEN)), "-" + ONE)


def test_arctan2_with_a_tiny_ratio() raises:
    """The angle is the ratio less a hair, exact ratio or not."""
    var tiny = BDec("1E-500")
    assert_equal(
        String(tiny.arctan2(28, DOWN, other=BDec(1))),
        "9.999999999999999999999999999E-501",
    )
    assert_equal(
        String(tiny.arctan2(28, UP, other=BDec(1))),
        "1.000000000000000000000000000E-500",
    )
    assert_equal(
        String(tiny.arctan2(28, DOWN, other=BDec(3))),
        "3.333333333333333333333333333E-501",
    )
    assert_equal(
        String(tiny.arctan2(28, UP, other=BDec(3))),
        "3.333333333333333333333333334E-501",
    )
    assert_equal(
        String((-tiny).arctan2(28, UP, other=BDec(7))),
        "-1.428571428571428571428571429E-501",
    )
    assert_equal(
        String((-tiny).arctan2(28, DOWN, other=BDec(7))),
        "-1.428571428571428571428571428E-501",
    )


def test_hypot_with_a_far_smaller_leg() raises:
    """The larger leg plus a hair, without squaring the smaller one."""
    var one = BDec(1)
    var far = BDec("1E-1000000000")
    assert_equal(String(one.hypot(28, DOWN, other=far)), ONE)
    assert_equal(String(one.hypot(28, UP, other=far)), ONE_UP)
    assert_equal(String(far.hypot(28, CEILING, other=-one)), ONE_UP)
    assert_equal(String(BDec(3).hypot(28, DOWN, other=BDec(4))), "5")


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
