"""
Test BigUInt construction from integral scalars of every supported width.

`BigUInt.from_integral_scalar()` is the single entry point for building a
BigUInt from any integral scalar, signed or unsigned; `BigUInt(value)` goes
through it. `BigUInt.from_unsigned_integral_scalar()` is the non-raising
unsigned-only path that the arithmetic fast paths use, and the two must agree
wherever both apply.
"""

from std import testing
from std.testing import assert_equal, assert_raises, assert_true

from decimo.biguint.biguint import BigUInt


def test_from_unsigned_scalar_widths() raises:
    """Every unsigned width converts correctly at 0, MAX, and the word bounds.
    """
    # 8- and 16-bit values always fit in a single base-10^9 word.
    assert_equal(String(BigUInt.from_unsigned_integral_scalar(UInt8(0))), "0")
    assert_equal(
        String(BigUInt.from_unsigned_integral_scalar(UInt8.MAX)), "255"
    )
    assert_equal(String(BigUInt.from_unsigned_integral_scalar(UInt16(0))), "0")
    assert_equal(
        String(BigUInt.from_unsigned_integral_scalar(UInt16.MAX)), "65535"
    )

    # 32-bit values straddle the one-word/two-word boundary at 10^9.
    assert_equal(String(BigUInt.from_unsigned_integral_scalar(UInt32(0))), "0")
    assert_equal(
        String(BigUInt.from_unsigned_integral_scalar(UInt32(999_999_999))),
        "999999999",
    )
    assert_equal(
        String(BigUInt.from_unsigned_integral_scalar(UInt32(1_000_000_000))),
        "1000000000",
    )
    assert_equal(
        String(BigUInt.from_unsigned_integral_scalar(UInt32.MAX)), "4294967295"
    )

    # Wider values go through the peeling loop, whose word count is derived
    # at compile time from the scalar width.
    assert_equal(String(BigUInt.from_unsigned_integral_scalar(UInt64(0))), "0")
    assert_equal(
        String(BigUInt.from_unsigned_integral_scalar(UInt64.MAX)),
        "18446744073709551615",
    )
    assert_equal(
        String(BigUInt.from_unsigned_integral_scalar(UInt128.MAX)),
        "340282366920938463463374607431768211455",
    )
    assert_equal(
        String(BigUInt.from_unsigned_integral_scalar(UInt256.MAX)),
        (
            "115792089237316195423570985008687907853"
            "269984665640564039457584007913129639935"
        ),
    )
    assert_equal(
        String(BigUInt.from_unsigned_integral_scalar(UInt.MAX)),
        "18446744073709551615",
    )


def test_from_integral_scalar_unsigned() raises:
    """The general entry point agrees with the unsigned-only one."""
    assert_equal(String(BigUInt.from_integral_scalar(UInt8.MAX)), "255")
    assert_equal(String(BigUInt.from_integral_scalar(UInt16.MAX)), "65535")
    assert_equal(String(BigUInt.from_integral_scalar(UInt32.MAX)), "4294967295")
    assert_equal(
        String(BigUInt.from_integral_scalar(UInt64.MAX)), "18446744073709551615"
    )
    assert_equal(
        String(BigUInt.from_integral_scalar(UInt128.MAX)),
        "340282366920938463463374607431768211455",
    )


def test_from_integral_scalar_signed() raises:
    """Non-negative signed scalars of every width convert correctly."""
    assert_equal(String(BigUInt.from_integral_scalar(Int8(0))), "0")
    assert_equal(String(BigUInt.from_integral_scalar(Int8.MAX)), "127")
    assert_equal(String(BigUInt.from_integral_scalar(Int16.MAX)), "32767")
    assert_equal(String(BigUInt.from_integral_scalar(Int32.MAX)), "2147483647")
    assert_equal(
        String(BigUInt.from_integral_scalar(Int64.MAX)), "9223372036854775807"
    )
    assert_equal(
        String(BigUInt.from_integral_scalar(Int128.MAX)),
        "170141183460469231731687303715884105727",
    )
    assert_equal(String(BigUInt.from_integral_scalar(Int(0))), "0")
    assert_equal(
        String(BigUInt.from_integral_scalar(Int(1_000_000_000))), "1000000000"
    )
    assert_equal(
        String(BigUInt.from_integral_scalar(Int.MAX)), "9223372036854775807"
    )


def test_from_integral_scalar_negative_raises() raises:
    """A negative value of any signed width is rejected."""
    with assert_raises():
        _ = BigUInt.from_integral_scalar(Int8(-1))
    with assert_raises():
        _ = BigUInt.from_integral_scalar(Int16(-1))
    with assert_raises():
        _ = BigUInt.from_integral_scalar(Int32(-1))
    with assert_raises():
        _ = BigUInt.from_integral_scalar(Int64(-1))
    with assert_raises():
        _ = BigUInt.from_integral_scalar(Int128(-1))
    with assert_raises():
        _ = BigUInt.from_integral_scalar(Int(-1))
    # The most negative value of a width is the case a naive negation would
    # get wrong, so check it explicitly.
    with assert_raises():
        _ = BigUInt.from_integral_scalar(Int8.MIN)
    with assert_raises():
        _ = BigUInt.from_integral_scalar(Int64.MIN)
    with assert_raises():
        _ = BigUInt.from_integral_scalar(Int.MIN)


def test_constructor_accepts_all_integral_widths() raises:
    """`BigUInt(value)` now accepts signed scalars, not just `Int`."""
    assert_equal(String(BigUInt(UInt8(7))), "7")
    assert_equal(String(BigUInt(Int8(7))), "7")
    assert_equal(String(BigUInt(UInt32(4_294_967_295))), "4294967295")
    assert_equal(String(BigUInt(Int32(2_147_483_647))), "2147483647")
    assert_equal(String(BigUInt(UInt64.MAX)), "18446744073709551615")
    assert_equal(String(BigUInt(Int64.MAX)), "9223372036854775807")
    assert_equal(String(BigUInt(Int(12345))), "12345")
    with assert_raises():
        _ = BigUInt(Int(-1))


def test_zero_with_capacity() raises:
    """A reserved zero is an ordinary zero, whatever room it was given.

    The capacity itself is not observable, so what is checked is that the
    reserved buffer holds a valid single-word zero. Capacities below one are
    rejected by a `debug_assert`, so they cannot be exercised here — the suite
    runs with assertions on.
    """
    for capacity in [1, 2, 4, 64]:
        var value = BigUInt.zero_with_capacity(capacity)
        assert_equal(String(value), "0")
        assert_equal(len(value.words), 1)
        assert_true(value.is_zero())


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
