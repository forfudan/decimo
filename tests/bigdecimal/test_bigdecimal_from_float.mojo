"""Test that BigDecimal reads a binary float exactly.

`BigDecimal.from_float_scalar()` returns the value the float actually holds,
not the decimal literal somebody wrote to produce it. The expected strings
here are Python's `decimal.Decimal(value)`, which does the same thing, so
this file doubles as a compatibility check for the `decimo` Python package.
"""

from std import testing
from std.testing import assert_equal, assert_raises, assert_true

from decimo.bigdecimal.bigdecimal import BigDecimal


def test_the_float_not_the_literal() raises:
    """0.1 is not one tenth, and the conversion says so."""
    assert_equal(
        String(BigDecimal.from_float_scalar(0.1)),
        "0.1000000000000000055511151231257827021181583404541015625",
    )
    assert_equal(
        String(BigDecimal.from_float_scalar(1.0 / 3.0)),
        "0.333333333333333314829616256247390992939472198486328125",
    )
    # ...and it really is a different number from the literal.
    assert_true(BigDecimal.from_float_scalar(0.1) != BigDecimal("0.1"))


def test_values_that_are_exact_in_binary() raises:
    """A float whose value is a short decimal comes back short.

    The fraction is reduced first, the way `float.as_integer_ratio()` reports
    it. Without that, 0.5 would come back as 5 * 10^52 at scale 53 -- the same
    number, but trailing 52 zeros.
    """
    assert_equal(String(BigDecimal.from_float_scalar(0.5)), "0.5")
    assert_equal(String(BigDecimal.from_float_scalar(0.125)), "0.125")
    assert_equal(String(BigDecimal.from_float_scalar(1.5)), "1.5")
    assert_equal(String(BigDecimal.from_float_scalar(-2.5)), "-2.5")
    assert_equal(String(BigDecimal.from_float_scalar(1024.0)), "1024")
    assert_equal(
        String(BigDecimal.from_float_scalar(1e20)), "100000000000000000000"
    )


def test_zero_keeps_its_sign() raises:
    assert_equal(String(BigDecimal.from_float_scalar(0.0)), "0")
    assert_equal(String(BigDecimal.from_float_scalar(-0.0)), "-0")


def test_narrower_formats_read_exactly_too() raises:
    """Every binary format is read exactly, not just Float64."""
    assert_equal(
        String(BigDecimal.from_float_scalar(Float32(0.1))),
        "0.100000001490116119384765625",
    )
    assert_equal(
        String(BigDecimal.from_float_scalar(Float16(0.1))), "0.0999755859375"
    )
    assert_equal(String(BigDecimal.from_float_scalar(Float32(-2.5))), "-2.5")
    assert_equal(String(BigDecimal.from_float_scalar(Float16(0.5))), "0.5")


def test_subnormal() raises:
    """The smallest positive double is 2^-1074, which is 751 decimal digits.

    Its coefficient is 5^1074, so this is also the widest the power-of-five
    loop ever runs.
    """
    var text = String(BigDecimal.from_float_scalar(Float64(5e-324)))
    assert_true(text.startswith("4.940656458412465441765687928682213723650"))
    assert_true(text.endswith("265533447265625E-324"))
    # 751 significant digits: one before the point and 750 after, plus the
    # point and the five-character exponent.
    assert_equal(text.byte_length(), 751 + 1 + 5)


def test_matches_python_decimal() raises:
    """Every expected string here is `str(decimal.Decimal(value))` in CPython.

    This is the compatibility check that matters: the `decimo` Python package
    is a drop-in for `decimal`, and the constructor from a float was the one
    place the two disagreed.
    """
    assert_equal(
        String(BigDecimal.from_float_scalar(3.141592653589793)),
        "3.141592653589793115997963468544185161590576171875",
    )
    assert_equal(
        String(BigDecimal.from_float_scalar(123.456)),
        "123.4560000000000030695446184836328029632568359375",
    )
    assert_equal(
        String(BigDecimal.from_float_scalar(1e-5)),
        (
            "0.0000100000000000000008180305391403130954586231382563710212707"
            "51953125"
        ),
    )
    assert_equal(
        String(BigDecimal.from_float_scalar(2.220446049250313e-16)),
        "2.220446049250313080847263336181640625E-16",
    )
    assert_equal(
        String(BigDecimal.from_float_scalar(9007199254740991.0)),
        "9007199254740991",
    )
    assert_equal(
        String(BigDecimal.from_float_scalar(1e-20)),
        (
            "9.9999999999999994515327145420957165172950370278739244710771577"
            "6066783064379706047475337982177734375E-21"
        ),
    )
    assert_equal(
        String(BigDecimal.from_float_scalar(-1e-20)),
        (
            "-9.999999999999999451532714542095716517295037027873924471077157"
            "76066783064379706047475337982177734375E-21"
        ),
    )


def test_non_finite_raises() raises:
    """Neither infinity nor NaN is a decimal number."""
    with assert_raises():
        _ = BigDecimal.from_float_scalar(Float64("1e400"))
    with assert_raises():
        _ = BigDecimal.from_float_scalar(Float64("1e400") - Float64("1e400"))
    with assert_raises():
        _ = BigDecimal.from_float_scalar(Float32.MAX * Float32(2.0))


def test_agrees_with_rational() raises:
    """`Rational` already read floats exactly; now the two agree.

    A float is `n / 2^k`, so multiplying the decimal by the rational's
    denominator has to give its numerator back with nothing rounded away.
    """
    from decimo.rational.rational import Rational

    var values = [0.1, 0.5, -2.5, 0.125, 1.0 / 3.0, 123.456]
    for i in range(len(values)):
        var as_decimal = BigDecimal.from_float_scalar(values[i])
        var as_rational = Rational.from_float_scalar(values[i])
        var denominator = BigDecimal(as_rational.denominator)
        var numerator = BigDecimal(as_rational.numerator)
        # Compared by value: the product carries the scale the
        # multiplication gave it, so its text has trailing zeros that the
        # integer numerator does not.
        assert_true(as_decimal * denominator == numerator)


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
