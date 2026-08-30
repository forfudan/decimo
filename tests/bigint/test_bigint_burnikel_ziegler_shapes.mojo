"""
Pins two Burnikel-Ziegler shapes that `BigInt` got wrong.

`BigInt` carries its own copy of the algorithm, in base 2^64, and it had the
same short-dividend branch defect as `BigUInt`'s: a dividend of exactly three
parts, or four with a zero top, was sent to a single `three_by_two` at half
the block size, which can only produce half the quotient. `BigUInt` raised on
the shape; this copy returned a wrong quotient and no error at all.

It also had a second, independent defect in the block-count guard: the test
for "top limb at or above half the base" used the mask `0x80000000` -- bit 31,
left over from the 32-bit limbs this was written for. At 64 bits that is a bit
in the middle of the limb, so a top limb of exactly `2^63` passed the test,
the padding it guards did not happen, and under `ASSERT=all` the division
crashed on an out-of-bounds write in the accumulator. Under `ASSERT=none` it
would have written past the end silently.

Both are pinned with the algebraic oracle `q * y + r == x`, `0 <= r < y`, on
operands built just past `CUTOFF_BURNIKEL_ZIEGLER` so the transform path is
the one taken.
"""

from std import testing
from std.testing import assert_true

from decimo.bigint import arithmetics as bigint_arithmetics
from decimo.bigint.bigint import BigInt


def assert_divmod_invariant(x: BigInt, y: BigInt, context: String) raises:
    var q = x // y
    var r = x % y
    assert_true(
        r >= BigInt("0") and r < y,
        context + ": remainder is not in [0, y)",
    )
    assert_true(q * y + r == x, context + ": q * y + r != x")


def all_ones(limbs: Int) raises -> BigInt:
    return (BigInt("1") << (64 * limbs)) - BigInt("1")


def top_limb_half_base(limbs: Int) raises -> BigInt:
    """`2^63` in the top limb, all ones below it."""
    var value = BigInt("1") << (64 * limbs - 1)
    return value + all_ones(limbs - 1)


def test_a_dividend_of_exactly_three_parts() raises:
    """The shape the short-dividend branch used to mishandle."""
    comptime CUTOFF = bigint_arithmetics.CUTOFF_BURNIKEL_ZIEGLER
    for block in [CUTOFF, CUTOFF + 32]:
        var divisor_limbs = 2 * block
        var y = top_limb_half_base(divisor_limbs)
        for extra in [block - 1, block, block + 1, 2 * block]:
            var x = all_ones(divisor_limbs + extra)
            assert_divmod_invariant(
                x,
                y,
                String(divisor_limbs + extra)
                + " over "
                + String(divisor_limbs)
                + " limbs",
            )


def test_a_top_limb_of_exactly_two_to_the_63() raises:
    """Bit 63 set, bit 31 clear: the 32-bit mask missed this and did not pad."""
    comptime CUTOFF = bigint_arithmetics.CUTOFF_BURNIKEL_ZIEGLER
    var k = 2 * CUTOFF
    var y = BigInt("1") << (64 * k - 1)
    var x = (BigInt("1") << (64 * 2 * k - 1)) + (BigInt("1") << 20)
    assert_divmod_invariant(x, y, "top limb 2^63, exact block multiple")


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
