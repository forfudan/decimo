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
from std.testing import assert_equal, assert_true

from decimo.bigdecimal.bigdecimal import BigDecimal
from decimo.bigfloat.bigfloat import BigFloat
from decimo.bigint.bigint import BigInt
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


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
