"""
Tests the decimal conversions of `BigFloat`.

One direction is exact and the other rounds, so they are checked differently.

Coming in, the reference is CPython's own `float(text)`, which is correctly
rounded: at 53 bits the two agree on the bit pattern whenever the answer is a
normal double, because then one rounding happens and both make the same one.
A subnormal answer is the exception and has a test of its own. The comparison
is of bits rather than of printed text on purpose -- a formatter that prints
one digit fewer is not a conversion error, and two of these cases differ in
exactly that way.

Going out, the expansion is exact and can be checked against itself: a value
built from a decimal that fits the precision has to come back as that
decimal, and a value that does not fit has to come back as the exact binary
value it was rounded to, which CPython's `Decimal(float)` also prints.
"""

from std import testing
from std.memory import bitcast
from std.testing import assert_equal, assert_raises, assert_true

from decimo.bigdecimal.bigdecimal import BigDecimal
from decimo.bigfloat.bigfloat import BigFloat
from decimo.bigfloat.conversion import (
    _FIVE_POWER_SLACK,
    _FIXED_POINT_SLACK,
    _HALF,
    _NEITHER,
    _WHOLE,
    _boundary_kind,
    _five_power_truncated,
    _from_decimal_by_scaling,
    _from_decimal_exactly,
    _rounded_from_exact,
    _scaled_to_fixed_point,
    from_decimal_parts,
    to_rounded_bigdecimal,
)
from decimo.bigint.bigint import BigInt
from decimo.bigint.bitwise import trailing_zeros
from decimo.rounding_mode import RoundingMode


def test_parsing_agrees_with_cpython_at_53_bits() raises:
    """Every bit of `float(text)`, for the inputs that make it interesting.

    Powers of ten at both ends of the range, a value that needs a subnormal,
    two below the smallest one, the largest finite double, the two halves of
    `9007199254740993` where 53 bits run out, and the pair whose shortest
    decimal rendering disagrees with their value's digit count.
    """
    var texts = [
        "0.1",
        "0.2",
        "0.3",
        "0.5",
        "1",
        "2",
        "10",
        "0.30000000000000004",
        "9007199254740992",
        "9007199254740993",
        "1e300",
        "1e-300",
        "1.7976931348623157e308",
        "2.2250738585072014e-308",
        "4.9e-324",
        "1e-400",
        "1e400",
        "123456789012345678901234567890",
        "1234.5678",
        "-2.5",
        "-0.1",
        "58486257730153413.801801",
        "42679777501175387.1133376292",
        "3.141592653589793238462643383279502884197",
        "0.000001",
        "1e-320",
    ]
    var expected = [
        UInt64(4591870180066957722),
        UInt64(4596373779694328218),
        UInt64(4599075939470750515),
        UInt64(4602678819172646912),
        UInt64(4607182418800017408),
        UInt64(4611686018427387904),
        UInt64(4621819117588971520),
        UInt64(4599075939470750516),
        UInt64(4845873199050653696),
        UInt64(4845873199050653696),
        UInt64(9094988921128908188),
        UInt64(118622047889322841),
        UInt64(9218868437227405311),
        UInt64(4503599627370496),
        UInt64(1),
        UInt64(0),
        UInt64(9218868437227405312),
        UInt64(5042042089369253694),
        UInt64(4653144502051863213),
        UInt64(13836183955189006336),
        UInt64(13815242216921733530),
        UInt64(4857687580894293369),
        UInt64(4855711770865671115),
        UInt64(4614256656552045848),
        UInt64(4517329193108106637),
        UInt64(2024),
    ]
    for i in range(len(texts)):
        var parsed = BigFloat.from_string(texts[i])
        assert_equal(
            bitcast[DType.uint64](parsed.to_float64()),
            expected[i],
            "the bits of " + texts[i],
        )


def test_a_subnormal_answer_rounds_a_second_time() raises:
    """Parsing to 53 bits and then to a subnormal double rounds twice.

    A normal double is 53 bits, so a 53-bit `BigFloat` holds it exactly and
    `to_float64()` only reads it off. A subnormal double has fewer bits than
    that, so the second conversion rounds again, and two roundings can land a
    step away from the one: here the exact value is nearer the lower
    neighbour, but rounding it to 53 bits of precision first pushes it past
    the midpoint of the subnormal grid and the second rounding goes up.

    The value is not lost -- asking for a precision that leaves the grid room
    gives CPython's answer -- so this is a property of rounding to a
    precision rather than into an exponent range. Rounding into the range is
    what MPFR's `subnormalize` does, and this type cannot express a range yet.
    """
    var text = String("763178886372074e-323")
    assert_equal(
        bitcast[DType.uint64](BigFloat.from_string(text).to_float64()),
        1544691262782718,
        "53 bits, then the subnormal grid: two roundings",
    )
    assert_equal(
        bitcast[DType.uint64](BigFloat.from_string(text, 60).to_float64()),
        1544691262782717,
        "enough bits that only the second rounding decides, as in CPython",
    )


def test_a_tie_goes_the_way_the_mode_says() raises:
    """A decimal exactly between two binary floats, in every half mode.

    `9007199254740993` is the midpoint of `2^53` and `2^53 + 2`, the first
    place 53 bits run out, so nothing below the tie breaks it. Half-even
    takes the even one, half-up the one away from zero, half-down the one
    toward it, and the signs mirror.
    """
    var tie = String("9007199254740993")
    for negative in [False, True]:
        var text = String("-") + tie if negative else tie.copy()
        var sign = String("-") if negative else String("")
        var lower = BigDecimal(sign + "9007199254740992")
        var upper = BigDecimal(sign + "9007199254740994")
        assert_equal(
            BigFloat.from_string(
                text, 53, RoundingMode.ROUND_HALF_EVEN
            ).to_bigdecimal(),
            lower,
            "half-even takes the even significand",
        )
        assert_equal(
            BigFloat.from_string(
                text, 53, RoundingMode.ROUND_HALF_UP
            ).to_bigdecimal(),
            upper,
            "half-up goes away from zero",
        )
        assert_equal(
            BigFloat.from_string(
                text, 53, RoundingMode.ROUND_HALF_DOWN
            ).to_bigdecimal(),
            lower,
            "half-down goes toward zero",
        )

    # Just off the tie, the modes have nothing left to decide and agree.
    for mode in [
        RoundingMode.ROUND_HALF_EVEN,
        RoundingMode.ROUND_HALF_UP,
        RoundingMode.ROUND_HALF_DOWN,
    ]:
        assert_equal(
            BigFloat.from_string(
                "9007199254740993.1", 53, mode
            ).to_bigdecimal(),
            BigDecimal("9007199254740994"),
            "above the tie, every half mode rounds up",
        )
        assert_equal(
            BigFloat.from_string(
                "9007199254740992.9", 53, mode
            ).to_bigdecimal(),
            BigDecimal("9007199254740992"),
            "below the tie, every half mode rounds down",
        )


def test_the_expansion_is_exact() raises:
    """A binary float is a decimal, because `2^-k` is `5^k / 10^k`.

    The value here is the double nearest a tenth, whose exact expansion is
    what CPython's `Decimal(0.1)` prints -- fifty-five digits, none of them a
    rounding.
    """
    var tenth = BigFloat.from_float64(Float64(0.1))
    assert_equal(
        tenth.to_bigdecimal(),
        BigDecimal("0.1000000000000000055511151231257827021181583404541015625"),
        "the expansion of the double nearest a tenth",
    )

    # An integral value has no fractional part to expand.
    assert_equal(
        BigFloat.from_int(1000000).to_bigdecimal(),
        BigDecimal("1000000"),
        "an integer stays an integer",
    )

    # The smallest double is a power of two, so its expansion is a power of
    # five over a power of ten, and it is 751 digits long.
    var smallest = BigFloat.from_float64(bitcast[DType.float64](UInt64(1)))
    var expansion = smallest.to_bigdecimal()
    assert_equal(
        expansion.scale, 1074, "the smallest double has 1074 decimal places"
    )
    assert_equal(
        BigFloat.from_bigdecimal(expansion, 53).to_float64(),
        smallest.to_float64(),
        "and reading it back gives the same double",
    )


def test_a_decimal_that_fits_comes_back_whole() raises:
    """A value with few enough digits survives the trip both ways.

    Halves, quarters and eighths are binary floats exactly, so no rounding
    happens in either direction and the decimal that comes back is the one
    that went in.
    """
    for text in [
        "0.5",
        "0.25",
        "-0.125",
        "2.5",
        "1024",
        "0.0625",
        "123456789",
    ]:
        var value = BigFloat.from_string(text)
        assert_equal(
            value.to_bigdecimal(),
            BigDecimal(text),
            "the round trip of " + text,
        )


def test_a_high_precision_text_round_trips_its_digits() raises:
    """Two hundred bits hold sixty digits, and give them back.

    The digits are rounded once on the way in and once on the way out, so
    asking for fewer than the precision is worth -- sixty against about sixty
    is tight -- is what makes the trip lossless.
    """
    var digits = "3.14159265358979323846264338327950288419716939937510582097494"
    var value = BigFloat.from_string(digits, 200)
    assert_equal(
        value.to_bigdecimal_rounded(60),
        BigDecimal(digits),
        "sixty digits of pi through two hundred bits",
    )


def test_rounding_the_expansion_happens_once() raises:
    """The exact expansion is taken first, then rounded a single time.

    Rounding during the conversion and again to the digit count would be two
    roundings, which can land a step off. The check is that the shorter
    answer is what rounding the exact one gives.
    """
    var value = BigFloat.from_float64(Float64(0.1))
    var exact = value.to_bigdecimal()
    for digits in [1, 2, 5, 17, 20, 40]:
        var expected = exact.copy()
        expected.round_to_precision_inplace(
            precision=digits,
            rounding_mode=RoundingMode.ROUND_HALF_EVEN,
            remove_extra_digit_due_to_rounding=True,
            fill_zeros_to_precision=False,
        )
        assert_equal(
            value.to_bigdecimal_rounded(digits),
            expected,
            "at " + String(digits) + " digits",
        )


def test_the_rounding_mode_reaches_the_parsing() raises:
    """A tenth is between two doubles, and the mode picks which one.

    Toward zero takes the one below, away from zero the one above, and they
    differ by a single bit.
    """
    var down = BigFloat.from_string("0.1", 53, RoundingMode.ROUND_DOWN)
    var up = BigFloat.from_string("0.1", 53, RoundingMode.ROUND_UP)
    assert_equal(
        up.significand - down.significand,
        BigInt.one(),
        "the two sides differ by one unit in the last place",
    )
    assert_true(
        down.to_bigdecimal() < BigDecimal("0.1"), "toward zero lands below"
    )
    assert_true(
        up.to_bigdecimal() > BigDecimal("0.1"), "away from zero lands above"
    )

    # A negative value swaps which direction the two directed modes take.
    var ceiling = BigFloat.from_string("-0.1", 53, RoundingMode.ROUND_CEILING)
    var floor = BigFloat.from_string("-0.1", 53, RoundingMode.ROUND_FLOOR)
    assert_true(
        ceiling.to_bigdecimal() > BigDecimal("-0.1"),
        "toward positive infinity lands above",
    )
    assert_true(
        floor.to_bigdecimal() < BigDecimal("-0.1"),
        "toward negative infinity lands below",
    )


def test_the_three_names_parse() raises:
    """`nan`, `inf` and `infinity`, in any case and with a sign."""
    for text in ["nan", "NaN", "NAN"]:
        assert_true(BigFloat.from_string(text).is_nan(), text + " is not a NaN")
    for text in ["inf", "Inf", "INFINITY", "+inf", "+Infinity"]:
        var value = BigFloat.from_string(text)
        assert_true(value.is_infinite(), text + " is not an infinity")
        assert_true(not value.sign, text + " should be positive")
    for text in ["-inf", "-Infinity"]:
        var value = BigFloat.from_string(text)
        assert_true(value.is_infinite(), text + " is not an infinity")
        assert_true(value.sign, text + " should be negative")


def test_what_is_not_a_number_has_no_decimal() raises:
    """An infinity and a NaN are refused rather than invented."""
    for value in [BigFloat.nan(), BigFloat.infinity(), -BigFloat.infinity()]:
        var raised = False
        try:
            _ = value.to_bigdecimal()
        except:
            raised = True
        assert_true(raised, "a decimal was produced for " + String(value))

    # As text they are spelled out, which is what a reader expects to see.
    assert_equal(String(BigFloat.nan()), "NaN")
    assert_equal(String(BigFloat.infinity()), "Infinity")
    assert_equal(String(-BigFloat.infinity()), "-Infinity")


def test_text_is_decimal_and_the_parts_are_asked_for() raises:
    """A float prints as a number; the parts have their own method.

    An exact short value prints short -- `1`, not `1.0000000000000000` --
    because the expansion carries the smallest scale that holds it and
    nothing pads it back out. That is what `BigDecimal` does with the same
    value, and what CPython's `Decimal(1.0)` prints.
    """
    assert_equal(String(BigFloat.from_int(1)), "1", "one is one")
    assert_equal(
        String(BigFloat.from_string("0.1")),
        "0.10000000000000001",
        "a value that needs its digits gets them",
    )
    assert_equal(
        BigFloat.from_int(1).internal_representation(),
        "4503599627370496p-52@53",
        "the parts are still reachable",
    )
    assert_equal(
        BigFloat.from_string("-2.5").to_string(2),
        "-2.5",
        "a digit count can be asked for",
    )


def test_a_digit_count_must_be_positive() raises:
    var raised = False
    try:
        _ = BigFloat.from_int(1).to_bigdecimal_rounded(0)
    except:
        raised = True
    assert_true(raised, "zero digits were accepted")


def test_parsing_what_is_not_a_number_raises() raises:
    """The digits go to `BigDecimal`'s parser, and its refusals come back."""
    for text in ["", "abc", "1.2.3", "--1", "1e", "0x10"]:
        var raised = False
        try:
            _ = BigFloat.from_string(text)
        except:
            raised = True
        assert_true(raised, "the text " + text + " was accepted")


def test_bigdecimal_and_bigfloat_round_trip_at_high_precision() raises:
    """A decimal wide enough for the precision survives both conversions.

    Three hundred bits is about ninety digits, so eighty digits of decimal
    go in and come back unchanged.
    """
    var digits = String("1.") + "1234567890" * 8
    var original = BigDecimal(digits)
    var through = BigFloat.from_bigdecimal(original, 300)
    assert_equal(
        through.to_bigdecimal_rounded(81),
        original,
        "eighty-one digits through three hundred bits",
    )


# ===----------------------------------------------------------------------=== #
# The scaled way out
# ===----------------------------------------------------------------------=== #
#
# A few digits of a value with a deep exponent are taken by scaling it by a
# power of ten in fixed point, not by expanding it whole. The tests below
# come in two kinds: the pieces that carry an error bound, checked against
# exact arithmetic, and the answers, checked against the expansion the
# conversion used to take and against CPython where the expansion is too
# long to build.


def _both_ways(
    significand: BigInt,
    binary_exponent: Int,
    negative: Bool,
    digits: Int,
    rounding_mode: RoundingMode,
    label: String,
) raises:
    """Checks the scaled way to the digits against the expansion.

    Args:
        significand: The significand, never negative.
        binary_exponent: The power of two it is scaled by.
        negative: Whether the value is negative.
        digits: How many significant digits to keep.
        rounding_mode: Which way to round them.
        label: What to say if the two disagree.

    Raises:
        AssertionError: If the two ways disagree.
        Error: Propagated from the conversions.

    Notes:

    The text, not the value, because the two have to agree on the place as
    well as on the digits: `0.5` and `0.500` are the same number and only one
    of them is the answer.
    """
    assert_equal(
        String(
            to_rounded_bigdecimal(
                significand,
                binary_exponent,
                negative,
                digits,
                rounding_mode,
                Int.MAX,
            )
        ),
        String(
            _rounded_from_exact(
                significand, binary_exponent, negative, digits, rounding_mode
            )
        ),
        label,
    )


def test_the_boundary_rule_matches_exact_arithmetic() raises:
    """Whether the scaled value is whole, a half, or neither.

    The rule reads the twos and fives of the significand and the two
    exponents, and never a digit. These hundred and twenty answers come from
    CPython's `fractions.Fraction`, which builds the value exactly and looks
    at its denominator. Forty of each outcome, because the one that is hard
    to reach is the half and a sweep of random values finds almost none.
    """
    var cases = [
        (BigInt("4503599627382841"), -60, 59, _HALF),
        (BigInt("3"), -1, 1, _WHOLE),
        (BigInt("2750000000"), 0, -8, _HALF),
        (BigInt("875"), -3, 3, _WHOLE),
        (BigInt("4503599627382841"), -7, 4, _NEITHER),
        (BigInt("7"), -13, 12, _HALF),
        (BigInt("4000"), -7, 1, _HALF),
        (BigInt("1000000"), -1, -3, _WHOLE),
        (BigInt("1"), 7, 21, _WHOLE),
        (BigInt("875"), -13, 12, _HALF),
        (BigInt("1000000000000000000000000000000"), 1, 0, _WHOLE),
        (BigInt("1024"), -13, -1, _NEITHER),
        (BigInt("9094947017729282379150390625"), 13, -8, _WHOLE),
        (BigInt("7"), 60, 21, _WHOLE),
        (BigInt("1000000"), 3, 1, _WHOLE),
        (BigInt("781250000000000000"), -1, 21, _WHOLE),
        (BigInt("3"), 13, 1, _WHOLE),
        (BigInt("875"), 60, -65, _NEITHER),
        (BigInt("9094947017729282379150390625"), 7, -8, _HALF),
        (BigInt("9094947017729282379150390625"), 60, -61, _NEITHER),
        (BigInt("78125"), -3, 2, _HALF),
        (BigInt("4000"), 7, 3, _WHOLE),
        (BigInt("2750000000"), -13, 5, _HALF),
        (BigInt("1024"), 3, 21, _WHOLE),
        (BigInt("781250000000000000"), -3, -11, _HALF),
        (BigInt("9007199254740993"), -60, -21, _NEITHER),
        (BigInt("1000000000000000000000000000000"), -60, 30, _WHOLE),
        (BigInt("875"), 0, -1, _HALF),
        (BigInt("1000000"), -1, -6, _HALF),
        (BigInt("4503599627382841"), -3, 2, _HALF),
        (BigInt("875"), 60, 3, _WHOLE),
        (BigInt("7"), 3, -1, _NEITHER),
        (BigInt("2750000000"), 60, 21, _WHOLE),
        (BigInt("1000000000000000000000000000000"), -7, -55, _NEITHER),
        (BigInt("3"), -60, 59, _HALF),
        (BigInt("1024"), -60, 8, _NEITHER),
        (BigInt("1024"), 60, -72, _NEITHER),
        (BigInt("2750000000"), -7, 1, _WHOLE),
        (BigInt("4503599627382841"), -7, 6, _HALF),
        (BigInt("2750000000"), -1, -21, _NEITHER),
        (BigInt("9007199254740993"), -7, 6, _HALF),
        (BigInt("4503599627382841"), -60, -8, _NEITHER),
        (BigInt("4000"), 3, -10, _NEITHER),
        (BigInt("4503599627382841"), 1, -2, _NEITHER),
        (BigInt("781250000000000000"), 7, 0, _WHOLE),
        (BigInt("781250000000000000"), -7, -7, _HALF),
        (BigInt("2750000000"), -3, -5, _HALF),
        (BigInt("781250000000000000"), 60, -8, _WHOLE),
        (BigInt("7"), 7, -21, _NEITHER),
        (BigInt("9094947017729282379150390625"), -3, 2, _HALF),
        (BigInt("2750000000"), 60, 0, _WHOLE),
        (BigInt("3"), -7, 4, _NEITHER),
        (BigInt("1024"), 3, -1, _NEITHER),
        (BigInt("1000000000000000000000000000000"), -3, -21, _WHOLE),
        (BigInt("781250000000000000"), 3, -17, _HALF),
        (BigInt("1000000000000000000000000000000"), 1, -8, _WHOLE),
        (BigInt("875"), -7, 6, _HALF),
        (BigInt("78125"), 3, -4, _HALF),
        (BigInt("4503599627382841"), 7, -8, _NEITHER),
        (BigInt("7"), 7, 3, _WHOLE),
        (BigInt("9094947017729282379150390625"), 13, -14, _HALF),
        (BigInt("2750000000"), 1, -9, _HALF),
        (BigInt("1000000"), 60, -8, _NEITHER),
        (BigInt("9094947017729282379150390625"), 3, -8, _NEITHER),
        (BigInt("1000000000000000000000000000000"), -13, -17, _WHOLE),
        (BigInt("875"), -7, -21, _NEITHER),
        (BigInt("7"), 7, 0, _WHOLE),
        (BigInt("1000000000000000000000000000000"), -13, -18, _HALF),
        (BigInt("875"), 1, 3, _WHOLE),
        (BigInt("781250000000000000"), -1, -13, _HALF),
        (BigInt("9094947017729282379150390625"), -3, 8, _WHOLE),
        (BigInt("1024"), 1, -21, _NEITHER),
        (BigInt("1000000000000000000000000000000"), -3, -28, _HALF),
        (BigInt("2750000000"), -60, 52, _HALF),
        (BigInt("1000000000000000000000000000000"), 1, 1, _WHOLE),
        (BigInt("9007199254740993"), -60, -3, _NEITHER),
        (BigInt("2750000000"), 3, 21, _WHOLE),
        (BigInt("4000"), 0, -7, _NEITHER),
        (BigInt("9007199254740993"), 60, -21, _NEITHER),
        (BigInt("4503599627382841"), -1, 0, _HALF),
        (BigInt("9007199254740993"), 0, 1, _WHOLE),
        (BigInt("78125"), 13, -15, _NEITHER),
        (BigInt("4000"), 3, 8, _WHOLE),
        (BigInt("78125"), -1, 0, _HALF),
        (BigInt("1000000"), -13, 6, _HALF),
        (BigInt("9007199254740993"), -13, 10, _NEITHER),
        (BigInt("7"), -13, 21, _WHOLE),
        (BigInt("4503599627382841"), 60, -21, _NEITHER),
        (BigInt("7"), -7, 6, _HALF),
        (BigInt("875"), -60, 58, _NEITHER),
        (BigInt("875"), 0, 21, _WHOLE),
        (BigInt("1024"), 3, 3, _WHOLE),
        (BigInt("875"), 1, -2, _HALF),
        (BigInt("3"), -3, 2, _HALF),
        (BigInt("4000"), -3, -7, _NEITHER),
        (BigInt("781250000000000000"), 0, -14, _HALF),
        (BigInt("7"), -7, 1, _NEITHER),
        (BigInt("1000000000000000000000000000000"), 13, -45, _NEITHER),
        (BigInt("1"), 60, 3, _WHOLE),
        (BigInt("3"), -7, 6, _HALF),
        (BigInt("9094947017729282379150390625"), 0, 3, _WHOLE),
        (BigInt("781250000000000000"), 3, -37, _NEITHER),
        (BigInt("1000000000000000000000000000000"), -60, 29, _HALF),
        (BigInt("4000"), -7, 21, _WHOLE),
        (BigInt("875"), -3, 2, _HALF),
        (BigInt("781250000000000000"), 1, -15, _HALF),
        (BigInt("7"), -3, -1, _NEITHER),
        (BigInt("875"), -1, -1, _NEITHER),
        (BigInt("7"), -60, 1, _NEITHER),
        (BigInt("2750000000"), 3, -12, _NEITHER),
        (BigInt("3"), 0, 1, _WHOLE),
        (BigInt("2750000000"), 0, -17, _NEITHER),
        (BigInt("1000000"), 13, 3, _WHOLE),
        (BigInt("78125"), -60, 59, _HALF),
        (BigInt("3"), 13, 0, _WHOLE),
        (BigInt("3"), -13, 10, _NEITHER),
        (BigInt("3"), 7, -9, _NEITHER),
        (BigInt("2750000000"), -3, -8, _NEITHER),
        (BigInt("4000"), -60, 54, _HALF),
        (BigInt("1000000"), 3, 8, _WHOLE),
    ]
    for row in cases:
        assert_equal(
            _boundary_kind(row[0], row[1], row[2]),
            row[3],
            String(row[0]) + " p" + String(row[1]) + " e" + String(row[2]),
        )


def test_the_power_of_five_keeps_within_its_slack() raises:
    """The truncated power of five is below the true one, and not by much.

    Two claims the scaling rests on. Below, because a quotient taken with a
    divisor that is too small is too large, which is what puts the whole and
    half cases on the nose rather than a unit under. Not by much, because
    `_FIXED_POINT_SLACK` is worked out from `_FIVE_POWER_SLACK`.
    """
    for width in [16, 32, 64, 97, 200, 333]:
        for degree in [0, 1, 2, 7, 13, 40, 41, 100, 255, 256, 1000, 4096]:
            var pair = _five_power_truncated(degree, width)
            var exact = BigInt(5).power(degree)
            var approximated = pair[0] << pair[1] if pair[1] >= 0 else pair[
                0
            ] >> (-pair[1])
            var label = String(degree) + " to " + String(width) + " bits"
            assert_true(pair[0].bit_length() <= width, label + " is too wide")
            assert_true(exact >= approximated, label + " is above the power")
            if pair[1] > 0:
                var slack = (BigInt.one() << pair[1]) * BigInt(
                    _FIVE_POWER_SLACK
                )
                assert_true(
                    exact - approximated <= slack, label + " is too far below"
                )
            else:
                assert_equal(exact, approximated, label + " is not exact")


def _scaled_exactly(
    significand: BigInt, binary_exponent: Int, shift: Int, guard: Int
) raises -> BigInt:
    """`significand * 2^binary_exponent * 10^shift` in units of `2^-guard`.

    Args:
        significand: The significand, never negative.
        binary_exponent: The power of two it is scaled by.
        shift: The power of ten to scale it by, either sign.
        guard: The fractional bits to keep.

    Returns:
        The value, truncated toward nought, with whole powers of five and no
        approximation anywhere.

    Raises:
        Error: Propagated from the arithmetic.
    """
    var place = binary_exponent + shift + guard
    if shift >= 0:
        var value = significand * BigInt(5).power(shift)
        return value << place if place >= 0 else value >> (-place)
    var power = BigInt(5).power(-shift)
    if place >= 0:
        return (significand << place).truncate_divide(power)
    return significand.truncate_divide(power << (-place))


def test_the_scaled_fixed_point_keeps_within_its_slack() raises:
    """The scaling is within `_FIXED_POINT_SLACK` units of the true value.

    Every rounding decision rests on this bound: the guard tests read the
    computed value as the true one give or take that many units of `2^-guard`,
    and the working width is chosen to make it so. Here the true value is
    built exactly, with whole powers of five, which is only possible for the
    shifts a test can afford -- the conversion itself meets shifts of `10^18`.

    The bound holds while the value fits `integer_bits`, which is what the
    conversion's digit count guarantees, so the fit is asserted too.
    """
    for bits in [1, 24, 53, 113]:
        var significand = (BigInt.one() << (bits - 1)) + BigInt(
            7 % (1 << (bits - 1))
        )
        for shift in [-600, -100, -30, -3, 0, 3, 30, 100, 600]:
            for integer_bits in [20, 40, 100]:
                for guard in [32, 64]:
                    # The value is put near the top of the room it has, which
                    # is where the bound is tightest.
                    var exponent = (
                        integer_bits - 8 - bits - (shift * 10 + 2) // 3
                    )
                    var scaled = _scaled_to_fixed_point(
                        significand, exponent, shift, integer_bits, guard
                    )
                    var exact = _scaled_exactly(
                        significand, exponent, shift, guard
                    )
                    var label = (
                        String(bits)
                        + " bits by 10^"
                        + String(shift)
                        + " at "
                        + String(integer_bits)
                        + " and "
                        + String(guard)
                    )
                    assert_true(
                        (scaled >> guard).bit_length() <= integer_bits,
                        label + " does not fit the room it was given",
                    )
                    var difference = (
                        scaled - exact if scaled >= exact else exact - scaled
                    )
                    assert_true(
                        difference <= BigInt(_FIXED_POINT_SLACK),
                        label + " is out by " + String(difference),
                    )


def test_a_boundary_scaling_lands_on_the_nose() raises:
    """Where the scaled value is whole or a half, the fixed point says so.

    The two cases the Ziv loop could not settle are answered by the rule
    instead, and that only works if the scaling lands exactly on the whole
    number or exactly half a unit above it. Nothing below the guard may be
    left over, at any guard.
    """
    var held = False
    for power in [0, 4, 8, 20, 50, 90, 200]:
        var five = BigInt(5).power(power)
        for odd in [BigInt.one(), BigInt(3), BigInt(123456789)]:
            var significand = five * odd
            # The value is `10^power * odd`, so its digit count is known and
            # the shift that puts `digits` of them before the point is too.
            # The slack in the working width covers a shift one or two out,
            # which is as far as the chooser's estimate can be.
            var leading = power + odd.number_of_digits() - 1
            for digits in [1, 2, 7, 17, 25]:
                var integer_bits = (digits * 10 + 2) // 3 + 8
                var wanted = digits - 1 - leading
                for guard in [32, 64, 128]:
                    for shift in range(wanted - 2, wanted + 3):
                        var kind = _boundary_kind(significand, power, shift)
                        if kind == _NEITHER:
                            continue
                        var scaled = _scaled_to_fixed_point(
                            significand, power, shift, integer_bits, guard
                        )
                        var rest = scaled - ((scaled >> guard) << guard)
                        var expected = (
                            BigInt.zero() if kind
                            == _WHOLE else BigInt.one() << (guard - 1)
                        )
                        held = True
                        assert_equal(
                            rest,
                            expected,
                            (
                                "10^"
                                + String(power)
                                + " times "
                                + String(odd)
                                + " shifted by "
                                + String(shift)
                                + " at guard "
                                + String(guard)
                            ),
                        )
    assert_true(
        held, "no whole or half scaling was reached, so nothing was tested"
    )


def test_the_scaling_agrees_with_the_expansion() raises:
    """The two ways to the digits give the same digits.

    The expansion is the way the conversion used to go, so it is the oracle
    for the way it goes now. Both are asked directly, with the chooser told
    to take the scaling, over a spread of significand widths, exponents,
    digit counts and all seven rounding modes.
    """
    var modes = [
        RoundingMode.ROUND_DOWN,
        RoundingMode.ROUND_UP,
        RoundingMode.ROUND_CEILING,
        RoundingMode.ROUND_FLOOR,
        RoundingMode.ROUND_HALF_UP,
        RoundingMode.ROUND_HALF_DOWN,
        RoundingMode.ROUND_HALF_EVEN,
    ]
    # Nought first, which has no digits to scale and still has to come back
    # the way the expansion gives it, sign and all.
    for negative in [False, True]:
        for digits in [1, 7, 25]:
            _both_ways(
                BigInt.zero(),
                0,
                negative,
                digits,
                RoundingMode.ROUND_HALF_EVEN,
                "nought to " + String(digits) + " digits",
            )

    var state = UInt64(0x2545F4914F6CDD1D)
    for bits in [1, 5, 53, 113]:
        var significand = BigInt.one()
        while significand.bit_length() < bits:
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            var take = 32 if bits - significand.bit_length() > 32 else (
                bits - significand.bit_length()
            )
            significand = (significand << take) + BigInt(
                Int(state % UInt64(1 << take))
            )
        for exponent in [0, -bits, 17, -400, 400]:
            for negative in [False, True]:
                for digits in [1, 7, 25]:
                    for mode in modes:
                        _both_ways(
                            significand,
                            exponent,
                            negative,
                            digits,
                            mode,
                            (
                                String(bits)
                                + " bits p"
                                + String(exponent)
                                + " to "
                                + String(digits)
                                + " digits"
                            ),
                        )


def test_a_value_beside_a_boundary_rounds_the_same_way() raises:
    """A float a step from a decimal boundary goes the way the expansion goes.

    These are the values the Ziv loop has to widen for: the nearest float to
    a decimal tie, and the nearest float to the kept value itself, which sit
    a unit in the last place from the boundary the rounding is deciding. A
    sweep of ordinary values almost never produces one.
    """
    var modes = [
        RoundingMode.ROUND_DOWN,
        RoundingMode.ROUND_UP,
        RoundingMode.ROUND_HALF_UP,
        RoundingMode.ROUND_HALF_DOWN,
        RoundingMode.ROUND_HALF_EVEN,
    ]
    for precision in [11, 113]:
        for digits in [1, 17]:
            var ten = BigInt(10).power(digits - 1)
            var leaders = [
                ten.copy(),
                ten + BigInt.one(),
                ten * BigInt(10) - BigInt.one(),
            ]
            for leader in leaders:
                for scale in [0, 40, 400, -40, -400]:
                    var targets = [
                        (leader * BigInt(2) + BigInt.one(), -(scale + 1)),
                        (leader.copy(), -scale),
                    ]
                    for target in targets:
                        var parts = from_decimal_parts(
                            target[0],
                            target[1],
                            precision,
                            False,
                            RoundingMode.ROUND_HALF_EVEN,
                        )
                        for mode in modes:
                            _both_ways(
                                parts[0],
                                parts[1],
                                False,
                                digits,
                                mode,
                                (
                                    String(precision)
                                    + " bits beside "
                                    + String(target[0])
                                    + "e"
                                    + String(target[1])
                                ),
                            )


def test_an_exact_decimal_of_many_digits_rounds_the_same_way() raises:
    """A whole power of ten asked for fewer digits than it has.

    `5^n * 2^n` is `10^n`, and asking for a few digits of it divides by a
    power of five too wide for the working width. That is the one place the
    scaling divides rather than multiplies and still has to land exactly on
    a whole number.
    """
    var modes = [
        RoundingMode.ROUND_DOWN,
        RoundingMode.ROUND_UP,
        RoundingMode.ROUND_HALF_EVEN,
    ]
    for power in [8, 20, 50, 90, 200, 500]:
        var five = BigInt(5).power(power)
        for odd in [BigInt.one(), BigInt(3), BigInt(123456789)]:
            var significand = five * odd
            for digits in [1, 2, 7, 17, 25]:
                for mode in modes:
                    _both_ways(
                        significand,
                        power,
                        False,
                        digits,
                        mode,
                        (
                            "10^"
                            + String(power)
                            + " to "
                            + String(digits)
                            + " digits"
                        ),
                    )


def test_either_way_to_the_digits_gives_the_same_answer() raises:
    """The chooser picks on cost, so both of its answers must be the one.

    Asked for the scaling, for the expansion and for whichever it would take
    by itself, the three agree. The deepest of these values has an expansion
    of six thousand digits, which is the point: the answer is the same and
    only the work differs.
    """
    var significand = (BigInt.one() << 52) + BigInt(1234567890123)
    for exponent in [-52, -300, -1074, -20000]:
        for digits in [1, 17, 40]:
            var scaling = to_rounded_bigdecimal(
                significand,
                exponent,
                False,
                digits,
                RoundingMode.ROUND_HALF_EVEN,
                Int.MAX,
            )
            var expansion = to_rounded_bigdecimal(
                significand,
                exponent,
                False,
                digits,
                RoundingMode.ROUND_HALF_EVEN,
                1,
            )
            var chosen = to_rounded_bigdecimal(
                significand,
                exponent,
                False,
                digits,
                RoundingMode.ROUND_HALF_EVEN,
            )
            var label = String(exponent) + " to " + String(digits) + " digits"
            assert_equal(
                String(scaling), String(expansion), label + ", the two ways"
            )
            assert_equal(
                String(scaling), String(chosen), label + ", the chosen way"
            )


def test_a_tie_in_the_digits_goes_the_way_the_mode_says() raises:
    """Where exactly a half is dropped, and the digit kept is even or odd.

    An odd significand over two is a decimal that ends in five, so asking for
    one digit fewer than it has drops exactly a half and nothing else. That
    is the case the boundary rule exists for, and the only one where
    `HALF_EVEN` reads the last digit kept: every one of these values is a tie
    and the digit before it is even for half of them.
    """
    var modes = [
        RoundingMode.ROUND_DOWN,
        RoundingMode.ROUND_UP,
        RoundingMode.ROUND_CEILING,
        RoundingMode.ROUND_FLOOR,
        RoundingMode.ROUND_HALF_UP,
        RoundingMode.ROUND_HALF_DOWN,
        RoundingMode.ROUND_HALF_EVEN,
    ]
    var odds = [
        BigInt(5),
        BigInt(7),
        BigInt(9),
        BigInt(11),
        BigInt(25),
        BigInt(27),
        BigInt(12345678901234567),
        BigInt(5).power(30) * BigInt(2) + BigInt.one(),
        (BigInt.one() << 113) - BigInt.one(),
    ]
    var evens = 0
    for odd in odds:
        var kept = odd >> 1
        var digits = kept.number_of_digits()
        if (kept >> 1) << 1 == kept:
            evens += 1
        for negative in [False, True]:
            for mode in modes:
                _both_ways(
                    odd,
                    -1,
                    negative,
                    digits,
                    mode,
                    String(odd) + " halved to " + String(digits) + " digits",
                )
    assert_true(evens > 0, "no tie kept an even digit")
    assert_true(evens < len(odds), "no tie kept an odd digit")


def test_a_deep_exponent_gives_the_digits_cpython_computes() raises:
    """Digits of values whose expansion could never be built.

    `2^-9223372036854775756` has about `2.8 * 10^18` decimal places, so the
    expansion is not an option and CPython's `decimal` is the reference: its
    `log10` is correctly rounded, and these answers were taken at two hundred
    digits of working precision and confirmed at a hundred and thirty. The
    first of them, `2^-1000000`, was confirmed a third way, against the exact
    digits of `5^1000000`.
    """
    var cases = [
        (
            BigInt("1"),
            -1000000,
            20,
            RoundingMode.ROUND_HALF_EVEN,
            "1.0100340591980302247E-301030",
        ),
        (
            BigInt("1"),
            -1000000,
            20,
            RoundingMode.ROUND_DOWN,
            "1.0100340591980302247E-301030",
        ),
        (
            BigInt("1"),
            -1000000,
            20,
            RoundingMode.ROUND_UP,
            "1.0100340591980302248E-301030",
        ),
        (
            BigInt("1"),
            -1000000000,
            20,
            RoundingMode.ROUND_HALF_EVEN,
            "2.1677979676169340022E-301029996",
        ),
        (
            BigInt("1"),
            1000000000,
            20,
            RoundingMode.ROUND_HALF_EVEN,
            "4.6129760011690693931E+301029995",
        ),
        (
            BigInt("1"),
            -1000000000000,
            25,
            RoundingMode.ROUND_HALF_EVEN,
            "1.044250726930468202952437E-301029995664",
        ),
        (
            BigInt("1"),
            1000000000000000,
            20,
            RoundingMode.ROUND_HALF_EVEN,
            "1.5675223395448293252E+301029995663981",
        ),
        (
            BigInt("1"),
            -9223372036854775756,
            17,
            RoundingMode.ROUND_HALF_EVEN,
            "3.2612747445751642E-2776511644261678551",
        ),
        (
            BigInt("1"),
            9223372036854775707,
            17,
            RoundingMode.ROUND_HALF_EVEN,
            "5.4468175131673881E+2776511644261678535",
        ),
        (
            BigInt("4503599627382841"),
            -9223372036854775708,
            17,
            RoundingMode.ROUND_HALF_EVEN,
            "4.1341568874812047E-2776511644261678521",
        ),
        (
            BigInt("4503599627382841"),
            9223372036854775707,
            17,
            RoundingMode.ROUND_DOWN,
            "2.4530285322722981E+2776511644261678551",
        ),
        (
            BigInt("9094947017729282379150390625"),
            -9223372036854775708,
            25,
            RoundingMode.ROUND_HALF_EVEN,
            "8.348863346112420332561934E-2776511644261678509",
        ),
        (
            BigInt("9094947017729282379150390625"),
            -9223372036854775708,
            1,
            RoundingMode.ROUND_HALF_EVEN,
            "8E-2776511644261678509",
        ),
        (
            BigInt("9007199254740993"),
            -1234567890123456789,
            30,
            RoundingMode.ROUND_HALF_EVEN,
            "1.32594955715912165603899364826E-371641966610754594",
        ),
    ]
    for row in cases:
        assert_equal(
            String(
                to_rounded_bigdecimal(row[0], row[1], False, row[2], row[3])
            ),
            row[4],
            String(row[1]) + " to " + String(row[2]) + " digits",
        )


def test_the_ends_of_the_exponent_range_print() raises:
    """A value at either end of the range prints its digits.

    Printing used to expand the value first, so the smallest and largest
    values a `BigFloat` can hold could not be printed at all: the expansion
    has more digits than there is memory. The digits are CPython's.
    """
    var smallest = BigFloat(
        significand=BigInt.one() << 52,
        exponent=Int.MIN + 52,
        precision=53,
        sign=False,
    )
    var largest = BigFloat(
        significand=BigInt.one() << 52,
        exponent=Int.MAX - 52,
        precision=53,
        sign=True,
    )
    assert_equal(
        smallest.to_string(17),
        "1.4687475724421519E-2776511644261678535",
        "the smallest value there is",
    )
    assert_equal(
        largest.to_string(17),
        "-6.9046614899002713E+2776511644261678565",
        "the largest value there is",
    )


# ===----------------------------------------------------------------------=== #
# The scaled way in
# ===----------------------------------------------------------------------=== #
#
# The way in has the same two routes as the way out: the power of ten built
# whole, which is quickest while it is small, and the power truncated to a
# working width, which is the only way when the decimal exponent has
# eighteen figures. The routes are checked against each other, and against
# CPython where the whole power could never be built.


def _both_routes(
    magnitude: BigInt,
    decimal_exponent: Int,
    precision: Int,
    negative: Bool,
    rounding_mode: RoundingMode,
    label: String,
) raises:
    """Checks the scaled route to the significand against the whole power.

    Args:
        magnitude: The decimal digits as an integer.
        decimal_exponent: The power of ten they are scaled by.
        precision: How many bits to keep.
        negative: The sign the directed modes read.
        rounding_mode: Which way to round.
        label: What to say if the two disagree.

    Raises:
        AssertionError: If the two routes disagree.
        Error: Propagated from the conversions.
    """
    # A size that keeps the scaling for every widening a right answer needs,
    # and hands back after a few more. `Int.MAX` would keep it for ever, and
    # a wrong boundary rule would then widen without end instead of failing.
    var scaled = _from_decimal_by_scaling(
        magnitude,
        decimal_exponent,
        precision,
        negative,
        rounding_mode,
        (precision + 256) * 4,
    )
    var whole = _from_decimal_exactly(
        magnitude, decimal_exponent, precision, negative, rounding_mode
    )
    assert_equal(scaled[0], whole[0], label + ", the significand")
    assert_equal(scaled[1], whole[1], label + ", the exponent")


def test_a_decimal_parses_the_same_way_either_route() raises:
    """The two routes to the significand give the same significand.

    A spread of digit counts, powers of ten either way, precisions and all
    seven rounding modes, with the tails that make a magnitude rich in twos
    and fives.
    """
    var modes = [
        RoundingMode.ROUND_DOWN,
        RoundingMode.ROUND_UP,
        RoundingMode.ROUND_CEILING,
        RoundingMode.ROUND_FLOOR,
        RoundingMode.ROUND_HALF_UP,
        RoundingMode.ROUND_HALF_DOWN,
        RoundingMode.ROUND_HALF_EVEN,
    ]
    var state = UInt64(0x9E3779B97F4A7C15)
    for digits in [1, 17, 40]:
        var magnitude = BigInt.one()
        while magnitude.number_of_digits() < digits:
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            magnitude = magnitude * BigInt(10) + BigInt(Int(state % UInt64(10)))
        for tail in [BigInt.one(), BigInt(5), BigInt(1024)]:
            var value = magnitude * tail
            for exponent in [-1000, -41, -3, 1, 3, 41]:
                for precision in [1, 53, 113]:
                    for mode in modes:
                        _both_routes(
                            value,
                            exponent,
                            precision,
                            exponent < 0,
                            mode,
                            (
                                String(digits)
                                + " digits e"
                                + String(exponent)
                                + " to "
                                + String(precision)
                                + " bits"
                            ),
                        )


def test_a_decimal_that_is_a_binary_float_parses_to_it_exactly() raises:
    """A decimal that is a binary float comes back as that float.

    `m * 10^d` for a positive `d` is a whole number of `2^d`, so when `5^d`
    fits the precision the value is a float already and no mode has anything
    to round. Each of these parses to the same significand under all seven
    modes, and that significand at that exponent is the value itself.
    """
    var modes = [
        RoundingMode.ROUND_DOWN,
        RoundingMode.ROUND_UP,
        RoundingMode.ROUND_CEILING,
        RoundingMode.ROUND_FLOOR,
        RoundingMode.ROUND_HALF_UP,
        RoundingMode.ROUND_HALF_DOWN,
        RoundingMode.ROUND_HALF_EVEN,
    ]
    for odd in [1, 3, 5, 7, 125, 999]:
        for exponent in [1, 2, 3, 7, 17, 41]:
            var head = BigInt(odd) * BigInt(5).power(exponent)
            for twos in [0, 1, 10, 64, 200]:
                var magnitude = BigInt(odd) << twos
                var exact = (head << twos) << exponent
                for precision in [head.bit_length(), head.bit_length() + 7]:
                    for negative in [False, True]:
                        var first = from_decimal_parts(
                            magnitude,
                            exponent,
                            precision,
                            negative,
                            RoundingMode.ROUND_DOWN,
                        )
                        var label = (
                            String(magnitude)
                            + "e"
                            + String(exponent)
                            + " to "
                            + String(precision)
                            + " bits"
                        )
                        assert_equal(
                            first[0] << first[1],
                            exact,
                            label + " is not the value",
                        )
                        for mode in modes:
                            var parts = from_decimal_parts(
                                magnitude,
                                exponent,
                                precision,
                                negative,
                                mode,
                            )
                            assert_equal(
                                parts[0], first[0], label + ", the significand"
                            )
                            assert_equal(
                                parts[1], first[1], label + ", the exponent"
                            )


def test_a_deep_decimal_exponent_parses_what_cpython_computes() raises:
    """Decimals whose power of ten could never be built.

    `10^1000000000` has over three hundred million digits, and the exponent
    here reaches eighteen figures. The significands come from CPython's
    `decimal`, whose `ln` is correctly rounded, taken at a hundred and twenty
    digits of working precision and confirmed at a hundred and seventy.
    """
    var cases = [
        (
            BigInt("12345678901234567"),
            -100016,
            53,
            BigInt("6344893790027535"),
            -332245,
        ),
        (
            BigInt("12345678901234567"),
            -1000000016,
            53,
            BigInt("6011489095677160"),
            -3321928147,
        ),
        (
            BigInt("12345678901234567"),
            999999984,
            53,
            BigInt("5142418764458928"),
            3321928043,
        ),
        (
            BigInt("12345678901234567"),
            -1000000000000000016,
            53,
            BigInt("6082925441164801"),
            -3321928094887362400,
        ),
        (
            BigInt("12345678901234567"),
            999999999999999984,
            53,
            BigInt("5082027492684656"),
            3321928094887362296,
        ),
        (
            BigInt("9999999999999999999"),
            -2000000000000000018,
            53,
            BigInt("6738221307732553"),
            -6643856189774724745,
        ),
        (
            BigInt("1"),
            -2776511644261678000,
            53,
            BigInt("7200129597079684"),
            -9223372036854773980,
        ),
        (
            BigInt("1"),
            2776511644261678000,
            53,
            BigInt("5633901259743451"),
            9223372036854773875,
        ),
        (
            BigInt("12345678901234567"),
            -1000000016,
            300,
            BigInt(
                "1359536878546490089359964328124498944451659716890413964142822101490479431212259983269865772"
            ),
            -3321928394,
        ),
    ]
    for row in cases:
        var parts = from_decimal_parts(
            row[0], row[1], row[2], False, RoundingMode.ROUND_HALF_EVEN
        )
        var label = String(row[1]) + " to " + String(row[2]) + " bits"
        assert_equal(parts[0], row[3], label + ", the significand")
        assert_equal(parts[1], row[4], label + ", the exponent")


def test_a_decimal_past_the_exponent_range_is_refused() raises:
    """A power of ten no binary exponent can hold is a refusal, not a guess.

    `10^-5000000000000000000` is `2^-16609640474436811792`, and an `Int` stops
    at a quarter of that. The old way did not reach the question: it tried to
    build the power first.
    """
    with assert_raises(contains="past the exponents"):
        _ = from_decimal_parts(
            BigInt.one(),
            -5_000_000_000_000_000_000,
            53,
            False,
            RoundingMode.ROUND_HALF_EVEN,
        )
    with assert_raises(contains="past the exponents"):
        _ = from_decimal_parts(
            BigInt.one(),
            5_000_000_000_000_000_000,
            53,
            False,
            RoundingMode.ROUND_HALF_EVEN,
        )


def test_either_route_to_the_significand_agrees() raises:
    """The chooser picks on cost, so both of its answers must be the one.

    Asked for the scaling, for the whole power, and for whichever it would
    take by itself, the three agree.
    """
    var magnitude = BigInt("123456789012345678901234567")
    for exponent in [-8000, -300, -17, 17, 300, 8000]:
        for precision in [11, 53, 200]:
            var scaled = _from_decimal_by_scaling(
                magnitude,
                exponent,
                precision,
                False,
                RoundingMode.ROUND_HALF_EVEN,
                Int.MAX,
            )
            var whole = _from_decimal_exactly(
                magnitude,
                exponent,
                precision,
                False,
                RoundingMode.ROUND_HALF_EVEN,
            )
            var chosen = from_decimal_parts(
                magnitude,
                exponent,
                precision,
                False,
                RoundingMode.ROUND_HALF_EVEN,
            )
            var label = (
                "e" + String(exponent) + " to " + String(precision) + " bits"
            )
            assert_equal(scaled[0], whole[0], label + ", the two routes")
            assert_equal(scaled[1], whole[1], label + ", the two exponents")
            assert_equal(scaled[0], chosen[0], label + ", the chosen route")
            assert_equal(scaled[1], chosen[1], label + ", the chosen exponent")


def test_an_exponent_whose_scaling_wrapped_still_prints() raises:
    """Values the exact power of five was reached for by a wrapped product.

    The kernel takes the power of five whole when it fits the working width,
    and the test for that multiplied the degree by seven, which for a degree
    of eighteen figures wraps round into a yes and asks for a power of five
    with a billion billion digits. The band it wrapped in is a quarter of the
    exponent range, and these five values sit in it. The digits are
    CPython's.
    """
    var cases = [
        (-5_000_000_000_000_000_000, "3.8447251704325141E-1505149978319905961"),
        (-6_000_000_000_000_000_000, "2.3503168068295821E-1806179973983887156"),
        (-8_000_000_000_000_000_000, "8.7831159624901292E-2408239965311849547"),
        (5_000_000_000_000_000_000, "5.2753860691088074E+1505149978319905991"),
        (6_000_000_000_000_000_000, "8.6296492220600951E+1806179973983887186"),
    ]
    for row in cases:
        var value = BigFloat(
            significand=BigInt.one() << 52,
            exponent=row[0],
            precision=53,
            sign=False,
        )
        assert_equal(value.to_string(17), row[1], "2^" + String(row[0]))


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
