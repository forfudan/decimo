# ===----------------------------------------------------------------------=== #
# Copyright 2025-2026 Yuhao Zhu
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# ===----------------------------------------------------------------------=== #

"""Multiplies decimal magnitudes with a number-theoretic transform.

Toom-3 was the largest algorithm available for `BigUInt`. Its complexity is
O(n^1.465), so a transform of complexity O(n log n) is faster for long enough
operands. This module provides that tier.

The transform is not written again here. `decimo.bigint.ntt` provides the
field arithmetic modulo the Goldilocks prime, the twiddle tables and the two
transforms. Those work on residues and do not depend on the base. Only the
packing is different.

A base-2^64 magnitude is a bit string, so `bigint` may cut it at any bit
position. A decimal magnitude is not. Its value is
`w[0] + w[1] * 10^18 + ...`, and only cuts at a power of ten are cheap.

The question is therefore how many decimal digits one coefficient should hold.
With `d` digits per coefficient, each product is below `10^(2d)`, and at most
`min(len_x, len_y)` of them are summed, so we need

    min(len_x, len_y) * 10^(2d) < P = 2^64 - 2^32 + 1

- `d = 9` (half a word) allows only 18 coefficients. Too few.
- `d = 3` divides a word evenly, but needs six coefficients per word.
- `d = 6` is used here. One word is 18 decimal digits, that is three
  coefficients of six digits. The bound allows about 1.8 * 10^7 coefficients,
  or 10^8 decimal digits.

Six digits are slightly less than 20 bits, while `bigint` usually packs 25
bits. A decimal transform is therefore about 25% longer for the same
number. Converting the base to avoid this would cost more.
"""

from std.memory import unsafe_memset_zero

from decimo.biguint.biguint import BigUInt

# Only for the unreachable guard in `multiply_slices_ntt()`. This is a cycle
# -- `arithmetics` imports this module for its dispatch -- but a compile-time
# one that Mojo resolves, and the alternative is an out-of-bounds write on a
# path that should be impossible rather than merely unlikely.
from decimo.biguint.arithmetics import multiply_slices_toom3
from decimo.bigint.ntt import (
    MAX_TRANSFORM_LOG,
    NTT_PRIME,
    build_twiddles,
    mod_mul,
    transform_forward,
    transform_inverse,
)

# ===----------------------------------------------------------------------=== #
# Cutting words into coefficients
# coefficients_for_words, pack_words, unpack_coefficients
# ===----------------------------------------------------------------------=== #

comptime DIGITS_PER_COEFFICIENT = 6
"""Decimal digits in one transform coefficient."""

comptime COEFFICIENT_BASE: UInt64 = 1_000_000
"""`10^DIGITS_PER_COEFFICIENT`, the base of the convolution."""

comptime COEFFICIENTS_PER_WORD = BigUInt.DIGITS_PER_WORD // DIGITS_PER_COEFFICIENT
"""Three. A word is eighteen digits and a coefficient is six, so a word cuts
into a whole number of coefficients and nothing straddles a word boundary."""


def coefficients_for_words(number_of_words: Int) -> Int:
    """Returns the number of coefficients needed for that many words.

    Args:
        number_of_words: Length of the magnitude in words.

    Returns:
        The number of six-digit coefficients.
    """
    return number_of_words * COEFFICIENTS_PER_WORD


def pack_words[
    o: Origin[mut=True]
](
    coefficients: Pointer[UInt64, o],
    words: ImmSpan[BigUInt.Word, _],
    bounds: Tuple[Int, Int],
):
    """Cuts a slice of words into six-digit coefficients.

    A word is eighteen digits and a coefficient is six, so each word gives
    exactly three and none of them straddles a word:

        c0 = w % 10^6
        c1 = (w / 10^6) % 10^6
        c2 = w / 10^12

    Args:
        coefficients: Destination, zeroed and long enough.
        words: The magnitude that the slice belongs to.
        bounds: Slice bounds (start inclusive, end exclusive).
    """
    comptime COEFFICIENT_BASE_SQUARED = COEFFICIENT_BASE * COEFFICIENT_BASE
    var out = 0
    for i in range(bounds[0], bounds[1]):
        var word = UInt64(words[i])
        coefficients[unsafe_offset=out] = word % COEFFICIENT_BASE
        coefficients[unsafe_offset=out + 1] = (
            word // COEFFICIENT_BASE
        ) % COEFFICIENT_BASE
        coefficients[unsafe_offset=out + 2] = word // COEFFICIENT_BASE_SQUARED
        out += COEFFICIENTS_PER_WORD


def unpack_coefficients(
    coefficients: Pointer[UInt64, _],
    number_of_coefficients: Int,
    number_of_words: Int,
) -> List[BigUInt.Word]:
    """Carries the convolution and writes it back as words.

    The coefficients returned by the transform are sums of products, so they
    are much larger than `10^6` and must be carried first. The words then
    follow from reversing `pack_words()`:

        w = c0 + c1 * 10^6 + c2 * 10^12

    Args:
        coefficients: The convolution.
        number_of_coefficients: How many coefficients carry a value.
        number_of_words: Upper bound on the length of the product.

    Returns:
        The product magnitude, without leading zero words.
    """
    var carried_length = number_of_coefficients + 2
    var carried = List[UInt64](capacity=carried_length)
    carried.resize(unsafe_uninit_length=carried_length)
    var carried_ptr = carried.unsafe_ptr()

    var carry: UInt64 = 0
    for k in range(number_of_coefficients):
        var total = coefficients[unsafe_offset=k] + carry
        carried_ptr[unsafe_offset=k] = total % COEFFICIENT_BASE
        carry = total // COEFFICIENT_BASE
    # The carry left after the last coefficient is always below the base, so
    # the second slot written below is always zero.
    #
    # An individual convolution coefficient can be close to the prime, and
    # therefore an intermediate carry can reach ~10^13. The *final* carry
    # cannot. The product is below `10^(DIGITS_PER_WORD * number_of_words)`,
    # and `6 * number_of_coefficients` is within six digits of that exponent, so
    # what is left after carrying through every coefficient cannot reach
    # `10^6`. The second slot exists only so the reconstruction loop can read
    # `k + 2` without a bounds test.
    debug_assert(
        carry < COEFFICIENT_BASE,
        "biguint.ntt.unpack_coefficients(): final carry does not fit",
    )
    carried_ptr[unsafe_offset=number_of_coefficients] = carry % COEFFICIENT_BASE
    carried_ptr[unsafe_offset=number_of_coefficients + 1] = (
        carry // COEFFICIENT_BASE
    )

    comptime COEFFICIENT_BASE_SQUARED = COEFFICIENT_BASE * COEFFICIENT_BASE
    var words = List[BigUInt.Word](capacity=number_of_words)
    words.resize(unsafe_uninit_length=number_of_words)
    var words_ptr = words.unsafe_ptr()

    var k = 0
    for w in range(number_of_words):
        var c0: UInt64 = 0
        var c1: UInt64 = 0
        var c2: UInt64 = 0
        if k < carried_length:
            c0 = carried_ptr[unsafe_offset=k]
        if k + 1 < carried_length:
            c1 = carried_ptr[unsafe_offset=k + 1]
        if k + 2 < carried_length:
            c2 = carried_ptr[unsafe_offset=k + 2]

        words_ptr[unsafe_offset=w] = BigUInt.Word(
            c0 + c1 * COEFFICIENT_BASE + c2 * COEFFICIENT_BASE_SQUARED
        )
        k += COEFFICIENTS_PER_WORD

    while len(words) > 1 and words[len(words) - 1] == 0:
        words.shrink(len(words) - 1)
    return words^


# ===----------------------------------------------------------------------=== #
# Choosing between the transform and Toom-3
# transform_length_for, should_multiply_ntt
# ===----------------------------------------------------------------------=== #

comptime CUTOFF_NTT = 1024
"""Below this many words in either operand, Toom-3 always wins."""

comptime NTT_RELATIVE_COST: Float64 = 0.313
"""Cost of one butterfly against one Toom-3 word-step. Measured, not guessed.

Re-swept at eighteen digits a word (20260828), because both sides moved and
they did not move together. Toom-3's step count quartered -- half the words in
each operand -- while a step only doubled in price, so Toom-3 gained about 2x.
The transform packs *digits* into coefficients and so gained nothing: a word
now gives three coefficients instead of one and a half, and the transform for
a given number of digits is the length it always was. The crossover moved with
the difference, from 1 024 to 2 048 base-10^9 words to somewhere between 3 052
and 4 072 words here -- 9 000 digits to 55 000.

       wa      wb   toom3 ms   ntt ms   toom/ntt
      509     509      0.050    0.116      0.43
    1 019   1 019      0.149    0.241      0.62
    2 036   2 036      0.486    0.556      0.87
    3 052   3 052      0.913    1.229      0.74
    4 072   4 072      1.585    1.198      1.32   <- transform ahead
    6 106   6 106      2.734    2.575      1.06
    8 140   8 140      4.427    2.564      1.73
    2 486   1 243      0.547    0.549      1.00
    2 982   1 491      0.698    0.563      1.24
    3 973   1 989      1.209    1.254      0.96
    4 970   2 486      1.603    1.193      1.34
    7 949   3 977      2.425    2.704      0.90

The unbalanced rows are there because `a * b` with `b` half of `a` is the
common shape and it is not the same question: fewer coefficients means a
shorter transform, so the crossover sits lower. They are also why the answer
is not monotonic -- 7 949 by 3 977 needs a 65 536-point transform where
4 970 by 2 486 fits in 32 768, and the step costs more than the extra words.

`(0.3068, 0.3186)` reproduces all twelve rows; 0.313 is the middle."""


def transform_length_for(len_x: Int, len_y: Int) -> Tuple[Int, Int]:
    """Returns the transform length and its base-two logarithm.

    Args:
        len_x: Words in the first operand.
        len_y: Words in the second operand.

    Returns:
        The length and its logarithm, or `(0, 0)` if the product would need a
        transform longer than `MAX_TRANSFORM_LOG` allows.
    """
    var needed = (
        coefficients_for_words(len_x) + coefficients_for_words(len_y) - 1
    )
    var log_length = 0
    var length = 1
    while length < needed:
        length <<= 1
        log_length += 1
        if log_length > MAX_TRANSFORM_LOG:
            return (0, 0)
    return (length, log_length)


def should_multiply_ntt(len_x: Int, len_y: Int) -> Bool:
    """Returns True if the transform is expected to beat Toom-3.

    The transform length steps at every power of two while Toom-3 grows
    smoothly, so near the crossover the faster algorithm alternates. The two
    costs are compared directly instead of using a single size cutoff.

    Args:
        len_x: Words in the first operand.
        len_y: Words in the second operand.

    Returns:
        True when the transform is cheaper.
    """
    if len_x < CUTOFF_NTT or len_y < CUTOFF_NTT:
        return False

    var chosen = transform_length_for(len_x, len_y)
    var length = chosen[0]
    if length == 0:
        return False

    # The convolution must stay below the prime. This is the bound given in the
    # module docstring. It is checked, because exceeding it would wrap around
    # and give a wrong product rather than an error.
    #
    # The count is of *coefficients*, not words: a convolution coefficient sums
    # at most `min(coefficients_a, coefficients_b)` products, and a word gives
    # three coefficients. Counting words here would allow operands three times
    # as long as the prime can hold.
    var largest_term = (COEFFICIENT_BASE - 1) * (COEFFICIENT_BASE - 1)
    var terms = min(
        coefficients_for_words(len_x), coefficients_for_words(len_y)
    )
    if UInt64(terms) > NTT_PRIME // largest_term:
        return False

    var transform_cost = (
        Float64(length) * Float64(chosen[1]) * NTT_RELATIVE_COST
    )
    var toom3_cost = (Float64(len_x) * Float64(len_y)) ** 0.7325
    return transform_cost < toom3_cost


# ===----------------------------------------------------------------------=== #
# Multiplication
# multiply_slices_ntt
# ===----------------------------------------------------------------------=== #


def multiply_slices_ntt(
    imm x: BigUInt,
    imm y: BigUInt,
    bounds_x: Tuple[Int, Int],
    bounds_y: Tuple[Int, Int],
) -> BigUInt:
    """Multiplies two BigUInt slices with the transform.

    Both slices must be non-empty. `should_multiply_ntt()` decides whether this
    is the cheaper route and rejects sizes that the transform cannot hold.
    Correctness does not depend on calling it first, only speed does.

    Complexity: O(n log n), against Toom-3's O(n^1.465).

    Args:
        x: The first BigUInt operand.
        y: The second BigUInt operand.
        bounds_x: Slice bounds for x (start inclusive, end exclusive).
        bounds_y: Slice bounds for y (start inclusive, end exclusive).

    Returns:
        The product of the two slices.
    """
    var len_x = bounds_x[1] - bounds_x[0]
    var len_y = bounds_y[1] - bounds_y[0]

    var chosen = transform_length_for(len_x, len_y)
    var length = chosen[0]
    var log_length = chosen[1]
    debug_assert(
        length > 0,
        (
            "biguint.ntt.multiply_slices_ntt(): the product needs a transform"
            " longer than MAX_TRANSFORM_LOG allows"
        ),
    )
    if length == 0:
        # Unreachable through the dispatcher, which rejects these sizes. Guard
        # it anyway: this function is callable directly, and a zero length
        # would send `pack_words()` past the end of an empty buffer.
        return multiply_slices_toom3(x, y, bounds_x, bounds_y)

    var forward_twiddles = List[UInt64]()
    var inverse_twiddles = List[UInt64]()
    build_twiddles(log_length, forward_twiddles, inverse_twiddles)

    var left = List[UInt64](capacity=length)
    left.resize(unsafe_uninit_length=length)
    var right = List[UInt64](capacity=length)
    right.resize(unsafe_uninit_length=length)
    var left_ptr = left.unsafe_ptr()
    var right_ptr = right.unsafe_ptr()

    unsafe_memset_zero(ptr=left_ptr, count=length)
    unsafe_memset_zero(ptr=right_ptr, count=length)
    pack_words(left_ptr, x.words.as_span(), bounds_x)
    pack_words(right_ptr, y.words.as_span(), bounds_y)

    var forward_ptr = forward_twiddles.unsafe_ptr()
    var inverse_ptr = inverse_twiddles.unsafe_ptr()
    transform_forward(left_ptr, length, log_length, forward_ptr)
    transform_forward(right_ptr, length, log_length, forward_ptr)
    for i in range(length):
        left_ptr[unsafe_offset=i] = mod_mul(
            left_ptr[unsafe_offset=i], right_ptr[unsafe_offset=i]
        )
    transform_inverse(left_ptr, length, log_length, inverse_ptr)

    var product = unpack_coefficients(
        left_ptr,
        coefficients_for_words(len_x) + coefficients_for_words(len_y) - 1,
        len_x + len_y,
    )
    return BigUInt(raw_words=product^)
