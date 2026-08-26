"""Tests the base-billion number-theoretic transform multiplication."""

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
            assert_matches_schoolbook(word_counts[i] * 9, word_counts[j] * 9)


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
    var word_counts = [2048, 4096, 5000]
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
        assert_matches_schoolbook(count * 9, count * 9)


def test_coefficients_for_words() raises:
    """Two words give three coefficients, a lone word gives two."""
    testing.assert_equal(biguint_ntt.coefficients_for_words(0), 0)
    testing.assert_equal(biguint_ntt.coefficients_for_words(1), 2)
    testing.assert_equal(biguint_ntt.coefficients_for_words(2), 3)
    testing.assert_equal(biguint_ntt.coefficients_for_words(3), 5)
    testing.assert_equal(biguint_ntt.coefficients_for_words(4), 6)
    testing.assert_equal(biguint_ntt.coefficients_for_words(101), 152)


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
    """The measured crossover sits between 1024 and 2048 words."""
    testing.assert_false(biguint_ntt.should_multiply_ntt(512, 512))
    testing.assert_false(biguint_ntt.should_multiply_ntt(1024, 1024))
    testing.assert_true(biguint_ntt.should_multiply_ntt(2048, 2048))


def test_multiply_routes_large_operands_through_the_transform() raises:
    """End to end: `multiply()` must stay correct once it starts using it."""
    var x = BigUInt(build_digits(2100 * 9, 7))
    var y = BigUInt(build_digits(2100 * 9, 5))
    var expected = biguint_arithmetics.multiply_slices_schoolbook(
        x, y, (0, len(x.words)), (0, len(y.words))
    )
    testing.assert_equal(
        String(biguint_arithmetics.multiply(x, y)), String(expected)
    )


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
