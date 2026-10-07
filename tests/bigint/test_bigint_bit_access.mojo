"""
Tests bit-level access on `BigInt`.

A negative value is read as an infinite-width two's complement, which is the
view `&`, `|`, `^`, `~` and `>>` already present on this type and the one
Python, GMP and Java share. So the reference for every case here is CPython:
`(x >> k) & 1` for a bit, `x | (1 << k)` and its siblings for the three
writes, and `popcount(x ^ y)` for the distance.

The cases that matter are the negative ones. Reading the magnitude and
keeping the sign aside would agree with two's complement on `-1` and `-2` by
coincidence and part ways at `-3`, which is why the tables below run past
those.
"""

from std import testing
from std.testing import assert_equal, assert_true

from decimo.bigint.bigint import BigInt
from decimo.bigint.bitwise import (
    bit_scan0,
    bit_scan1,
    clear_bit,
    flip_bit,
    hamming_distance,
    set_bit,
    test_bit,
    trailing_zeros,
)


def test_test_bit_against_cpython() raises:
    """The low bits of each value, as `(x >> k) & 1` gives them."""
    var values = [5, -5, -1, -8, 0, 255, -256, -3, 1024, -1024]
    var expected = [
        "10100000",
        "11011111",
        "11111111",
        "00011111",
        "00000000",
        "11111111",
        "00000000",
        "10111111",
        "00000000",
        "00000000",
    ]
    for i in range(len(values)):
        var x = BigInt(values[i])
        var bits = String("")
        for k in range(8):
            bits += "1" if test_bit(x, k) else "0"
        assert_equal(bits, expected[i], "the low bits of " + String(values[i]))


def test_test_bit_agrees_with_the_and_operator() raises:
    """`test_bit(x, k)` and `x & (1 << k)` read the same bit.

    This is the consistency that picked the convention. Reading the magnitude
    instead would answer `true` for `test_bit(-3, 1)` while `-3 & 2` is zero.
    """
    var values = [
        BigInt("5"),
        BigInt("-3"),
        BigInt("-5"),
        BigInt("-8"),
        BigInt("-1"),
        BigInt("123456789012345678901234567890"),
        BigInt("-123456789012345678901234567890"),
    ]
    for x in values:
        for k in range(0, 130):
            var mask = BigInt.one() << k
            var by_operator = (x & mask) != BigInt.zero()
            assert_equal(
                test_bit(x, k),
                by_operator,
                "bit " + String(k) + " of " + String(x),
            )


def test_test_bit_far_above_the_magnitude() raises:
    """Past the top, every bit is the sign's."""
    assert_true(not test_bit(BigInt("255"), 1000), "a positive value reads 0")
    assert_true(test_bit(BigInt("-255"), 1000), "a negative value reads 1")
    assert_true(not test_bit(BigInt.zero(), 1000), "zero reads 0")


def test_the_three_writes_against_their_operators() raises:
    """Each write is its operator, so the test is that it stays that way."""
    var values = [
        BigInt("5"),
        BigInt("-5"),
        BigInt("-8"),
        BigInt("0"),
        BigInt("-1"),
        BigInt("98765432109876543210"),
        BigInt("-98765432109876543210"),
    ]
    for x in values:
        for k in range(0, 70):
            var mask = BigInt.one() << k
            assert_equal(set_bit(x, k), x | mask, "set at " + String(k))
            assert_equal(clear_bit(x, k), x & ~mask, "clear at " + String(k))
            assert_equal(flip_bit(x, k), x ^ mask, "flip at " + String(k))


def test_the_three_writes_against_cpython() raises:
    """A handful of values spelled out, from CPython."""
    assert_equal(set_bit(BigInt(5), 3), BigInt(13), "5 with bit 3 set")
    assert_equal(clear_bit(BigInt(5), 0), BigInt(4), "5 with bit 0 cleared")
    assert_equal(flip_bit(BigInt(-5), 1), BigInt(-7), "-5 with bit 1 flipped")
    assert_equal(set_bit(BigInt(-8), 0), BigInt(-7), "-8 with bit 0 set")
    assert_equal(clear_bit(BigInt(-1), 0), BigInt(-2), "-1 with bit 0 cleared")


def test_writing_a_bit_is_idempotent() raises:
    """Setting a set bit changes nothing; flipping twice returns."""
    for x in [BigInt("12"), BigInt("-12"), BigInt("0")]:
        for k in [0, 1, 2, 5, 64, 65]:
            var once = set_bit(x, k)
            assert_equal(set_bit(once, k), once, "set twice at " + String(k))
            var cleared = clear_bit(x, k)
            assert_equal(
                clear_bit(cleared, k), cleared, "clear twice at " + String(k)
            )
            assert_equal(
                flip_bit(flip_bit(x, k), k), x, "flip twice at " + String(k)
            )
            assert_true(
                test_bit(once, k), "the set bit did not read back as set"
            )
            assert_true(
                not test_bit(cleared, k),
                "the cleared bit did not read back as clear",
            )


def test_trailing_zeros() raises:
    """The lowest set bit, which the sign does not move."""
    var cases = [
        (0, -1),
        (1, 0),
        (2, 1),
        (8, 3),
        (12, 2),
        (-1, 0),
        (-8, 3),
        (-12, 2),
    ]
    for item in cases:
        assert_equal(
            trailing_zeros(BigInt(item[0])),
            item[1],
            "trailing zeros of " + String(item[0]),
        )

    # A value with its lowest set bit well inside the second word.
    var wide = BigInt.one() << 100
    assert_equal(trailing_zeros(wide), 100, "a bit in the second word")
    assert_equal(trailing_zeros(-wide), 100, "and its negation")


def test_the_scans_against_cpython() raises:
    """The first set and clear bit at or above a start."""
    var values = [0, 1, 8, -8, 12, -12, 255, -255]
    var scan1 = [-1, 0, 3, 3, 2, 2, 0, 0]
    var scan0 = [0, 1, 0, 0, 0, 0, 8, 1]
    for i in range(len(values)):
        var x = BigInt(values[i])
        assert_equal(bit_scan1(x, 0), scan1[i], "scan1 of " + String(values[i]))
        assert_equal(bit_scan0(x, 0), scan0[i], "scan0 of " + String(values[i]))


def test_the_scans_find_nothing_only_where_they_cannot() raises:
    """Above the magnitude the bits are the sign's, so one scan ends there.

    A non-negative value has no set bit past its top, and a negative one has
    no clear bit. The other direction always finds something.
    """
    assert_equal(bit_scan1(BigInt("255"), 8), -1, "no set bit above 255")
    assert_equal(bit_scan1(BigInt.zero(), 0), -1, "no set bit in zero")
    assert_equal(bit_scan0(BigInt("-1"), 0), -1, "no clear bit in -1")
    assert_equal(bit_scan0(BigInt("-256"), 8), -1, "no clear bit above -256")

    assert_true(bit_scan0(BigInt("255"), 0) >= 0, "a positive value has a zero")
    assert_true(bit_scan1(BigInt("-255"), 0) >= 0, "a negative value has a one")


def test_the_scans_at_the_largest_index() raises:
    """A scan that starts at `Int.MAX` still answers from the sign.

    Above the magnitude every bit is the sign's, so the answer there is
    `start` itself or nothing at all. An earlier version computed its loop
    bound as `start + 1`, which overflowed to a negative number and reported
    that `-1` -- whose every bit is set -- had no set bit at `Int.MAX`.
    """
    assert_equal(
        bit_scan1(BigInt("-1"), Int.MAX), Int.MAX, "every bit of -1 is set"
    )
    assert_equal(
        bit_scan0(BigInt("255"), Int.MAX),
        Int.MAX,
        "every bit above 255 is clear",
    )
    assert_equal(
        bit_scan1(BigInt("255"), Int.MAX), -1, "255 has no set bit up there"
    )
    assert_equal(
        bit_scan0(BigInt("-1"), Int.MAX), -1, "-1 has no clear bit anywhere"
    )


def test_a_redundant_write_does_not_build_a_mask() raises:
    """Setting a bit that is already set is a copy, however high it is.

    Every bit of a negative value above its magnitude is set, so this is a
    no-op -- but an earlier version formed `1 << index` first, which at a
    billion would be 125 megabytes to answer `-1`. The index here is large
    enough to be slow if the mask came back, and the test is that it returns
    at all.
    """
    assert_equal(
        set_bit(BigInt("-1"), 10_000_000), BigInt("-1"), "a set bit stays set"
    )
    assert_equal(
        clear_bit(BigInt("255"), 10_000_000),
        BigInt("255"),
        "a clear bit stays clear",
    )
    assert_equal(
        set_bit(BigInt("-8"), 10_000_000), BigInt("-8"), "above a negative top"
    )
    assert_equal(
        clear_bit(BigInt.zero(), 10_000_000), BigInt.zero(), "zero stays zero"
    )


def test_the_scans_agree_with_reading_bit_by_bit() raises:
    """The scans are a loop over `test_bit`, and must stay equal to one."""
    var values = [
        BigInt("0"),
        BigInt("1"),
        BigInt("-1"),
        BigInt("12345"),
        BigInt("-12345"),
        BigInt("1") << 80,
    ]
    for x in values:
        for start in [0, 1, 5, 64, 70]:
            var by_scan = bit_scan1(x, start)
            var by_hand = -1
            for k in range(start, 200):
                if test_bit(x, k):
                    by_hand = k
                    break
            assert_equal(
                by_scan,
                by_hand,
                "scan1 at " + String(start) + " of " + String(x),
            )


def test_hamming_distance() raises:
    """`popcount(x ^ y)`, and a refusal where the count is unbounded."""
    assert_equal(hamming_distance(BigInt(5), BigInt(3)), 2, "5 against 3")
    assert_equal(hamming_distance(BigInt(-5), BigInt(-3)), 2, "-5 against -3")
    assert_equal(
        hamming_distance(BigInt(7), BigInt(7)), 0, "a value with itself"
    )
    assert_equal(
        hamming_distance(BigInt("1") << 100, BigInt.zero()),
        1,
        "a single high bit",
    )

    var raised = False
    try:
        _ = hamming_distance(BigInt(5), BigInt(-3))
    except:
        raised = True
    assert_true(raised, "a mismatched pair of signs was accepted")


def test_hamming_distance_counts_what_test_bit_sees() raises:
    """Counted by hand over the bits, for same-signed pairs."""
    var pairs = [
        (BigInt("12345"), BigInt("54321")),
        (BigInt("-12345"), BigInt("-54321")),
        (BigInt("0"), BigInt("255")),
    ]
    for pair in pairs:
        var counted = 0
        for k in range(0, 200):
            if test_bit(pair[0], k) != test_bit(pair[1], k):
                counted += 1
        assert_equal(
            hamming_distance(pair[0], pair[1]),
            counted,
            "the distance disagrees with the bits",
        )


def test_a_negative_index_raises() raises:
    """There is no bit below the zeroth."""
    var x = BigInt(5)
    for index in [-1, -64]:
        var raised = False
        try:
            _ = test_bit(x, index)
        except:
            raised = True
        assert_true(raised, "test_bit accepted " + String(index))

        raised = False
        try:
            _ = set_bit(x, index)
        except:
            raised = True
        assert_true(raised, "set_bit accepted " + String(index))

        raised = False
        try:
            _ = bit_scan1(x, index)
        except:
            raised = True
        assert_true(raised, "bit_scan1 accepted " + String(index))


def test_the_methods_match_the_functions() raises:
    """Each method is the free function, which is what the tests exercise."""
    var x = BigInt("-12345678901234567890")
    assert_equal(x.test_bit(7), test_bit(x, 7), "test_bit")
    assert_equal(x.set_bit(7), set_bit(x, 7), "set_bit")
    assert_equal(x.clear_bit(7), clear_bit(x, 7), "clear_bit")
    assert_equal(x.flip_bit(7), flip_bit(x, 7), "flip_bit")
    assert_equal(x.trailing_zeros(), trailing_zeros(x), "trailing_zeros")
    assert_equal(x.bit_scan1(3), bit_scan1(x, 3), "bit_scan1")
    assert_equal(x.bit_scan0(3), bit_scan0(x, 3), "bit_scan0")
    assert_equal(
        x.hamming_distance(BigInt("-1")),
        hamming_distance(x, BigInt("-1")),
        "hamming_distance",
    )


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
