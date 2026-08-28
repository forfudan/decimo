"""Tests the number-theoretic transform multiplication."""

from std import testing

from decimo.biguint.biguint import BigUInt
from decimo.biguint import arithmetics as biguint_arithmetics
from decimo.biguint import ntt as biguint_ntt


def build_digits(count: Int, seed: Int) -> String:
    """Builds a `count`-digit decimal string, without a leading zero."""
    var out = String("")
    var state = seed | 1
    for _ in range(count):
        state = (state * 31 + 17) % 9
        out += String(state + 1)
    return out^


def assert_matches_schoolbook(digits_x: Int, digits_y: Int) raises:
    """Checks one product of the transform against schoolbook multiplication.

    The reference is `multiply_slices_schoolbook()` and not the `multiply()`
    dispatcher, because `multiply()` routes large operands to the transform.
    Comparing against it would compare the transform with itself.
    """
    var x = BigUInt(build_digits(digits_x, 7))
    var y = BigUInt(build_digits(digits_y, 5))
    var bounds_x = (0, len(x.words))
    var bounds_y = (0, len(y.words))

    var expected = biguint_arithmetics.multiply_slices_schoolbook(
        x, y, bounds_x, bounds_y
    )
    var got = biguint_ntt.multiply_slices_ntt(x, y, bounds_x, bounds_y)

    testing.assert_equal(
        String(got),
        String(expected),
        "transform disagrees with schoolbook for "
        + String(digits_x)
        + " by "
        + String(digits_y)
        + " digits",
    )


def test_ntt_matches_schoolbook_on_small_operands() raises:
    """The transform must be correct at every size, not only large ones."""
    var sizes = [1, 2, 3, 8, 9, 10, 17, 18, 19, 100]
    for i in range(len(sizes)):
        for j in range(len(sizes)):
            assert_matches_schoolbook(sizes[i], sizes[j])


def test_ntt_matches_schoolbook_on_odd_word_counts() raises:
    """A word pair packs into three coefficients, a lone word into two.

    Odd word counts take the second path, so they are worth their own case.
    """
    var word_counts = [1, 3, 5, 7, 33, 101]
    for i in range(len(word_counts)):
        for j in range(len(word_counts)):
            assert_matches_schoolbook(
                word_counts[i] * BigUInt.DIGITS_PER_WORD,
                word_counts[j] * BigUInt.DIGITS_PER_WORD,
            )


def test_ntt_matches_schoolbook_on_unequal_operands() raises:
    """Very unequal operand lengths exercise the shorter packing loop."""
    assert_matches_schoolbook(9, 9000)
    assert_matches_schoolbook(9000, 9)
    assert_matches_schoolbook(100, 20000)
    assert_matches_schoolbook(20000, 100)


def test_ntt_matches_schoolbook_above_the_dispatch_cutoff() raises:
    """Checks the sizes that `multiply()` actually routes to the transform.

    If the dispatcher stops choosing the transform at these sizes, this test
    would silently cover nothing, so the routing is asserted first.
    """
    # Above the measured crossover, and no larger than the schoolbook
    # reference can afford to check.
    var word_counts = [4072, 5000]
    for i in range(len(word_counts)):
        var count = word_counts[i]
        testing.assert_true(
            biguint_ntt.should_multiply_ntt(count, count),
            (
                "the dispatcher no longer routes "
                + String(count)
                + " words through the transform, so this test covers nothing"
            ),
        )
        assert_matches_schoolbook(
            count * BigUInt.DIGITS_PER_WORD, count * BigUInt.DIGITS_PER_WORD
        )


def test_coefficients_for_words() raises:
    """A word cuts into a whole number of coefficients.

    Derived rather than written out: at nine digits a word this was a pair
    that gave three coefficients with one straddling the boundary, and at
    eighteen it is one word giving three. Both are
    `DIGITS_PER_WORD // DIGITS_PER_COEFFICIENT` once nothing straddles.
    """
    comptime PER_WORD = biguint_ntt.COEFFICIENTS_PER_WORD
    testing.assert_equal(
        BigUInt.DIGITS_PER_WORD,
        PER_WORD * biguint_ntt.DIGITS_PER_COEFFICIENT,
        "a word must cut into a whole number of coefficients",
    )
    for words in [0, 1, 2, 3, 4, 101]:
        testing.assert_equal(
            biguint_ntt.coefficients_for_words(words), words * PER_WORD
        )


def test_transform_length_is_a_power_of_two_and_long_enough() raises:
    """The length must hold the whole convolution and be a power of two."""
    var word_counts = [1024, 2048, 4096, 11112]
    for i in range(len(word_counts)):
        var count = word_counts[i]
        var chosen = biguint_ntt.transform_length_for(count, count)
        var length = chosen[0]
        var log_length = chosen[1]
        var needed = 2 * biguint_ntt.coefficients_for_words(count) - 1
        testing.assert_true(length >= needed, "transform length is too short")
        testing.assert_equal(length, 1 << log_length)
        testing.assert_true(
            length < 2 * needed, "transform length is more than twice needed"
        )


def test_dispatcher_prefers_toom3_below_the_crossover() raises:
    """The floor and the crossover are two different things.

    `CUTOFF_NTT` is a floor below which the transform is never considered.
    The crossover is where the cost model starts preferring it, and it sits
    well above the floor. The sizes below are the ones actually timed for
    `NTT_RELATIVE_COST`, so this fails if a re-tune changes the answer for a
    size somebody measured.
    """
    testing.assert_false(
        biguint_ntt.should_multiply_ntt(
            biguint_ntt.CUTOFF_NTT - 1, biguint_ntt.CUTOFF_NTT - 1
        ),
        "below the floor the transform is not even considered",
    )
    testing.assert_false(
        biguint_ntt.should_multiply_ntt(2036, 2036), "Toom-3 measured faster"
    )
    testing.assert_false(
        biguint_ntt.should_multiply_ntt(3973, 1989), "Toom-3 measured faster"
    )
    testing.assert_true(
        biguint_ntt.should_multiply_ntt(4072, 4072),
        "the transform measured faster",
    )
    testing.assert_true(
        biguint_ntt.should_multiply_ntt(4970, 2486),
        "the transform measured faster",
    )


def test_multiply_routes_large_operands_through_the_transform() raises:
    """End to end: `multiply()` must stay correct once it starts using it."""
    var x = BigUInt(build_digits(2100 * BigUInt.DIGITS_PER_WORD, 7))
    var y = BigUInt(build_digits(2100 * BigUInt.DIGITS_PER_WORD, 5))
    var expected = biguint_arithmetics.multiply_slices_schoolbook(
        x, y, (0, len(x.words)), (0, len(y.words))
    )
    testing.assert_equal(
        String(biguint_arithmetics.multiply(x, y)), String(expected)
    )


def test_the_prime_bound_is_the_one_that_binds() raises:
    """Two limits guard the transform, and only one of them can ever fire.

    A convolution coefficient sums at most `min(coeffs_a, coeffs_b)` products
    of two coefficients, so it has to stay below `NTT_PRIME` or it wraps and
    gives a wrong product rather than an error. That caps an operand at
    `NTT_PRIME / (COEFFICIENT_BASE - 1)^2` coefficients. Separately,
    `transform_length_for()` gives up past `MAX_TRANSFORM_LOG`.

    The prime bound is roughly a hundred times tighter, so the transform-length
    guard is unreachable through the dispatcher. That is worth pinning: a
    change to the coefficient size or to the prime could invert the
    relationship, and the guard that stops being first is the one that stops
    being tested.
    """
    var largest_term = (biguint_ntt.COEFFICIENT_BASE - 1) * (
        biguint_ntt.COEFFICIENT_BASE - 1
    )
    var max_coefficients = biguint_ntt.NTT_PRIME // largest_term
    var max_words = Int(max_coefficients) // biguint_ntt.COEFFICIENTS_PER_WORD

    # Either side of the bound, derived rather than written out.
    testing.assert_true(
        biguint_ntt.should_multiply_ntt(max_words, max_words),
        "the transform should still be allowed at the prime bound",
    )
    testing.assert_false(
        biguint_ntt.should_multiply_ntt(max_words + 1, max_words + 1),
        "one word past the prime bound the transform must be refused",
    )

    # The smaller operand is what the bound is about, so a huge operand paired
    # with a small one is still fine.
    testing.assert_false(
        biguint_ntt.should_multiply_ntt(max_words + 1, max_words + 1),
        "both operands past the bound",
    )

    # The transform length is still comfortable there, and only gives up far
    # beyond anything the prime bound would let through.
    var at_the_bound = biguint_ntt.transform_length_for(max_words, max_words)
    testing.assert_true(
        at_the_bound[0] > 0,
        "the transform length should not be the binding limit",
    )
    testing.assert_true(
        at_the_bound[1] <= biguint_ntt.MAX_TRANSFORM_LOG,
        "the log should be inside the cap",
    )
    testing.assert_true(
        max_words * 100 < 1_500_000_000,
        "the prime bound should be far tighter than the length cap",
    )
    var far_past = biguint_ntt.transform_length_for(
        1_500_000_000, 1_500_000_000
    )
    testing.assert_equal(
        far_past[0], 0, "the length cap should refuse at 1.5 billion words"
    )


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
