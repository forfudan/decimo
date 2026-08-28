"""
Sweeps `BigInt`'s shifts across every bit position of a word.

The existing shift tests are spot checks. This file walks the shift amount
continuously so that both the whole-word part and the sub-word part of the
split take every value, which is where a shift built on a word width goes
wrong: `to_hex_string()` broke exactly that way when the limbs moved to 64
bits, and nothing noticed because no test rendered a `BigInt` as hex.

The oracle needs no Python. A left shift by `s` is a multiplication by `2^s`
and a right shift is a floor division by it, and `BigInt`'s multiply and
floor-divide are well covered elsewhere. That also pins the rounding
direction for negative values, which is the part of the right shift with real
logic in it: it rounds toward negative infinity, so it has to add one to the
magnitude whenever a set bit is shifted out.
"""

from std import testing
from std.testing import assert_equal

from decimo.bigint.bigint import BigInt

comptime MAX_SHIFT = 200


def assert_same(got: BigInt, want: BigInt, context: String) raises:
    """Compares without spelling either value out unless they differ.

    Rendering a `BigInt` as decimal is a repeated division, and at a few
    thousand checks it dominates the runtime of the whole file.
    """
    if got != want:
        assert_equal(String(got), String(want), context)


def powers_of_two(count: Int) raises -> List[BigInt]:
    """Builds `2^0` through `2^count` by doubling, for use as the oracle."""
    var powers = List[BigInt](capacity=count + 1)
    var power = BigInt("1")
    for _ in range(count + 1):
        powers.append(power.copy())
        power = power + power
    return powers^


def sweep_values() raises -> List[BigInt]:
    """Values that put a set bit at each interesting position of a word."""
    var values = List[BigInt]()
    values.append(BigInt("0"))
    values.append(BigInt("1"))
    values.append(BigInt("-1"))
    values.append(BigInt("3"))
    values.append(BigInt("-3"))
    # 2^63, the top bit of one word
    values.append(BigInt("9223372036854775808"))
    values.append(BigInt("-9223372036854775808"))
    # 2^64 - 1, a full word
    values.append(BigInt("18446744073709551615"))
    # 2^64, a set bit with an empty word below it
    values.append(BigInt("18446744073709551616"))
    values.append(BigInt("-18446744073709551616"))
    # 2^128 - 1, two full words
    values.append(BigInt("340282366920938463463374607431768211455"))
    values.append(BigInt("-340282366920938463463374607431768211455"))
    # An odd multi-word value, so bits are lost at every right shift
    values.append(BigInt("123456789012345678901234567890123456789012345678901"))
    values.append(
        BigInt("-123456789012345678901234567890123456789012345678901")
    )
    # A multi-word value whose low words are zero, so nothing is lost until
    # the shift reaches the third word
    values.append(BigInt("18446744073709551616") ** 3)
    values.append(BigInt("-1") * (BigInt("18446744073709551616") ** 3))
    return values^


def test_left_shift_is_multiplication_by_a_power_of_two() raises:
    var powers = powers_of_two(MAX_SHIFT)
    var values = sweep_values()
    for value in values:
        for shift in range(MAX_SHIFT + 1):
            assert_same(
                value << shift,
                value * powers[shift],
                "left shift by " + String(shift),
            )


def test_right_shift_is_floor_division_by_a_power_of_two() raises:
    var powers = powers_of_two(MAX_SHIFT)
    var values = sweep_values()
    for value in values:
        for shift in range(MAX_SHIFT + 1):
            assert_same(
                value >> shift,
                value // powers[shift],
                "right shift by " + String(shift),
            )


def test_a_right_shift_undoes_a_left_shift() raises:
    var values = sweep_values()
    for value in values:
        for shift in range(MAX_SHIFT + 1):
            assert_same(
                (value << shift) >> shift,
                value,
                "round trip by " + String(shift),
            )


def test_the_in_place_shifts_agree_with_the_out_of_place_ones() raises:
    var values = sweep_values()
    for value in values:
        for shift in range(MAX_SHIFT + 1):
            var shifted_left = value.copy()
            shifted_left <<= shift
            assert_same(
                shifted_left,
                value << shift,
                "in-place left shift by " + String(shift),
            )

            var shifted_right = value.copy()
            shifted_right >>= shift
            assert_same(
                shifted_right,
                value >> shift,
                "in-place right shift by " + String(shift),
            )


def test_shifting_past_the_whole_value() raises:
    """A right shift wider than the value keeps only the sign: 0 or -1."""
    var values = sweep_values()
    for value in values:
        for shift in [256, 512, 1000]:
            var expected = BigInt("0")
            if value < BigInt("0"):
                expected = BigInt("-1")
            assert_same(
                value >> shift, expected, "far right shift by " + String(shift)
            )


def test_a_negative_shift_reverses_the_direction() raises:
    """`shift < 0` delegates to the opposite shift rather than raising."""
    var values = sweep_values()
    for value in values:
        for shift in [1, 63, 64, 65, 129]:
            assert_same(value << -shift, value >> shift, "negative left")
            assert_same(value >> -shift, value << shift, "negative right")


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
