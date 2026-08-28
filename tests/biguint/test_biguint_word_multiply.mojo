"""
Test `multiply_by_word_inplace()` across its two paths.

`y` of 0, 1 or 2 short-circuits into `multiply_by_word_le_2_inplace()`, which
multiplies a vector of words at a time and normalises the carries afterwards;
everything else goes through the general 128-bit loop. The split is invisible
from outside, so the sweep below crosses it without caring where it is.

Neither path had a test. The vectorised one is the more interesting of the
two: it depends on a doubled word staying inside the word type, which is a
property of the base, and on `VECTOR_WIDTH` dividing the work correctly for
word counts that are not a multiple of it.
"""

from std import testing
from std.testing import assert_equal

from decimo.biguint.biguint import BigUInt
import decimo.biguint.arithmetics as biguint_arithmetics


def _repeat(text: String, times: Int) -> String:
    var out = String("")
    for _ in range(times):
        out += text
    return out^


def test_multiply_by_word_small_multipliers_every_word_count() raises:
    """`y` from 0 to 6, over word counts that straddle `VECTOR_WIDTH`.

    Word counts one through nine cover a partial vector, an exact vector and
    a vector plus a remainder, whichever width is configured.
    """
    for words in range(1, 10):
        # A value with `words` full words, every digit a nine, which is the
        # worst case for carries.
        var text = _repeat("9", words * BigUInt.DIGITS_PER_WORD)
        for y in range(0, 7):
            var value = BigUInt(text)
            biguint_arithmetics.multiply_by_word_inplace(value, BigUInt.Word(y))
            value.assert_invariant("multiply_by_word_inplace")

            var expected = BigUInt(text)
            var accumulator = BigUInt("0")
            for _ in range(y):
                accumulator = accumulator + expected
            assert_equal(
                String(value),
                String(accumulator),
                "multiply_by_word_inplace(9... x "
                + String(words)
                + " words, "
                + String(y)
                + ")",
            )


def test_multiply_by_word_carries_across_the_word_boundary() raises:
    """Doubling a word that sits just below the base must carry, not wrap."""
    var boundary = String(BigUInt.BASE_MAX)  # one word, all nines

    for y in [0, 1, 2]:
        var value = BigUInt(boundary)
        biguint_arithmetics.multiply_by_word_inplace(value, BigUInt.Word(y))
        var expected = String(BigUInt("0"))
        if y == 1:
            expected = boundary
        elif y == 2:
            expected = String(BigUInt(boundary) + BigUInt(boundary))
        assert_equal(
            String(value), expected, "boundary word times " + String(y)
        )
        value.assert_invariant("boundary")


def test_multiply_by_word_large_multipliers() raises:
    """The general path, with `y` up to the largest a word can hold."""
    var text = _repeat("1234567890", 12)
    for y in [
        3,
        4,
        5,
        10,
        999,
        1_000_000_007,
        BigUInt.BASE_MAX,
        BigUInt.BASE_MAX - 1,
    ]:
        var value = BigUInt(text)
        biguint_arithmetics.multiply_by_word_inplace(value, BigUInt.Word(y))
        value.assert_invariant("multiply_by_word_inplace, large y")

        # Check against repeated addition for the small ones, and against
        # `BigUInt * BigUInt` for the rest.
        var expected = BigUInt(text) * BigUInt(String(y))
        assert_equal(String(value), String(expected), "times " + String(y))


def test_multiply_by_word_zero_and_one_are_exact() raises:
    """Zero collapses to a canonical zero; one leaves the value untouched."""
    for words in range(1, 6):
        var text = _repeat("7", words * BigUInt.DIGITS_PER_WORD)

        var zeroed = BigUInt(text)
        biguint_arithmetics.multiply_by_word_inplace(zeroed, BigUInt.Word(0))
        assert_equal(String(zeroed), "0")
        assert_equal(len(zeroed.words), 1, "zero must be a single word")
        zeroed.assert_invariant("times zero")

        var same = BigUInt(text)
        biguint_arithmetics.multiply_by_word_inplace(same, BigUInt.Word(1))
        assert_equal(String(same), text)


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
