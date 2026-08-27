"""
Test the number-theoretic transform multiplication: field arithmetic, the
transform round trip, and agreement with the Toom-3 path it replaces.
"""

from std import testing
from decimo.bigint.bigint import BigInt, Magnitude
import decimo.bigint.arithmetics as bigint_arithmetics
import decimo.bigint.ntt as bigint_ntt


# ===----------------------------------------------------------------------=== #
# Helpers
# ===----------------------------------------------------------------------=== #


def _pseudo_random_words(count: Int, seed: UInt64) -> Magnitude:
    """Builds `count` words from a linear congruential generator.

    The top word is forced non-zero so that the operand really is `count`
    words long, which is what the size-dependent dispatch keys on.
    """
    var state = seed | 1
    var words = Magnitude(capacity=count)
    for _ in range(count):
        state = state * 6364136223846793005 + 1442695040888963407
        words.append(state)
    words[count - 1] |= UInt64(1) << 63
    return words^


def _assert_matches_reference(
    len_a: Int, len_b: Int, seed: UInt64, top_bits: Int
) raises:
    """Checks the transform against the schoolbook path on one product.

    The reference is `_multiply_magnitudes_schoolbook()` specifically, and not
    the `multiply()` dispatcher, because `multiply()` now routes large operands
    to the transform itself — comparing against it would compare the transform
    with itself and pass no matter what. Schoolbook is the only multiplication
    in the module that neither recurses nor dispatches, so it stays independent
    however the cutoffs move. It is covered by its own tests and by every
    arithmetic test in the suite.

    It is O(n*m), which at the sizes here costs a few milliseconds. That is the
    price of an independent reference and it is worth paying.

    Args:
        len_a: Word count of the first operand.
        len_b: Word count of the second operand.
        seed: Seed for the operand generator.
        top_bits: When in `1..63`, shortens the first operand's top word to
            this many bits, so that bit lengths are not all multiples of 64.
            The chunk width the planner picks depends on the bit length, not
            the word count.
    """
    var words_a = _pseudo_random_words(len_a, seed)
    var words_b = _pseudo_random_words(len_b, seed ^ 0xFFFF_FFFF_FFFF_FFFF)
    if top_bits > 0 and top_bits < 64:
        words_a[len_a - 1] = UInt64(1) << UInt64(top_bits - 1)

    var expected = bigint_arithmetics._multiply_magnitudes_schoolbook(
        words_a.as_span(), words_b.as_span()
    )
    var actual = bigint_ntt.multiply_magnitudes_ntt(
        words_a.as_span(), words_b.as_span()
    )

    var expected_length = len(expected)
    while expected_length > 1 and expected[expected_length - 1] == 0:
        expected_length -= 1

    var label = " for len_a=" + String(len_a) + ", len_b=" + String(len_b)
    testing.assert_equal(
        len(actual),
        expected_length,
        "transform product has the wrong word count" + label,
    )
    for i in range(expected_length):
        testing.assert_equal(
            actual[i],
            expected[i],
            "transform product differs at word " + String(i) + label,
        )


# ===----------------------------------------------------------------------=== #
# Test: field arithmetic
# ===----------------------------------------------------------------------=== #


def test_ntt_prime_supports_the_transform() raises:
    """`P - 1` is divisible by `2^32`, which is what gives the roots of unity.
    """
    testing.assert_equal(
        bigint_ntt.NTT_PRIME - 1,
        (UInt64(1) << 32) * ((UInt64(1) << 32) - 1),
        "P - 1 should be 2^32 * (2^32 - 1)",
    )


def test_ntt_generator_is_primitive() raises:
    """`7` generates the whole multiplicative group modulo `P`.

    A generator is exactly an element whose order is not a proper divisor of
    `P - 1`, so it suffices to check `7^((P-1)/q) != 1` at every prime `q`
    dividing `P - 1 = 2^32 * 3 * 5 * 17 * 257 * 65537`. Without this the
    transform would still run, but on a root of unity of too small an order,
    and would silently wrap for long inputs.
    """
    var prime_factors = [
        UInt64(2),
        UInt64(3),
        UInt64(5),
        UInt64(17),
        UInt64(257),
        UInt64(65537),
    ]
    var modulus = bigint_ntt.NTT_PRIME
    for i in range(len(prime_factors)):
        var power = bigint_ntt.mod_power(
            UInt64(7), (modulus - 1) // prime_factors[i]
        )
        testing.assert_not_equal(
            power,
            UInt64(1),
            "7 is not a primitive root: order divides (P-1)/"
            + String(prime_factors[i]),
        )
    testing.assert_equal(
        bigint_ntt.mod_power(UInt64(7), modulus - 1),
        UInt64(1),
        "Fermat: 7^(P-1) should be 1",
    )


def test_ntt_modular_multiplication_reduces() raises:
    """Every product lands in `[0, P)` and matches a 128-bit reference."""
    var modulus = bigint_ntt.NTT_PRIME
    var samples = [
        UInt64(0),
        UInt64(1),
        UInt64(2),
        UInt64(0xFFFF_FFFF),
        UInt64(1) << 32,
        UInt64(0xDEAD_BEEF_1234_5678),
        modulus - 1,
        modulus - 2,
    ]
    for i in range(len(samples)):
        for j in range(len(samples)):
            var a = samples[i] % modulus
            var b = samples[j] % modulus
            var expected = UInt64((UInt128(a) * UInt128(b)) % UInt128(modulus))
            var actual = bigint_ntt.mod_mul(a, b)
            testing.assert_equal(
                actual,
                expected,
                "mod_mul is wrong at i=" + String(i) + ", j=" + String(j),
            )


# ===----------------------------------------------------------------------=== #
# Test: the planner
# ===----------------------------------------------------------------------=== #


def test_ntt_plan_never_overflows_the_modulus() raises:
    """The planned chunk width keeps every convolution coefficient below `P`.

    This is the one bound that cannot be caught by spot-checking products: a
    plan that is one bit too wide only wraps on operands whose chunks happen to
    be near the top of their range, which random tests miss most of the time.
    Checking the bound itself covers every operand at that size.
    """
    var word_counts = [
        1,
        2,
        7,
        63,
        64,
        255,
        1000,
        1024,
        4096,
        10400,
        65536,
        104200,
        1000000,
    ]
    for i in range(len(word_counts)):
        var bits = word_counts[i] * 64
        var plan = bigint_ntt._plan(bits, bits)
        var terms = UInt128(min(plan.coefficients_a, plan.coefficients_b))
        var chunk_max = UInt128((UInt64(1) << UInt64(plan.chunk_bits)) - 1)
        testing.assert_true(
            terms * chunk_max * chunk_max < UInt128(bigint_ntt.NTT_PRIME),
            "plan overflows the modulus at "
            + String(word_counts[i])
            + " words",
        )
        testing.assert_true(
            plan.coefficients_a + plan.coefficients_b - 1 <= plan.length,
            "transform is too short at " + String(word_counts[i]) + " words",
        )
        testing.assert_true(
            plan.chunk_bits * plan.coefficients_a >= bits,
            "chunks do not cover the operand at "
            + String(word_counts[i])
            + " words",
        )


def test_ntt_dispatch_prefers_toom3_when_small() raises:
    """The transform is never chosen where Toom-3 is known to be faster."""
    testing.assert_false(
        bigint_ntt.should_multiply_ntt(1, 1), "1 word should not use the NTT"
    )
    testing.assert_false(
        bigint_ntt.should_multiply_ntt(768, 768),
        "the Toom-3 cutoff should not use the NTT",
    )
    testing.assert_false(
        bigint_ntt.should_multiply_ntt(2048, 2048),
        "2048 words should not use the NTT",
    )
    testing.assert_true(
        bigint_ntt.should_multiply_ntt(65536, 65536),
        "65536 words should use the NTT",
    )


# ===----------------------------------------------------------------------=== #
# Test: products
# ===----------------------------------------------------------------------=== #


def test_ntt_matches_reference_on_small_sizes() raises:
    """Every word-count pair up to 24 x 24, so no edge case hides in a corner.

    Small operands never reach the transform through the dispatcher, but they
    exercise the shortest transforms, where an off-by-one in the level indexing
    or the twiddle offsets shows up immediately.
    """
    for len_a in range(1, 25):
        for len_b in range(1, 25):
            _assert_matches_reference(
                len_a, len_b, UInt64(len_a * 1000 + len_b), (len_a * 7) % 33
            )


def test_ntt_matches_reference_around_power_of_two_boundaries() raises:
    """Sizes that straddle a transform-length step and a chunk-width change.

    The planner's choice changes discontinuously at these sizes, so a product
    just below and just above each one exercises both branches.
    """
    var word_counts = [
        63,
        64,
        65,
        255,
        256,
        257,
        511,
        512,
        513,
        1023,
        1024,
        1025,
        2047,
        2048,
        2049,
        4095,
        4096,
        4097,
    ]
    for i in range(len(word_counts)):
        _assert_matches_reference(
            word_counts[i], word_counts[i], UInt64(i * 977 + 1), (i * 5) % 33
        )


def test_ntt_matches_reference_on_unbalanced_operands() raises:
    """One long operand against a short one, in both orders."""
    var pairs_long = [4096, 3000, 1024, 5000]
    var pairs_short = [3, 64, 999, 1]
    for i in range(len(pairs_long)):
        _assert_matches_reference(
            pairs_long[i], pairs_short[i], UInt64(i * 13 + 7), (i * 11) % 33
        )
        _assert_matches_reference(
            pairs_short[i], pairs_long[i], UInt64(i * 13 + 7), (i * 11) % 33
        )


def test_ntt_matches_reference_on_extreme_words() raises:
    """All-ones and single-bit operands, where the chunk bound is tightest.

    Random words average half the chunk range; all-ones operands sit at the top
    of it, which is where a chunk width one bit too wide would wrap.
    """

    def _all_ones(count: Int) -> Magnitude:
        var words = Magnitude(capacity=count)
        for _ in range(count):
            words.append(~UInt64(0))
        return words^

    var word_counts = [1, 2, 17, 64, 1024, 2048, 4096]
    for i in range(len(word_counts)):
        var count = word_counts[i]
        var ones = _all_ones(count)
        var expected = bigint_arithmetics._multiply_magnitudes_schoolbook(
            ones.as_span(), ones.as_span()
        )
        var actual = bigint_ntt.multiply_magnitudes_ntt(
            ones.as_span(), ones.as_span()
        )
        var expected_length = len(expected)
        while expected_length > 1 and expected[expected_length - 1] == 0:
            expected_length -= 1
        testing.assert_equal(
            len(actual),
            expected_length,
            "all-ones square has the wrong length at "
            + String(count)
            + " words",
        )
        for k in range(expected_length):
            testing.assert_equal(
                actual[k],
                expected[k],
                "all-ones square differs at word "
                + String(k)
                + " of "
                + String(count),
            )


def test_ntt_matches_reference_above_the_dispatch_cutoff() raises:
    """Sizes the dispatcher actually routes through the transform.

    The assertion on `should_multiply_ntt()` is the point of the test rather
    than a precondition: without it, a later change to the cutoffs could move
    these sizes back onto Toom-3 and leave the whole file testing a path that
    production never takes, silently and with everything still green.
    """
    var word_counts = [5000, 8192, 10400]
    for i in range(len(word_counts)):
        var count = word_counts[i]
        testing.assert_true(
            bigint_ntt.should_multiply_ntt(count, count),
            "the dispatcher no longer routes "
            + String(count)
            + " words through the transform, so this test covers nothing",
        )
        _assert_matches_reference(
            count, count, UInt64(i * 6151 + 3), (i * 9 + 1) % 33
        )


def test_ntt_product_round_trips_through_division() raises:
    """`(a * b) / b == a` for operands routed through the transform.

    An independent check on the transform that does not lean on the Toom-3
    path at all: division is implemented by a different algorithm entirely, so
    a shared bug would have to be present in both.
    """
    var words_a = _pseudo_random_words(6000, 0xABCD_1234_5678_9ABC)
    var words_b = _pseudo_random_words(5000, 0x1357_9BDF_2468_ACE0)
    var a = BigInt(raw_words=words_a^, sign=False)
    var b = BigInt(raw_words=words_b^, sign=False)

    var product = bigint_arithmetics.multiply(a, b)
    var quotient = bigint_arithmetics.truncate_divide(product, b)
    testing.assert_equal(String(quotient), String(a), "(a * b) / b should be a")


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
