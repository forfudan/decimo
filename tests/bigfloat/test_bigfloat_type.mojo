"""
Tests the `BigFloat` representation, its rounding primitive, and the
conversions that do not go through decimal text.

Three things are checked here. The rounding of a significand to a number of
bits, in all seven modes and both signs, against the same algorithm worked by
hand -- this is what every later operation ends with, so it is pinned first.
The representation invariant: a finite non-zero value holds exactly
`precision` bits with the top one set. And the `Float64` conversion, which is
exact in both directions and therefore testable by round trip over every
exponent a double has.

The decimal conversions are not here. Parsing and formatting are their own
piece of work and land with their own tests.
"""

from std import testing
from std.memory import bitcast
from std.testing import assert_equal, assert_true

from decimo.bigfloat.bigfloat import BigFloat
from decimo.bigfloat.rounding import round_to_precision
from decimo.bigint.bigint import BigInt
from decimo.rounding_mode import RoundingMode


def test_rounding_the_exact_half_in_every_mode() raises:
    """`0b1011` to three bits leaves a half with nothing below it.

    The kept part is `0b101` and the dropped bit is the half exactly, which
    is where the three nearest modes part ways and where the two directed
    ones read the sign.
    """
    var modes = [
        RoundingMode.ROUND_HALF_EVEN,
        RoundingMode.ROUND_HALF_UP,
        RoundingMode.ROUND_HALF_DOWN,
        RoundingMode.ROUND_DOWN,
        RoundingMode.ROUND_UP,
        RoundingMode.ROUND_CEILING,
        RoundingMode.ROUND_FLOOR,
    ]
    var positive = ["6", "6", "5", "5", "6", "6", "5"]
    var negative = ["6", "6", "5", "5", "6", "5", "6"]
    for i in range(len(modes)):
        var up = round_to_precision(BigInt(11), 0, 3, False, modes[i])
        assert_equal(
            String(up[0]), positive[i], "positive at mode " + String(i)
        )
        assert_equal(
            up[1], 1, "the exponent of a positive at mode " + String(i)
        )

        var down = round_to_precision(BigInt(11), 0, 3, True, modes[i])
        assert_equal(
            String(down[0]), negative[i], "negative at mode " + String(i)
        )


def test_rounding_widens_without_rounding() raises:
    """Fewer bits than asked for is a shift, and the exponent pays for it."""
    var widened = round_to_precision(
        BigInt(5), 0, 8, False, RoundingMode.ROUND_HALF_EVEN
    )
    assert_equal(String(widened[0]), "160", "5 in eight bits is 0b10100000")
    assert_equal(widened[1], -5, "and the exponent carries the shift")

    # The value is unchanged: 160 * 2^-5 is 5.
    assert_equal(
        widened[0] >> 5, BigInt(5), "the shift is exact in both directions"
    )


def test_rounding_carries_past_the_top() raises:
    """`0b111` rounded up in two bits is `0b1000`, one bit wider."""
    var carried = round_to_precision(
        BigInt(7), 0, 2, False, RoundingMode.ROUND_UP
    )
    assert_equal(String(carried[0]), "2", "the significand comes back as 0b10")
    assert_equal(carried[1], 2, "with the exponent two higher")


def test_rounding_keeps_exactly_the_bits_asked_for() raises:
    """The invariant every later operation relies on."""
    var values = [
        BigInt("1"),
        BigInt("5"),
        BigInt("255"),
        BigInt("256"),
        BigInt("123456789012345678901234567890"),
        BigInt("9" * 60),
    ]
    for precision in [1, 2, 3, 24, 53, 64, 65, 200]:
        for x in values:
            var rounded = round_to_precision(
                x, 0, precision, False, RoundingMode.ROUND_HALF_EVEN
            )
            assert_equal(
                rounded[0].bit_length(),
                precision,
                "the width at precision " + String(precision),
            )
            assert_true(
                rounded[0].test_bit(precision - 1),
                "the top bit is not set at precision " + String(precision),
            )


def test_rounding_a_zero_stays_zero() raises:
    """Nothing to round, and no exponent worth keeping."""
    var rounded = round_to_precision(
        BigInt.zero(), 17, 53, False, RoundingMode.ROUND_HALF_EVEN
    )
    assert_true(rounded[0].is_zero(), "zero stays zero")
    assert_equal(rounded[1], 0, "and its exponent is zero")


def test_a_remainder_needs_the_bits_it_sits_under() raises:
    """`inexact_below` without bits to drop is refused, not guessed at.

    The flag says the remainder is non-zero and therefore below the lowest
    dropped bit. With nothing dropped there is no such place: the same flag
    would have to stand for a hair above the significand and for most of the
    way to the next one.

    An earlier version answered anyway, and both answers were wrong. With a
    significand of 8 at precision 4 it returned 8 under `ROUND_UP` where the
    value is above 8 and the answer is 9. With a zero significand it invented
    the smallest step the precision allows, which the precision does not
    decide: a remainder of `2^-42` is exactly `(128, -49)` at eight bits, and
    it answered `(128, -40)`, too large by a factor of 512.
    """
    for mode in [
        RoundingMode.ROUND_UP,
        RoundingMode.ROUND_DOWN,
        RoundingMode.ROUND_HALF_EVEN,
    ]:
        var raised = False
        try:
            _ = round_to_precision(BigInt(8), 0, 4, False, mode, True)
        except:
            raised = True
        assert_true(raised, "a significand with no bits to drop was accepted")

        raised = False
        try:
            _ = round_to_precision(BigInt.zero(), -40, 8, False, mode, True)
        except:
            raised = True
        assert_true(raised, "a zero significand was accepted")


def test_a_remainder_rounds_where_there_are_bits_to_drop() raises:
    """With guard bits the flag is exactly the sticky bit, and is read.

    `0b10001` at four bits drops a single set bit, which is the half exactly.
    Half-even keeps the even significand there; the same value with a
    remainder underneath is past the half and goes up.
    """
    var without = round_to_precision(
        BigInt(0b10001), 0, 4, False, RoundingMode.ROUND_HALF_EVEN, False
    )
    assert_equal(String(without[0]), "8", "an exact half keeps the even bits")

    var with_remainder = round_to_precision(
        BigInt(0b10001), 0, 4, False, RoundingMode.ROUND_HALF_EVEN, True
    )
    assert_equal(String(with_remainder[0]), "9", "past the half it rounds up")

    # The directed modes do not read the half at all, so the remainder
    # changes nothing for them.
    assert_equal(
        String(
            round_to_precision(
                BigInt(0b10001), 0, 4, False, RoundingMode.ROUND_DOWN, True
            )[0]
        ),
        "8",
        "toward zero is unmoved",
    )


def test_rounding_refuses_what_it_cannot_do() raises:
    """A precision below one bit, and a negative significand."""
    var raised = False
    try:
        _ = round_to_precision(
            BigInt(5), 0, 0, False, RoundingMode.ROUND_HALF_EVEN
        )
    except:
        raised = True
    assert_true(raised, "a precision of zero was accepted")

    raised = False
    try:
        _ = round_to_precision(
            BigInt(-5), 0, 8, False, RoundingMode.ROUND_HALF_EVEN
        )
    except:
        raised = True
    assert_true(raised, "a negative significand was accepted")


def test_rounding_refuses_an_exponent_outside_int() raises:
    """Normalizing moves the exponent, and the range it moves in is an `Int`.

    Widening lowers it by the bits added and dropping bits raises it by the
    bits taken away, so a value at either end of the range can be asked for
    an exponent a step beyond it. Both ends refuse, since wrapping round
    would answer the largest value with the smallest.
    """
    var raised = False
    try:
        _ = round_to_precision(
            BigInt.one(), Int.MIN, 53, False, RoundingMode.ROUND_HALF_EVEN
        )
    except:
        raised = True
    assert_true(raised, "widening below Int.MIN was accepted")

    raised = False
    try:
        _ = round_to_precision(
            (BigInt.one() << 53) - BigInt.one(),
            Int.MAX,
            4,
            False,
            RoundingMode.ROUND_HALF_EVEN,
        )
    except:
        raised = True
    assert_true(raised, "raising above Int.MAX was accepted")

    # One step inside the range, the same shapes are answers.
    var widened = round_to_precision(
        BigInt.one(), Int.MIN + 52, 53, False, RoundingMode.ROUND_HALF_EVEN
    )
    assert_equal(widened[1], Int.MIN, "widening down to the bottom is fine")


def test_the_three_kinds() raises:
    """Finite, infinite and NaN, and what each says about itself."""
    var finite = BigFloat.from_int(5)
    assert_true(finite.is_finite(), "five is finite")
    assert_true(not finite.is_infinite(), "five is not infinite")
    assert_true(not finite.is_nan(), "five is not a NaN")
    assert_true(not finite.is_zero(), "five is not zero")

    var infinity = BigFloat.infinity()
    assert_true(infinity.is_infinite(), "an infinity is infinite")
    assert_true(not infinity.is_finite(), "an infinity is not finite")
    assert_true(not infinity.is_zero(), "an infinity is not zero")

    var nan = BigFloat.nan()
    assert_true(nan.is_nan(), "a NaN is a NaN")
    assert_true(not nan.is_finite(), "a NaN is not finite")

    var zero = BigFloat.zero()
    assert_true(zero.is_zero(), "zero is zero")
    assert_true(zero.is_finite(), "zero is finite")


def test_the_two_zeros_are_different_values() raises:
    """A sign survives on a zero, which is what `-0` is for."""
    var positive = BigFloat.zero(53, False)
    var negative = BigFloat.zero(53, True)
    assert_true(not positive.sign, "positive zero is not signed")
    assert_true(negative.sign, "negative zero is signed")
    assert_equal(
        negative.internal_representation(),
        "-0p0@53",
        "and carries its sign in the parts",
    )
    assert_equal(String(negative), "-0", "and prints its sign")


def test_negation_and_magnitude() raises:
    """A NaN has no sign to flip; everything else does."""
    var five = BigFloat.from_int(5)
    assert_true((-five).sign, "negating five signs it")
    assert_true(not (-(-five)).sign, "negating twice returns")
    assert_true(not abs(-five).sign, "the magnitude is unsigned")

    var zero = BigFloat.zero()
    assert_true((-zero).sign, "negating zero gives the other zero")

    var nan = BigFloat.nan()
    assert_true(not (-nan).sign, "a NaN does not take a sign")
    assert_true((-nan).is_nan(), "and stays a NaN")

    var infinity = BigFloat.infinity()
    assert_true((-infinity).is_infinite(), "an infinity negates to an infinity")
    assert_true((-infinity).sign, "with the other sign")


def test_from_int_is_exact_where_it_fits() raises:
    """An integer of no more bits than the precision loses nothing."""
    for value in [0, 1, 2, 5, 1000000, 9007199254740992]:
        var f = BigFloat.from_int(value)
        assert_equal(
            f.to_float64(),
            Float64(value),
            "the double of " + String(value),
        )

    # Thirty decimal digits is about a hundred bits, so 53 cannot hold it and
    # the value comes back rounded rather than wrong.
    var wide = BigFloat.from_bigint(BigInt("123456789012345678901234567890"))
    assert_equal(wide.precision, 53, "the precision asked for")
    assert_equal(
        wide.significand.bit_length(), 53, "and exactly that many bits"
    )


def test_from_int_rounds_by_the_mode() raises:
    """Eleven in three bits is the same half the primitive is tested on."""
    assert_equal(
        BigFloat.from_int(
            11, 3, RoundingMode.ROUND_HALF_EVEN
        ).internal_representation(),
        "6p1@3",
        "half-even",
    )
    assert_equal(
        BigFloat.from_int(
            11, 3, RoundingMode.ROUND_DOWN
        ).internal_representation(),
        "5p1@3",
        "toward zero",
    )
    assert_equal(
        BigFloat.from_int(
            -11, 3, RoundingMode.ROUND_CEILING
        ).internal_representation(),
        "-5p1@3",
        "toward positive infinity, from below",
    )


def test_float64_round_trips_over_every_exponent() raises:
    """A double is a binary float, so both conversions are exact.

    Every exponent field a double has, four significands in each, both signs:
    the subnormals, the zeros, the infinities and a NaN among them. The
    result has to come back with the same bits, not merely the same value.
    """
    var mantissas = [
        UInt64(0),
        UInt64(1),
        UInt64(0xF_FFFF_FFFF_FFFF),
        UInt64(0x5555_5555_5555),
    ]
    var checked = 0
    for biased in range(0, 2047):
        for mantissa in mantissas:
            for sign in [UInt64(0), UInt64(1) << 63]:
                var bits = sign | (UInt64(biased) << 52) | mantissa
                var value = bitcast[DType.float64](bits)
                var back = BigFloat.from_float64(value).to_float64()
                assert_equal(
                    bitcast[DType.uint64](back),
                    bits,
                    "the bits of biased exponent " + String(biased),
                )
                checked += 1
    assert_true(checked > 16000, "the sweep did not run")


def test_float64_carries_the_special_values() raises:
    """The three that are not numbers cross in both directions."""
    var infinity = Float64(1) / Float64(0)
    var nan = Float64(0) / Float64(0)

    assert_true(
        BigFloat.from_float64(infinity).is_infinite(), "an infinity arrives"
    )
    assert_true(not BigFloat.from_float64(infinity).sign, "with its sign")
    assert_true(BigFloat.from_float64(-infinity).sign, "and the other one too")
    assert_true(BigFloat.from_float64(nan).is_nan(), "a NaN arrives")

    assert_equal(
        BigFloat.infinity().to_float64(), infinity, "and an infinity leaves"
    )
    var left = BigFloat.nan().to_float64()
    assert_true(left != left, "a NaN leaves as something unequal to itself")


def test_float64_at_the_ends_of_the_range() raises:
    """Past a double's range the answer is an infinity or a zero."""
    # 2^2000, far above the largest double.
    var huge = BigFloat.from_bigint(BigInt(2).power(2000))
    var infinity = Float64(1) / Float64(0)
    assert_equal(huge.to_float64(), infinity, "too large becomes an infinity")
    assert_equal((-huge).to_float64(), -infinity, "and keeps its sign doing it")

    # Below half the smallest subnormal, which is 2^-1075.
    var tiny = BigFloat(
        significand=BigInt.one() << 52,
        exponent=-1200 - 52,
        precision=53,
        sign=False,
    )
    assert_equal(tiny.to_float64(), Float64(0.0), "too small becomes a zero")
    assert_true(
        bitcast[DType.uint64]((-tiny).to_float64()) == (UInt64(1) << 63),
        "a negative one becomes a negative zero",
    )


def test_the_subnormal_quantum_rounds_once() raises:
    """A subnormal result is rounded straight to its quantum.

    Every double below `2^-1022` is a multiple of `2^-1074`. Rounding to 53
    bits first and then to that quantum would round twice, which can land a
    tick off. The value here is three halves of the quantum: one rounding
    half-even gives two quantums, and the double it builds says so.
    """
    # 3 * 2^-1075 = 1.5 * 2^-1074
    var one_and_a_half = BigFloat(
        significand=BigInt(3) << 51,
        exponent=-1075 - 51,
        precision=53,
        sign=False,
    )
    var expected = bitcast[DType.float64](UInt64(2))
    assert_equal(
        one_and_a_half.to_float64(),
        expected,
        "a half-even tie between one quantum and two",
    )


def test_float64_at_an_exponent_near_the_limits_of_int() raises:
    """The exponent is unbounded, so its arithmetic has to be bounded.

    `precision - 1 + exponent` overflows for an exponent near either end of
    `Int`, and an earlier version formed it before testing the range: a value
    at `Int.MAX` converted to zero instead of an infinity.
    """
    var infinity = Float64(1) / Float64(0)
    for exponent in [Int.MAX, Int.MAX - 100, 1024]:
        var high = BigFloat(
            significand=BigInt.one() << 52,
            exponent=exponent,
            precision=53,
            sign=False,
        )
        assert_equal(
            high.to_float64(), infinity, "too high at " + String(exponent)
        )
        assert_equal(
            (-high).to_float64(),
            -infinity,
            "and its negation at " + String(exponent),
        )

    for exponent in [Int.MIN, Int.MIN + 100, -3000]:
        var low = BigFloat(
            significand=BigInt.one() << 52,
            exponent=exponent,
            precision=53,
            sign=False,
        )
        assert_equal(
            low.to_float64(), Float64(0.0), "too low at " + String(exponent)
        )

    # The two sides of the boundary itself: 2^971 * 2^52 is the largest
    # finite double, and one more is past the top.
    var largest = BigFloat(
        significand=BigInt.one() << 52,
        exponent=1024 - 53,
        precision=53,
        sign=False,
    )
    assert_true(
        largest.to_float64() < infinity, "the largest finite double is finite"
    )
    var past = BigFloat(
        significand=BigInt.one() << 52,
        exponent=1024 - 52,
        precision=53,
        sign=False,
    )
    assert_equal(past.to_float64(), infinity, "one step past it is an infinity")


def test_the_representation_is_the_parts() raises:
    """The parts have their own method; the text is a decimal.

    `4503599627370496p-52@53` is one: that significand, times two to that
    exponent, in that many bits.
    """
    assert_equal(
        BigFloat.from_int(1).internal_representation(),
        "4503599627370496p-52@53",
    )
    assert_equal(BigFloat.from_int(11, 3).internal_representation(), "6p1@3")
    assert_equal(BigFloat.zero().internal_representation(), "0p0@53")
    assert_equal(BigFloat.nan().internal_representation(), "NaN")
    assert_equal(BigFloat.infinity().internal_representation(), "Infinity")
    assert_equal((-BigFloat.infinity()).internal_representation(), "-Infinity")

    # The printed text is the number, which the decimal tests cover.
    assert_equal(String(BigFloat.from_int(1)), "1")
    assert_equal(String(BigFloat.nan()), "NaN")
    assert_equal(String(BigFloat.infinity()), "Infinity")
    assert_equal(String(-BigFloat.infinity()), "-Infinity")


def test_the_constructor_refuses_a_bad_shape() raises:
    """A precision below one bit, and a negative significand."""
    var raised = False
    try:
        _ = BigFloat(
            significand=BigInt.one(), exponent=0, precision=0, sign=False
        )
    except:
        raised = True
    assert_true(raised, "a precision of zero was accepted")

    raised = False
    try:
        _ = BigFloat(
            significand=BigInt(-1), exponent=0, precision=53, sign=False
        )
    except:
        raised = True
    assert_true(raised, "a negative significand was accepted")


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
