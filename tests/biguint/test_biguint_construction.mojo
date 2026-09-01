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


def test_to_int_at_and_beyond_its_range() raises:
    """`to_int()` returns the value or raises; it never returns a wrong one.

    The version before this one built the whole value in an `Int128` and
    compared once at the end, guarded by a word count that allowed one word
    more than `Int.MAX` needs. The multiply overflowed before the comparison
    ran, so `10^21` came back as 6873995514006732800.
    """
    assert_equal(BigUInt("0").to_int(), 0)
    assert_equal(BigUInt("1").to_int(), 1)
    assert_equal(BigUInt(String(Int.MAX)).to_int(), Int.MAX)

    # One past the top, and far enough past it to need an extra word.
    for over in [
        "9223372036854775808",
        "9999999999999999999",
        "1000000000000000000000",
        "1" + "0" * 60,
    ]:
        with assert_raises():
            _ = BigUInt(over).to_int()


def test_to_uint64_across_the_word_boundary() raises:
    """Every word count that fits a `UInt64` round-trips.

    The value that caught this was `10^18`: exactly one word plus one at
    eighteen digits a word, and the old SIMD reassembly scaled the second word
    by `10^9`, so it came back as `10^9`.
    """
    for text in [
        "0",
        "1",
        "999999999999999999",
        "1000000000000000000",
        "1000000000000000001",
        "9223372036854775807",
        "18446744073709551614",
        "18446744073709551615",
    ]:
        assert_equal(String(BigUInt(text).to_uint64()), text)

    for over in ["18446744073709551616", "1" + "0" * 30]:
        with assert_raises():
            _ = BigUInt(over).to_uint64()


def test_to_uint128_across_the_word_boundary() raises:
    """Same for `UInt128`, up to and including its maximum.

    `to_uint128()` does not raise -- see its docstring -- so only values the
    caller is allowed to hand it are checked here.
    """
    for text in [
        "0",
        "999999999999999999",
        "1000000000000000000",
        "18446744073709551616",
        "170141183460469231731687303715884105727",
        "340282366920938463463374607431768211455",
    ]:
        assert_equal(String(BigUInt(text).to_uint128()), text)


def test_overflow_predicates_at_their_boundaries() raises:
    """`is_uint64_overflow()` and `is_uint128_overflow()` on both sides.

    The `UInt128` one used to read one past the end of a four-word value and
    let five-word values -- the only length that can overflow -- fall through
    to `False`.
    """
    assert_true(not BigUInt(String(UInt64.MAX)).is_uint64_overflow())
    assert_true(BigUInt("18446744073709551616").is_uint64_overflow())

    assert_true(
        not BigUInt(
            "340282366920938463463374607431768211455"
        ).is_uint128_overflow()
    )
    assert_true(
        BigUInt("340282366920938463463374607431768211456").is_uint128_overflow()
    )
    assert_true(BigUInt("9" * 45).is_uint128_overflow())


def test_is_one_and_is_two() raises:
    """`is_two()` used to answer `False` for two, and for everything else.

    It asked for a two-word value and then for the second word to be zero,
    which the no-leading-zero invariant forbids, so nothing could pass it.
    """
    assert_true(BigUInt("1").is_one())
    assert_true(not BigUInt("0").is_one())
    assert_true(not BigUInt("2").is_one())

    assert_true(BigUInt("2").is_two())
    assert_true(not BigUInt("0").is_two())
    assert_true(not BigUInt("1").is_two())
    assert_true(not BigUInt("3").is_two())
    # A value whose lowest word is 2 but which carries more words.
    assert_true(not BigUInt("1" + "0" * 18 + "2").is_two())


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
