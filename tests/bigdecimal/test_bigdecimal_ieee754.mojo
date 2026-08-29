"""
Tests for `BigDecimal` and the IEEE 754 decimal128 interchange format.

Every decimal128 fits a `BigDecimal` exactly, so the round trip is bit for
bit in both directions; the other way round can be refused.
"""

from std import testing
from std.testing import assert_equal, assert_true

from decimo.bigdecimal.bigdecimal import BigDecimal


def test_round_trip_is_exact() raises:
    """A decimal128 read and written again is the same sixteen bytes."""

    def _check(bits: UInt128, text: String) raises:
        var value = BigDecimal.from_ieee754_decimal128(bits)
        assert_equal(String(value), text)
        assert_equal(value.to_ieee754_decimal128(), bits)

    _check(UInt128(0x30400000000000000000000000000001), "1")
    _check(UInt128(0x303E000000000000000000000000000A), "1.0")
    _check(UInt128(0xB0400000000000000000000000000001), "-1")
    _check(UInt128(0x303A0000000000000000000000000001), "0.001")
    # The whole coefficient, which `Decimal128` has no room for.
    _check(
        UInt128(0x3041ED09BEAD87C0378D8E63FFFFFFFF),
        "9999999999999999999999999999999999",
    )
    # And both ends of the exponent.
    _check(UInt128(0x5FFE0000000000000000000000000001), "1E+6111")
    _check(UInt128(0x00000000000000000000000000000001), "1E-6176")


def test_writing_refuses_what_the_format_cannot_hold() raises:
    """A `BigDecimal` has neither the 34 digits nor the exponent range as a
    limit, so this is the direction that can fail."""
    var raised = False
    try:
        _ = BigDecimal(
            "12345678901234567890123456789012345"
        ).to_ieee754_decimal128()
    except:
        raised = True
    assert_true(raised, "35 digits do not fit decimal128")

    raised = False
    try:
        _ = BigDecimal("1E+7000").to_ieee754_decimal128()
    except:
        raised = True
    assert_true(raised, "an exponent of 7000 does not fit decimal128")


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
