"""
Tests for the fixed-width accumulator `Wide` and its fixed-point form, which
the `Decimal128` series run in.
"""

from std import testing
from std.testing import assert_equal, assert_false, assert_true

from decimo.decimal128.decimal128 import Decimal128
from decimo.decimal128.wide import (
    FIXED_ONE,
    Extended,
    Wide,
    extended_e_hundredth,
    extended_e_power_of_two,
    extended_e_tenth,
    extended_ln10,
    extended_ln2,
    fixed_divide_by_int,
    fixed_from_wide,
    fixed_multiply,
    wide_e_hundredth,
    wide_e_power_of_two,
    wide_e_tenth,
    wide_from_fixed,
    wide_ln10,
    wide_ln2,
)


def test_wide_round_trip() raises:
    """A `Decimal128` widened and narrowed again is the same number."""

    def _check(text: String) raises:
        assert_equal(
            String(Wide.from_decimal(Decimal128(text)).to_decimal()), text
        )

    _check("1")
    _check("0")
    _check("-1")
    _check("123.456")
    _check("0.0000000000000000000000000001")
    _check("79228162514264337593543950335")
    _check("-79228162514264337593543950335")


def test_wide_arithmetic() raises:
    """The four operations agree with what `Decimal128` gets for values it
    holds exactly."""
    var three = Wide.from_int(3)
    var four = Wide.from_int(4)
    assert_equal(String((three + four).to_decimal()), "7")
    assert_equal(String((three - four).to_decimal()), "-1")
    assert_equal(String((three * four).to_decimal()), "12")
    assert_equal(String((three / four).to_decimal()), "0.75")
    assert_equal(String(four.divide_by_int(8).to_decimal()), "0.5")
    assert_true((three - three).is_zero())


def test_wide_carries_more_than_decimal128() raises:
    """A third, tripled, comes back whole.

    In `Decimal128` the same round trip loses the last digit, which is the
    reason this type exists.
    """
    var third = Wide.from_int(1) / Wide.from_int(3)
    # Ten digits of headroom, so the third that came back rounds to one
    # across every digit `Decimal128` keeps. The trailing zeros stay: the
    # value is not exactly one, and saying so is the point.
    assert_equal(
        String((third * Wide.from_int(3)).to_decimal()),
        "1.0000000000000000000000000000",
    )


def test_wide_rounds_once() raises:
    """Narrowing rounds half-even, from the digits the accumulator holds."""
    var value = Wide.from_int(1) / Wide.from_int(3)
    assert_equal(String(value.to_decimal()), "0.3333333333333333333333333333")
    var two_thirds = Wide.from_int(2) / Wide.from_int(3)
    assert_equal(
        String(two_thirds.to_decimal()), "0.6666666666666666666666666667"
    )


def test_wide_truncation_and_scaling() raises:
    """Whole parts and decimal shifts."""
    assert_equal(Wide.from_decimal(Decimal128("7.9")).to_int_truncated(), 7)
    assert_equal(Wide.from_decimal(Decimal128("-7.9")).to_int_truncated(), -7)
    assert_equal(Wide.from_decimal(Decimal128("0.4")).to_int_truncated(), 0)
    assert_equal(Wide.from_decimal(Decimal128("7.5")).to_int_nearest(), 8)
    assert_equal(Wide.from_decimal(Decimal128("-7.5")).to_int_nearest(), -8)
    assert_equal(
        Wide.from_decimal(Decimal128("0.25"))
        .scaled_by_power_of_ten(2)
        .to_int_truncated(),
        25,
    )


def test_wide_constants() raises:
    """The stored constants are right to every digit they carry."""
    assert_equal(
        String(wide_ln2().to_decimal()), "0.6931471805599453094172321215"
    )
    assert_equal(
        String(wide_ln10().to_decimal()), "2.3025850929940456840179914547"
    )
    assert_equal(
        String(wide_e_power_of_two(0).to_decimal()),
        "2.7182818284590452353602874714",
    )
    assert_equal(
        String(wide_e_power_of_two(6).to_decimal()),
        "6235149080811616882909238708.9",
    )
    assert_equal(String(wide_e_tenth(0).to_decimal()), "1")
    assert_equal(
        String(wide_e_tenth(5).to_decimal()), "1.6487212707001281468486507878"
    )
    assert_equal(String(wide_e_hundredth(0).to_decimal()), "1")
    assert_equal(
        String(wide_e_hundredth(5).to_decimal()),
        "1.0512710963760240396975176363",
    )


def test_fixed_point() raises:
    """The fixed-point form the series use."""
    var half = fixed_from_wide(Wide.from_decimal(Decimal128("0.5")))
    assert_equal(String(wide_from_fixed(half).to_decimal()), "0.5")
    assert_equal(fixed_multiply(half, half) * Int256(4), FIXED_ONE)
    assert_equal(fixed_divide_by_int(FIXED_ONE, 4) * Int256(4), FIXED_ONE)

    var negative = fixed_from_wide(Wide.from_decimal(Decimal128("-0.5")))
    assert_equal(negative, -half)
    # Truncation is toward zero on both sides, so a product and its negation
    # stay symmetric rather than drifting a unit apart.
    assert_equal(fixed_multiply(negative, half), -fixed_multiply(half, half))
    assert_equal(
        fixed_divide_by_int(negative, 3), -fixed_divide_by_int(half, 3)
    )

    # A value far below the fixed scale reads as zero rather than reaching
    # past the reciprocal table.
    var tiny = Wide(UInt256(1), -200, False)
    assert_equal(fixed_from_wide(tiny), Int256(0))


def test_extended_arithmetic() raises:
    """The second width, whose mantissas are too long to multiply directly.

    A product of two 75-digit numbers has 150 digits and no register holds
    it, so it is assembled from halves; a quotient is a narrow reciprocal
    doubled by one Newton step. Both are checked here against values whose
    digits are known.
    """
    var one = Extended.from_int(1)
    var three = Extended.from_int(3)
    var seven = Extended.from_int(7)

    # A third, three times, is one across every digit `Decimal128` prints.
    assert_equal(
        String(((one / three) * three).to_decimal()),
        "1.0000000000000000000000000000",
    )
    assert_equal(
        String(((one / seven) * seven).to_decimal()),
        "1.0000000000000000000000000000",
    )
    assert_equal(
        String((one / three).to_decimal()), "0.3333333333333333333333333333"
    )
    assert_equal(
        String((three / seven).to_decimal()), "0.4285714285714285714285714286"
    )

    # Signs on both sides of a division.
    assert_equal(
        String((one / (-three)).to_decimal()), "-0.3333333333333333333333333333"
    )
    assert_equal(
        String(((-one) / three).to_decimal()), "-0.3333333333333333333333333333"
    )
    assert_equal(
        String(((-one) / (-three)).to_decimal()),
        "0.3333333333333333333333333333",
    )

    # Adding across a gap wider than the mantissa leaves the larger alone.
    var tiny = Extended(UInt256(1), -300, False)
    assert_equal(String((one + tiny).to_decimal()), "1")
    assert_equal(String((one - one).to_decimal()), "0")


def test_extended_holds_more_digits_than_wide() raises:
    """A seventh, to 75 digits and to 38, agrees where they overlap."""
    var narrow = Wide.from_int(1) / Wide.from_int(7)
    var wide = Extended.from_int(1) / Extended.from_int(7)
    assert_equal(String(wide.to_width[38]().mantissa), String(narrow.mantissa))
    assert_equal(String(narrow.mantissa).byte_length(), 38)
    assert_equal(String(wide.mantissa).byte_length(), 75)


def test_both_widths_carry_the_same_constants() raises:
    """Narrowing a 75-digit constant gives the 38-digit one exactly.

    The two are written out separately, so this is what keeps them one
    value: a typo in either is a failure here.
    """

    def _same(narrow: Wide, wide: Extended) raises:
        var narrowed = wide.to_width[38]()
        assert_equal(String(narrowed.mantissa), String(narrow.mantissa))
        assert_equal(narrowed.exponent, narrow.exponent)

    _same(wide_ln2(), extended_ln2())
    _same(wide_ln10(), extended_ln10())
    for index in range(7):
        _same(wide_e_power_of_two(index), extended_e_power_of_two(index))
    for digit in range(10):
        _same(wide_e_tenth(digit), extended_e_tenth(digit))
        _same(wide_e_hundredth(digit), extended_e_hundredth(digit))


def test_conversion_refuses_an_undecided_rounding() raises:
    """With room to be wrong, a value on a boundary is not rounded.

    The mantissa below ends `...500000000`, exactly halfway between two
    `Decimal128` values. Trusted to the digit it is exact, that rounds to
    even; trusted only to within a hundred units, the true value could be on
    either side and there is no answer to give.
    """
    var on_the_tie = Wide(
        UInt256(12345678901234567890123456789500000000), -37, False
    )
    # Trusted to the digit, the tie goes to the even neighbour, which
    # carries the nine up.
    assert_equal(
        String(on_the_tie.to_decimal_decided(UInt256(0)).value()),
        "1.2345678901234567890123456790",
    )
    assert_false(Bool(on_the_tie.to_decimal_decided(UInt256(100))))

    # Far from any boundary, the same slack decides.
    var clear = Wide(
        UInt256(12345678901234567890123456789012345678), -37, False
    )
    assert_true(Bool(clear.to_decimal_decided(UInt256(100))))

    # Exactly on a multiple, which is the same case: the digits being
    # dropped are all zeros, but with room to be wrong the true value may
    # sit either side of the multiple, so this width cannot say the value
    # terminates here. `cos(1E-10)` is the one that showed it -- its 38
    # digits end in zeros and it continues `...41666` at the 41st.
    var on_a_multiple = Wide(
        UInt256(12345678901234567890123456789000000000), -37, False
    )
    assert_equal(
        String(on_a_multiple.to_decimal_decided(UInt256(0)).value()),
        "1.2345678901234567890123456789",
    )
    assert_false(Bool(on_a_multiple.to_decimal_decided(UInt256(100))))

    # Just above an exact multiple: the rounding is not in doubt, but the
    # claim that nothing was lost is, and that claim is what decides whether
    # the trailing zeros stay.
    var almost_exact = Wide(
        UInt256(12345678901234567890123456789000000007), -37, False
    )
    assert_equal(
        String(almost_exact.to_decimal_decided(UInt256(0)).value()),
        "1.2345678901234567890123456789",
    )
    assert_false(Bool(almost_exact.to_decimal_decided(UInt256(100))))


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
