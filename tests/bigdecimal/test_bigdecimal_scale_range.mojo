"""
Scales at the edge of what a `BigDecimal` holds.

A scale is an `Int`, and `Int` wraps silently. A parsed exponent past it came
out as a small one -- `1E18446744073709551916` read as `1E+300` -- and a scale
doubled by squaring wrapped the same way, so `10 ** 1E+19` printed
`1E-8446744073709551616`. Scales now stay within `MAX_SCALE`, a quarter of
`Int.MAX`, and a result past it raises `OverflowError`.

A rounded sum used to be built from the exact one, and with two operands
`10^18` digits apart that allocation took the process down. It is now formed
from the operands and the precision alone.
"""

from std import testing
from std.testing import assert_equal, assert_raises

from decimo.bigdecimal.arithmetics import add, add_inplace, subtract
from decimo.bigdecimal.bigdecimal import BDec
from decimo.bigfloat.bigfloat import BigFloat
from decimo.bigint.bigint import BigInt
from decimo.rounding_mode import RoundingMode
from decimo.str import MAX_SCALE


def test_an_exponent_past_the_limit_is_refused() raises:
    """The parser raises rather than wrap, for every type that uses it."""
    for text in [
        "1E18446744073709551916",
        "1E-18446744073709551916",
        "1E+9223372036854775808",
        "1E+" + String(MAX_SCALE + 1),
        "0.5E-" + String(MAX_SCALE),
    ]:
        with assert_raises(contains="beyond"):
            _ = BDec(text)
        with assert_raises():
            _ = BigInt(text)
        with assert_raises():
            _ = BigFloat(text)
    assert_equal(
        String(BDec("1E+" + String(MAX_SCALE))),
        "1E+" + String(MAX_SCALE),
    )
    assert_equal(
        String(BDec("1E-" + String(MAX_SCALE))),
        "1E-" + String(MAX_SCALE),
    )


def test_a_product_past_the_limit_is_refused() raises:
    """Multiplying and dividing check the scale they form."""
    var huge = BDec("1E+" + String(MAX_SCALE // 2 + 1))
    with assert_raises(contains="too large"):
        _ = huge.multiply(huge)
    with assert_raises(contains="too large"):
        _ = huge * huge
    var tiny = BDec("1E-" + String(MAX_SCALE // 2 + 1))
    with assert_raises(contains="too small"):
        _ = tiny * tiny
    with assert_raises(contains="too small"):
        _ = tiny / huge


def test_a_power_past_the_range_is_refused() raises:
    """Powers whose answer has no scale to hold it, by either route."""
    var cases: List[Tuple[String, String, String]] = [
        ("10", "1E+19", "too large"),
        ("1E+1000", "1E+1000", "too large"),
        ("1.5", "1E+1000", "too large"),
        ("2", "123456789012345678901234567890", "too large"),
        ("1.0000001", "1E+30", "too large"),
        ("0.0001", "1E+1000", "too small"),
        ("10", "-1E+19", "too small"),
    ]
    for item in cases:
        var base = BDec(item[0])
        var exponent = BDec(item[1])
        with assert_raises(contains=item[2]):
            _ = base**exponent
        with assert_raises(contains=item[2]):
            _ = base.power(exponent)
        with assert_raises(contains=item[2]):
            _ = base.power(exponent, 28, RoundingMode.ROUND_DOWN)


def test_a_power_with_a_long_whole_exponent() raises:
    """A base of one digit and a scale, raised past a thousand million."""
    assert_equal(String(BDec(-1).power(BDec(1000000000))), "1")
    assert_equal(
        String(BDec(-1).power(BDec(1000000001), 28, RoundingMode.ROUND_DOWN)),
        "-1",
    )
    assert_equal(
        String(BDec(-1).power(BDec("1E+20"), 28, RoundingMode.ROUND_UP)),
        "1",
    )
    assert_equal(String(BDec(-1) ** BDec("1E+20")), "1")
    assert_equal(String(BDec(10).power(BDec(1000000000))), "1E+1000000000")
    assert_equal(String(BDec("0.1").power(BDec(1000000000))), "1E-1000000000")


def test_a_power_with_a_large_product_keeps_its_digits() raises:
    """`y * ln(x)` in the thousands of millions, against Python's `decimal`.

    The exponential turns the product's absolute error into the answer's
    relative error, so its integer digits have to be carried as well.
    """
    var cases: List[Tuple[String, String, String]] = [
        ("2", "1E+12", "9.576244231492743284805059496E+301029995663"),
        ("2", "-1E+12", "1.044250726930468202952436781E-301029995664"),
        (
            "2",
            "1000000000000000.5",
            "2.216811351907101362435154942E+301029995663981",
        ),
        ("2", "10000000000", "4.363268634556242898858291088E+3010299956"),
    ]
    for item in cases:
        var base = BDec(item[0])
        var exponent = BDec(item[1])
        assert_equal(
            String(base**exponent), item[2], item[0] + "**" + item[1]
        )
        assert_equal(
            String(base.power(exponent)), item[2], item[0] + "^" + item[1]
        )


def test_a_rounded_sum_beside_a_huge_gap() raises:
    """Operands `MAX_SCALE` digits apart, which used to abort the process."""
    var huge = BDec("1E+" + String(MAX_SCALE))
    var tiny = BDec("1E-" + String(MAX_SCALE))
    var one = BDec(1)
    var huge_text = "1.000000000000000000000000000E+" + String(MAX_SCALE)
    assert_equal(String(huge + one), huge_text)
    assert_equal(String(huge - one), huge_text)
    assert_equal(String(one + tiny), "1.000000000000000000000000000")
    assert_equal(
        String(add(one, tiny, 28, RoundingMode.ROUND_UP)),
        "1.000000000000000000000000001",
    )
    assert_equal(
        String(subtract(one, tiny, 28, RoundingMode.ROUND_DOWN)),
        "0.9999999999999999999999999999",
    )
    assert_equal(
        String(BDec("0E-" + String(MAX_SCALE)) + one),
        "1.000000000000000000000000000",
    )
    var x = BDec(1)
    x += tiny
    assert_equal(String(x), "1.000000000000000000000000000")
    x -= huge
    assert_equal(String(x), "-" + huge_text)


def test_a_rounded_sum_beside_a_far_operand_matches_the_exact_sum() raises:
    """The shortcut against rounding the exact sum, near every boundary.

    The near operands end in tails that sit on, just below and just above a
    midpoint, and on a power of ten, so that a stand-in placed one digit too
    high would move a rounding. The far operands run from just past where the
    shortcut starts to well past it, with both signs.
    """
    var nears: List[String] = [
        "1",
        "1000",
        "-1000",
        "12345",
        "1234.5",
        "12344.5",
        "1.23449999",
        "1.234500000000001",
        "99999",
        "-99999.5",
        "100000",
        "0.00012345",
    ]
    var modes: List[RoundingMode] = [
        RoundingMode.ROUND_DOWN,
        RoundingMode.ROUND_UP,
        RoundingMode.ROUND_HALF_UP,
        RoundingMode.ROUND_HALF_DOWN,
        RoundingMode.ROUND_HALF_EVEN,
        RoundingMode.ROUND_CEILING,
        RoundingMode.ROUND_FLOOR,
    ]
    for near_text in nears:
        var near = BDec(near_text)
        for gap in range(3, 30):
            for far_text in ["1", "-1", "9", "-5", "4.99"]:
                var far = BDec(far_text + "E" + String(near.adjusted() - gap))
                for precision in [1, 3, 5, 8]:
                    for mode in modes:
                        var exact = add(near, far)
                        exact.round_to_precision_inplace(
                            precision,
                            mode,
                            remove_extra_digit_due_to_rounding=True,
                            fill_zeros_to_precision=False,
                        )
                        var label = (
                            near_text
                            + " + "
                            + String(far)
                            + " at "
                            + String(precision)
                            + " in "
                            + String(mode)
                        )
                        assert_equal(
                            String(add(near, far, precision, mode)),
                            String(exact),
                            label,
                        )
                        assert_equal(
                            String(add(far, near, precision, mode)),
                            String(exact),
                            label + ", swapped",
                        )
                        var accumulated = near.copy()
                        add_inplace(accumulated, far, precision, mode)
                        assert_equal(
                            String(accumulated), String(exact), label + ", +="
                        )
                        assert_equal(
                            String(subtract(near, -far, precision, mode)),
                            String(exact),
                            label + ", as a subtraction",
                        )


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
