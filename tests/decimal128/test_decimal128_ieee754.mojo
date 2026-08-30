"""
Tests for the IEEE 754 decimal128 interchange format: `decimo.ieee754` and
the `Decimal128` conversions built on it.

The hexadecimal patterns are the format's own, and the first few are the
values MongoDB's BSON specification writes out for the same numbers.
"""

from std import testing
from std.testing import assert_equal, assert_false, assert_true

from decimo.decimal128.decimal128 import Decimal128
from decimo.ieee754 import (
    DECIMAL128_MAX_COEFFICIENT,
    decimal128_from_bytes,
    decimal128_infinity,
    decimal128_is_finite,
    decimal128_is_infinity,
    decimal128_is_nan,
    decimal128_is_signaling_nan,
    decimal128_quiet_nan,
    decimal128_to_bytes,
    decode_decimal128,
    encode_decimal128,
)


def test_known_patterns() raises:
    """The sixteen bytes for numbers whose encoding is written down
    elsewhere."""

    def _check(text: String, bits: UInt128) raises:
        assert_equal(Decimal128(text).to_ieee754(), bits)
        assert_equal(String(Decimal128.from_ieee754(bits)), text)

    _check("1", UInt128(0x30400000000000000000000000000001))
    _check("0", UInt128(0x30400000000000000000000000000000))
    _check("-1", UInt128(0xB0400000000000000000000000000001))
    _check("0.001", UInt128(0x303A0000000000000000000000000001))
    # A trailing zero is part of the encoding, not noise to be tidied away:
    # `1.0` and `1` are one number and two patterns.
    _check("1.0", UInt128(0x303E000000000000000000000000000A))
    _check(
        "12345678901234567890123456789",
        UInt128(0x3040000027E41B3246BEC9B16E398115),
    )
    _check(
        "0.0000000000000000000000000001",
        UInt128(0x30080000000000000000000000000001),
    )

    # Negative zero keeps its sign.
    assert_equal(
        Decimal128("-0").to_ieee754(),
        UInt128(0xB0400000000000000000000000000000),
    )


def test_round_trip_through_the_format() raises:
    """Every value this type holds comes back as itself, digit for digit."""

    def _check(text: String) raises:
        var value = Decimal128(text)
        assert_equal(String(Decimal128.from_ieee754(value.to_ieee754())), text)

    _check("0")
    _check("1")
    _check("-1")
    _check("79228162514264337593543950335")
    _check("-79228162514264337593543950335")
    _check("0.0000000000000000000000000001")
    _check("7.9228162514264337593543950335")
    _check("123.4500")
    _check("-0.000000000000000000000000000")


def test_encoding_refuses_what_the_format_cannot_hold() raises:
    """The coefficient stops at 34 digits and the exponent at 6111."""
    var raised = False
    try:
        _ = encode_decimal128(False, DECIMAL128_MAX_COEFFICIENT + UInt128(1), 0)
    except:
        raised = True
    assert_true(raised, "35 digits should be refused")

    raised = False
    try:
        _ = encode_decimal128(False, UInt128(1), 6112)
    except:
        raised = True
    assert_true(raised, "an exponent above 6111 should be refused")

    raised = False
    try:
        _ = encode_decimal128(False, UInt128(1), -6177)
    except:
        raised = True
    assert_true(raised, "an exponent below -6176 should be refused")

    # The two ends themselves are fine.
    _ = encode_decimal128(False, DECIMAL128_MAX_COEFFICIENT, 6111)
    _ = encode_decimal128(True, DECIMAL128_MAX_COEFFICIENT, -6176)


def test_decoding_into_a_smaller_type() raises:
    """The format reaches further than `Decimal128`, so this direction rounds
    and can fail."""

    def _refuses(bits: UInt128) raises:
        var raised = False
        try:
            _ = Decimal128.from_ieee754(bits)
        except:
            raised = True
        assert_true(raised, "the value is past what Decimal128 holds")

    # 34 digits, and a hundred orders of magnitude too far.
    _refuses(UInt128(0x3041ED09BEAD87C0378D8E63FFFFFFFF))
    _refuses(UInt128(0x31080000000000000000000000000001))
    _refuses(UInt128(0x5FFE0000000000000000000000000001))

    # Below the smallest scale, the answer is zero rather than a refusal.
    assert_equal(
        String(
            Decimal128.from_ieee754(UInt128(0x01600000000000000000000000000001))
        ),
        "0.0000000000000000000000000000",
    )

    # And what does fit is rounded to nearest, ties to even.
    assert_equal(
        String(
            Decimal128.from_ieee754(UInt128(0x303A009BD30A3C645943DD1690A03BFB))
        ),
        "12345678901234567890123456789",
    )
    assert_equal(
        String(
            Decimal128.from_ieee754(UInt128(0x303A009BD30A3C645943DD1690A03BFC))
        ),
        "12345678901234567890123456790",
    )
    assert_equal(
        String(
            Decimal128.from_ieee754(UInt128(0x30040000000000000000000000000033))
        ),
        "0.0000000000000000000000000001",
    )


def test_infinities_and_nans() raises:
    """The format has them; decimo does not, and says so."""
    var infinity = decimal128_infinity()
    var negative_infinity = decimal128_infinity(sign=True)
    var nan = decimal128_quiet_nan()

    assert_equal(infinity, UInt128(0x78000000000000000000000000000000))
    assert_equal(nan, UInt128(0x7C000000000000000000000000000000))

    assert_true(decimal128_is_infinity(infinity))
    assert_true(decimal128_is_infinity(negative_infinity))
    assert_true(decimal128_is_nan(nan))
    assert_false(decimal128_is_finite(infinity))
    assert_false(decimal128_is_finite(nan))
    assert_true(decimal128_is_finite(Decimal128("1").to_ieee754()))

    var signaling = UInt128(0x7E000000000000000000000000000000)
    assert_true(decimal128_is_nan(signaling))
    assert_true(decimal128_is_signaling_nan(signaling))
    assert_false(decimal128_is_signaling_nan(nan))

    for bits in [infinity, negative_infinity, nan, signaling]:
        var raised = False
        try:
            _ = decode_decimal128(bits)
        except:
            raised = True
        assert_true(raised, "decoding one of these should raise")


def test_the_second_coefficient_layout_reads_as_zero() raises:
    """The layout that begins the coefficient with an implied `100`.

    Its smallest value is `2^113`, which is `1.038E+34` and larger than any
    coefficient decimal128 allows, so every value written that way is
    non-canonical -- and the standard says a non-canonical coefficient is
    zero.
    """
    var parts = decode_decimal128(UInt128(0x6C100000000000000000000000000000))
    assert_equal(parts[1], UInt128(0))
    assert_equal(
        String(
            Decimal128.from_ieee754(UInt128(0x6C100000000000000000000000000000))
        ),
        "0",
    )


def test_bytes_in_either_order() raises:
    """Sixteen bytes, little-endian as BSON writes them or the other way."""
    var bits = Decimal128("1").to_ieee754()
    var little = decimal128_to_bytes(bits)
    var big = decimal128_to_bytes[little_endian=False](bits)

    assert_equal(little[0], UInt8(1))
    assert_equal(little[14], UInt8(0x40))
    assert_equal(little[15], UInt8(0x30))
    assert_equal(big[0], UInt8(0x30))
    assert_equal(big[1], UInt8(0x40))
    assert_equal(big[15], UInt8(1))

    assert_equal(decimal128_from_bytes(little), bits)
    assert_equal(decimal128_from_bytes[little_endian=False](big), bits)


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
