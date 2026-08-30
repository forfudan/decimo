"""
Sweeps Burnikel-Ziegler division over the operand shapes its recursion
handles specially.

The existing tests pin named cases against CPython, and the schoolbook and
Burnikel-Ziegler paths against each other, on operands of hundreds to
thousands of words. What the recursion has that the schoolbook does not is a
set of shape decisions -- how the divisor is padded to the block grid, how the
dividend is cut into blocks, when a short dividend takes one three-by-two
division instead of two -- and none of the named cases sat on those seams.

One of them was wrong. `two_by_one` sent any dividend of three parts or fewer,
or of four parts with a zero top, to a single `three_by_two` at half the block
size. A `2n`-by-`n` quotient can be `n` words; `three_by_two(n/2)` gives
`n/2`. So a dividend below `b * B^n` but not below `b * B^(n/2)` -- which is
what the second block of every multi-block division looks like, the previous
remainder shifted up and joined to the next block -- came back a word too
wide from the inner recursion, the two-step correction could not bring it
down, and `r -= d` raised. All nines, 48 words over a 32-word divisor whose
top word is `BASE_HALF`, at `BURNIKEL_ZIEGLER_BLOCK_WORDS = 16`. 33 and 64
over 32 were fine, which is why nothing had ever hit it. `BigInt`'s copy of
the algorithm had the same branch and returned a wrong quotient rather than
raising.

The oracle needs nothing external: `q * y + r == x` and `0 <= r < y`, with the
multiply and the comparison well covered elsewhere. The shapes are chosen so
the block count of the divisor, the number of dividend blocks and the size of
the top block each take every residue that matters, and the digit patterns
are the two that push the estimate hardest -- all nines, and a one followed
by zeros with a one at the bottom.
"""

from std import testing
from std.testing import assert_true

from decimo.biguint import arithmetics as biguint_arithmetics
from decimo.biguint.biguint import BigUInt


def repeated(digit: String, count: Int) -> String:
    var out = String("")
    for _ in range(count):
        out += digit
    return out^


def one_zeros_one(count: Int) -> String:
    """`1 000...0 1` with `count` digits in total, at least two."""
    return "1" + repeated("0", count - 2) + "1"


def assert_divmod_invariant(x: BigUInt, y: BigUInt, context: String) raises:
    var remainder = BigUInt()
    var quotient = biguint_arithmetics.floor_divide_modulo(x, y, remainder)
    assert_true(remainder < y, context + ": remainder is not below the divisor")
    var back = quotient * y + remainder
    assert_true(back == x, context + ": q * y + r != x")
    # And the quotient-only entry agrees with the tuple form.
    assert_true(
        biguint_arithmetics.floor_divide(x, y) == quotient,
        context + ": floor_divide disagrees with floor_divide_modulo",
    )


def test_every_residue_of_the_block_size() raises:
    """Divisor word counts around each multiple of the block size.

    The divisor is padded up to a multiple of `BURNIKEL_ZIEGLER_BLOCK_WORDS`,
    so the count just below a multiple, at it, and just above are the three
    that exercise different amounts of padding.
    """
    comptime BLOCK = biguint_arithmetics.BURNIKEL_ZIEGLER_BLOCK_WORDS
    comptime DIGITS = BigUInt.DIGITS_PER_WORD
    for multiple in [2, 3, 4]:
        for offset in [-1, 0, 1]:
            var divisor_words = multiple * BLOCK + offset
            for dividend_extra in [1, BLOCK - 1, BLOCK, BLOCK + 1, 2 * BLOCK]:
                var dividend_words = divisor_words + dividend_extra
                var y = BigUInt(repeated("9", divisor_words * DIGITS))
                var x = BigUInt(repeated("9", dividend_words * DIGITS))
                assert_divmod_invariant(
                    x,
                    y,
                    "nines, "
                    + String(dividend_words)
                    + " over "
                    + String(divisor_words)
                    + " words",
                )
                var y2 = BigUInt(one_zeros_one(divisor_words * DIGITS))
                var x2 = BigUInt(one_zeros_one(dividend_words * DIGITS))
                assert_divmod_invariant(
                    x2,
                    y2,
                    "1..01, "
                    + String(dividend_words)
                    + " over "
                    + String(divisor_words)
                    + " words",
                )


def test_a_short_top_block_and_a_one_word_quotient() raises:
    """The dividend's top block need not be full, and the quotient can be one.
    """
    comptime BLOCK = biguint_arithmetics.BURNIKEL_ZIEGLER_BLOCK_WORDS
    comptime DIGITS = BigUInt.DIGITS_PER_WORD
    var divisor_words = 3 * BLOCK
    var y = BigUInt(repeated("9", divisor_words * DIGITS))
    # Dividends from just over the divisor to a few digits into the next word.
    for extra_digits in [1, 2, DIGITS - 1, DIGITS, DIGITS + 1, 2 * DIGITS]:
        var x = BigUInt(repeated("9", divisor_words * DIGITS + extra_digits))
        assert_divmod_invariant(
            x, y, "short top block, " + String(extra_digits) + " extra digits"
        )
    # x == y, x == y + 1, x == 2y - 1: quotients of exactly 1, 1 and 1.
    assert_divmod_invariant(y, y, "x == y")
    assert_divmod_invariant(y + BigUInt.one(), y, "x == y + 1")
    var twice_less_one = y + y - BigUInt.one()
    assert_divmod_invariant(twice_less_one, y, "x == 2y - 1")
    assert_divmod_invariant(y + y, y, "x == 2y")


def test_a_dividend_of_exactly_three_parts() raises:
    """The shape that took the wrong branch, and its neighbours.

    A divisor whose top word is `BASE_HALF` -- the smallest a normalised
    divisor can be -- against a dividend of all nines makes every inner
    quotient as large as it can be. At `divisor + BLOCK` words the second
    block is exactly three parts wide and used to be sent to a single
    `three_by_two`; one word either side it was not, and passed.
    """
    comptime BLOCK = biguint_arithmetics.BURNIKEL_ZIEGLER_BLOCK_WORDS
    comptime DIGITS = BigUInt.DIGITS_PER_WORD
    var half = String(BigUInt.BASE_HALF)
    for divisor_words in [2 * BLOCK, 2 * BLOCK + 1, 3 * BLOCK - 1]:
        # top word exactly BASE_HALF, then nines
        var y = BigUInt(half + repeated("9", (divisor_words - 1) * DIGITS))
        for dividend_words in [
            divisor_words + 1,
            divisor_words + BLOCK,
            2 * divisor_words,
        ]:
            var x = BigUInt(repeated("9", dividend_words * DIGITS))
            assert_divmod_invariant(
                x,
                y,
                "half-word divisor, "
                + String(dividend_words)
                + " over "
                + String(divisor_words),
            )


def test_just_either_side_of_the_cutoff() raises:
    """The hand-off to the schoolbook, at the word count that decides it."""
    comptime CUTOFF = biguint_arithmetics.CUTOFF_BURNIKEL_ZIEGLER
    comptime DIGITS = BigUInt.DIGITS_PER_WORD
    for divisor_words in [CUTOFF - 1, CUTOFF, CUTOFF + 1]:
        var y = BigUInt(repeated("9", divisor_words * DIGITS))
        for dividend_words in [divisor_words + 1, 2 * divisor_words + 3]:
            var x = BigUInt(one_zeros_one(dividend_words * DIGITS))
            assert_divmod_invariant(
                x,
                y,
                "cutoff, "
                + String(dividend_words)
                + " over "
                + String(divisor_words),
            )


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
