"""
Test Rational conversions: parsing, and the bridges to and from Float64,
BigInt and BigDecimal.

The expected values are the ones CPython gives for `fractions.Fraction`,
`float(Fraction)` and `decimal.Decimal`, so a difference here is a real
difference in behaviour rather than a difference of convention.
"""

from std import testing
from std.testing import assert_equal, assert_true

from decimo.bigdecimal.bigdecimal import BigDecimal
from decimo.bigint.bigint import BigInt
from decimo.rational.rational import Rational
from decimo.rounding_mode import RoundingMode
from decimo.traits import Parsable


# ===----------------------------------------------------------------------=== #
# Parsing
# ===----------------------------------------------------------------------=== #


def test_parse_fraction_form() raises:
    """A "p/q" string is read exactly and reduced."""
    assert_equal(String(Rational("3/7")), "3/7")
    assert_equal(String(Rational("6/14")), "3/7")
    assert_equal(String(Rational("-6/14")), "-3/7")
    assert_equal(String(Rational("6/-14")), "-3/7")
    assert_equal(String(Rational("-6/-14")), "3/7")
    assert_equal(String(Rational("8/4")), "2")
    assert_equal(String(Rational("0/5")), "0")


def test_parse_decimal_form() raises:
    """A single decimal literal is read exactly, not as a float would be."""
    assert_equal(String(Rational("42")), "42")
    assert_equal(String(Rational("-42")), "-42")
    assert_equal(String(Rational("1.5")), "3/2")
    assert_equal(String(Rational("-0.125")), "-1/8")
    assert_equal(String(Rational("7e-3")), "7/1000")
    assert_equal(String(Rational("1.23e5")), "123000")
    assert_equal(String(Rational("-0.00100e-2")), "-1/100000")
    # 0.1 as a decimal literal is exactly one tenth, unlike the Float64 of
    # the same name.
    assert_equal(String(Rational("0.1")), "1/10")


def test_parse_accepts_what_bigdecimal_accepts() raises:
    """Separators and spaces are allowed on both sides of the slash."""
    assert_equal(String(Rational("  1_000, 000 / 3 ")), "1000000/3")
    assert_equal(String(Rational("+1.5")), "3/2")


def test_parse_mixed_form() raises:
    """Either side of the slash may itself be a decimal literal."""
    assert_equal(String(Rational("1.5/2.5")), "3/5")
    assert_equal(String(Rational("1e2/4")), "25")


def test_parse_rejects_nonsense() raises:
    """A string that is not a rational raises rather than parsing to zero."""
    var raised = False
    try:
        _ = Rational("not a number")
    except:
        raised = True
    assert_true(raised, "Rational('not a number') should raise")

    raised = False
    try:
        _ = Rational("1/2/3")
    except:
        raised = True
    assert_true(raised, "Rational('1/2/3') should raise")

    raised = False
    try:
        _ = Rational("3/")
    except:
        raised = True
    assert_true(raised, "Rational('3/') should raise")


def test_parse_rejects_zero_denominator() raises:
    """A zero denominator raises, as no rational has one."""
    var raised = False
    try:
        _ = Rational("3/0")
    except:
        raised = True
    assert_true(raised, "Rational('3/0') should raise")

    raised = False
    try:
        _ = Rational("3/0.0")
    except:
        raised = True
    assert_true(raised, "Rational('3/0.0') should raise")


def _parse_all[
    T: Movable & Deinitable & Parsable
](tokens: List[String]) raises -> List[T]:
    """Parses every token into `T`, naming no concrete type."""
    var out = List[T](capacity=len(tokens))
    for token in tokens:
        out.append(T.from_string(token))
    return out^


def test_parsable_conformance() raises:
    """`Rational` is usable through the `Parsable` trait, not just declared."""
    var tokens: List[String] = ["3/7", "0.1", "-42"]
    var values = _parse_all[Rational](tokens)

    assert_true(values[0] == Rational("3/7"), "3/7 through the trait")
    assert_true(
        values[1] + values[1] == Rational(1, 5),
        "0.1 + 0.1 is exactly 1/5 through the trait",
    )
    assert_true(values[2] == Rational(-42), "-42 through the trait")


# ===----------------------------------------------------------------------=== #
# From Float64
# ===----------------------------------------------------------------------=== #


def test_from_float_exact() raises:
    """A float that is a dyadic fraction converts to that fraction."""
    assert_equal(String(Rational.from_float(0.5)), "1/2")
    assert_equal(String(Rational.from_float(-2.5)), "-5/2")
    assert_equal(String(Rational.from_float(0.0)), "0")
    assert_equal(String(Rational.from_float(-0.0)), "0")
    assert_equal(String(Rational.from_float(1.0)), "1")
    assert_equal(String(Rational.from_float(-3.0)), "-3")


def test_from_float_is_the_float_not_the_literal() raises:
    """0.1 converts to the value the Float64 holds, not to one tenth."""
    assert_equal(
        String(Rational.from_float(0.1)),
        "3602879701896397/36028797018963968",
    )
    assert_true(
        Rational.from_float(0.1) != Rational("1/10"),
        "the Float64 0.1 is not one tenth",
    )


def test_from_float_extremes() raises:
    """The ends of the Float64 range survive the round trip."""
    var values: List[Float64] = [
        5e-324,  # smallest positive subnormal
        1e-320,  # a subnormal with trailing zero bits
        2.2250738585072014e-308,  # smallest normal
        1.7976931348623157e308,  # largest finite
        -1.7976931348623157e308,
    ]
    for value in values:
        assert_equal(
            Rational.from_float(value).to_float(),
            value,
            "round trip of " + String(value),
        )


def test_from_float_rejects_non_finite() raises:
    """Infinity and NaN are not rational numbers."""
    var raised = False
    try:
        _ = Rational.from_float(Float64("1e400"))
    except:
        raised = True
    assert_true(raised, "from_float(inf) should raise")

    raised = False
    try:
        _ = Rational.from_float(Float64("1e400") - Float64("1e400"))
    except:
        raised = True
    assert_true(raised, "from_float(nan) should raise")


# ===----------------------------------------------------------------------=== #
# From BigDecimal
# ===----------------------------------------------------------------------=== #


def test_from_bigdecimal() raises:
    """A decimal is a fraction already, so the conversion is exact."""
    assert_equal(
        String(Rational.from_bigdecimal(BigDecimal("123.456"))), "15432/125"
    )
    assert_equal(String(Rational.from_bigdecimal(BigDecimal("-0.125"))), "-1/8")
    assert_equal(String(Rational.from_bigdecimal(BigDecimal("0"))), "0")
    assert_equal(String(Rational.from_bigdecimal(BigDecimal("42"))), "42")
    # A negative scale is trailing zeros, not a fraction.
    assert_equal(
        String(Rational.from_bigdecimal(BigDecimal("4.2E+4"))), "42000"
    )


def test_bigdecimal_constructor() raises:
    """The BigDecimal constructor is the same conversion."""
    assert_true(
        Rational(BigDecimal("-0.125")) == Rational(-1, 8),
        "Rational(BigDecimal) should convert exactly",
    )


def test_bigdecimal_round_trip() raises:
    """Every exactly-representable value survives both directions."""
    var values: List[String] = ["0.5", "-0.125", "123.456", "0", "1e-9"]
    for value in values:
        var rational = Rational(BigDecimal(value))
        assert_true(
            Rational(rational.to_bigdecimal()) == rational,
            "round trip of " + value,
        )


# ===----------------------------------------------------------------------=== #
# To Float64
# ===----------------------------------------------------------------------=== #


def test_to_float() raises:
    """The nearest Float64, matching CPython's `float(Fraction(...))`."""
    assert_equal(Rational("1/3").to_float(), 0.3333333333333333)
    assert_equal(Rational("2/3").to_float(), 0.6666666666666666)
    assert_equal(Rational("1/7").to_float(), 0.14285714285714285)
    assert_equal(Rational("22/7").to_float(), 3.142857142857143)
    assert_equal(Rational("355/113").to_float(), 3.1415929203539825)
    assert_equal(Rational("-7/2").to_float(), -3.5)
    assert_equal(Rational(0).to_float(), 0.0)
    assert_equal(Rational("1/10").to_float(), 0.1)
    assert_equal(
        Rational(BigInt(2) ** 100, BigInt(3) ** 50).to_float(),
        1765780.963259017,
    )


def test_to_float_ties_to_even() raises:
    """A value exactly halfway between two floats rounds to the even one.

    This is the case a decimal detour gets wrong: the halfway point has 53
    decimal digits, so rounding it to a working precision first moves it off
    the tie and the second rounding then goes the wrong way.
    """
    # 1 + 2^-53 sits halfway between 1.0 and the next float up. The even
    # significand is 1.0's.
    var lower_tie = Rational(BigInt(2) ** 53 + BigInt(1), BigInt(2) ** 53)
    assert_equal(lower_tie.to_float(), 1.0, "1 + 2^-53 rounds down to 1.0")

    # 1 + 3 * 2^-53 sits halfway one ULP further up, where the even
    # significand is the upper one.
    var upper_tie = Rational(BigInt(2) ** 53 + BigInt(3), BigInt(2) ** 53)
    assert_equal(
        upper_tie.to_float(),
        1.0000000000000004,
        "1 + 3 * 2^-53 rounds up",
    )


def test_to_float_out_of_range() raises:
    """Beyond the Float64 range the result saturates, as BigInt's does."""
    assert_equal(Rational(BigInt(10) ** 400).to_float(), Float64("1e400"))
    assert_equal(Rational(-(BigInt(10) ** 400)).to_float(), -Float64("1e400"))
    assert_equal(Rational(BigInt(1), BigInt(10) ** 400).to_float(), 0.0)


def test_float_dunder() raises:
    """`Float64(x)` is `x.to_float()`."""
    assert_equal(Float64(Rational("1/4")), 0.25)
    assert_equal(Float64(Rational("1/3")), Rational("1/3").to_float())


# ===----------------------------------------------------------------------=== #
# To integer
# ===----------------------------------------------------------------------=== #


def test_to_integer_truncates_toward_zero() raises:
    """Truncation, not flooring: -7/2 is -3, not -4."""
    assert_equal(String(Rational("7/2").to_integer()), "3")
    assert_equal(String(Rational("-7/2").to_integer()), "-3")
    assert_equal(String(Rational("-1/2").to_integer()), "0")
    assert_equal(String(Rational("42").to_integer()), "42")
    assert_equal(String(Rational(0).to_integer()), "0")


def test_to_int_and_dunder() raises:
    """The Int forms agree with the BigInt one."""
    assert_equal(Rational("7/2").to_int(), 3)
    assert_equal(Int(Rational("-9/4")), -2)
    assert_equal(Int(Rational(-42)), -42)


def test_to_int_overflow_raises() raises:
    """A value past the range of Int raises rather than wrapping."""
    var raised = False
    try:
        _ = Rational(BigInt(10) ** 30).to_int()
    except:
        raised = True
    assert_true(raised, "to_int() of 10^30 should raise")


# ===----------------------------------------------------------------------=== #
# To BigDecimal
# ===----------------------------------------------------------------------=== #


def test_to_bigdecimal_exact() raises:
    """A value with a finite decimal form keeps that form, unpadded."""
    assert_equal(String(Rational("1/2").to_bigdecimal()), "0.5")
    assert_equal(String(Rational("-1/8").to_bigdecimal()), "-0.125")
    assert_equal(String(Rational(42).to_bigdecimal()), "42")
    assert_equal(String(Rational(0).to_bigdecimal()), "0")
    assert_equal(String(Rational("3/2").to_bigdecimal(precision=5)), "1.5")


def test_to_bigdecimal_inexact() raises:
    """A repeating value is cut to `precision` significant digits."""
    assert_equal(
        String(Rational("1/3").to_bigdecimal()),
        "0.3333333333333333333333333333",
    )
    assert_equal(String(Rational("1/3").to_bigdecimal(precision=5)), "0.33333")
    assert_equal(
        String(Rational("-1/3").to_bigdecimal(precision=5)), "-0.33333"
    )
    assert_equal(String(Rational("2/3").to_bigdecimal(precision=5)), "0.66667")
    # Significant digits, not decimal places: the exponent moves instead.
    assert_equal(
        String(Rational("100000/3").to_bigdecimal(precision=3)), "3.33E+4"
    )


def test_to_bigdecimal_rounding_modes() raises:
    """Each mode decides the last digit of 2/3 and -2/3 its own way."""
    var two_thirds = Rational("2/3")
    var minus_two_thirds = Rational("-2/3")

    assert_equal(
        String(
            two_thirds.to_bigdecimal(
                precision=5, rounding_mode=RoundingMode.ROUND_DOWN
            )
        ),
        "0.66666",
    )
    assert_equal(
        String(
            two_thirds.to_bigdecimal(
                precision=5, rounding_mode=RoundingMode.ROUND_UP
            )
        ),
        "0.66667",
    )
    assert_equal(
        String(
            two_thirds.to_bigdecimal(
                precision=5, rounding_mode=RoundingMode.ROUND_CEILING
            )
        ),
        "0.66667",
    )
    assert_equal(
        String(
            two_thirds.to_bigdecimal(
                precision=5, rounding_mode=RoundingMode.ROUND_FLOOR
            )
        ),
        "0.66666",
    )
    assert_equal(
        String(
            minus_two_thirds.to_bigdecimal(
                precision=5, rounding_mode=RoundingMode.ROUND_CEILING
            )
        ),
        "-0.66666",
    )
    assert_equal(
        String(
            minus_two_thirds.to_bigdecimal(
                precision=5, rounding_mode=RoundingMode.ROUND_FLOOR
            )
        ),
        "-0.66667",
    )


def test_to_bigdecimal_half_modes() raises:
    """1/8 is exactly 0.125, so two digits is a tie the modes split."""
    var one_eighth = Rational("1/8")

    assert_equal(
        String(
            one_eighth.to_bigdecimal(
                precision=2, rounding_mode=RoundingMode.ROUND_HALF_EVEN
            )
        ),
        "0.12",
    )
    assert_equal(
        String(
            one_eighth.to_bigdecimal(
                precision=2, rounding_mode=RoundingMode.ROUND_HALF_UP
            )
        ),
        "0.13",
    )
    assert_equal(
        String(
            one_eighth.to_bigdecimal(
                precision=2, rounding_mode=RoundingMode.ROUND_HALF_DOWN
            )
        ),
        "0.12",
    )
    # 3/8 is 0.375: half-even now rounds up, to the even digit 8.
    assert_equal(
        String(
            Rational("3/8").to_bigdecimal(
                precision=2, rounding_mode=RoundingMode.ROUND_HALF_EVEN
            )
        ),
        "0.38",
    )


def test_to_bigdecimal_carries_into_a_new_digit() raises:
    """Rounding 999.999 to three digits carries the whole way."""
    assert_equal(
        String(Rational("999999/1000").to_bigdecimal(precision=3)), "1.00E+3"
    )
    assert_equal(String(Rational("99/100").to_bigdecimal(precision=1)), "1")


def test_to_bigdecimal_rejects_non_positive_precision() raises:
    """A precision of zero digits has no result to give."""
    var raised = False
    try:
        _ = Rational("1/3").to_bigdecimal(precision=0)
    except:
        raised = True
    assert_true(raised, "precision=0 should raise")

    raised = False
    try:
        _ = Rational("1/3").to_bigdecimal(precision=-1)
    except:
        raised = True
    assert_true(raised, "precision=-1 should raise")


# ===----------------------------------------------------------------------=== #
# Narrower floating-point types and integral scalars
# ===----------------------------------------------------------------------=== #


def test_from_float_narrower_types() raises:
    """`from_float` reads every binary format exactly, not just Float64.

    The references are CPython's `Fraction` of the same bit pattern, so a
    difference here is a difference in what the bits are taken to mean.
    """
    assert_equal(
        String(Rational.from_float(Float32(0.1))),
        "13421773/134217728",
        "Float32(0.1) is 13421773 * 2^-27",
    )
    assert_equal(
        String(Rational.from_float(Float16(0.1))),
        "819/8192",
        "Float16(0.1) is 819 * 2^-13",
    )
    assert_equal(
        String(Rational.from_float(BFloat16(0.1))),
        "205/2048",
        "BFloat16(0.1) is 205 * 2^-11",
    )

    # A value every format holds exactly reads the same out of all of them.
    assert_equal(String(Rational.from_float(Float16(-2.5))), "-5/2")
    assert_equal(String(Rational.from_float(BFloat16(-2.5))), "-5/2")
    assert_equal(String(Rational.from_float(Float32(-2.5))), "-5/2")
    assert_equal(String(Rational.from_float(Float64(-2.5))), "-5/2")

    assert_equal(String(Rational.from_float(Float32(0.0))), "0")
    assert_equal(String(Rational.from_float(Float16(0.0))), "0")


def test_from_float_narrower_subnormals_and_non_finite() raises:
    """The narrow formats keep their subnormals, and still reject inf/NaN."""
    # 2^-24 is the smallest positive Float16, a subnormal.
    assert_equal(
        String(Rational.from_float(Float16(6e-8))),
        "1/16777216",
        "the smallest Float16 subnormal is 2^-24",
    )

    var raised = False
    try:
        _ = Rational.from_float(Float32.MAX * Float32(2.0))
    except:
        raised = True
    assert_true(raised, "an infinite Float32 is not a rational")

    raised = False
    try:
        _ = Rational.from_float(Float16(0.0) / Float16(0.0))
    except:
        raised = True
    assert_true(raised, "a Float16 NaN is not a rational")


def test_from_integral_scalar() raises:
    """Every integral width lands on an exact integer with denominator 1."""
    assert_equal(String(Rational.from_integral_scalar(Int8(-5))), "-5")
    assert_equal(String(Rational.from_integral_scalar(Int8.MIN)), "-128")
    assert_equal(String(Rational.from_integral_scalar(UInt8.MAX)), "255")
    assert_equal(String(Rational.from_integral_scalar(Int32(0))), "0")
    assert_equal(
        String(Rational.from_integral_scalar(Int64.MIN)),
        "-9223372036854775808",
    )
    assert_equal(
        String(Rational.from_integral_scalar(UInt64.MAX)),
        "18446744073709551615",
    )

    var one = Rational.from_integral_scalar(Int(7))
    assert_equal(String(one.denominator), "1", "an integer has denominator 1")


def test_integral_scalar_constructor_is_implicit() raises:
    """An integral scalar converts to a Rational wherever one is wanted."""
    assert_equal(String(Rational(42)), "42")
    assert_equal(String(Rational(Int64(-7))), "-7")
    assert_equal(String(Rational(UInt32(9))), "9")

    var coerced: Rational = 12
    assert_equal(String(coerced), "12")

    # And it composes with the arithmetic, which is the point of @implicit.
    assert_equal(String(Rational("1/3") + 1), "4/3")


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
