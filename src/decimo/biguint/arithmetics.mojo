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

"""
Implements basic arithmetic functions for the BigUInt type.
"""

from std.algorithm import vectorize
from std import math
from std.memory import unsafe_memcpy, unsafe_memset_zero

from decimo.biguint.biguint import BigUInt, WORD_DTYPE, Coefficient
from decimo.wordlist import WordList
import decimo.biguint.comparison as biguint_comparison
from decimo.errors import (
    OverflowError,
    ValueError,
    ZeroDivisionError,
)
from decimo.rounding_mode import RoundingMode
import decimo.biguint.ntt as biguint_ntt
from decimo.utility import alias_as_immutable_source

comptime CUTOFF_KARATSUBA = 128
"""The cutoff number of words for using Karatsuba multiplication.

Raised from 64 when the schoolbook base case became product-scanning. A Comba
column reduces the base once per result word instead of once per partial
product, which makes the quadratic kernel fast enough that Karatsuba's extra
`BigUInt` allocations and additions do not pay until much later.

Re-swept after the move to eighteen digits a word (20260828) and left where
the base change put it: 128 is best or tied against 64 and 256 at every size
from 32 to 1024 words.
"""
comptime CUTOFF_TOOM3 = 512
"""The cutoff number of words for using Toom-3 multiplication.

NOTE: Karatsuba is used for `CUTOFF_KARATSUBA < max_words <= CUTOFF_TOOM3`.

Swept at eighteen digits a word (20260828), three runs each, ns:

| words | 384 | 512 |
| ----- | --- | --- |
|   512 | 47.0 k | 45.8 k |
|  1 024 | 140.1 k | 139.6 k |
|  1 536 | 291.4 k | 269.1 k |
|  2 048 | 469.6 k | 446.0 k |

Neutral to a thousand words and 1.05-1.08x above it. Worth noting that 512 is
neither the base-10^9 value (768) nor half of it (384, where the base change
put it): unlike the vector widths, this one really did move, and not by the
factor anyone would have guessed. Sweep, do not scale.
"""
comptime CUTOFF_BURNIKEL_ZIEGLER = 24
"""The cutoff number of words for using Burnikel-Ziegler division.

Schoolbook is used outright when the divisor has at most this many words
*and* the dividend has at most twice as many; a longer dividend goes to
Burnikel-Ziegler whatever the divisor's width. So this is not the same number
as the block size below, and it is not a divisor-width cutoff on its own.

Raised from 32 on 20260826, after the Knuth D multiply-subtract step was taken
off its carry chain. A 2.9x faster schoolbook stays ahead of the recursion for
longer. Measured on the 2n-by-n shape the condition selects, best of nine:

| divisor words | schoolbook | best Burnikel-Ziegler |
| ------------- | ---------- | --------------------- |
| 32            | 1972 ns    | 2662 ns               |
| 48            | 3920 ns    | 4537 ns               |
| 64            | 6515 ns    | 6480 ns               |

64 is where they meet, so the crossover sits just below it.

Re-swept at eighteen digits a word (20260828) over 16, 24, 32, 48 and 64,
with dividends from 16 to 1024 words and a divisor half that. No value beats
another by more than about 2.5%, and the direction is not consistent across
sizes: an apparent advantage for 48 at 512 and 1024 words did not survive a
second run. Left alone. Recorded so the next person does not repeat it.
"""
comptime BURNIKEL_ZIEGLER_BLOCK_WORDS = 16
"""The block size the Burnikel-Ziegler recursion bottoms out at.

Once the recursion reaches a divisor of at most this many words it calls
schoolbook, so this sets the size of the base case rather than deciding
whether the algorithm runs at all.

Retuned twice on 20260826, and the second time undid the first. Vectorizing
the word kernels made the base case cheaper, which favoured a smaller one, and
32 went to 24. Then taking the multiply-subtract off its carry chain made the
base case cheaper again -- and that favoured a *larger* one, because what the
base case now costs is closer to what the recursion's own bookkeeping costs.
Back to 32:

| divisor words | at 24     | at 32     | at 48     |
| ------------- | --------- | --------- | --------- |
| 112           | 15648 ns  | 13059 ns  | 13255 ns  |
| 224           | 37998 ns  | 32644 ns  | 32742 ns  |
| 448           | 99662 ns  | 88127 ns  | 88516 ns  |
| 1112          | 341317 ns | 341121 ns | 325803 ns |

48 is 4.5% better at 1112 words and within 1.5% everywhere else, so it is the
other defensible choice; 32 is picked because the 1000-digit case, which is
the 112-word row, is the one being tuned for.
"""
# ===----------------------------------------------------------------------=== #
# List of functions in this module:
#
# negative(x: BigUInt) -> BigUInt
# absolute(x: BigUInt) -> BigUInt
#
# add(x1: BigUInt, x2: BigUInt) -> BigUInt
# add_slices_carry_select(x: BigUInt, y: BigUInt) -> BigUInt
# add_slices(x: BigUInt, y: BigUInt, start_x: Int, end_x: Int, start_y: Int, end_y: Int) -> BigUInt
# add_inplace(x1: BigUInt, x2: BigUInt)
# add_by_word_inplace(x: BigUInt, y: BigUInt.Word) -> None
#
# subtract(x1: BigUInt, x2: BigUInt) -> BigUInt
# subtract_carry_select(x1: BigUInt, x2: BigUInt) -> BigUInt
# subtract_inplace(x1: BigUInt, x2: BigUInt) -> None
# subtract_no_check_inplace(x1: BigUInt, x2: BigUInt) -> None
# subtract_by_word_inplace(x: BigUInt, y: BigUInt.Word) -> None
#
# multiply(x1: BigUInt, x2: BigUInt) -> BigUInt
# multiply_slices_schoolbook(x: BigUInt, y: BigUInt, start_x: Int, end_x: Int, start_y: Int, end_y: Int) -> BigUInt
# multiply_slices_karatsuba(x: BigUInt, y: BigUInt, start_x: Int, end_x: Int, start_y: Int, end_y: Int, cutoff_number_of_words: Int) -> BigUInt
# multiply_slices_toom3(x: BigUInt, y: BigUInt, bounds_x: Tuple[Int, Int], bounds_y: Tuple[Int, Int]) -> BigUInt
# multiply_by_word_inplace(x: BigUInt, y: BigUInt.Word) -> None
# multiply_by_power_of_ten(x: BigUInt, n: Int) -> BigUInt
# multiply_by_power_of_base_inplace(mut x: BigUInt, n: Int)
# exact_divide_by_2_inplace(mut x: BigUInt)
# exact_divide_by_3_inplace(mut x: BigUInt)
#
# floor_divide(x1: BigUInt, x2: BigUInt) -> BigUInt
# floor_divide_schoolbook(x1: BigUInt, x2: BigUInt) -> BigUInt
# floor_divide_estimate_quotient(x1: BigUInt, x2: BigUInt, j: Int, m: Int) -> UInt64
# floor_divide_by_word_inplace(mut x: BigUInt, y: BigUInt.Word) -> None
# floor_divide_by_uint64_inplace(mut x: BigUInt, y: UInt64) -> None
# floor_divide_by_2_inplace(x: BigUInt) -> None
# floor_divide_by_power_of_ten(x: BigUInt, n: Int) -> BigUInt
# floor_divide_by_power_of_ten_inplace(x: BigUInt, n: Int) -> None
# floor_divide_by_power_of_base(x: BigUInt, n: Int) -> BigUInt
# floor_divide_by_power_of_base_inplace(x: BigUInt, n: Int) -> None
#
# truncate_divide(x1: BigUInt, x2: BigUInt) -> BigUInt
# ceil_divide(x1: BigUInt, x2: BigUInt) -> BigUInt
#
# floor_modulo(x1: BigUInt, x2: BigUInt) -> BigUInt
# floor_modulo_by_power_of_ten(x: BigUInt, n: Int) -> BigUInt
# ceil_modulo(x1: BigUInt, x2: BigUInt) -> BigUInt
# floor_divide_modulo(x1: BigUInt, x2: BigUInt) -> Tuple[BigUInt, BigUInt]
# floor_divide_modulo(x: BigUInt, y: BigUInt, mut remainder: BigUInt) -> BigUInt
# floor_divide_modulo_schoolbook(x, y, mut remainder: BigUInt) -> BigUInt
# floor_divide_modulo_burnikel_ziegler(a, b, cut_off, mut remainder) -> BigUInt
# floor_divide_modulo_by_word(x, y: BigUInt.Word, mut remainder: BigUInt.Word) -> BigUInt
# floor_divide_modulo_by_uint64(x, y: UInt64, mut remainder: UInt64) -> BigUInt
#
# normalize_carries_lt_2_bases(x: BigUInt) -> None
# normalize_carries_lt4_bases(x: BigUInt) -> None
# power_of_10(n: Int) -> BigUInt
# ===----------------------------------------------------------------------=== #

# ===----------------------------------------------------------------------=== #
# Unary operations
# negative, absolute
# ===----------------------------------------------------------------------=== #


# ===----------------------------------------------------------------------=== #
# Word-level addition and subtraction kernels
#
# A decimal word does not carry by overflowing, so the carry out of a word
# cannot be read off the hardware flags the way a base-2^64 one can: it is a
# comparison against `BASE`, and the comparison depends on the carry coming in.
# Written directly, that puts a compare on the loop-carried dependency chain.
#
# Short runs use the carry-select trick: both answers — the one for carry-in 0
# and the one for carry-in 1 — are computed from the operands alone, off the
# critical path, and the incoming carry only picks between them. What remains
# loop-carried is a select, so the chain is roughly one cycle per word rather
# than the three or four an add-compare-branch chain costs.
#
# From one vector's worth of words up, a two-pass shape wins instead: add the
# words in vectors with no carries at all, then walk the carries. Two words
# sum to less than `2 * BASE`, which is well inside the word type, so the
# vector pass cannot overflow, and the
# reduction is a comparison and a masked subtract. The walk that follows stays
# a single pass, because a word that generated a carry came out at `BASE - 2`
# or below and cannot generate a second one when it takes the carry beneath it.
# Only a word sitting exactly at `BASE - 1` can, and that word did not
# generate.
#
# The two passes run a block at a time rather than over the whole operand, and
# that is what makes this beat the carry-select chain. An earlier whole-operand
# version of the same idea lost, because it walked the words twice through
# memory; a block stays in L1, so the carry walk reads what the vector pass has
# just written, and the generate flags live in a stack buffer instead of a heap
# allocation. Measured on an M4 Pro: 2.1x faster from 100 words up, 1.6x at 16,
# break-even at 8, and slower below that, which is why the short path stays.
# ===----------------------------------------------------------------------=== #

# One 256-bit vector of words, and the run length that the two-pass kernels
# chew through between carry walks. Both halved with the word count when the
# base moved, to keep the same number of *bytes* per vector and per block.
# Provisional: they want re-sweeping, like every other cutoff here.
comptime WORDS_PER_VECTOR = 8
comptime WORDS_PER_CARRY_BLOCK = 64

comptime WORDS_PER_SHORT_DIVISOR = 4
"""Below this many divisor words, Knuth D's multiply-subtract stays in one
pass. See `_multiply_subtract_words`."""


@always_inline
def _add_words[
    o: Origin[mut=True],
    o_a: Origin[mut=False],
    o_b: Origin[mut=False],
](
    rp: Pointer[BigUInt.Word, o],
    ap: Pointer[BigUInt.Word, o_a],
    bp: Pointer[BigUInt.Word, o_b],
    n_words: Int,
    carry_in: BigUInt.Word,
) -> BigUInt.Word:
    """Adds `n_words` words: `r = a + b`, least significant first.

    `r` may alias `a` or `b` word-for-word.

    Args:
        rp: Destination, at least `n_words` words.
        ap: First summand, at least `n_words` words.
        bp: Second summand, at least `n_words` words.
        n_words: Number of words to add.
        carry_in: Carry into the lowest word, 0 or 1.

    Returns:
        The carry out of the highest word, 0 or 1.
    """
    if n_words < WORDS_PER_VECTOR:
        return _add_words_carry_select(rp, ap, bp, n_words, carry_in)
    return _add_words_vectorized(rp, ap, bp, n_words, carry_in)


def _add_words_vectorized[
    o: Origin[mut=True],
    o_a: Origin[mut=False],
    o_b: Origin[mut=False],
](
    rp: Pointer[BigUInt.Word, o],
    ap: Pointer[BigUInt.Word, o_a],
    bp: Pointer[BigUInt.Word, o_b],
    n_words: Int,
    carry_in: BigUInt.Word,
) -> BigUInt.Word:
    """The long-run path of `_add_words()`. Not inlined on purpose.

    It carries a block-sized stack buffer, and inlining that into the callers
    made them set the frame up on every call, including the short ones that
    never reach here. That cost the one-word add 17%.

    Args:
        rp: Destination, at least `n_words` words.
        ap: First summand, at least `n_words` words.
        bp: Second summand, at least `n_words` words.
        n_words: Number of words to add, at least `WORDS_PER_VECTOR`.
        carry_in: Carry into the lowest word, 0 or 1.

    Returns:
        The carry out of the highest word, 0 or 1.
    """
    var generated = InlineArray[BigUInt.Word, WORDS_PER_CARRY_BLOCK](
        uninitialized=True
    )
    var gp = generated.unsafe_ptr()
    var zeros = SIMD[WORD_DTYPE, WORDS_PER_VECTOR](0)
    var ones = SIMD[WORD_DTYPE, WORDS_PER_VECTOR](1)
    var bases = SIMD[WORD_DTYPE, WORDS_PER_VECTOR](BigUInt.BASE)

    var carry = carry_in
    var start = 0
    while start < n_words:
        var end = min(start + WORDS_PER_CARRY_BLOCK, n_words)

        var i = start
        while i + WORDS_PER_VECTOR <= end:
            var sums = (
                ap.unsafe_offset(i).unsafe_load[width=WORDS_PER_VECTOR]()
                + bp.unsafe_offset(i).unsafe_load[width=WORDS_PER_VECTOR]()
            )
            var carried = sums.ge(bases)
            rp.unsafe_offset(i).unsafe_store(carried.select(sums - bases, sums))
            gp.unsafe_offset(i - start).unsafe_store(
                carried.select(ones, zeros)
            )
            i += WORDS_PER_VECTOR
        while i < end:
            var sum = ap[unsafe_offset=i] + bp[unsafe_offset=i]
            var carried = BigUInt.Word(sum >= BigUInt.BASE)
            rp[unsafe_offset=i] = sum - BigUInt.BASE if carried != 0 else sum
            gp[unsafe_offset=i - start] = carried
            i += 1

        for j in range(start, end):
            var word = rp[unsafe_offset=j] + carry
            if word >= BigUInt.BASE:
                rp[unsafe_offset=j] = word - BigUInt.BASE
                carry = 1
            else:
                rp[unsafe_offset=j] = word
                carry = gp[unsafe_offset=j - start]

        start = end

    return carry


@always_inline
def _add_words_carry_select[
    o: Origin[mut=True],
    o_a: Origin[mut=False],
    o_b: Origin[mut=False],
](
    rp: Pointer[BigUInt.Word, o],
    ap: Pointer[BigUInt.Word, o_a],
    bp: Pointer[BigUInt.Word, o_b],
    n_words: Int,
    carry_in: BigUInt.Word,
) -> BigUInt.Word:
    """Adds `n_words` words with the carry off the critical path.

    The short-run path of `_add_words()`, and the reference implementation for
    it: same arguments, same result, no vectors.

    Args:
        rp: Destination, at least `n_words` words.
        ap: First summand, at least `n_words` words.
        bp: Second summand, at least `n_words` words.
        n_words: Number of words to add.
        carry_in: Carry into the lowest word, 0 or 1.

    Returns:
        The carry out of the highest word, 0 or 1.
    """
    var carry = carry_in
    for i in range(n_words):
        var raw = ap[unsafe_offset=i] + bp[unsafe_offset=i]
        var carry_if_0 = BigUInt.Word(raw >= BigUInt.BASE)
        var carry_if_1 = BigUInt.Word(raw >= BigUInt.BASE_MAX)
        var word_if_0 = raw - BigUInt.BASE if carry_if_0 != 0 else raw
        var word_if_1 = raw + 1 - BigUInt.BASE if carry_if_1 != 0 else raw + 1
        rp[unsafe_offset=i] = word_if_1 if carry != 0 else word_if_0
        carry = carry_if_1 if carry != 0 else carry_if_0
    return carry


@always_inline
def _subtract_words[
    o: Origin[mut=True],
    o_a: Origin[mut=False],
    o_b: Origin[mut=False],
](
    rp: Pointer[BigUInt.Word, o],
    ap: Pointer[BigUInt.Word, o_a],
    bp: Pointer[BigUInt.Word, o_b],
    n_words: Int,
    borrow_in: BigUInt.Word,
) -> BigUInt.Word:
    """Subtracts `n_words` words: `r = a - b`, least significant first.

    The borrow counterpart of `_add_words()`, with the same aliasing freedom
    and the same two shapes. The wrapped `a - b` is deliberate: it is the right
    answer modulo 2^32 once `BASE` is added back.

    Args:
        rp: Destination, at least `n_words` words.
        ap: Minuend, at least `n_words` words.
        bp: Subtrahend, at least `n_words` words.
        n_words: Number of words to subtract.
        borrow_in: Borrow into the lowest word, 0 or 1.

    Returns:
        The borrow out of the highest word, 0 or 1.
    """
    if n_words < WORDS_PER_VECTOR:
        return _subtract_words_borrow_select(rp, ap, bp, n_words, borrow_in)
    return _subtract_words_vectorized(rp, ap, bp, n_words, borrow_in)


def _subtract_words_vectorized[
    o: Origin[mut=True],
    o_a: Origin[mut=False],
    o_b: Origin[mut=False],
](
    rp: Pointer[BigUInt.Word, o],
    ap: Pointer[BigUInt.Word, o_a],
    bp: Pointer[BigUInt.Word, o_b],
    n_words: Int,
    borrow_in: BigUInt.Word,
) -> BigUInt.Word:
    """The long-run path of `_subtract_words()`. Not inlined, for the reason
    given on `_add_words_vectorized()`.

    Args:
        rp: Destination, at least `n_words` words.
        ap: Minuend, at least `n_words` words.
        bp: Subtrahend, at least `n_words` words.
        n_words: Number of words to subtract, at least `WORDS_PER_VECTOR`.
        borrow_in: Borrow into the lowest word, 0 or 1.

    Returns:
        The borrow out of the highest word, 0 or 1.
    """
    var borrowed_flags = InlineArray[BigUInt.Word, WORDS_PER_CARRY_BLOCK](
        uninitialized=True
    )
    var gp = borrowed_flags.unsafe_ptr()
    var zeros = SIMD[WORD_DTYPE, WORDS_PER_VECTOR](0)
    var ones = SIMD[WORD_DTYPE, WORDS_PER_VECTOR](1)
    var bases = SIMD[WORD_DTYPE, WORDS_PER_VECTOR](BigUInt.BASE)

    var borrow = borrow_in
    var start = 0
    while start < n_words:
        var end = min(start + WORDS_PER_CARRY_BLOCK, n_words)

        var i = start
        while i + WORDS_PER_VECTOR <= end:
            var minuends = ap.unsafe_offset(i).unsafe_load[
                width=WORDS_PER_VECTOR
            ]()
            var subtrahends = bp.unsafe_offset(i).unsafe_load[
                width=WORDS_PER_VECTOR
            ]()
            var differences = minuends - subtrahends
            var borrowed = minuends.lt(subtrahends)
            rp.unsafe_offset(i).unsafe_store(
                borrowed.select(differences + bases, differences)
            )
            gp.unsafe_offset(i - start).unsafe_store(
                borrowed.select(ones, zeros)
            )
            i += WORDS_PER_VECTOR
        while i < end:
            var minuend = ap[unsafe_offset=i]
            var subtrahend = bp[unsafe_offset=i]
            var difference = minuend - subtrahend
            var borrowed = BigUInt.Word(minuend < subtrahend)
            rp[unsafe_offset=i] = (
                difference + BigUInt.BASE if borrowed != 0 else difference
            )
            gp[unsafe_offset=i - start] = borrowed
            i += 1

        # A word that borrowed came out at 1 or above, so taking the borrow
        # beneath it cannot make it borrow again. Only a word left at zero can.
        for j in range(start, end):
            var word = rp[unsafe_offset=j]
            if borrow != 0:
                if word == 0:
                    rp[unsafe_offset=j] = BigUInt.BASE_MAX
                    borrow = 1
                    continue
                word -= 1
            rp[unsafe_offset=j] = word
            borrow = gp[unsafe_offset=j - start]

        start = end

    return borrow


@always_inline
def _subtract_words_borrow_select[
    o: Origin[mut=True],
    o_a: Origin[mut=False],
    o_b: Origin[mut=False],
](
    rp: Pointer[BigUInt.Word, o],
    ap: Pointer[BigUInt.Word, o_a],
    bp: Pointer[BigUInt.Word, o_b],
    n_words: Int,
    borrow_in: BigUInt.Word,
) -> BigUInt.Word:
    """Subtracts `n_words` words with the borrow off the critical path.

    The short-run path of `_subtract_words()`, and the reference
    implementation for it.

    Args:
        rp: Destination, at least `n_words` words.
        ap: Minuend, at least `n_words` words.
        bp: Subtrahend, at least `n_words` words.
        n_words: Number of words to subtract.
        borrow_in: Borrow into the lowest word, 0 or 1.

    Returns:
        The borrow out of the highest word, 0 or 1.
    """
    var borrow = borrow_in
    for i in range(n_words):
        var minuend = ap[unsafe_offset=i]
        var subtrahend = bp[unsafe_offset=i]
        var raw = minuend - subtrahend
        var borrow_if_0 = BigUInt.Word(minuend < subtrahend)
        var borrow_if_1 = BigUInt.Word(minuend <= subtrahend)
        var word_if_0 = raw + BigUInt.BASE if borrow_if_0 != 0 else raw
        var word_if_1 = raw - 1 + BigUInt.BASE if borrow_if_1 != 0 else raw - 1
        rp[unsafe_offset=i] = word_if_1 if borrow != 0 else word_if_0
        borrow = borrow_if_1 if borrow != 0 else borrow_if_0
    return borrow


def _multiply_subtract_words[
    o: Origin[mut=True],
    o_y: Origin[mut=False],
](
    rp: Pointer[BigUInt.Word, o],
    yp: Pointer[BigUInt.Word, o_y],
    n_words: Int,
    quotient: BigUInt.Word,
) -> BigUInt.Word:
    """`r[0..n) -= quotient * y[0..n)`, returning what to take off `r[n]`.

    The multiply-subtract step of Knuth D, and the whole of its inner cost.

    Written the obvious way, `product = quotient * y[i] + carry` puts the
    division by `BASE` on the loop-carried chain: carry feeds the product, the
    product feeds the division, the division feeds the next carry, about nine
    cycles a word. But `quotient * y[i]` does not actually depend on the
    carry. Computing all of those first, with their splits, lets them
    pipeline, and leaves only a combine-and-subtract walk running serially --
    two chains, both an add and a compare deep.

    A partial product is below `BASE^2`, which needs 128 bits, but the divide
    that splits it is by a *constant* and the compiler expands that into a
    multiply-high rather than calling a helper. The subtraction stays in one
    word: `r[i] + BASE` is below `2 * BASE`, which a word holds.

    Worth 2.1x at 112 words and 2.3x at 224, which is where the schoolbook
    base case of Burnikel-Ziegler sits.

    Args:
        rp: The running remainder window, `n_words` words.
        yp: The divisor, `n_words` words.
        n_words: Number of words in the divisor.
        quotient: The estimated quotient word, below `BASE`.

    Returns:
        The amount to subtract from the word above the window.
    """
    comptime BASE_WORD = BigUInt.Word(BigUInt.BASE)
    comptime BASE_WIDE = UInt128(BigUInt.BASE)
    var quotient_wide = UInt128(quotient)

    # A short divisor takes the obvious single pass. The two-pass form below
    # buys latency with two blocks of stack, and at four or eight words the
    # stack costs more than the carry chain does: a 28-digit division is a
    # four-word divisor, and it spent most of its time setting up buffers it
    # used four slots of.
    if n_words <= WORDS_PER_SHORT_DIVISOR:
        var short_pending = BigUInt.Word(0)
        var short_borrow = BigUInt.Word(0)
        for i in range(n_words):
            var product = quotient_wide * UInt128(yp[unsafe_offset=i])
            var high = BigUInt.Word(product // BASE_WIDE)
            var digit = (
                BigUInt.Word(product - UInt128(high) * BASE_WIDE)
                + short_pending
            )
            short_pending = high
            if digit >= BASE_WORD:
                digit -= BASE_WORD
                short_pending += 1
            var biased = rp[unsafe_offset=i] + BASE_WORD - digit - short_borrow
            short_borrow = BigUInt.Word(biased < BASE_WORD)
            rp[unsafe_offset=i] = biased - BASE_WORD + short_borrow * BASE_WORD
        return short_pending + short_borrow

    var highs = InlineArray[BigUInt.Word, WORDS_PER_CARRY_BLOCK](
        uninitialized=True
    )
    var lows = InlineArray[BigUInt.Word, WORDS_PER_CARRY_BLOCK](
        uninitialized=True
    )
    var hp = highs.unsafe_ptr()
    var lp = lows.unsafe_ptr()

    var pending_high = BigUInt.Word(0)
    var borrow = BigUInt.Word(0)
    var start = 0
    while start < n_words:
        var end = min(start + WORDS_PER_CARRY_BLOCK, n_words)

        # Independent of the carry, so these pipeline.
        for i in range(start, end):
            var product = quotient_wide * UInt128(yp[unsafe_offset=i])
            var high = product // BASE_WIDE
            hp[unsafe_offset=i - start] = BigUInt.Word(high)
            lp[unsafe_offset=i - start] = BigUInt.Word(
                product - high * BASE_WIDE
            )

        # The serial part: carry the product's high word into the next digit,
        # then take that digit out of the running remainder.
        for i in range(start, end):
            var digit = lp[unsafe_offset=i - start] + pending_high
            pending_high = hp[unsafe_offset=i - start]
            if digit >= BASE_WORD:
                digit -= BASE_WORD
                pending_high += 1
            var biased = rp[unsafe_offset=i] + BASE_WORD - digit - borrow
            borrow = BigUInt.Word(biased < BASE_WORD)
            rp[unsafe_offset=i] = biased - BASE_WORD + borrow * BASE_WORD

        start = end

    return pending_high + borrow


@always_inline
def _carry_into_tail[
    o: Origin[mut=True], o_a: Origin[mut=False]
](
    rp: Pointer[BigUInt.Word, o],
    ap: Pointer[BigUInt.Word, o_a],
    start: Int,
    end: Int,
    carry_in: BigUInt.Word,
) -> BigUInt.Word:
    """Copies `a[start:end]` into `r`, absorbing a carry on the way.

    The carry dies at the first word below `BASE_MAX`, so the loop usually runs
    once; the untouched remainder is a single memory copy. `r` may alias `a`,
    in which case the copy is elided.

    Args:
        rp: Destination, at least `end` words.
        ap: Source, at least `end` words.
        start: First word to process.
        end: One past the last word to process.
        carry_in: Carry into word `start`, 0 or 1.

    Returns:
        The carry out of word `end - 1`, 0 or 1.
    """
    var carry = carry_in
    var i = start
    while carry != 0 and i < end:
        var raw = ap[unsafe_offset=i] + carry
        carry = BigUInt.Word(raw >= BigUInt.BASE)
        rp[unsafe_offset=i] = raw - BigUInt.BASE if carry != 0 else raw
        i += 1
    if i < end and rp.unsafe_offset(i) != ap.unsafe_offset(i):
        unsafe_memcpy(
            dest=rp.unsafe_offset(i), src=ap.unsafe_offset(i), count=end - i
        )
    return carry


@always_inline
def _borrow_into_tail[
    o: Origin[mut=True], o_a: Origin[mut=False]
](
    rp: Pointer[BigUInt.Word, o],
    ap: Pointer[BigUInt.Word, o_a],
    start: Int,
    end: Int,
    borrow_in: BigUInt.Word,
) -> BigUInt.Word:
    """Copies `a[start:end]` into `r`, absorbing a borrow on the way.

    The borrow counterpart of `_carry_into_tail()`.

    Args:
        rp: Destination, at least `end` words.
        ap: Source, at least `end` words.
        start: First word to process.
        end: One past the last word to process.
        borrow_in: Borrow into word `start`, 0 or 1.

    Returns:
        The borrow out of word `end - 1`, 0 or 1.
    """
    var borrow = borrow_in
    var i = start
    while borrow != 0 and i < end:
        var minuend = ap[unsafe_offset=i]
        borrow = BigUInt.Word(minuend == 0)
        rp[unsafe_offset=i] = BigUInt.BASE_MAX if borrow != 0 else minuend - 1
        i += 1
    if i < end and rp.unsafe_offset(i) != ap.unsafe_offset(i):
        unsafe_memcpy(
            dest=rp.unsafe_offset(i), src=ap.unsafe_offset(i), count=end - i
        )
    return borrow


def negative(x: BigUInt) raises -> BigUInt:
    """Returns the negative of a BigUInt number if it is zero.

    Args:
        x: The BigUInt value to compute the negative of.

    Raises:
        OverflowError: If the number is non-zero.

    Returns:
        A new BigUInt containing the negative of x.
    """
    if not x.is_zero():
        debug_assert[assert_mode="none"](
            len(x.words) == 1, "negative(): leading zero words"
        )
        raise OverflowError(
            function="negative()",
            message="Negative of non-zero unsigned integer is undefined",
        )
    return BigUInt.zero()  # Return zero


def absolute(x: BigUInt) -> BigUInt:
    """Returns the absolute value of a BigUInt number.

    Args:
        x: The BigUInt value to compute the absolute value of.

    Returns:
        A new BigUInt containing the absolute value of x.
    """
    return x.copy()


# ===----------------------------------------------------------------------=== #
# Addition algorithms
# add, add_inplace, add_by_word_inplace
# ===----------------------------------------------------------------------=== #


def add(x: BigUInt, y: BigUInt) -> BigUInt:
    """Returns the sum of two unsigned integers.

    Args:
        x: The first unsigned integer operand.
        y: The second unsigned integer operand.

    Returns:
        The sum of the two unsigned integers.

    Notes:

    This function will consider the special cases first, and then call
    `add_slices_carry_select()` to handle the addition of the two numbers.
    """
    debug_assert[assert_mode="none"](
        len(x.words) != 0, "BigUInt is uninitialized!"
    )
    debug_assert[assert_mode="none"](
        len(y.words) != 0, "BigUInt is uninitialized!"
    )

    # Short circuit cases
    if x.is_zero():
        debug_assert[assert_mode="none"](
            len(x.words) == 1, "add(): leading zero words"
        )
        return y.copy()
    if y.is_zero():
        debug_assert[assert_mode="none"](
            len(y.words) == 1, "add(): leading zero words"
        )
        return x.copy()

    if len(x.words) == 1:
        if len(y.words) == 1:
            # If both numbers are single-word, we can handle them with UInt32
            return BigUInt.from_unsigned_integral_scalar(
                x.words[0] + y.words[0]
            )
        else:  # If x is single-word, we can handle it with UInt32
            var result = y.copy()
            add_by_word_inplace(result, x.words[0])
            return result^

    if len(y.words) == 1:
        # If y is single-word, we can handle it with UInt32
        var result = x.copy()
        add_by_word_inplace(result, y.words[0])
        return result^

    # Two words are `10^36`, so the sum needs 128 bits where it used to need
    # 64. Still worth a shortcut: the general path allocates and walks.
    if len(x.words) <= 2 and len(y.words) <= 2:
        return BigUInt.from_unsigned_integral_scalar(
            x.to_uint128_with_first_2_words()
            + y.to_uint128_with_first_2_words()
        )

    # Normal cases
    # Yuhao ZHU:
    # Use SIMD operations for addition if both numbers are large enough.
    # This will first add the words in parallel, and then handle the carries.
    # Although you use an extra loop to normalize the carries, this is still
    # faster than the school method for large numbers, as the normalized carries
    # can be simplified to addition and subtraction instead of floor division
    # and modulo operations.
    # This speeds up the addition by 2x-4x for large numbers.
    return add_slices_carry_select(x, y, (0, len(x.words)), (0, len(y.words)))


def add_slices(
    x: BigUInt, y: BigUInt, bounds_x: Tuple[Int, Int], bounds_y: Tuple[Int, Int]
) -> BigUInt:
    """Adds two BigUInt slices using the school method.

    Args:
        x: The first BigUInt operand (first summand).
        y: The second BigUInt operand (second summand).
        bounds_x: A tuple containing the start and end indices of the slice in x.
        bounds_y: A tuple containing the start and end indices of the slice in y.

    Returns:
        A new BigUInt containing the sum of the two slices.

    Notes:

    This function will consider the special cases first, and then call
    `add_slices_carry_select()` to handle the addition of the two slices.
    """

    var n_words_x_slice = bounds_x[1] - bounds_x[0]
    var n_words_y_slice = bounds_y[1] - bounds_y[0]

    # Short circuit cases
    if n_words_x_slice == 1:
        if x.words[bounds_x[0]] == 0:
            # x slice is zero, return y slice
            return BigUInt.from_slice(y, bounds_y)
        elif n_words_y_slice == 1:
            # If both numbers are single-word, we can handle them with BigUInt.Word
            return BigUInt.from_unsigned_integral_scalar(
                x.words[bounds_x[0]] + y.words[bounds_y[0]]
            )
        else:
            # If y slice is longer
            var result = BigUInt.from_slice(y, bounds_y)
            add_by_word_inplace(result, x.words[bounds_x[0]])
            return result^
    if n_words_y_slice == 1:
        if y.words[bounds_y[0]] == 0:
            return BigUInt.from_slice(x, bounds_x)
        else:
            # If x slice is longer
            var result = BigUInt.from_slice(x, bounds_x)
            add_by_word_inplace(result, y.words[bounds_y[0]])
            return result^

    # Normal cases
    # Use SIMD operations for addition if both numbers are large enough.
    return add_slices_carry_select(x, y, bounds_x, bounds_y)


def add_slices_carry_select(
    x: BigUInt, y: BigUInt, bounds_x: Tuple[Int, Int], bounds_y: Tuple[Int, Int]
) -> BigUInt:
    """Adds two BigUInt slices in a single carry-select pass.

    Args:
        x: The first BigUInt operand (first summand).
        y: The second BigUInt operand (second summand).
        bounds_x: A tuple containing the start and end indices of the slice in x.
        bounds_y: A tuple containing the start and end indices of the slice in y.

    Returns:
        A new BigUInt containing the sum of the two slices.

    Notes:

    **Special cases are not handled here**. Please handle them in the caller.

    Working on the slices in place, through the indices, is what keeps this off
    the copy path: neither operand is materialised. See the kernel comment
    above `_add_words()` for why the loops are shaped the way they are.
    """

    var n_words_x_slice = bounds_x[1] - bounds_x[0]
    var n_words_y_slice = bounds_y[1] - bounds_y[0]
    var n_words_longer = max(n_words_x_slice, n_words_y_slice)
    var n_words_shorter = min(n_words_x_slice, n_words_y_slice)

    # One allocation sized for the possible carry word, not an exact-length
    # allocation followed by a `reserve()` that has to move it.
    var result = BigUInt(
        unsafe_uninit_length=n_words_longer,
        unsafe_uninit_capacity=n_words_longer + 1,
    )

    var xp = x.words.unsafe_ptr().unsafe_offset(bounds_x[0])
    var yp = y.words.unsafe_ptr().unsafe_offset(bounds_y[0])
    var rp = result.words.unsafe_ptr()

    var carry = _add_words(rp, xp, yp, n_words_shorter, BigUInt.Word(0))
    var longer = xp if n_words_x_slice > n_words_y_slice else yp
    carry = _carry_into_tail(rp, longer, n_words_shorter, n_words_longer, carry)
    if carry != 0:
        result.words.append(BigUInt.Word(1))

    result.remove_leading_empty_words()
    return result^


def add_inplace(mut x: BigUInt, y: BigUInt) -> None:
    """Increments a BigUInt number by another BigUInt number in place.

    Args:
        x: The first unsigned integer operand.
        y: The second unsigned integer operand.

    Notes:

    A single carry-select pass over the words of `y`, then the carry alone
    through whatever of `x` extends past it.
    """

    # Short circuit cases
    if x.is_zero():
        debug_assert[assert_mode="none"](
            len(x.words) == 1, "add_inplace(): leading zero words"
        )
        x.words = y.words.copy()  # Copy the words from y
        return
    if y.is_zero():
        debug_assert[assert_mode="none"](
            len(y.words) == 1, "add_inplace(): leading zero words"
        )
        return

    if len(y.words) == 1:
        add_by_word_inplace(x, y.words[0])
        return

    # Normal cases
    if len(x.words) < len(y.words):
        x.words.resize(length=len(y.words), fill=BigUInt.Word(0))

    var xp = x.words.unsafe_ptr()
    var carry = _add_words(
        xp,
        alias_as_immutable_source(xp),
        y.words.unsafe_ptr(),
        len(y.words),
        BigUInt.Word(0),
    )
    carry = _carry_into_tail(
        xp, alias_as_immutable_source(xp), len(y.words), len(x.words), carry
    )
    if carry != 0:
        x.words.append(BigUInt.Word(1))

    x.remove_leading_empty_words()

    return


def add_by_slice_inplace(
    mut x: BigUInt, y: BigUInt, bounds_y: Tuple[Int, Int]
) -> None:
    """Increments a BigUInt number in-place by another BigUInt slice.

    Args:
        x: The first unsigned integer operand.
        y: The second unsigned integer operand.
        bounds_y: A tuple containing the start and end indices of the slice in y.
    """

    # Short circuit cases
    if x.is_zero():
        debug_assert[assert_mode="none"](
            len(x.words) == 1, "add_by_slice_inplace(): leading zero words in x"
        )
        x = BigUInt.from_slice(
            y, bounds=(bounds_y[0], bounds_y[1])
        )  # Copy the words from y
        return
    if y.is_zero_in_bounds(bounds=bounds_y):
        # y slice is zero, which means that all the words in the slice are zero
        return

    var n_words_y_slice = bounds_y[1] - bounds_y[0]

    if n_words_y_slice == 1:
        add_by_word_inplace(x, y.words[bounds_y[0]])
        return

    # Normal cases
    if len(x.words) < n_words_y_slice:
        x.words.resize(length=n_words_y_slice, fill=BigUInt.Word(0))

    var xp = x.words.unsafe_ptr()
    var carry = _add_words(
        xp,
        alias_as_immutable_source(xp),
        y.words.unsafe_ptr().unsafe_offset(bounds_y[0]),
        n_words_y_slice,
        BigUInt.Word(0),
    )
    carry = _carry_into_tail(
        xp, alias_as_immutable_source(xp), n_words_y_slice, len(x.words), carry
    )
    if carry != 0:
        x.words.append(BigUInt.Word(1))

    return


def add_by_word_inplace(mut x: BigUInt, y: BigUInt.Word) -> None:
    """Increments a BigUInt number by a BigUInt.Word value.

    Args:
        x: The `BigUInt` number to increment.
        y: The `BigUInt.Word` value to add.
    """
    var carry: BigUInt.Word = y
    for i in range(len(x.words)):
        x.words[i] += carry
        if x.words[i] <= BigUInt.BASE_MAX:
            return  # No carry, we can stop early
        else:
            carry = 1  # Cannot be more than 1
            x.words[i] -= BigUInt.BASE
    else:
        x.words.append(BigUInt.Word(1))

    return


# ===----------------------------------------------------------------------=== #
# Subtraction algorithms
# ===----------------------------------------------------------------------=== #


def subtract(x: BigUInt, y: BigUInt) raises -> BigUInt:
    """Returns the difference of two unsigned integers.

    Args:
        x: The first unsigned integer (minuend).
        y: The second unsigned integer (subtrahend).

    Raises:
        OverflowError: If x < y (result would be negative).

    Returns:
        The result of subtracting y from x.
    """
    # A single borrow-select pass. The school method below is kept for
    # reference; it is the same algorithm with the borrow on the critical path.
    return subtract_carry_select(x, y)

    # Yuhao ZHU:
    # Below is a school method for subtraction.
    # You go from the least significant word to the most significant word.
    #
    # return subtract_schoolbook(x, y)


def subtract_schoolbook(x: BigUInt, y: BigUInt) raises -> BigUInt:
    """Returns the difference of two unsigned integers using the school method.

    Args:
        x: The first unsigned integer (minuend).
        y: The second unsigned integer (subtrahend).

    Raises:
        OverflowError: If y is greater than x.

    Returns:
        The result of subtracting y from x.
    """
    debug_assert[assert_mode="none"](
        len(x.words) != 0, "BigUInt is uninitialized!"
    )
    debug_assert[assert_mode="none"](
        len(y.words) != 0, "BigUInt is uninitialized!"
    )

    # If the subtrahend is zero, return the minuend
    if y.is_zero():
        debug_assert[assert_mode="none"](
            len(y.words) == 1, "subtract_schoolbook(): leading zero words"
        )
        return x.copy()

    # We need to determine which number has the larger magnitude
    var comparison_result = x.compare(y)
    if comparison_result == 0:
        # |x| = |y|
        return BigUInt.zero()  # Return zero
    if comparison_result < 0:
        raise OverflowError(
            function="subtract_schoolbook()",
            message=(
                "biguint.arithmetics.subtract(): Result is negative due to"
                " x < y"
            ),
        )

    # Now it is safe to subtract the smaller number from the larger one
    # The result will have no more words than the first number
    var result = BigUInt(uninitialized_capacity=len(x.words))
    var borrow: BigUInt.Word = 0  # Can either be 0 or 1

    for i in range(len(y.words)):
        if x.words[i] < borrow + y.words[i]:
            result.words.append(x.words[i] + BigUInt.BASE - borrow - y.words[i])
            borrow = 1  # Set borrow for the next word
        else:
            result.words.append(x.words[i] - borrow - y.words[i])
            borrow = 0  # No borrow for the next word

    # If x has more words than y, we need to handle the remaining words

    if borrow == 0:
        # If there is no borrow, we can just copy the remaining words
        for i in range(len(y.words), len(x.words)):
            result.words.append(x.words[i])

    else:
        var no_borrow_idx: Int = 0
        # At this stage, borrow can only be 0 or 1
        for i in range(len(y.words), len(x.words)):
            if x.words[i] >= borrow:
                result.words.append(x.words[i] - borrow)
                no_borrow_idx = i + 1
                break  # No more borrow, we can stop early
            else:  # x.words[i] == 0, borrow == 1
                result.words.append(BigUInt.BASE - borrow)

        for i in range(no_borrow_idx, len(x.words)):
            result.words.append(x.words[i])  # Copy the remaining words

    result.remove_leading_empty_words()
    return result^


def subtract_carry_select(x: BigUInt, y: BigUInt) raises -> BigUInt:
    """Returns the difference of two unsigned integers, borrow-select.

    Args:
        x: The first unsigned integer (minuend).
        y: The second unsigned integer (subtrahend).

    Raises:
        OverflowError: If y is greater than x.

    Returns:
        The result of subtracting y from x.

    Notes:

    One pass over the words of `y`, then the borrow alone through the rest of
    `x`. See the kernel comment above `_add_words()`.
    """
    debug_assert[assert_mode="none"](
        len(x.words) != 0, "BigUInt is uninitialized!"
    )
    debug_assert[assert_mode="none"](
        len(y.words) != 0, "BigUInt is uninitialized!"
    )

    # If the subtrahend is zero, return the minuend.
    # Yuhao ZHU:
    # This step is important because y can be of zero words and is longer than
    # x. That would run the loop past the end of the result, whose length is
    # the length of x, and the loop works on unsafe pointers.
    if y.is_zero():
        debug_assert[assert_mode="none"](
            len(y.words) == 1, "subtract_carry_select(): leading zero words"
        )
        return x.copy()

    # We need to determine which number has the larger magnitude
    var comparison_result = x.compare(y)
    if comparison_result == 0:
        # |x| = |y|
        return BigUInt.zero()  # Return zero
    if comparison_result < 0:
        raise OverflowError(
            function="subtract()",
            message=(
                "biguint.arithmetics.subtract(): Result is negative due to"
                " x < y"
            ),
        )

    # Now it is safe to subtract the smaller number from the larger one.
    # The result will have no more words than the first number.
    var result = BigUInt(unsafe_uninit_length=len(x.words))

    var xp = x.words.unsafe_ptr()
    var rp = result.words.unsafe_ptr()
    var borrow = _subtract_words(
        rp, xp, y.words.unsafe_ptr(), len(y.words), BigUInt.Word(0)
    )
    _ = _borrow_into_tail(rp, xp, len(y.words), len(x.words), borrow)

    result.remove_leading_empty_words()

    return result^


def subtract_greater(x: BigUInt, y: BigUInt) -> BigUInt:
    """Returns `x - y`, where the caller has already established `x > y`.

    `subtract()` compares its operands to decide whether the result would be
    negative, and raises if so. Its callers in `BigDecimal` have just done
    that comparison themselves, to work out which way round to subtract and
    what sign to give the answer -- so the comparison happens twice, and the
    caller carries an error path for something it has proved cannot happen.

    This is the same borrow-select pass with neither.

    Args:
        x: The minuend. Must be strictly greater than `y`.
        y: The subtrahend, which must not be zero.

    Returns:
        `x - y`.
    """
    debug_assert[assert_mode="none"](
        len(x.words) != 0 and len(y.words) != 0, "BigUInt is uninitialized!"
    )
    debug_assert[assert_mode="none"](
        x.compare(y) > 0,
        "biguint.arithmetics.subtract_greater(): x must be greater than y",
    )

    var result = BigUInt(unsafe_uninit_length=len(x.words))
    var xp = x.words.unsafe_ptr()
    var rp = result.words.unsafe_ptr()
    var borrow = _subtract_words(
        rp, xp, y.words.unsafe_ptr(), len(y.words), BigUInt.Word(0)
    )
    _ = _borrow_into_tail(rp, xp, len(y.words), len(x.words), borrow)
    result.remove_leading_empty_words()
    return result^


def subtract_inplace(mut x: BigUInt, y: BigUInt) raises -> None:
    """Subtracts y from x in place.

    Args:
        x: The `BigUInt` minuend, modified in place.
        y: The `BigUInt` subtrahend.

    Raises:
        OverflowError: If x < y (result would be negative).
    """

    # If the subtrahend is zero, return the minuend
    if y.is_zero():
        debug_assert[assert_mode="none"](
            len(y.words) == 1, "subtract_inplace(): leading zero words"
        )
        return

    # We need to determine which number has the larger magnitude
    var comparison_result = x.compare(y)
    if comparison_result == 0:
        x.words.resize(unsafe_uninit_length=1)
        x.words[0] = BigUInt.Word(0)  # Result is zero
        # This return is load-bearing. Without it the equal-operands case falls
        # through into the subtraction below, which subtracts `y` from the
        # one-word zero that `x` has just become: the loop runs over
        # `len(y.words)` words and reads and writes past the end of `x`, and
        # the result looks plausible rather than obviously wrong. `x -= x`
        # returned `877910460` for one 18-word operand. The out-of-place
        # `subtract()` is unaffected; only this in-place path was.
        return
    elif comparison_result < 0:
        raise OverflowError(
            function="subtract_inplace()",
            message=(
                "biguint.arithmetics.subtract(): Result is negative due to"
                " x < y"
            ),
        )

    # Now it is safe to subtract the smaller number from the larger one

    # If y is a single-word number, we can handle it with BigUInt.Word
    if len(y.words) == 1:
        subtract_by_word_inplace(x, y.words[0])
        return

    # Note that len(x.words) >= len(y.words) here
    var xp = x.words.unsafe_ptr()
    var borrow = _subtract_words(
        xp,
        alias_as_immutable_source(xp),
        y.words.unsafe_ptr(),
        len(y.words),
        BigUInt.Word(0),
    )
    _ = _borrow_into_tail(
        xp, alias_as_immutable_source(xp), len(y.words), len(x.words), borrow
    )

    x.remove_leading_empty_words()

    return


def subtract_no_check_inplace(mut x: BigUInt, y: BigUInt) -> None:
    """Subtracts y from x in-place without checking for underflow.

    Notes:

    This function assumes that x >= y, and it does not check for underflow.
    It is the caller's responsibility to ensure that x is greater than or
    equal to y before calling this function.

    Args:
        x: The `BigUInt` minuend, modified in place.
        y: The `BigUInt` subtrahend.
    """

    # If the subtrahend is zero, return the minuend
    if y.is_zero():
        debug_assert[assert_mode="none"](
            len(y.words) == 1, "subtract_no_check_inplace(): leading zero words"
        )
        return

    # Underflow checks are skipped here, so we assume x >= y
    # Note that len(x.words) >= len(y.words) under this assumption
    var xp = x.words.unsafe_ptr()
    var borrow = _subtract_words(
        xp,
        alias_as_immutable_source(xp),
        y.words.unsafe_ptr(),
        len(y.words),
        BigUInt.Word(0),
    )
    _ = _borrow_into_tail(
        xp, alias_as_immutable_source(xp), len(y.words), len(x.words), borrow
    )

    x.remove_leading_empty_words()

    return


def subtract_by_word_inplace(mut x: BigUInt, y: BigUInt.Word) -> None:
    """Subtracts a BigUInt.Word value from a BigUInt number in-place.

    Args:
        x: The BigUInt number to subtract from.
        y: The BigUInt.Word value to subtract.

    Notes:
        This function assumes that x >= y, and it does not check for underflow.
        It is the caller's responsibility to ensure that x is greater than or
        equal to y before calling this function.
    """

    debug_assert[assert_mode="none"](
        (len(x.words) > 1) or (x.words[0] >= y),
        "subtract_by_word_inplace(): Underflow due to x < y.",
    )

    x.words[0] -= y

    if len(x.words) == 1:
        return
    else:  # len(x.words) > 1
        # We need to handle the borrow for the rest of the words
        var borrow: BigUInt.Word = 0
        for ref word in x.words:
            if borrow == 0:
                if word <= BigUInt.BASE_MAX:  # 0 <= word <= 999_999_999
                    break  # No borrow, we can stop early
                else:  # word >= 3294967297, overflowed value
                    word += BigUInt.BASE
                    borrow = 1
            else:  # borrow == 1
                if (word >= 1) and (
                    word <= BigUInt.BASE_MAX
                ):  # 1 <= word <= 999_999_999
                    word -= 1
                    borrow = 0
                else:  # word >= 3294967297 or word == 0, overflowed value
                    word = (word + BigUInt.BASE) - 1
                    # borrow = 1
        x.remove_leading_empty_words()
        return


# ===----------------------------------------------------------------------=== #
# Multiplication algorithms
# ===----------------------------------------------------------------------=== #


def multiply(x: BigUInt, y: BigUInt) -> BigUInt:
    """Returns the product of two BigUInt numbers.

    Args:
        x: The first BigUInt operand (multiplicand).
        y: The second BigUInt operand (multiplier).

    Returns:
        The product of the two BigUInt numbers.

    Notes:
        This function uses a four-tier dispatch based on operand size:
        schoolbook multiplication for small numbers, Karatsuba for medium
        numbers, Toom-3 for large numbers, and a number-theoretic transform
        for very large ones. See `biguint.ntt` for the last one.
    """

    debug_assert[assert_mode="none"](
        len(x.words) != 0, "BigUInt is uninitialized!"
    )
    debug_assert[assert_mode="none"](
        len(y.words) != 0, "BigUInt is uninitialized!"
    )

    # SPECIAL CASE: both operands are a single word.
    #
    # `(BASE - 1)^2` needs 128 bits, so the product is `MUL` plus `UMULH`,
    # and the split back into words is two divisions by a constant, which the
    # compiler folds into multiply-high. The general path below would copy one
    # operand into a fresh buffer and then walk it, for a loop of length one.
    if len(x.words) == 1 and len(y.words) == 1:
        comptime BASE_WIDE = UInt128(BigUInt.BASE)
        var product = UInt128(x.words[0]) * UInt128(y.words[0])
        var high = product // BASE_WIDE
        var result = BigUInt(uninitialized_capacity=2)
        result.words.append(BigUInt.Word(product - high * BASE_WIDE))
        if high != 0:
            result.words.append(BigUInt.Word(high))
        return result^

    # SPECIAL CASES
    # If x or y is a single-word number
    # We can use `multiply_by_word_inplace` because this is only one loop
    # No need to split the long number into two parts
    if len(x.words) == 1:
        var x_word = x.words[0]
        if x_word == 0:
            return BigUInt.zero()
        elif x_word == 1:
            return y.copy()
        else:
            # Multiplying by a single word can add one word, so copy with room
            # for it: growing the buffer afterwards would allocate a second
            # time and copy what was just allocated.
            var result = y.copy_with_extra_capacity(1)
            multiply_by_word_inplace(result, x_word)
            return result^

    if len(y.words) == 1:
        var y_word = y.words[0]
        if y_word == 0:
            return BigUInt.zero()
        if y_word == 1:
            return x.copy()
        else:
            # Multiplying by a single word can add one word, so copy with room
            # for it: growing the buffer afterwards would allocate a second
            # time and copy what was just allocated.
            var result = x.copy_with_extra_capacity(1)
            multiply_by_word_inplace(result, y_word)
            return result^

    # CASE 1
    # The allocation cost is too high for small numbers to use Karatsuba
    # Use school multiplication for small numbers
    var max_words = max(len(x.words), len(y.words))
    if max_words <= CUTOFF_KARATSUBA:
        # return multiply_slices_schoolbook (x, y)
        return multiply_slices_schoolbook(
            x, y, (0, len(x.words)), (0, len(y.words))
        )
        # multiply_slices_schoolbook can also take x, y, and indices

    # CASE 2
    # Use Toom-3 multiplication for very large numbers.
    # Above a few thousand words the number-theoretic transform is cheaper
    # than Toom-3, so ask it first. See `biguint.ntt`.
    elif max_words > CUTOFF_TOOM3:
        if biguint_ntt.should_multiply_ntt(len(x.words), len(y.words)):
            return biguint_ntt.multiply_slices_ntt(
                x, y, (0, len(x.words)), (0, len(y.words))
            )
        return multiply_slices_toom3(x, y, (0, len(x.words)), (0, len(y.words)))

    # CASE 3
    # Use Karatsuba multiplication for medium-sized numbers
    else:
        return multiply_slices_karatsuba(
            x, y, (0, len(x.words)), (0, len(y.words)), CUTOFF_KARATSUBA
        )


def multiply_slices(
    x: BigUInt,
    y: BigUInt,
    bounds_x: Tuple[Int, Int],
    bounds_y: Tuple[Int, Int],
) -> BigUInt:
    """Returns the product of two BigUInt numbers.

    Args:
        x: The first BigUInt operand (multiplicand).
        y: The second BigUInt operand (multiplier).
        bounds_x: A tuple containing the start and end indices of the slice in x.
        bounds_y: A tuple containing the start and end indices of the slice in y.

    Returns:
        The product of the two BigUInt numbers.

    Notes:
        This function uses a four-tier dispatch based on operand size:
        schoolbook multiplication for small numbers, Karatsuba for medium
        numbers, Toom-3 for large numbers, and a number-theoretic transform
        for very large ones. See `biguint.ntt` for the last one.
    """
    var n_words_x_slice = bounds_x[1] - bounds_x[0]
    var n_words_y_slice = bounds_y[1] - bounds_y[0]

    # CASE 1
    # The allocation cost is too high for small numbers to use Karatsuba
    # Use school multiplication for small numbers
    var max_words = max(n_words_x_slice, n_words_y_slice)
    if max_words <= CUTOFF_KARATSUBA:
        # return multiply_slices_schoolbook (x, y)
        return multiply_slices_schoolbook(x, y, bounds_x, bounds_y)
        # multiply_slices_schoolbook can also take x, y, and indices

    # CASE 2
    # Use Toom-3 multiplication for very large numbers.
    # Above a few thousand words the number-theoretic transform is cheaper
    # than Toom-3, so ask it first. See `biguint.ntt`.
    elif max_words > CUTOFF_TOOM3:
        if biguint_ntt.should_multiply_ntt(n_words_x_slice, n_words_y_slice):
            return biguint_ntt.multiply_slices_ntt(x, y, bounds_x, bounds_y)
        return multiply_slices_toom3(x, y, bounds_x, bounds_y)

    # CASE 3
    # Use Karatsuba multiplication for medium-sized numbers
    else:
        return multiply_slices_karatsuba(
            x, y, bounds_x, bounds_y, CUTOFF_KARATSUBA
        )


def multiply_slices_schoolbook(
    imm x: BigUInt,
    imm y: BigUInt,
    bounds_x: Tuple[Int, Int],
    bounds_y: Tuple[Int, Int],
) -> BigUInt:
    """Multiplies two BigUInt slices using the schoolbook method.

    Args:
        x: The first BigUInt operand (multiplicand).
        y: The second BigUInt operand (multiplier).
        bounds_x: A tuple containing the start and end indices of the slice in x.
        bounds_y: A tuple containing the start and end indices of the slice in y.

    Returns:
        The product of the two BigUInt slices.
    """

    var n_words_x_slice = bounds_x[1] - bounds_x[0]
    var n_words_y_slice = bounds_y[1] - bounds_y[0]

    # CASE: One of the operands is zero or one
    if n_words_x_slice == 1:
        var x_word = x.words[bounds_x[0]]
        if x_word == 0:
            return BigUInt.zero()
        elif x_word == 1:
            return BigUInt.from_slice(y, (bounds_y[0], bounds_y[1]))
        else:
            var result = BigUInt.from_slice(y, (bounds_y[0], bounds_y[1]))
            multiply_by_word_inplace(result, x_word)
            result.assert_invariant("multiply_slices_schoolbook")
            return result^
    if n_words_y_slice == 1:
        var y_word = y.words[bounds_y[0]]
        if y_word == 0:
            return BigUInt.zero()
        elif y_word == 1:
            return BigUInt.from_slice(x, (bounds_x[0], bounds_x[1]))
        else:
            var result = BigUInt.from_slice(x, (bounds_x[0], bounds_x[1]))
            multiply_by_word_inplace(result, y_word)
            return result^

    # Product scanning (Comba): walk the result one word at a time, summing
    # the whole column `sum(x_i * y_j)` with `i + j == k` in a `UInt128`
    # accumulator before emitting a word.
    #
    # The operand-scanning form this replaces did a `% BASE` and a `// BASE`
    # on every one of the `n_x * n_y` partial products, and read and wrote the
    # result array on each of them too. Here the reduction happens once per
    # result word - `n_x + n_y` of them, not `n_x * n_y` - and the column
    # stays in registers. About 2.2x at 256 words, and ahead from two
    # words up, so there is no size gate any more.
    #
    # Overflow safety: each partial product is below `BASE^2 = 10^36`, which
    # is 120 bits, so the operands are widened *before* the multiply and not
    # after. The base-10^9 version could multiply in 64 bits and widen the
    # result, because `(10^9)^2` fit; writing it that way at eighteen digits a
    # word wraps before the cast ever happens, and every type in the
    # expression is still correct. A column of `k` such products needs
    # `k < 2^128 / 10^36`, about 340, and Karatsuba takes over long before a
    # column is that long. The column is unrolled over four independent
    # accumulators because a single one serialises on the 128-bit add.
    comptime BASE = UInt128(BigUInt.BASE)

    var result_length = n_words_x_slice + n_words_y_slice
    var result = BigUInt(unsafe_uninit_length=result_length)

    var start_x = bounds_x[0]
    var start_y = bounds_y[0]
    var x_words_ptr = x.words.unsafe_ptr()
    var y_words_ptr = y.words.unsafe_ptr()
    var result_ptr = result.words.unsafe_ptr()

    # There is no narrow path any more. The base-10^9 version summed a column
    # of at most sixteen products in a `UInt64`, because a partial product was
    # below `(10^9)^2 < 10^18`. A partial product is now below `(10^18)^2`,
    # which is 120 bits, so every column needs the accumulator below whatever
    # its length. That accumulator holds `2^128 / 10^36` -- about 340 --
    # products before it can overflow, and Karatsuba takes over long before a
    # column is that long.

    # `carry` is the part of the column sum at or above BASE, which belongs to
    # the next column. The last column leaves it holding the top word.
    var carry = UInt128(0)
    for k in range(result_length - 1):
        var i_low = 0 if k < n_words_y_slice else k - n_words_y_slice + 1
        var i_high = k if k < n_words_x_slice else n_words_x_slice - 1

        var acc0 = carry
        var acc1 = UInt128(0)
        var acc2 = UInt128(0)
        var acc3 = UInt128(0)

        var i = i_low
        while i + 3 <= i_high:
            acc0 += UInt128(x_words_ptr[unsafe_offset=start_x + i]) * UInt128(
                y_words_ptr[unsafe_offset=start_y + k - i]
            )
            acc1 += UInt128(
                x_words_ptr[unsafe_offset=start_x + i + 1]
            ) * UInt128(y_words_ptr[unsafe_offset=start_y + k - i - 1])
            acc2 += UInt128(
                x_words_ptr[unsafe_offset=start_x + i + 2]
            ) * UInt128(y_words_ptr[unsafe_offset=start_y + k - i - 2])
            acc3 += UInt128(
                x_words_ptr[unsafe_offset=start_x + i + 3]
            ) * UInt128(y_words_ptr[unsafe_offset=start_y + k - i - 3])
            i += 4
        while i <= i_high:
            acc0 += UInt128(x_words_ptr[unsafe_offset=start_x + i]) * UInt128(
                y_words_ptr[unsafe_offset=start_y + k - i]
            )
            i += 1

        var column = (acc0 + acc1) + (acc2 + acc3)
        result_ptr[unsafe_offset=k] = BigUInt.Word(column % BASE)
        carry = column // BASE

    result_ptr[unsafe_offset=result_length - 1] = BigUInt.Word(carry % BASE)

    result.remove_leading_empty_words()
    return result^


def multiply_slices_karatsuba(
    imm x: BigUInt,
    imm y: BigUInt,
    bounds_x: Tuple[Int, Int],
    bounds_y: Tuple[Int, Int],
    cutoff_number_of_words: Int,
) -> BigUInt:
    """Multiplies two BigUInt numbers using the Karatsuba algorithm.

    Args:
        x: The first BigUInt operand (multiplicand).
        y: The second BigUInt operand (multiplier).
        bounds_x: A tuple containing the start and end indices of the slice in x.
        bounds_y: A tuple containing the start and end indices of the slice in y.
        cutoff_number_of_words: The cutoff number of words for using Karatsuba
            multiplication. If the number of words in either operand is less
            than or equal to this value, the school method is used instead.

    Returns:
        The product of the two BigUInt numbers.

    Notes:

    This function uses a technique to avoid making copies of x and y.
    We just need to consider the slices of x and y by using the indices.
    """

    if x.is_zero_in_bounds(bounds=bounds_x) or y.is_zero_in_bounds(
        bounds=bounds_y
    ):
        return BigUInt.zero()

    # Number of words in the slice 1: end_x - start_x
    # Number of words in the slice 2: end_y - start_y
    var n_words_x_slice = bounds_x[1] - bounds_x[0]
    var n_words_y_slice = bounds_y[1] - bounds_y[0]

    # CASE 1:
    # If one number is only one-word long
    # we can use school multiplication because this is only one loop
    # No need to split the long number into two parts
    if n_words_x_slice == 1 or n_words_y_slice == 1:
        return multiply_slices_schoolbook(x, y, bounds_x, bounds_y)

    # CASE 2:
    # The allocation cost is too high for small numbers to use Karatsuba
    # Use school multiplication for small numbers
    var n_words_max = max(n_words_x_slice, n_words_y_slice)
    if n_words_max <= cutoff_number_of_words:
        # return multiply_slices_schoolbook (x, y)
        return multiply_slices_schoolbook(x, y, bounds_x, bounds_y)
        # multiply_slices_schoolbook can also takes in x, y, and indices

    # Otherwise, use Karatsuba

    # A number is split into two as-equal-length-as-possible parts:
    # x = x1 * 10^(9*m) + x0
    # The low part takes the first m words, the high part takes the rest.
    var m = n_words_max // 2
    var z0: BigUInt
    var z1: BigUInt
    var z2: BigUInt

    if n_words_x_slice <= m:
        # print("Karatsuba multiplication with x slice shorter than m words")
        # x slice is shorter than m words
        # Two times of multiplication
        # x0 = x_slice
        # x1 = 0
        # y0 = y_slice.words[:m]
        # y1 = y_slice.words[m:]
        z0 = multiply_slices_karatsuba(
            x,
            y,
            bounds_x,
            (bounds_y[0], bounds_y[0] + m),
            cutoff_number_of_words,
        )
        z1 = multiply_slices_karatsuba(
            x,
            y,
            bounds_x,
            (bounds_y[0] + m, bounds_y[1]),
            cutoff_number_of_words,
        )
        # z2 = 0

        z1.multiply_by_power_of_base_inplace(m)
        z1 += z0
        z1.remove_leading_empty_words()
        return z1^

    elif n_words_y_slice <= m:
        # print("Karatsuba multiplication with y slice shorter than m words")
        # y slice is shorter than m words
        # Two times of multiplication
        # x0 = x_slice.words[0:m]
        # x1 = x_slice.words[m:]
        # y0 = y_slice
        # y1 = 0
        z0 = multiply_slices_karatsuba(
            x,
            y,
            (bounds_x[0], bounds_x[0] + m),
            bounds_y,
            cutoff_number_of_words,
        )
        z1 = multiply_slices_karatsuba(
            x,
            y,
            (bounds_x[0] + m, bounds_x[1]),
            bounds_y,
            cutoff_number_of_words,
        )
        # z2 = 0
        z1.multiply_by_power_of_base_inplace(m)
        z1 += z0
        z1.remove_leading_empty_words()
        return z1^

    else:
        # print("normal Karatsuba multiplication")
        # Normal Karatsuba multiplication
        # Three times of multiplication
        # x0 = x_slice.words[0:m]
        # x1 = x_slice.words[m:]
        # y0 = y_slice.words[0:m]
        # y1 = y_slice.words[m:]

        # z0 = multiply_slices_karatsuba(x0, y0)
        z0 = multiply_slices_karatsuba(
            x,
            y,
            (bounds_x[0], bounds_x[0] + m),
            (bounds_y[0], bounds_y[0] + m),
            cutoff_number_of_words,
        )
        # z2 = multiply_slices_karatsuba(x1, y1)
        z2 = multiply_slices_karatsuba(
            x,
            y,
            (bounds_x[0] + m, bounds_x[1]),
            (bounds_y[0] + m, bounds_y[1]),
            cutoff_number_of_words,
        )
        # z3 = multiply_slices_karatsuba(x0 + x1, y0 + y1)
        # z1 = z3 - z2 -z0
        var x0_plus_x1 = add_slices(
            x,
            x,
            (bounds_x[0], bounds_x[0] + m),
            (bounds_x[0] + m, bounds_x[1]),
        )
        var y0_plus_y1 = add_slices(
            y,
            y,
            (bounds_y[0], bounds_y[0] + m),
            (bounds_y[0] + m, bounds_y[1]),
        )
        z1 = multiply_slices_karatsuba(
            x0_plus_x1,
            y0_plus_y1,
            (0, len(x0_plus_x1.words)),
            (0, len(y0_plus_y1.words)),
            cutoff_number_of_words,
        )

        # z1 >= z2 + z0 by construction
        subtract_no_check_inplace(z1, z2)
        subtract_no_check_inplace(z1, z0)

        # z2*9^(m * 2) + z1*9^m + z0
        z2.multiply_by_power_of_base_inplace(2 * m)
        z1.multiply_by_power_of_base_inplace(m)
        z2 += z1
        z2 += z0

        z2.remove_leading_empty_words()
        return z2^


def multiply_slices_toom3(
    imm x: BigUInt,
    imm y: BigUInt,
    bounds_x: Tuple[Int, Int],
    bounds_y: Tuple[Int, Int],
) -> BigUInt:
    """Multiplies two BigUInt slices using the Toom-Cook 3-way algorithm.

    This algorithm splits each operand into 3 parts of roughly equal size,
    evaluates at 5 points (0, 1, -1, 2, inf), performs 5 recursive
    multiplications, and interpolates to recover the result.

    Complexity: O(n^log_3(5)) ≈ O(n^1.465), better than Karatsuba's O(n^1.585).

    Args:
        x: The first BigUInt operand.
        y: The second BigUInt operand.
        bounds_x: Slice bounds for x (start inclusive, end exclusive).
        bounds_y: Slice bounds for y (start inclusive, end exclusive).

    Returns:
        The product of the two BigUInt slices.
    """

    var nx = bounds_x[1] - bounds_x[0]
    var ny = bounds_y[1] - bounds_y[0]

    # Fall back to Karatsuba for small or very asymmetric operands
    var n_max = max(nx, ny)
    var n_min = min(nx, ny)
    if n_max <= CUTOFF_TOOM3 or n_min <= CUTOFF_KARATSUBA:
        return multiply_slices_karatsuba(
            x, y, bounds_x, bounds_y, CUTOFF_KARATSUBA
        )

    # Split into 3 parts of size m (last part may be smaller)
    # x = x2 * B^(2m) + x1 * B^m + x0
    # y = y2 * B^(2m) + y1 * B^m + y0
    var m = (n_max + 2) // 3  # ceil(n/3)

    # Define slice bounds for x parts: x0, x1, x2
    var sx0_start = bounds_x[0]
    var sx0_end = min(sx0_start + m, bounds_x[1])
    var sx1_start = sx0_end
    var sx1_end = min(sx1_start + m, bounds_x[1])
    var sx2_start = sx1_end
    var sx2_end = bounds_x[1]

    # Define slice bounds for y parts: y0, y1, y2
    var sy0_start = bounds_y[0]
    var sy0_end = min(sy0_start + m, bounds_y[1])
    var sy1_start = sy0_end
    var sy1_end = min(sy1_start + m, bounds_y[1])
    var sy2_start = sy1_end
    var sy2_end = bounds_y[1]

    # Check if parts exist (slices may be empty for shorter operands)
    var has_x1 = sx1_start < sx1_end
    var has_x2 = sx2_start < sx2_end
    var has_y1 = sy1_start < sy1_end
    var has_y2 = sy2_start < sy2_end

    # ===================================================================
    # EVALUATION: Compute p(t) and q(t) at t = 0, 1, -1, 2, ∞
    #
    # Shared subexpression: x0+x2 is used for both p(1) and p(-1).
    # Similarly y0+y2 for q(1) and q(-1).
    # ===================================================================

    # --- Compute x0+x2 (shared between p(1) and p(-1)) ---
    var x0_plus_x2: BigUInt
    if has_x2:
        x0_plus_x2 = add_slices(
            x, x, (sx0_start, sx0_end), (sx2_start, sx2_end)
        )
    else:
        x0_plus_x2 = BigUInt.from_slice(x, (sx0_start, sx0_end))

    # --- Compute y0+y2 (shared between q(1) and q(-1)) ---
    var y0_plus_y2: BigUInt
    if has_y2:
        y0_plus_y2 = add_slices(
            y, y, (sy0_start, sy0_end), (sy2_start, sy2_end)
        )
    else:
        y0_plus_y2 = BigUInt.from_slice(y, (sy0_start, sy0_end))

    # --- Evaluate p(1) = x0 + x1 + x2 = (x0+x2) + x1 ---
    var px1: BigUInt
    if has_x1:
        px1 = add_slices(
            x0_plus_x2, x, (0, len(x0_plus_x2.words)), (sx1_start, sx1_end)
        )
    else:
        px1 = x0_plus_x2.copy()

    # --- Evaluate q(1) = y0 + y1 + y2 = (y0+y2) + y1 ---
    var qy1: BigUInt
    if has_y1:
        qy1 = add_slices(
            y0_plus_y2, y, (0, len(y0_plus_y2.words)), (sy1_start, sy1_end)
        )
    else:
        qy1 = y0_plus_y2.copy()

    # --- Evaluate p(-1) = (x0+x2) - x1 (signed) ---
    var pxm1: BigUInt
    var pxm1_neg: Bool
    if has_x1:
        var x1_val = BigUInt.from_slice(x, (sx1_start, sx1_end))
        var cmp = biguint_comparison.compare(x0_plus_x2, x1_val)
        if cmp >= 0:
            pxm1 = x0_plus_x2.copy()
            subtract_no_check_inplace(pxm1, x1_val)
            pxm1_neg = False
        else:
            pxm1 = x1_val^
            subtract_no_check_inplace(pxm1, x0_plus_x2)
            pxm1_neg = True
    else:
        pxm1 = x0_plus_x2.copy()
        pxm1_neg = False

    # --- Evaluate q(-1) = (y0+y2) - y1 (signed) ---
    var qym1: BigUInt
    var qym1_neg: Bool
    if has_y1:
        var y1_val = BigUInt.from_slice(y, (sy1_start, sy1_end))
        var cmp = biguint_comparison.compare(y0_plus_y2, y1_val)
        if cmp >= 0:
            qym1 = y0_plus_y2.copy()
            subtract_no_check_inplace(qym1, y1_val)
            qym1_neg = False
        else:
            qym1 = y1_val^
            subtract_no_check_inplace(qym1, y0_plus_y2)
            qym1_neg = True
    else:
        qym1 = y0_plus_y2.copy()
        qym1_neg = False

    # --- Evaluate p(2) = x0 + 2*x1 + 4*x2 using Horner: (x2*2 + x1)*2 + x0
    var px2: BigUInt
    if has_x2:
        px2 = BigUInt.from_slice(x, (sx2_start, sx2_end))
        multiply_by_word_inplace(px2, BigUInt.Word(2))
    else:
        px2 = BigUInt.zero()
    if has_x1:
        var x1_slice = BigUInt.from_slice(x, (sx1_start, sx1_end))
        add_inplace(px2, x1_slice)
    multiply_by_word_inplace(px2, BigUInt.Word(2))
    var x0_slice = BigUInt.from_slice(x, (sx0_start, sx0_end))
    add_inplace(px2, x0_slice)

    # --- Evaluate q(2) = y0 + 2*y1 + 4*y2 using Horner: (y2*2 + y1)*2 + y0
    var qy2: BigUInt
    if has_y2:
        qy2 = BigUInt.from_slice(y, (sy2_start, sy2_end))
        multiply_by_word_inplace(qy2, BigUInt.Word(2))
    else:
        qy2 = BigUInt.zero()
    if has_y1:
        var y1_slice = BigUInt.from_slice(y, (sy1_start, sy1_end))
        add_inplace(qy2, y1_slice)
    multiply_by_word_inplace(qy2, BigUInt.Word(2))
    var y0_slice = BigUInt.from_slice(y, (sy0_start, sy0_end))
    add_inplace(qy2, y0_slice)

    # ===================================================================
    # POINTWISE MULTIPLICATION: 5 recursive multiplications
    # ===================================================================

    # v0 = p(0) * q(0) = x0 * y0 (use original bounds, no copy)
    var v0 = multiply_slices(x, y, (sx0_start, sx0_end), (sy0_start, sy0_end))

    # vinf = p(∞) * q(∞) = x2 * y2 (use original bounds, no copy)
    var vinf: BigUInt
    if has_x2 and has_y2:
        vinf = multiply_slices(x, y, (sx2_start, sx2_end), (sy2_start, sy2_end))
    else:
        vinf = BigUInt.zero()

    # v1 = p(1) * q(1)
    var v1 = multiply(px1, qy1)

    # vm1 = p(-1) * q(-1), sign = pxm1_neg XOR qym1_neg
    var vm1 = multiply(pxm1, qym1)
    var vm1_neg = pxm1_neg != qym1_neg  # XOR

    # v2 = p(2) * q(2)
    var v2 = multiply(px2, qy2)

    # ===================================================================
    # INTERPOLATION: Recover w0, w1, w2, w3, w4
    # Result = w0 + w1*B^m + w2*B^(2m) + w3*B^(3m) + w4*B^(4m)
    #
    # The product polynomial is:
    #   r(t) = w0 + w1*t + w2*t^2 + w3*t^3 + w4*t^4
    # where:
    #   v0 = r(0) = w0
    #   v1 = r(1) = w0 + w1 + w2 + w3 + w4
    #   vm1 = r(-1) = w0 - w1 + w2 - w3 + w4
    #   v2 = r(2) = w0 + 2*w1 + 4*w2 + 8*w3 + 16*w4
    #   vinf = r(∞) = w4
    #
    # Interpolation formulas:
    #   w0 = v0
    #   w4 = vinf
    #   t1 = (v1 - vm1_signed) / 2    = w1 + w3
    #   w2 = (v1 + vm1_signed) / 2 - w0 - w4
    #   t3 = (v2 - w0 - 16*w4) / 2    = w1 + 2*w2 + 4*w3
    #   w3 = (t3 - 2*w2 - t1) / 3
    #   w1 = t1 - w3
    #
    # All w0..w4 and intermediates t1, t3 are non-negative.
    # ===================================================================

    # w0 = v0 (will use directly)
    # w4 = vinf (will use directly)

    # --- Compute t1 = (v1 - vm1_signed) / 2 = w1 + w3 ---
    # v1 - vm1_signed:
    #   if vm1_neg: v1 - (-|vm1|) = v1 + |vm1|
    #   else:       v1 - |vm1|
    var t1: BigUInt
    if vm1_neg:
        t1 = add(v1, vm1)
    else:
        # v1 - vm1 = 2*(w1 + w3) >= 0
        t1 = v1.copy()
        subtract_no_check_inplace(t1, vm1)
    exact_divide_by_2_inplace(t1)

    # --- Compute w2 = (v1 + vm1_signed) / 2 - w0 - w4 ---
    # v1 + vm1_signed:
    #   if vm1_neg: v1 - |vm1|
    #   else:       v1 + |vm1|
    var w2: BigUInt
    if vm1_neg:
        w2 = v1.copy()
        subtract_no_check_inplace(w2, vm1)
    else:
        w2 = add(v1, vm1)
    exact_divide_by_2_inplace(w2)
    # w2 = w2 - w0 - w4 (both subtractions are safe: result = w2 >= 0)
    subtract_no_check_inplace(w2, v0)
    subtract_no_check_inplace(w2, vinf)

    # --- Compute t3 = (v2 - w0 - 16*w4) / 2 = w1 + 2*w2 + 4*w3 ---
    var t3 = v2^  # move v2, no longer needed
    subtract_no_check_inplace(t3, v0)
    # Subtract 16 * vinf
    if not vinf.is_zero():
        var vinf_16 = vinf.copy()
        multiply_by_word_inplace(vinf_16, BigUInt.Word(16))
        subtract_no_check_inplace(t3, vinf_16)
    exact_divide_by_2_inplace(t3)

    # --- Compute w3 = (t3 - 2*w2 - t1) / 3 ---
    # Avoid copy: subtract w2 twice instead of creating w2*2
    subtract_no_check_inplace(t3, w2)
    subtract_no_check_inplace(t3, w2)
    subtract_no_check_inplace(t3, t1)
    exact_divide_by_3_inplace(t3)
    # t3 now holds w3

    # --- Compute w1 = t1 - w3 ---
    subtract_no_check_inplace(t1, t3)
    # t1 now holds w1

    # ===================================================================
    # RECOMPOSITION: result = w0 + w1*B^m + w2*B^(2m) + w3*B^(3m) + w4*B^(4m)
    # ===================================================================

    # Pre-allocate the result array.
    # Maximum result length: nx + ny words (product of two numbers).
    var result_len = nx + ny
    var result = BigUInt(unsafe_uninit_length=result_len)
    unsafe_memset_zero(ptr=result.words.unsafe_ptr(), count=result_len)

    # Helper: add a BigUInt value at a word offset into result
    @parameter
    def _add_at_offset(mut result: BigUInt, value: BigUInt, offset: Int):
        """Adds value into result starting at the given word offset."""
        if value.is_zero():
            return
        var carry: UInt64 = 0
        for i in range(len(value.words)):
            var pos = offset + i
            if pos >= len(result.words):
                break
            var s = UInt64(result.words[pos]) + UInt64(value.words[i]) + carry
            result.words[pos] = BigUInt.Word(s % UInt64(BigUInt.BASE))
            carry = s // UInt64(BigUInt.BASE)
        # Propagate remaining carry
        var pos = offset + len(value.words)
        while carry > 0 and pos < len(result.words):
            var s = UInt64(result.words[pos]) + carry
            result.words[pos] = BigUInt.Word(s % UInt64(BigUInt.BASE))
            carry = s // UInt64(BigUInt.BASE)
            pos += 1

    _add_at_offset(result, v0, 0)  # w0 at offset 0
    _add_at_offset(result, t1, m)  # w1 at offset m (stored in t1)
    _add_at_offset(result, w2, 2 * m)  # w2 at offset 2m
    _add_at_offset(result, t3, 3 * m)  # w3 at offset 3m (stored in t3)
    _add_at_offset(result, vinf, 4 * m)  # w4 at offset 4m

    result.remove_leading_empty_words()
    return result^


def multiply_by_word_inplace(mut x: BigUInt, y: BigUInt.Word):
    """Multiplies in-place a BigUInt by a UInt32 value.

    Args:
        x: The BigUInt value to multiply.
        y: The single word to multiply by.
    """
    # Short circuit cases when y is between 0 and 4
    # See `multiply_by_word_le_2_inplace()` for details
    # The performance is the best when `y <= 2`
    if y <= 2:
        multiply_by_word_le_2_inplace(x, y)
        return

    comptime BASE_WIDE = UInt128(BigUInt.BASE)
    var y_wide = UInt128(y)
    var product: UInt128
    var carry = UInt128(0)

    for i in range(len(x.words)):
        product = UInt128(x.words[i]) * y_wide + carry
        x.words[i] = BigUInt.Word(product % BASE_WIDE)
        carry = product // BASE_WIDE

    if carry > 0:
        x.words.append(BigUInt.Word(carry))


def multiply_by_word_le_2_inplace(mut x: BigUInt, y: BigUInt.Word):
    """Multiplies in-place a BigUInt by a UInt32 value which is between 0 and 4.

    Args:
        x: The BigUInt value to multiply.
        y: The single word to multiply by. It must be between 0 and 4.

    Notes:

    The short-circuit path of `multiply_by_word_inplace()`, for `y` of 0, 1
    or 2.

    A valid word doubled is below `2 * BASE`, which the word type holds with
    room to spare, so the vector pass can multiply without carrying and leave
    the carries to a single walk afterwards.

    It used to handle 3 and 4 as well, on the same idea -- `4 * BASE` also
    fits -- but the caller has always gated at `y <= 2`, because normalising
    carries that can reach four bases costs more than it saves. Those branches
    were therefore unreachable, and are gone, along with the four-base carry
    walk that only they called.
    """
    debug_assert[assert_mode="none"](
        y <= 2,
        "biguint.arithmetics.multiply_by_word_le_2_inplace(): y must be 0, 1",
        " or 2.",
    )

    # y is 0, x becomes 0
    if y == 0:
        x.words = Coefficient(BigUInt.Word(0), __list_literal__=None)
        return

    # y is 1, x stays the same
    if y == 1:
        return

    # y is 2, we can just shift the digits of each word to the left by 1
    def vector_multiply_by_2[simd_width: Int](i: Int) {mut x}:
        """Shifts the digits of each word to the left by 1."""
        x.words.unsafe_ptr().unsafe_store[width=simd_width](
            i, x.words.unsafe_ptr().unsafe_load[width=simd_width](i) << 1
        )

    vectorize[BigUInt.VECTOR_WIDTH](len(x.words), vector_multiply_by_2)
    normalize_carries_lt_2_bases(x)


def multiply_by_power_of_ten(x: BigUInt, n: Int) -> BigUInt:
    """Multiplies a BigUInt by 10^n (n >= 0).

    Args:
        x: The BigUInt value to multiply.
        n: The power of 10 to multiply by.

    Returns:
        A new BigUInt containing the result of the multiplication.

    Notes:

    In non-debug model, if n is less than or equal to 0, the function returns x
    unchanged. In debug mode, it asserts that n is non-negative.
    """
    debug_assert[assert_mode="none"](
        n >= 0, "multiply_by_power_of_ten(): n must be non-negative, got ", n
    )

    if n <= 0:
        return x.copy()

    if x.is_zero():
        debug_assert[assert_mode="none"](
            len(x.words) == 1, "multiply_by_power_of_ten(): leading zero words"
        )
        return BigUInt.zero()  # Multiplying zero by anything is still zero

    var number_of_zero_words = n // BigUInt.DIGITS_PER_WORD
    var number_of_remaining_digits = n % BigUInt.DIGITS_PER_WORD

    var result = BigUInt(
        uninitialized_capacity=number_of_zero_words + len(x.words) + 1
    )
    # Add zero words
    for _ in range(number_of_zero_words):
        result.words.append(BigUInt.Word(0))
    # Add the original words times 10^number_of_remaining_digits
    if number_of_remaining_digits == 0:
        for i in range(len(x.words)):
            result.words.append(x.words[i])
    else:  # number_of_remaining_digits > 0
        # `number_of_remaining_digits` runs from 1 to `DIGITS_PER_WORD - 1`,
        # so this is a lookup rather than the `if` chain it used to be: that
        # chain stopped at 8 because a word held nine digits, and a wider word
        # would have folded every larger shift into the last branch.
        var carry = UInt128(0)
        var product: UInt128
        var multiplier = BigUInt.Word(1)
        for _ in range(number_of_remaining_digits):
            multiplier *= 10

        for i in range(len(x.words)):
            product = UInt128(x.words[i]) * UInt128(multiplier) + carry
            result.words.append(BigUInt.Word(product % UInt128(BigUInt.BASE)))
            carry = product // UInt128(BigUInt.BASE)
        # Add the last carry if it exists
        if carry > 0:
            result.words.append(BigUInt.Word(carry))

    result.remove_leading_empty_words()
    return result^


def multiply_by_power_of_ten_inplace(mut x: BigUInt, n: Int):
    """Multiplies a BigUInt in-place by 10^n (n >= 0).

    Args:
        x: The BigUInt value to multiply.
        n: The power of 10 to multiply by.

    Notes:

    In non-debug model, if n is less than or equal to 0, the function returns x
    unchanged. In debug mode, it asserts that n is non-negative.
    """
    debug_assert[assert_mode="none"](
        n >= 0,
        "multiply_by_power_of_ten_inplace(): n must be non-negative, got ",
        n,
    )

    if n <= 0:
        return

    if x.is_zero():
        debug_assert[assert_mode="none"](
            len(x.words) == 1,
            "multiply_by_power_of_ten_inplace(): leading zero words",
        )
        # If x is zero, we can just return
        # No need to add zeros, it will still be zero
        return

    var number_of_zero_words = n // BigUInt.DIGITS_PER_WORD
    var number_of_remaining_digits = n % BigUInt.DIGITS_PER_WORD

    # SPECIAL CASE: If n is a multiple of 9
    if number_of_remaining_digits == 0:
        # If n is a multiple of 9, we just need to add zero words
        x.multiply_by_power_of_base_inplace(number_of_zero_words)
        return

    else:  # number_of_remaining_digits > 0
        # The number of words to add is number_of_zero_words + 1
        # For example, if n = 10, we add two words
        # The most significant word may not be used
        # We need to make sure that it is initialized to zero finally
        var x_original_length = len(x.words)
        x.words.resize(
            unsafe_uninit_length=len(x.words) + number_of_zero_words + 1
        )  # New length = original length + number of zero words + 1

        # `number_of_remaining_digits` runs from 1 to `DIGITS_PER_WORD - 1`,
        # so this is a lookup rather than the `if` chain it used to be: that
        # chain stopped at 8 because a word held nine digits, and a wider word
        # would have folded every larger shift into the last branch.
        var carry = UInt128(0)
        var product: UInt128
        var multiplier = BigUInt.Word(1)
        for _ in range(number_of_remaining_digits):
            multiplier *= 10

        for i in range(x_original_length):
            product = UInt128(x.words[i]) * UInt128(multiplier) + carry
            x.words[i] = BigUInt.Word(product % UInt128(BigUInt.BASE))
            carry = product // UInt128(BigUInt.BASE)

        # Add the last carry no matter it is 0 or not
        x.words[x_original_length] = BigUInt.Word(carry)

        # Now we shift the words to the right by number_of_zero_words
        for i in range(len(x.words) - 1, number_of_zero_words - 1, -1):
            x.words[i] = x.words[i - number_of_zero_words]

        # Fill the first number_of_zero_words with zeros
        for i in range(number_of_zero_words):
            x.words[i] = BigUInt.Word(0)

        # Remove the most significant zero word
        x.remove_leading_empty_words()
        return


def multiply_by_power_of_base(x: BigUInt, n: Int) -> BigUInt:
    """Multiplies a BigUInt by `BASE^n` (n >= 0).
    This equals to appending `n` zero words to the end of the number.

    Args:
        x: The BigUInt value to multiply.
        n: The power of `BASE` to multiply by. Should be non-negative.

    Notes:

    In non-debug model, if n is less than or equal to 0, the function returns x
    unchanged. In debug mode, it asserts that n is non-negative.

    Returns:
        A new `BigUInt` containing the result of the multiplication.
    """
    debug_assert[assert_mode="none"](
        n >= 0,
        "multiply_by_power_of_base(): n must be non-negative, got ",
        n,
    )

    if n <= 0:
        return x.copy()  # No change needed

    if x.is_zero():
        debug_assert[assert_mode="none"](
            len(x.words) == 1,
            "multiply_by_power_of_base_inplace(): leading zero words",
        )
        # If x is zero, we can just return
        # No need to add zeros, it will still be zero
        return BigUInt.zero()

    var res = BigUInt(unsafe_uninit_length=len(x.words) + n)
    # Fill the first n words with zeros
    unsafe_memset_zero(ptr=res.words.unsafe_ptr(), count=n)
    # Copy the original words to the end of the new list
    unsafe_memcpy(
        dest=res.words.unsafe_ptr().unsafe_offset(n),
        src=x.words.unsafe_ptr(),
        count=len(x.words),
    )

    res.remove_leading_empty_words()
    return res^


def multiply_by_power_of_base_inplace(mut x: BigUInt, n: Int):
    """Multiplies a BigUInt in-place by `BASE^n` (n >= 0).
    This equals to appending `n` zero words to the end of the number.

    Args:
        x: The BigUInt value to multiply.
        n: The power of `BASE` to multiply by. Should be non-negative.

    Notes:

    In non-debug model, if n is less than or equal to 0, the function returns x
    unchanged. In debug mode, it asserts that n is non-negative.
    """
    debug_assert[assert_mode="none"](
        n >= 0,
        "multiply_by_power_of_base_inplace(): n must be non-negative, got ",
        n,
    )

    if n <= 0:
        return  # No change needed

    if x.is_zero():
        debug_assert[assert_mode="none"](
            len(x.words) == 1,
            "multiply_by_power_of_base_inplace(): leading zero words",
        )
        # If x is zero, we can just return
        # No need to add zeros, it will still be zero
        return

    # The number of words to add is n
    # For example, if n = 3, we add three words of zeros
    # x1, x2, x3, x4 -> x1, x2, x3, x4, 0, 0, 0
    x.words.resize(unsafe_uninit_length=len(x.words) + n)
    # Move the existing words to the right by n positions
    # x1, x2, x3, x4, _, _, _ -> 0, 0, 0, x1, x2, x3, x4
    for i in range(len(x.words) - 1, n - 1, -1):
        x.words[i] = x.words[i - n]
    # Fill the first n words with zeros
    for i in range(n):
        x.words[i] = BigUInt.Word(0)

    x.remove_leading_empty_words()
    return


def exact_divide_by_2_inplace(mut x: BigUInt):
    """Divides a BigUInt by 2 exactly, in-place.

    The caller must ensure that x is even (divisible by 2).
    Uses long division over the words, from MSB to LSB.

    Args:
        x: The `BigUInt` value to divide, modified in place.
    """
    var carry: BigUInt.Word = 0
    for i in range(len(x.words) - 1, -1, -1):
        # carry is 0 or 1; carry * BASE + words[i] fits in BigUInt.Word
        # because max = 1 * 10^9 + 999_999_999 = 1_999_999_999 < 2^32
        var val = carry * BigUInt.Word(BigUInt.BASE) + x.words[i]
        x.words[i] = val // 2
        carry = val % 2
    x.remove_leading_empty_words()


def exact_divide_by_3_inplace(mut x: BigUInt):
    """Divides a BigUInt by 3 exactly, in-place.

    The caller must ensure that x is divisible by 3.
    Uses long division over the words, from MSB to LSB.

    Notes:

    The straightforward form — build `carry * BASE + word`, divide it, take the
    modulus — puts *two* dependent multiplications on the loop-carried chain,
    because a compiler turns both the division and the modulus by a constant
    into multiply-high.

    The division comes off the chain by splitting it. Since `10^9 = 3 * T + 1`
    with `T = 333_333_333`, writing `word = 3 * d + m`:

        carry * 10^9 + word = 3 * (carry * T + d) + (carry + m)

    so, with `carry + m <= 4`,

        quotient = carry * T + d + (carry + m >= 3)
        new carry = (carry + m) mod 3

    `d` and `m` depend only on `word`, so the one division left is off the
    chain. See `bigint.arithmetics._exact_divide_by_3_inplace()`, which uses
    the same identity in base 2^32 — both bases happen to be `1 mod 3`.
    Every power of ten is, so this survives a change of `DIGITS_PER_WORD`.

    Args:
        x: The `BigUInt` value to divide, modified in place.
    """
    comptime BASE_OVER_THREE = BigUInt.Word(
        BigUInt.BASE_MAX // 3
    )  # 333_333_333

    var carry = BigUInt.Word(0)  # 0, 1 or 2
    var xp = x.words.unsafe_ptr()
    for i in range(len(x.words) - 1, -1, -1):
        var word = xp[unsafe_offset=i]
        var word_quotient = word // 3  # off the chain
        var word_remainder = word - 3 * word_quotient  # off the chain, 0..2
        var total = carry + word_remainder  # on the chain, 0..4
        var carried = BigUInt.Word(total >= 3)
        xp[unsafe_offset=i] = carry * BASE_OVER_THREE + word_quotient + carried
        carry = total - 3 * carried
    x.remove_leading_empty_words()


# ===----------------------------------------------------------------------=== #
# Division Algorithms
# floor_divide
# floor_divide_schoolbook
# floor_divide_burnikel_ziegler
#
# Each of these has a `floor_divide_modulo_*` sibling that also hands back the
# remainder. The remainder is a by-product of the division either way, so the
# siblings do the work and these drop it.
# ===----------------------------------------------------------------------=== #


def floor_divide(x: BigUInt, y: BigUInt) raises -> BigUInt:
    """Returns the quotient of two BigUInt numbers, truncating toward zero.

    Args:
        x: The dividend.
        y: The divisor.

    Returns:
        The quotient of x / y, truncated toward zero.

    Raises:
        ZeroDivisionError: If the divisor is zero.

    Notes:
        It is equal to truncated division for positive numbers.
    """

    debug_assert[assert_mode="none"](
        (len(x.words) != 0) and (len(y.words) != 0),
        "biguint.arithmetics.floor_divide(): BigUInt x ",
        x,
        " and / or ",
        y,
        " is uninitialized!",
    )

    debug_assert[assert_mode="none"](
        (len(x.words) == 1) or (x.words[len(x.words) - 1] != 0),
        "biguint.arithmetics.floor_divide(): BigUInt x ",
        x,
        " has leading zero words!",
    )
    debug_assert[assert_mode="none"](
        (len(y.words) == 1) or (y.words[len(y.words) - 1] != 0),
        "biguint.arithmetics.floor_divide(): BigUInt y ",
        y,
        " has leading zero words!",
    )

    # CASE: y is zero
    if y.is_zero():
        raise ZeroDivisionError(
            function="floor_divide()",
            message="Division by zero",
        )

    # CASE: Dividend is zero
    if x.is_zero():
        debug_assert[assert_mode="none"](
            len(x.words) == 1,
            "biguint.arithmetics.floor_divide(): x has leading zero words",
        )
        return BigUInt.zero()  # Return zero

    # CASE: x is not greater than y
    var comparison_result: Int8 = x.compare(y)
    # SUB-CASE: dividend < divisor
    if comparison_result < 0:
        return BigUInt.zero()  # Return zero
    # SUB-CASE: dividend == divisor
    if comparison_result == 0:
        return BigUInt.one()  # Return one

    # CASE: y is single word
    if len(y.words) == 1:
        # SUB-CASE: Division by one
        if y.words[0] == 1:
            return x.copy()
        # SUB-CASE: Single word // single word
        if len(x.words) == 1:
            var result = BigUInt.from_word_unsafe(x.words[0] // y.words[0])
            return result^
        # SUB-CASE: Divisor is single word (<= 9 digits)
        else:
            return floor_divide_by_word(x, y.words[0])

    # A two-word divisor used to take a `UInt64` shortcut. Two words are now
    # `10^36`, which no `UInt64` holds, so it goes through Knuth D with
    # everything else. A single word still fits, and that path is above.

    # CASE: y is three or four words
    #
    # There used to be a `floor_divide_by_uint128` shortcut here, on the
    # reasoning that a divisor small enough to sit in one machine word should
    # be divided by in one machine word. It measured the other way round.
    # arm64 has no 128-bit divide, let alone a 256-bit one, so every step of
    # that routine called a software division helper -- and the routine is
    # written in `UInt256`, so it called the 256-bit one, twice per group of
    # four dividend words. Knuth D did the same job with the divisions the
    # hardware actually has -- 64-bit then, 128-by-64 now that a word is
    # eighteen digits, and still not a call.
    #
    # Measured, best of nine, this file at 6e63828 (ns):
    #
    #   divisor   dividend    uint128    Knuth D
    #   3 words    6 words        306        239
    #   3 words   10 words        669        292
    #   3 words   16 words       1034        399
    #   4 words   10 words        393        273
    #   4 words   16 words        834        389
    #
    # The gap widens with the dividend, because the shortcut's cost is linear
    # in dividend words with a large constant while Knuth D's is linear with a
    # small one. It won only at two sizes, both of them a dividend that is an
    # exact multiple of four words, where the routine skips its leading-group
    # branch -- not a reason to keep a slower path for every other size.
    #
    # One- and two-word divisors keep their shortcuts: `UInt32` and `UInt64`
    # division *is* a hardware instruction, and those paths win by 2-3x.
    #
    # The shortcut was correct, not just slow -- `x == q * y + r` with
    # `r < y` was checked across 555 operand shapes before it was removed.

    # CASE: Divisor is 10^n
    if y.is_power_of_10():
        var result = floor_divide_by_power_of_ten(
            x, y.number_of_trailing_zeros()
        )
        return result^

    # CASE: Division of small numbers
    # If the number of words in the dividend and the divisor is small enough,
    # we can use the schoolbook division algorithm.
    # 2n-by-n where n is the cutoff number of words for Burnikel-Ziegler
    if (len(x.words) <= CUTOFF_BURNIKEL_ZIEGLER * 2) and (
        len(y.words) <= CUTOFF_BURNIKEL_ZIEGLER
    ):
        # I will normalize the divisor to improve quotient estimation
        # Calculate normalization factor to make leading digit of divisor
        # as large as possible
        var ndigits_to_shift = calculate_ndigits_for_normalization(
            y.words[len(y.words) - 1]
        )

        if ndigits_to_shift == 0:
            # No normalization needed, just use the general division algorithm
            return floor_divide_schoolbook(x, y)
        else:
            # Normalize the divisor and dividend
            var normalized_x = multiply_by_power_of_ten(x, ndigits_to_shift)
            var normalized_y = multiply_by_power_of_ten(y, ndigits_to_shift)
            return floor_divide_schoolbook(normalized_x, normalized_y)

    # CASE: division of very, very large numbers
    # Use the Burnikel-Ziegler division algorithm
    return floor_divide_burnikel_ziegler(
        x, y, cut_off=BURNIKEL_ZIEGLER_BLOCK_WORDS
    )


# TODO: Implement a `floor_divide_slices_schoolbook()` function that
# can be used for slices of BigUInt numbers.
def floor_divide_schoolbook(x: BigUInt, y: BigUInt) raises -> BigUInt:
    """**[PRIVATE]** General schoolbook division algorithm for BigInt10 numbers.

    Args:
        x: The dividend.
        y: The divisor.

    Returns:
        The quotient of x // y.

    Raises:
        ZeroDivisionError: If the divisor is zero.
    """
    var remainder = BigUInt.zero_with_capacity(4)
    return floor_divide_modulo_schoolbook(x, y, remainder)


def floor_divide_modulo_schoolbook(
    x: BigUInt, y: BigUInt, mut remainder: BigUInt
) raises -> BigUInt:
    """**[PRIVATE]** General schoolbook division algorithm for BigInt10 numbers,
    keeping the remainder.

    Args:
        x: The dividend.
        y: The divisor.
        remainder: Set to `x % y` on return.

    Returns:
        The quotient of x // y.

    Raises:
        ZeroDivisionError: If the divisor is zero.

    Notes:

    Knuth D keeps a running remainder for the whole run and this is the same
    buffer, handed back instead of dropped. Callers that want only the quotient
    go through `floor_divide_schoolbook()`.

    If the caller normalized the operands before calling, the remainder comes
    back scaled by the same factor and has to be scaled back down.
    """

    # Because the Burnikel-Ziegler division algorithm will fall back to this
    # function for small numbers, we need to ensure that special cases are
    # handled properly to improve performance.
    # CASE: y is zero
    if y.is_zero():
        raise ZeroDivisionError(
            message="Division by zero", function="floor_divide()"
        )

    # CASE: Dividend is zero
    if x.is_zero():
        debug_assert[assert_mode="none"](
            len(x.words) == 1,
            "biguint.arithmetics.floor_divide(): x has leading zero words",
        )
        overwrite_with_word(remainder, 0)
        return BigUInt.zero()  # Return zero

    # CASE: x is not greater than y
    var comparison_result: Int8 = x.compare(y)
    # SUB-CASE: dividend < divisor
    if comparison_result < 0:
        remainder = x.copy()  # The dividend passes through untouched
        return BigUInt.zero()  # Return zero
    # SUB-CASE: dividend == divisor
    if comparison_result == 0:
        overwrite_with_word(remainder, 0)
        return BigUInt.one()

    # CASE: y is single word
    if len(y.words) == 1:
        # SUB-CASE: Division by one
        if y.words[0] == 1:
            overwrite_with_word(remainder, 0)
            return x.copy()
        # SUB-CASE: Single word // single word
        if len(x.words) == 1:
            overwrite_with_word(remainder, x.words[0] % y.words[0])
            var result = BigUInt.from_word_unsafe(x.words[0] // y.words[0])
            return result^
        # SUB-CASE: Divisor is single word (<= 9 digits)
        else:
            var word_remainder = BigUInt.Word(0)
            var result = floor_divide_modulo_by_word(
                x, y.words[0], word_remainder
            )
            overwrite_with_word(remainder, word_remainder)
            return result^

    # A two-word divisor used to take a `UInt64` shortcut. Two words are now
    # `10^36`, which no `UInt64` holds, so it goes through Knuth D with
    # everything else. A single word still fits, and that path is above.

    # See `floor_divide()` for why three- and four-word divisors no longer
    # take a `UInt128` shortcut here.

    # ===----------------------------------------------=== #
    # ALL OTHER CASES
    # Schoolbook division, Knuth D style: each quotient word is estimated from
    # the top three words of the running remainder and then subtracted in a
    # single fused multiply-subtract over the `n + 1` word window it affects.
    #
    # The older form built `q * y` as a fresh `BigUInt`, shifted it up by
    # `index_of_word` words, compared it against the whole remainder and
    # subtracted it from the whole remainder. That is four passes over the
    # full dividend, plus an allocation, for every quotient word - which made
    # the routine cost `O(m * (n + m))` with a large constant instead of
    # `O(m * n)` with a small one. Windowing it was worth 2-4x, most of it in
    # the 100 to 1 000 digit band.
    comptime BASE = UInt64(BigUInt.BASE)

    var n = len(y.words)
    var n_words_diff = len(x.words) - n

    var result = BigUInt(uninitialized_capacity=n_words_diff + 1)
    for _ in range(n_words_diff + 1):
        result.words.append(0)

    # One guard word above the dividend, so `index_of_word + n` is always a
    # real position for the fused subtraction to take its final borrow from.
    # One buffer, filled once. Assigning `x.words.copy()` into a `BigUInt`
    # that had just been given room for `len + 1` words threw that buffer
    # away, allocated a second one of exactly `len`, and then the `append`
    # below could grow it a third time.
    var n_words_x = len(x.words)
    var running = BigUInt(unsafe_uninit_length=n_words_x + 1)
    var running_ptr = running.words.unsafe_ptr()
    unsafe_memcpy(dest=running_ptr, src=x.words.unsafe_ptr(), count=n_words_x)
    running_ptr[unsafe_offset=n_words_x] = BigUInt.Word(0)

    var y_ptr = y.words.unsafe_ptr()
    var r_ptr = running.words.unsafe_ptr()

    for index_of_word in range(n_words_diff, -1, -1):
        var quotient = floor_divide_estimate_quotient(running, y, index_of_word)

        # remainder[index .. index + n) -= quotient * y.
        #
        # `carry` carries both halves of the step: the high word of the
        # product, and the borrow, which is folded into it exactly one word
        # later - the same trick the base-2^32 Knuth D uses. Biasing the
        # difference by BASE keeps it non-negative, so the borrow is just
        # whether the biased value stayed below BASE.
        var carry = _multiply_subtract_words(
            r_ptr.unsafe_offset(index_of_word), y_ptr, n, quotient
        )
        # The estimate can be one or two too large. Each add-back returns the
        # divisor to the window and buys back one unit of the quotient.
        var top = index_of_word + n
        var top_value = UInt64(r_ptr[unsafe_offset=top])
        var correction_attempts = 0
        while top_value < carry:
            quotient -= 1
            correction_attempts += 1
            debug_assert[assert_mode="none"](
                correction_attempts <= 2, "Too many correction attempts"
            )
            var add_carry = UInt64(0)
            for i in range(n):
                var total = (
                    UInt64(r_ptr[unsafe_offset=index_of_word + i])
                    + UInt64(y_ptr[unsafe_offset=i])
                    + add_carry
                )
                if total >= BASE:
                    r_ptr[unsafe_offset=index_of_word + i] = BigUInt.Word(
                        total - BASE
                    )
                    add_carry = 1
                else:
                    r_ptr[unsafe_offset=index_of_word + i] = BigUInt.Word(total)
                    add_carry = 0
            top_value += add_carry
        r_ptr[unsafe_offset=top] = BigUInt.Word(top_value - carry)

        result.words[index_of_word] = quotient

    # Every quotient word has been subtracted out, so what is left of the
    # dividend below the divisor's width is the remainder. The words above it
    # are the guard word and the space the quotient was peeled from, all zero.
    running.words.resize(n, BigUInt.Word(0))
    running.remove_leading_empty_words()
    remainder = running^

    result.remove_leading_empty_words()
    return result^


def floor_divide_estimate_quotient(
    dividend: BigUInt, divisor: BigUInt, index_of_word: Int
) -> BigUInt.Word:
    """Estimates the quotient digit using 3-by-2 division.

    This function implements a 3-by-2 quotient estimation algorithm,
    which divides a 3-word dividend portion by a 2-word divisor to get
    an accurate quotient estimate.

    Args:
        dividend: The dividend BigUInt number.
        divisor: The divisor BigUInt number. Should be at least 2 words.
        index_of_word: The current position in the division algorithm.

    Returns:
        An estimated quotient digit, below `BASE`.

    Notes:

    The function performs division of a 3-word number by a 2-word number:
    Dividend portion: R = r2 * BASE^2 + r1 * BASE + r0.
    Divisor: D = d1 * BASE + d0.
    Goal: Estimate Q = R // D.
    """

    # This is Knuth's step D3. It divides the top two words of the remainder
    # by the divisor's top word rather than building the full three-by-two,
    # which is what keeps the estimate to a single division.
    #
    # `r2 * BASE + r1` needs 128 bits now: at eighteen digits a word the
    # product alone is `10^36`. It is a 128-by-64 divide with a runtime
    # divisor, and the compiler's own expansion of that is the right tool --
    # measured at 5.79 ns against 5.01 for the 64-bit divide it replaces, on a
    # serial chain, and there are half as many quotient words to spend it on.
    # A precomputed Moller-Granlund reciprocal, which is what `BigInt` needs
    # at base 2^64, measures *slower* here (6.94 ns) because the numerator is
    # not a full 128-bit value and the normalising shift lands on the critical
    # path. Do not reach for it.
    #
    # The estimate can be up to two too large, which the correction below
    # takes back one at a time; the caller is prepared for the same two, and
    # normalization -- `d1 >= BASE / 2` -- is what bounds it.
    comptime BASE = UInt128(BigUInt.BASE)

    var n = len(divisor.words)
    var base_index = index_of_word + n - 2
    var dividend_ptr = dividend.words.unsafe_ptr()
    var n_dividend = len(dividend.words)

    var r0 = UInt64(0)
    var r1 = UInt64(0)
    var r2 = UInt64(0)
    if base_index < n_dividend:
        r0 = UInt64(dividend_ptr[unsafe_offset=base_index])
    if base_index + 1 < n_dividend:
        r1 = UInt64(dividend_ptr[unsafe_offset=base_index + 1])
    if base_index + 2 < n_dividend:
        r2 = UInt64(dividend_ptr[unsafe_offset=base_index + 2])

    var divisor_ptr = divisor.words.unsafe_ptr()
    debug_assert[assert_mode="none"](
        n >= 2,
        "biguint.arithmetics.floor_divide_estimate_quotient(): ",
        "Divisor must have at least 2 words by design.",
    )
    var d0 = UInt64(divisor_ptr[unsafe_offset=n - 2])
    var d1 = UInt64(divisor_ptr[unsafe_offset=n - 1])

    var top = UInt128(r2) * BASE + UInt128(r1)
    var d1_wide = UInt128(d1)
    var quotient = top // d1_wide
    var rest = top - quotient * d1_wide

    if quotient >= BASE:
        quotient = BASE - 1
        rest = top - quotient * d1_wide

    # `quotient * d0` and `rest * BASE + r0` are both below `BASE^2`, so the
    # test is exact in 128 bits. At most two rounds: that is Knuth's bound for
    # a normalized divisor.
    while rest < BASE and quotient * UInt128(d0) > rest * BASE + UInt128(r0):
        quotient -= 1
        rest += d1_wide

    return BigUInt.Word(quotient)


def floor_divide_by_word(x: BigUInt, y: BigUInt.Word) -> BigUInt:
    """**[PRIVATE]** Divides a BigUInt by a BigUInt.Word divisor.

    Args:
        x: The BigUInt value to divide by the divisor.
        y: The BigUInt.Word divisor. Must be non-zero.

    Notes:

    This function is used internally for division by single word divisors.
    It is not intended for public use. You need to ensure that y is non-zero.

    Returns:
        The quotient of x divided by y.
    """
    # The remainder falls out of the loop for free, so there is one loop and
    # this is the caller that does not want it.
    var remainder = BigUInt.Word(0)
    return floor_divide_modulo_by_word(x, y, remainder)


def floor_divide_modulo_by_word(
    x: BigUInt, y: BigUInt.Word, mut remainder: BigUInt.Word
) -> BigUInt:
    """**[PRIVATE]** Divides a BigUInt by a UInt32 divisor, keeping the
    remainder.

    Args:
        x: The BigUInt value to divide by the divisor.
        y: The UInt32 divisor. Must be non-zero.
        remainder: Set to `x % y` on return.

    Returns:
        The quotient of x divided by y.

    Notes:

    The remainder is returned through an argument rather than in a tuple
    because a `BigUInt` cannot be moved out of a returned tuple yet
    (modular/modular#5330), and the quotient is the value worth keeping cheap.
    """
    debug_assert[assert_mode="none"](
        y != 0,
        "biguint.arithmetics.floor_divide_modulo_by_word(): Division by zero",
    )

    # Single-word dividend: O(1) exact result. This path is also what keeps the
    # loop below well-formed -- for a one-word `x` with `x.words[0] < y` the
    # quotient is 0, and without it `result` would be built with zero words,
    # returning a `BigUInt` that violates the non-empty-words invariant.
    if len(x.words) == 1:
        remainder = x.words[0] % y
        return BigUInt.from_word_unsafe(x.words[0] // y)

    # Most significant word of the dividend
    var dividend = UInt128(x.words[len(x.words) - 1] // y)
    var carry = UInt128(x.words[len(x.words) - 1] % y)
    var y_wide = UInt128(y)
    var result: BigUInt
    if dividend == 0:
        result = BigUInt(unsafe_uninit_length=len(x.words) - 1)
    else:
        result = BigUInt(unsafe_uninit_length=len(x.words))
        result.words[len(result.words) - 1] = BigUInt.Word(dividend)

    # Process the rest of the words.
    #
    # This loop used to hoist raw pointers out of both buffers, on the
    # reasoning that the indexed form reloads a `List` data field per element;
    # it was recorded as a stable +4-8% at >=256 words. That no longer
    # reproduces. Measured on this function on Mojo 1.0.0, at 256 / 1024 /
    # 8192 / 65536 words, the two forms are within 1.6% of each other and the
    # indexed form is marginally ahead at the largest sizes -- the loop runs at
    # ~3.35 ns/word either way, which is the two 64-bit divides, and addressing
    # never surfaces behind them. The indexed form is kept because it is also
    # bounds-checked under `-D ASSERT=all`.
    for i in range(len(x.words) - 2, -1, -1):
        dividend = carry * UInt128(BigUInt.BASE) + UInt128(x.words[i])
        result.words[i] = BigUInt.Word(dividend // y_wide)
        carry = dividend % y_wide

    # `carry` is what is left of the dividend once every word has been
    # consumed, which is the remainder.
    remainder = BigUInt.Word(carry)

    debug_assert[assert_mode="none"](
        (len(result.words) == 1) or (result.words[len(result.words) - 1] != 0),
        "biguint.arithmetics.floor_divide_modulo_by_word(): ",
        "Result has leading zero words",
    )
    result.assert_invariant("floor_divide_modulo_by_word")
    return result^


def floor_divide_by_word_inplace(mut x: BigUInt, y: BigUInt.Word) -> None:
    """Divides a BigUInt by a UInt32 divisor in-place.

    Args:
        x: The BigUInt value to divide by the divisor.
        y: The UInt32 divisor. Must be non-zero.

    Notes:

    This function is used internally for division by single word divisors.
    It is not intended for public use. You need to ensure that y is non-zero.
    """
    debug_assert[assert_mode="none"](
        y != 0,
        "biguint.arithmetics.floor_divide_by_word_inplace(): Division by zero",
    )

    # Most significant word of the dividend. `top` is read before the value is
    # shortened below: the loop that follows walks down from `top - 1`, and
    # deriving that bound from `len(x.words)` after a `shrink()` would skip the
    # word just below the one that was dropped and leave it undivided.
    var top = len(x.words) - 1
    var dividend = UInt128(x.words[top] // y)
    var carry = UInt128(x.words[top] % y)
    var y_wide = UInt128(y)
    if dividend == 0:
        if top == 0:
            # A single-word dividend smaller than the divisor has a quotient of
            # zero, and `BigUInt` spells zero as one zero word. Shrinking here
            # would leave the value with no words at all, and every operation
            # that reaches for `words[len(words) - 1]` - comparison first among
            # them - then indexes out of bounds.
            x.words[0] = BigUInt.Word(0)
            return
        x.words.shrink(top)
    else:
        x.words[top] = BigUInt.Word(dividend)

    # Process the rest of the words
    for i in range(top - 1, -1, -1):
        dividend = carry * UInt128(BigUInt.BASE) + UInt128(x.words[i])
        x.words[i] = BigUInt.Word(dividend // y_wide)
        carry = dividend % y_wide


def floor_divide_modulo_by_uint64(
    x: BigUInt, y: UInt64, mut remainder: UInt64
) -> BigUInt:
    """Divides a BigUInt by UInt64, keeping the remainder.

    Args:
        x: The `BigUInt` dividend.
        y: The `UInt64` divisor. Must be smaller than `BASE`.
        remainder: Set to `x % y` on return. It is smaller than `y`, so it
            always fits in a `UInt64`.

    Returns:
        The quotient of x divided by y.

    Notes:

    A divisor below `BASE` *is* a word now, so this is `_by_word` under
    another name and delegates to it. The base-10^9 version could not: a
    `UInt64` spanned two words there, so it walked the dividend in pairs,
    reassembling each pair with a SIMD dot product and carrying
    `carry * 10^18` between them. None of that survives a word that already
    holds eighteen digits.
    """
    debug_assert[assert_mode="none"](
        UInt128(y) < UInt128(BigUInt.BASE),
        "biguint.arithmetics.floor_divide_modulo_by_uint64(): ",
        "divisor must be below BASE.",
    )
    return floor_divide_modulo_by_word(x, BigUInt.Word(y), remainder)


def floor_divide_by_uint64_inplace(mut x: BigUInt, y: UInt64) -> None:
    """Divides a BigUInt by UInt64 in-place.

    Args:
        x: The BigUInt value to divide by the divisor.
        y: The UInt64 divisor. Must be smaller than `BASE`.

    Notes:

    See `floor_divide_modulo_by_uint64()` for why this is now the same
    operation as the single-word one.
    """
    debug_assert[assert_mode="none"](
        UInt128(y) < UInt128(BigUInt.BASE),
        "biguint.arithmetics.floor_divide_by_uint64_inplace(): ",
        "divisor must be below BASE.",
    )
    floor_divide_by_word_inplace(x, BigUInt.Word(y))


def floor_divide_by_2_inplace(mut x: BigUInt) -> None:
    """Divides a BigUInt by 2 in-place.

    Args:
        x: The BigUInt value to divide by 2.
    """
    if x.is_zero():
        debug_assert[assert_mode="none"](
            len(x.words) == 1, "floor_divide_by_2_inplace(): leading zero words"
        )
        return

    # Process from most significant to least significant word
    var base: BigUInt.Word = BigUInt.BASE
    var is_carry: Bool = False
    for ith in range(len(x.words) - 1, -1, -1):
        if is_carry:
            x.words[ith] += base
        if x.words[ith] & 1:
            is_carry = True
        else:
            is_carry = False
        x.words[ith] >>= 1
    x.remove_leading_empty_words()


# TODO: If `n` is a multiple of `DIGITS_PER_WORD`, the in-place version can
# be optimized by delegating to `floor_divide_by_power_of_base_inplace`.
def floor_divide_by_power_of_ten(x: BigUInt, n: Int) -> BigUInt:
    """Floor divides a BigUInt by 10^n (n>=0).
    It is equal to removing the last n digits of the number.

    Args:
        x: The BigUInt value to divide.
        n: The power of 10 to divide by. Should be non-negative.

    Returns:
        A new BigUInt containing the result of the division.

    Notes:

    In non-debug model, if n is less than or equal to 0, the function returns x
    unchanged. In debug mode, it asserts that n is non-negative.
    """
    # The message is passed as separate pieces rather than concatenated: a
    # `debug_assert` argument is built at the call site before the assert's
    # own `comptime if` can discard it, so `"..." + String(n)` allocates a
    # string on every call even in a build with assertions compiled out.
    # That cost ~59 ns here, more than the division being guarded.
    # Upstream bug, still open as of Mojo 1.0.0:
    # https://github.com/modular/modular/issues/6439
    debug_assert[assert_mode="none"](
        n >= 0,
        (
            "biguint.arithmetics.floor_divide_by_power_of_ten(): n must be"
            " non-negative but got "
        ),
        n,
    )

    if n <= 0:
        return x.copy()

    var word_shift = n // BigUInt.DIGITS_PER_WORD
    var digit_shift = n % BigUInt.DIGITS_PER_WORD

    # If we need to drop more words than exists, the result is zero.
    if word_shift >= len(x.words):
        return BigUInt.zero()

    # Whole-word divide: delegate to the cheaper specialised path.
    if digit_shift == 0:
        return floor_divide_by_power_of_base(x, word_shift)

    # Drop the low `word_shift` words via memcpy, then sub-word shift.
    var keep = len(x.words) - word_shift
    var result = BigUInt(unsafe_uninit_length=keep)
    unsafe_memcpy(
        dest=result.words.unsafe_ptr(),
        src=x.words.unsafe_ptr().unsafe_offset(word_shift),
        count=keep,
    )
    _shift_right_by_decimal_digits_inplace(result, digit_shift)
    return result^


def floor_divide_by_power_of_ten_inplace(mut x: BigUInt, n: Int):
    """In-place version of `floor_divide_by_power_of_ten`. Drops the
    `n` lowest decimal digits of `x` directly inside its `words`
    storage, avoiding an allocation when only a sub-word shift is
    needed.

    Args:
        x: The BigUInt value to divide in place.
        n: The power of 10 to divide by. Should be non-negative.

    Notes:

    No-op when `n <= 0`. When `n` is at least the current decimal
    width, `x` becomes the canonical zero (a single word holding 0).
    Delegates to `floor_divide_by_power_of_base_inplace` whenever
    `n` is a multiple of `DIGITS_PER_WORD`, which is the common case for
    word-aligned truncation. In debug mode, asserts that `n` is non-negative.
    """
    debug_assert[assert_mode="none"](
        n >= 0,
        "biguint.arithmetics.floor_divide_by_power_of_ten_inplace(): ",
        "n must be non-negative but got ",
        n,
    )

    if n <= 0:
        return

    var word_shift = n // BigUInt.DIGITS_PER_WORD
    var digit_shift = n % BigUInt.DIGITS_PER_WORD

    if word_shift >= len(x.words):
        x.words.shrink(0)
        x.words.append(BigUInt.Word(0))
        return

    if digit_shift == 0:
        floor_divide_by_power_of_base_inplace(x, word_shift)
        return

    if word_shift > 0:
        # Forward shift is safe: dst index < src index, dst[i] is
        # written before src[i+1] is read.
        var keep = len(x.words) - word_shift
        # The pointer is taken once. Indexing `x.words[i]` inside the loop
        # would ask `WordList` where its storage lives on every access, and
        # the answer is a branch the compiler will not always hoist out from
        # under a store.
        var pointer = x.words.unsafe_ptr()
        for i in range(keep):
            pointer[unsafe_offset=i] = pointer[unsafe_offset=i + word_shift]
        x.words.shrink(keep)

    _shift_right_by_decimal_digits_inplace(x, digit_shift)


def _shift_right_by_decimal_digits_inplace(mut x: BigUInt, digit_shift: Int):
    """Divides `x` in place by `10^digit_shift`, where
    `1 <= digit_shift < DIGITS_PER_WORD`. Assumes any whole-word shift has
    already been applied; this only performs the sub-word digit shift and
    canonicalises the result.
    """
    debug_assert[assert_mode="none"](
        digit_shift >= 1 and digit_shift < BigUInt.DIGITS_PER_WORD,
        (
            "biguint.arithmetics._shift_right_by_decimal_digits_inplace(): "
            "digit_shift must be below DIGITS_PER_WORD"
        ),
    )
    var divisor = BigUInt.Word(1)
    for _ in range(digit_shift):
        divisor *= 10
    var power_of_carry = BigUInt.BASE // divisor
    var carry = BigUInt.Word(0)
    var pointer = x.words.unsafe_ptr()
    for i in range(len(x.words) - 1, -1, -1):
        var word = pointer[unsafe_offset=i]
        var quot = word // divisor
        var rem = word % divisor
        pointer[unsafe_offset=i] = quot + carry * power_of_carry
        carry = rem
    x.remove_leading_empty_words()


def floor_modulo_by_power_of_ten(x: BigUInt, n: Int) -> BigUInt:
    """Returns `x % 10^n` (n >= 0), which is the last n digits of the number.

    Args:
        x: The BigUInt value to take the remainder of.
        n: The power of 10 to take the remainder by. Should be non-negative.

    Returns:
        A new BigUInt holding the low n decimal digits of x.

    Notes:

    The companion of `floor_divide_by_power_of_ten()`: that one drops the low
    n digits, this one keeps them.
    """
    debug_assert[assert_mode="none"](
        n >= 0,
        (
            "biguint.arithmetics.floor_modulo_by_power_of_ten(): n must be"
            " non-negative but got "
        ),
        n,
    )

    if n <= 0:
        return BigUInt.zero()

    var word_count = n // BigUInt.DIGITS_PER_WORD
    var digit_count = n % BigUInt.DIGITS_PER_WORD

    # Asking for more digits than the number has keeps all of them.
    if word_count >= len(x.words):
        return x.copy()

    # A whole number of words is a straight prefix of the buffer.
    if digit_count == 0:
        var result = BigUInt(unsafe_uninit_length=word_count)
        unsafe_memcpy(
            dest=result.words.unsafe_ptr(),
            src=x.words.unsafe_ptr(),
            count=word_count,
        )
        result.remove_leading_empty_words()
        return result^

    # Otherwise the top kept word is a partial one: 10^digit_count of it.
    var modulus = BigUInt.Word(1)
    for _ in range(digit_count):
        modulus *= 10

    var result = BigUInt(unsafe_uninit_length=word_count + 1)
    unsafe_memcpy(
        dest=result.words.unsafe_ptr(),
        src=x.words.unsafe_ptr(),
        count=word_count,
    )
    result.words[word_count] = x.words[word_count] % modulus
    result.remove_leading_empty_words()
    return result^


def floor_divide_by_power_of_base(x: BigUInt, n: Int) -> BigUInt:
    """Floor divides a BigUInt by `BASE^n` (n>=0).
    This function is equivalent to removing the last n words of the number.

    Args:
        x: The BigUInt value to divide.
        n: The power of `BASE` to divide by. Should be non-negative.

    Returns:
        A new BigUInt containing the result of the division.

    Notes:

    In non-debug model, if n is less than or equal to 0, the function returns x
    unchanged. In debug mode, it asserts that n is non-negative.
    """
    # Message in pieces, not concatenated -- see `floor_divide_by_power_of_ten()`.
    debug_assert[assert_mode="none"](
        n >= 0,
        (
            "biguint.arithmetics.floor_divide_by_power_of_base(): n must be"
            " non-negative but got "
        ),
        n,
    )

    if n <= 0:
        return x.copy()

    var n_words_of_result = len(x.words) - n
    if n_words_of_result <= 0:
        # If we need to drop more words than exists, result is zero
        return BigUInt.zero()
    else:
        var result = BigUInt(unsafe_uninit_length=n_words_of_result)
        unsafe_memcpy(
            dest=result.words.unsafe_ptr(),
            src=x.words.unsafe_ptr().unsafe_offset(n),
            count=n_words_of_result,
        )
        return result^


def floor_divide_by_power_of_base_inplace(mut x: BigUInt, n: Int):
    """In-place version of `floor_divide_by_power_of_base`. Drops
    the `n` lowest words of `x` directly inside its `words`
    storage, avoiding an allocation.

    Args:
        x: The BigUInt value to divide in place.
        n: The power of `BASE` to divide by. Should be non-negative.

    Notes:

    No-op when `n <= 0`. When `n` is at least the current word count,
    `x` becomes the canonical zero (a single word holding 0). In
    debug mode, asserts that `n` is non-negative.
    """
    # Message in pieces, not concatenated -- see `floor_divide_by_power_of_ten()`.
    debug_assert[assert_mode="none"](
        n >= 0,
        (
            "biguint.arithmetics.floor_divide_by_power_of_base_inplace(): n"
            " must be non-negative but got "
        ),
        n,
    )

    if n <= 0:
        return

    var keep = len(x.words) - n
    if keep <= 0:
        x.words.shrink(0)
        x.words.append(BigUInt.Word(0))
        return

    # Forward shift is safe: dst index < src index, dst[i] is written
    # before src[i+1] is read.
    for i in range(keep):
        x.words[i] = x.words[i + n]
    x.words.shrink(keep)


# FAST RUCURSIVE DIVISION ALGORITHM
# =============================== #
# The following functions implement the Burnikel-Ziegler algorithm.
#
# floor_divide_burnikel_ziegler
# floor_divide_two_by_one
# floor_divide_three_by_two
# floor_divide_three_by_two_words
# floor_divide_four_by_two_words
#
# Yuhao Zhu:
# I tried to write this implementation based on the research report
# "Fast Recursive Division" by Christoph Burnikel and Joachim Ziegler.
# MPI-I-98-1-022, October 1998.
# The paper is mainly based on 2^k-based integers, and therefore, some tricks
# cannot be applied to 10^k-based integers. For example, when normalizing the
# divisor to let its most significant word be at least BASE//2, we cannot simply
# shift the bits until the most significant bit is 1.
# TODO: Some optimization needs to be done in future to
# - avoid unnecessary memory allocations and copies


def floor_divide_burnikel_ziegler(
    a: BigUInt, b: BigUInt, cut_off: Int
) raises -> BigUInt:
    """Divides BigUInt using the Burnikel-Ziegler algorithm.

    Args:
        a: The dividend.
        b: The divisor.
        cut_off: The cutoff value for the number of words in the divisor to use
            the schoolbook division algorithm. It also determines the size of
            the blocks used in the recursive division algorithm.

    Returns:
        The quotient of `a` divided by `b`.

    Raises:
        Error: If an arithmetic error occurs during computation.
    """
    var remainder = BigUInt.zero_with_capacity(4)
    return floor_divide_modulo_burnikel_ziegler(a, b, cut_off, remainder)


def floor_divide_modulo_burnikel_ziegler(
    a: BigUInt, b: BigUInt, cut_off: Int, mut remainder: BigUInt
) raises -> BigUInt:
    """Divides BigUInt using the Burnikel-Ziegler algorithm, keeping the
    remainder.

    Args:
        a: The dividend.
        b: The divisor.
        cut_off: The cutoff value for the number of words in the divisor to use
            the schoolbook division algorithm. It also determines the size of
            the blocks used in the recursive division algorithm.
        remainder: Set to `a % b` on return.

    Returns:
        The quotient of `a` divided by `b`.

    Raises:
        Error: If an arithmetic error occurs during computation.

    Notes:

    The recursion already carries the remainder from block to block in `z`, so
    the only work this adds over the quotient-only form is undoing the
    normalization on the way out. Callers that want only the quotient go
    through `floor_divide_burnikel_ziegler()`.
    """

    var BLOCK_SIZE_OF_WORDS = cut_off

    # STEP 1:
    # Normalize the divisor b to n words so that
    # (1) it is of the form j*2^k and
    # (2) the most significant word is at least `BASE_HALF`.

    var normalized_b = b.copy()
    var normalized_a = a.copy()
    var ndigits_to_shift: Int

    if normalized_b.words[len(normalized_b.words) - 1] < BigUInt.BASE_HALF:
        ndigits_to_shift = calculate_ndigits_for_normalization(
            normalized_b.words[len(normalized_b.words) - 1]
        )
    else:
        ndigits_to_shift = 0

    # The divisor is padded to n = j * 2^k words, where 2^k is the smallest
    # power of two that brings the block size j down to BLOCK_SIZE_OF_WORDS.
    # k is the depth of the recursion: halving n stays even all the way down
    # to j, which is what the recursion needs, since it drops to schoolbook
    # the moment it is handed an odd block size.
    #
    # j is derived from the divisor rather than pinned at BLOCK_SIZE_OF_WORDS.
    # Pinning it rounds n up to a multiple of 2^k * BLOCK_SIZE_OF_WORDS, which
    # for a 5 556-word divisor means padding to 8 192 - both operands carry
    # nearly 50% dead words through every level of the recursion. Deriving j
    # pads the same divisor to 5 632.
    var depth = 0
    while math.ceildiv(len(normalized_b.words), 1 << depth) > (
        BLOCK_SIZE_OF_WORDS
    ):
        depth += 1
    var n = math.ceildiv(len(normalized_b.words), 1 << depth) * (1 << depth)

    var n_digits_to_scale_up = (
        n - len(normalized_b.words)
    ) * BigUInt.DIGITS_PER_WORD + ndigits_to_shift

    multiply_by_power_of_ten_inplace(normalized_b, n_digits_to_scale_up)
    multiply_by_power_of_ten_inplace(normalized_a, n_digits_to_scale_up)

    # The digit shift lands the top word in `[BASE / 10, BASE)`, and
    # Burnikel-Ziegler needs `[BASE_HALF, BASE)`. Scaling by
    # `floor(BASE_MAX / msw)` closes the rest of the gap, and does it for any
    # base: the product is at most `BASE_MAX`, and one more multiple would
    # exceed it, so `msw * gap_ratio > BASE_MAX - msw >= BASE_HALF - 1`
    # whenever `msw <= BASE_HALF`. Above that the ratio is 1 and there is
    # nothing to do.
    #
    # This used to branch on `msw >= 250_000_000` -- `BASE / 4` written out --
    # and take `gap_ratio = 2`. At eighteen digits a word that test is true
    # for every normalised `msw`, so the ratio was always 2 and a top word
    # below `BASE / 4` came out still under `BASE_HALF`.
    var gap_ratio = (
        BigUInt.Word(BigUInt.BASE_MAX)
        // normalized_b.words[len(normalized_b.words) - 1]
    )

    if gap_ratio >= 2:
        multiply_by_word_inplace(normalized_b, gap_ratio)
        multiply_by_word_inplace(normalized_a, gap_ratio)

    # STEP 2: Split the normalized a into blocks of size n.
    # t is the number of blocks in the dividend.
    var t = math.ceildiv(len(normalized_a.words), n)
    if len(normalized_a.words) == t * n:
        # If the number of words in the dividend is already a multiple of n
        # We check if the most significant word is >= `BASE_HALF`.
        # If it is, we need to add one more block to the dividend.
        # This ensures that the most significant word of the dividend
        # is smaller than `BASE_HALF`.
        # In this sense, the first 2-by-1 division will generate a quotient
        # of either 0 or 1, which would otherwise exceed n-word capacity.
        #
        # The length tested is `normalized_a`'s, not `a`'s. `t` counts blocks
        # of the normalized dividend, and normalization scales it by the same
        # power of ten as the divisor, so it is usually the longer of the two:
        # `len(a.words)` and `t * n` could only agree by accident. `BigInt`'s
        # copy of this algorithm has always tested the normalized length.
        if normalized_a.words[len(normalized_a.words) - 1] >= BigUInt.BASE_HALF:
            t += 1

    var z = BigUInt.zero()  # Remainder of the division
    var q = BigUInt.zero()
    var q_i: BigUInt

    for i in range(t - 2, -1, -1):
        # The below function is the recursive division algorithm.
        # var q_i, r = floor_divide_two_by_one(z, normalized_b, n, cut_off)

        # The below function is the recursive division algorithm but works
        # with slices of the dividend and divisor.
        # Save the remainder in z as it will be carried over to the next
        # iteration and we can do some inplace operations.

        if i == t - 2:
            # The first iteration, we can use the slize of normalized_a
            q = floor_divide_slices_two_by_one(
                normalized_a,
                normalized_b,
                bounds_a=((t - 2) * n, len(normalized_a.words)),
                bounds_b=(0, len(normalized_b.words)),
                n=n,
                cut_off=cut_off,
                remainder=z,
            )
        else:
            # `z` is both the dividend and where the next remainder goes, and
            # it cannot be borrowed two ways at once, so the new remainder
            # lands in its own value and is moved back over `z`.
            var next_z = BigUInt.zero()
            q_i = floor_divide_slices_two_by_one(
                z,
                normalized_b,
                bounds_a=(0, len(z.words)),
                bounds_b=(0, len(normalized_b.words)),
                n=n,
                cut_off=cut_off,
                remainder=next_z,
            )
            z = next_z^
            multiply_by_power_of_base_inplace(q, n)
            q += q_i

        if i > 0:
            multiply_by_power_of_base_inplace(z, n)
            # z = r + a[(i - 1) * n : i * n]
            add_by_slice_inplace(
                z,
                normalized_a,
                bounds_y=((i - 1) * n, i * n),
            )

    # `z` is the remainder of the *normalized* division. The operands were
    # scaled by 10^n_digits_to_scale_up and then by gap_ratio, so the remainder
    # carries both factors and both divide out exactly.
    if gap_ratio >= 2:
        floor_divide_by_word_inplace(z, gap_ratio)
    if n_digits_to_scale_up > 0:
        floor_divide_by_power_of_ten_inplace(z, n_digits_to_scale_up)
    z.remove_leading_empty_words()
    remainder = z^

    q.remove_leading_empty_words()
    return q^


# ===----------------------------------------------------------------------=== #
# Legacy Burnikel-Ziegler recursion (hand-written, kept for reference)
#
# `floor_divide_two_by_one()` and `floor_divide_three_by_two()` below are the
# original hand-written pair, and they call only each other -- nothing outside
# this block reaches them. The live path is the `_slices_` pair, which does the
# same recursion over index bounds instead of materialising `a0`, `a1`, `a2`,
# `a3`, `b0`, `b1` as separate values, and hands its remainder back through an
# argument instead of a tuple.
#
# They are kept deliberately: they read as the algorithm is written down, which
# makes them the clearest statement of what the `_slices_` pair is doing, and
# they are the reference the optimized form was checked against.
#
# Do not copy the base case here into new code. It calls the quotient-only
# `floor_divide_schoolbook()` and then rebuilds the remainder as `a - q * b`,
# which is a full multiply that the division had already done the work for.
# The live pair took that out on 20260826 and it was worth 12% of a
# 1000-digit division.
# ===----------------------------------------------------------------------=== #


def floor_divide_two_by_one(
    a: BigUInt, b: BigUInt, n: Int, cut_off: Int
) raises -> Tuple[BigUInt, BigUInt]:
    """Divides a BigUInt by another BigUInt using a recursive approach.
    The divisor has n words and the dividend has 2n words.

    Args:
        a: The dividend as a BigUInt.
        b: The divisor as a BigUInt. The most significant word must be at least
           `BASE_HALF`.
        n: The number of words in the divisor.
        cut_off: The minimum number of words for the recursive division.

    Returns:
        A tuple containing the quotient and the remainder as BigUInt.

    Notes:

    You need to ensure that n is even to continue with the algorithm.
    Otherwise, it will use the schoolbook division algorithm.

    Raises:
        Error: If an arithmetic error occurs during computation.
    """
    debug_assert[assert_mode="none"](
        b.words[len(b.words) - 1] >= BigUInt.BASE_HALF,
        "b[-1] must be at least half the base",
    )

    if (n & 1 == 1) or (n <= cut_off):
        # Legacy: rebuilding the remainder with a multiply. See the block
        # comment above -- the live `_slices_` pair takes it from schoolbook.
        var q = floor_divide_schoolbook(a, b)
        var r = a - q * b
        return (q^, r^)

    else:
        var a0 = BigUInt.from_slice(a, bounds=(0, n // 2))
        var a1 = BigUInt.from_slice(a, bounds=(n // 2, n))
        var a2 = BigUInt.from_slice(a, bounds=(n, n + n // 2))
        var a3 = BigUInt.from_slice(a, bounds=(n + n // 2, n + n))

        var b0 = BigUInt.from_slice(b, bounds=(0, n // 2))
        var b1 = BigUInt.from_slice(b, bounds=(n // 2, n))

        # TODO: Refine this when Mojo support move values of unpacked tuples
        var _tuple = floor_divide_three_by_two(
            a3, a2, a1, b1, b0, n // 2, cut_off
        )  # q is q1
        var q = _tuple[0].copy()
        ref r = _tuple[1]

        var r0 = BigUInt.from_slice(r, bounds=(0, n // 2))
        var r1 = BigUInt.from_slice(r, bounds=(n // 2, n))
        # TODO: Refine this when Mojo support move values of unpacked tuples
        _tuple = floor_divide_three_by_two(r1, r0, a0, b1, b0, n // 2, cut_off)
        ref q0 = _tuple[0]  # q0
        var s = _tuple[1].copy()  # s is the final remainder

        # q -> q1q0
        multiply_by_power_of_base_inplace(q, n // 2)
        q += q0

        return (q^, s^)


def floor_divide_three_by_two(
    a2: BigUInt,
    a1: BigUInt,
    a0: BigUInt,
    b1: BigUInt,
    b0: BigUInt,
    n: Int,
    cut_off: Int,
) raises -> Tuple[BigUInt, BigUInt]:
    """Divides a 3-part number by a 2-part number.

    Args:
        a2: The most significant part of the dividend.
        a1: The middle part of the dividend.
        a0: The least significant part of the dividend.
        b1: The most significant part of the divisor.
        b0: The least significant part of the divisor.
        n: The number of part in the divisor.
        cut_off: The minimum number of part for the recursive division.

    Returns:
        A tuple containing the quotient and the remainder as BigUInt.

    Notes:

    a is a BigUInt with 3n words and b is a BigUInt with 2n words.

    Raises:
        Error: If an arithmetic error occurs during computation.
    """

    var a2a1: BigUInt
    if a2.is_zero():
        debug_assert[assert_mode="none"](
            len(a2.words) == 1,
            "floor_divide_three_by_two(): leading zero words",
        )
        a2a1 = a1.copy()
    else:
        a2a1 = a2.copy()
        multiply_by_power_of_base_inplace(a2a1, n)
        a2a1 += a1
    # TODO: Refine this when Mojo support move values of unpacked tuples
    var _tuple = floor_divide_two_by_one(a2a1, b1, n, cut_off)
    var q = _tuple[0].copy()
    ref c = _tuple[1]  # c is the carry
    var d = q * b0
    multiply_by_power_of_base_inplace(c, n)
    var r = c + a0

    if r < d:
        var b = b1.copy()
        multiply_by_power_of_base_inplace(b, n)
        b += b0
        q -= BigUInt.one()
        r += b
        if r < d:
            q -= BigUInt.one()
            r += b

    r -= d
    return (q^, r^)


# Yuhao ZHU:
# The following two functions are OPTIMIZED versions of the
# `floor_divide_two_by_one` and `floor_divide_three_by_two` functions.
# They record the boundaries of the slices of the dividend and divisor
# to avoid unnecessary recursive slicing and copying of the BigUInt objects.
def floor_divide_slices_two_by_one(
    a: BigUInt,
    b: BigUInt,
    bounds_a: Tuple[Int, Int],
    bounds_b: Tuple[Int, Int],
    n: Int,
    cut_off: Int,
    mut remainder: BigUInt,
) raises -> BigUInt:
    """Divides a BigUInt by another BigUInt using a recursive approach.
    The divisor has n words and the dividend has 2n words.

    Args:
        a: The dividend.
        b: The divisor.
        bounds_a: The range of words in the dividend to consider [start, end).
        bounds_b: The range of words in the divisor to consider [start, end).
            The most significant word must be at least `BASE_HALF`.
        n: The number of words in the divisor.
        cut_off: The minimum number of words for the recursive division.
        remainder: Set to the remainder of the division on return.

    Returns:
        The quotient of the division.

    Notes:

    The remainder comes back through an argument rather than in a tuple: a
    BigUInt cannot be moved out of a returned tuple yet
    (modular/modular#5330), so every level of this recursion used to copy the
    values it wanted to keep.

    You need to ensure that n is even to continue with the algorithm.
    Otherwise, it will use the schoolbook division algorithm.

    a_slice ~ [a0, a1, a2, a3] ~ a3a2a1a0 is a BigUInt with 2n words (n//2 per part).\\
    b_slice ~ [b0, b1] ~ b1b0 is a BigUInt with n words (n//2 per part).\\
    bounds_a3 = (bounds_a[0] + n + n // 2, bounds_a[0] + 2 * n)\\
    bounds_a2 = (bounds_a[0] + n, bounds_a[0] + n + n // 2)\\
    bounds_a1 = (bounds_a[0] + n // 2, bounds_a[0] + n)\\
    bounds_a0 = (bounds_a[0], bounds_a[0] + n // 2)\\
    bounds_b1 = (bounds_b[0] + n // 2, bounds_b[0] + n)\\
    bounds_b0 = (bounds_b[0], bounds_b[0] + n // 2).

    Raises:
        Error: If an arithmetic error occurs during computation.
    """

    debug_assert[assert_mode="none"](
        b.words[len(b.words) - 1] >= BigUInt.BASE_HALF,
        (
            "floor_divide_slices_two_by_one(): b[-1] must be at least"
            " half the base"
        ),
    )

    if (n & 1 == 1) or (n <= cut_off):
        debug_assert[assert_mode="none"](
            (n <= cut_off) or (n & 1 == 0),
            "floor_divide_slices_two_by_one(): ",
            "n must be even by design but got ",
            n,
        )
        # If n is odd or less than the cutoff, use the schoolbook division
        # algorithm.
        #
        # Schoolbook already has the remainder when it finishes -- Knuth D
        # leaves it in the running window -- so take it. This used to call the
        # quotient-only form and then rebuild the remainder as
        # `a - q * b`, which is a full n-by-n multiply per base case, and the
        # recursion reaches this base case many times.
        var a_slice = BigUInt.from_slice(a, bounds_a)
        var b_slice = BigUInt.from_slice(b, bounds_b)
        return floor_divide_modulo_schoolbook(a_slice, b_slice, remainder)

    elif (bounds_a[0] + n + n // 2 >= bounds_a[1]) or a.is_zero_in_bounds(
        bounds=(bounds_a[0] + n + n // 2, bounds_a[1])
    ):
        # If a3 is empty or zero
        # We just need to use three-by-two division once: a2a1a0 // b1b0
        # Note that the condition must be short-circuited to avoid slicing
        # an empty BigUInt.
        return floor_divide_slices_three_by_two(
            a, b, bounds_a, bounds_b, n // 2, cut_off, remainder
        )

    else:
        var bounds_a1a3 = (bounds_a[0] + n // 2, bounds_a[1])

        # We use the most significant three parts of the dividend
        # a3a2a1 // b1b0
        var r = BigUInt.zero()  # r is the carry
        var q = floor_divide_slices_three_by_two(
            a, b, bounds_a1a3, bounds_b, n // 2, cut_off, r
        )  # q is q1

        multiply_by_power_of_base_inplace(r, n // 2)
        add_by_slice_inplace(r, a, (bounds_a[0], bounds_a[0] + n // 2))
        # The final remainder is written straight into the caller's argument.
        var q0 = floor_divide_slices_three_by_two(
            r, b, (0, len(r.words)), bounds_b, n // 2, cut_off, remainder
        )

        # q -> q1q0
        multiply_by_power_of_base_inplace(q, n // 2)
        q += q0

        return q^


def floor_divide_slices_three_by_two(
    a: BigUInt,
    b: BigUInt,
    bounds_a: Tuple[Int, Int],
    bounds_b: Tuple[Int, Int],
    n: Int,
    cut_off: Int,
    mut remainder: BigUInt,
) raises -> BigUInt:
    """Divides a 3n-word BigUInt slice by a 2n-word BigUInt slice.

    Args:
        a: The dividend.
        b: The divisor.
        bounds_a: The range of words in the dividend to consider [start, end).
        bounds_b: The range of words in the divisor to consider [start, end).
        n: The number of words in each part of the dividend and divisor.
        cut_off: The minimum number of words for the recursive division.
        remainder: Set to the remainder of the division on return.

    Returns:
        The quotient of the division.

    Notes:

    a_slice ~ [a0, a1, a2] ~ a2a1a0 is a BigUInt with 3n words.\\
    b_slice ~ [b0, b1] ~ b1b0 is a BigUInt with 2n words.\\
    bounds_a2 = (bounds_a[0] + 2 * n, bounds_a[0] + 3 * n)\\
    bounds_a1 = (bounds_a[0] + n, bounds_a[0] + 2 * n)\\
    bounds_a0 = (bounds_a[0], bounds_a[0] + n)\\
    bounds_b1 = (bounds_b[0] + n, bounds_b[0] + 2 * n)\\
    bounds_b0 = (bounds_b[0], bounds_b[0] + n).

    Raises:
        Error: If an arithmetic error occurs during computation.
    """

    # SPECIAL CASE:
    # If a2 is empty or zero, than it becomes a2a1 // b1b0
    # Because the most significant word of b1 is at least `BASE_HALF`,
    # The quotient will be either 1 or 0.
    if bounds_a[0] + 2 * n == bounds_a[1]:
        debug_assert[assert_mode="none"](
            a.words[bounds_a[1] - 1] != 0,
            "the most significant word of a must not be zero",
        )
        var a_slice = BigUInt.from_slice(a, (bounds_a[0], bounds_a[1]))
        var b_slice = BigUInt.from_slice(b, bounds_b)
        if a_slice.compare(b_slice) >= 0:
            subtract_inplace(a_slice, b_slice)
            remainder = a_slice^
            return BigUInt.one()
        else:
            remainder = a_slice^
            return BigUInt.zero()

    # Now we can safely assume that a2 is not empty.
    var bounds_a0 = (bounds_a[0], bounds_a[0] + n)
    var bounds_a2a1 = (bounds_a[0] + n, bounds_a[1])
    var bounds_b1 = (bounds_b[0] + n, bounds_b[1])
    var bounds_b0 = (bounds_b[0], bounds_b[0] + n)

    var c = BigUInt.zero()  # c is the carry
    var q = floor_divide_slices_two_by_one(
        a, b, bounds_a2a1, bounds_b1, n, cut_off, c
    )

    var d = multiply_slices(q, b, (0, len(q.words)), bounds_b0)
    multiply_by_power_of_base_inplace(c, n)
    var r = add_slices(c, a, bounds_x=(0, len(c.words)), bounds_y=bounds_a0)

    if r < d:
        q -= BigUInt.one()
        # r = r + b
        add_by_slice_inplace(r, b, bounds_y=bounds_b)
        if r < d:
            q -= BigUInt.one()
            # r = r + b
            add_by_slice_inplace(r, b, bounds_y=bounds_b)

    r -= d
    q.remove_leading_empty_words()
    r.remove_leading_empty_words()
    remainder = r^
    return q^


# Yuhao ZHU:
# The following functions are most granular implementations of the
# Burnikel-Ziegler algorithm, which divide a 3-word number by a 2-word number
# and a 4-word number by a 2-word number, respectively.
# They are not used because they are too granular and not efficient.
# When then size of the divisor is less than N, we switch to the schoolbook
# division algorithm.
# However, these functions are still valid and can be used if needed.
def floor_divide_three_by_two_words(
    a2: BigUInt.Word,
    a1: BigUInt.Word,
    a0: BigUInt.Word,
    b1: BigUInt.Word,
    b0: BigUInt.Word,
) raises -> Tuple[BigUInt.Word, BigUInt.Word, BigUInt.Word]:
    """Divides a 3-word number by a 2-word number.
    b1 must be at least `BASE_HALF`.

    Args:
        a2: The most significant word of the dividend.
        a1: The middle word of the dividend.
        a0: The least significant word of the dividend.
        b1: The most significant word of the divisor.
        b0: The least significant word of the divisor.

    Returns:
        A tuple containing
        (1) the quotient (as UInt32)
        (2) the most significant word of the remainder (as UInt32)
        (3) the least significant word of the remainder (as UInt32).

    Raises:
        ValueError: If b1 < `BASE_HALF`.

    Notes:

    a = a2 * BASE^2 + a1 * BASE + a0.
    b = b1 * BASE + b0.
    """
    if b1 < BigUInt.BASE_HALF:
        raise ValueError(
            message="b1 must be at least half the base",
            function="floor_divide_three_by_two_words()",
        )

    # Every intermediate here is two words wide, which was 64 bits at nine
    # digits a word and is 128 at eighteen. The literal base is gone with it.
    comptime BASE = UInt128(BigUInt.BASE)

    var a2a1 = UInt128(a2) * BASE + UInt128(a1)
    var b1_wide = UInt128(b1)

    var q = a2a1 // b1_wide
    var c = a2a1 - q * b1_wide
    var d = q * UInt128(b0)
    var r = c * BASE + UInt128(a0)

    if r < d:
        var b = b1_wide * BASE + UInt128(b0)
        q -= 1
        r += b
        if r < d:
            q -= 1
            r += b

    r -= d
    var r1 = BigUInt.Word(r // BASE)
    var r0 = BigUInt.Word(r % BASE)

    return (BigUInt.Word(q), r1, r0)


def floor_divide_four_by_two_words(
    a3: BigUInt.Word,
    a2: BigUInt.Word,
    a1: BigUInt.Word,
    a0: BigUInt.Word,
    b1: BigUInt.Word,
    b0: BigUInt.Word,
) raises -> Tuple[BigUInt.Word, BigUInt.Word, BigUInt.Word, BigUInt.Word]:
    """Divides a 4-word number by a 2-word number.

    Args:
        a3: The most significant word of the dividend.
        a2: The second most significant word of the dividend.
        a1: The second least significant word of the dividend.
        a0: The least significant word of the dividend.
        b1: The most significant word of the divisor.
        b0: The least significant word of the divisor.

    Returns:
        A tuple containing
        (1) the most significant word of the quotient (as BigUInt.Word)
        (2) the least significant word of the quotient (as BigUInt.Word)
        (3) the most significant word of the remainder (as BigUInt.Word)
        (4) the least significant word of the remainder (as BigUInt.Word).

    Raises:
        ValueError: If b1 < `BASE_HALF` or a >= b * 10^18.
    """

    if b1 < BigUInt.BASE_HALF:
        raise ValueError(
            message="b1 must be at least half the base",
            function="floor_divide_four_by_two_words()",
        )
    if a3 > b1:
        raise ValueError(
            message="a must be less than b * 10^18",
            function="floor_divide_four_by_two_words()",
        )
    elif a3 == b1:
        if a2 > b0:
            raise ValueError(
                message="a must be less than b * 10^18",
                function="floor_divide_four_by_two_words()",
            )
        elif a2 == b0:
            if a1 > 0:
                raise ValueError(
                    message="a must be less than b * 10^18",
                    function="floor_divide_four_by_two_words()",
                )
            elif a1 == 0:
                if a0 >= 0:
                    raise ValueError(
                        message="a must be less than b * 10^18",
                        function="floor_divide_four_by_two_words()",
                    )

    var q1, r1, r0 = floor_divide_three_by_two_words(a3, a2, a1, b1, b0)
    var q0, s1, s0 = floor_divide_three_by_two_words(r1, r0, a0, b1, b0)
    return (q1, q0, s1, s0)


@always_inline
def truncate_divide(x1: BigUInt, x2: BigUInt) raises -> BigUInt:
    """Returns the quotient of two BigUInt numbers, truncating toward zero.
    It is equal to floored division for unsigned numbers.
    See `floor_divide` for more details.

    Args:
        x1: The dividend.
        x2: The divisor.

    Returns:
        The quotient of `x1` divided by `x2`.

    Raises:
        ZeroDivisionError: If the divisor is zero.
    """
    return floor_divide(x1, x2)


def ceil_divide(x1: BigUInt, x2: BigUInt) raises -> BigUInt:
    """Returns the quotient of two BigUInt numbers, rounding up.

    Args:
        x1: The dividend.
        x2: The divisor.

    Returns:
        The quotient of x1 / x2, rounded up.

    Raises:
        ZeroDivisionError: If the divisor is zero.
    """

    # CASE: Division by zero
    if x2.is_zero():
        debug_assert[assert_mode="none"](
            len(x2.words) == 1,
            "ceil_divide(): leading zero words",
        )
        raise ZeroDivisionError(
            message="Division by zero", function="ceil_divide()"
        )

    # Apply floor division and check if there is a remainder
    var quotient = floor_divide(x1, x2)
    if quotient * x2 < x1:
        add_by_word_inplace(quotient, 1)
    return quotient^


def floor_modulo(x1: BigUInt, x2: BigUInt) raises -> BigUInt:
    """Returns the remainder of two BigUInt numbers, truncating toward zero.
    The remainder has the same sign as the dividend and satisfies:
    x1 = floor_divide(x1, x2) * x2 + floor_modulo(x1, x2).

    Args:
        x1: The dividend.
        x2: The divisor.

    Returns:
        The remainder of x1 being divided by x2.

    Raises:
        ZeroDivisionError: If the divisor is zero.

    Notes:
        It is equal to floored modulo for positive numbers.

        The division itself produces the remainder, so this drops the quotient
        rather than computing `x1 - x2 * quotient` after the fact. All the
        special cases it used to test first - zero divisor, zero dividend,
        divisor of one, dividend below divisor - are the first branches of
        `floor_divide_modulo()`, so they are still taken, just not twice.
    """
    var remainder = BigUInt.zero_with_capacity(4)
    try:
        _ = floor_divide_modulo(x1, x2, remainder)
    except e:
        raise ZeroDivisionError(
            message="See the above exception.",
            function="floor_modulo()",
            previous_error=e^,
        )
    return remainder^


@always_inline
def truncate_modulo(x1: BigUInt, x2: BigUInt) raises -> BigUInt:
    """Returns the remainder of two BigUInt numbers, truncating toward zero.
    It is equal to floored modulo for unsigned numbers.
    See `floor_modulo` for more details.

    Args:
        x1: The dividend.
        x2: The divisor.

    Returns:
        The remainder of x1 being divided by x2.

    Raises:
        ZeroDivisionError: If the divisor is zero.
    """
    try:
        return floor_modulo(x1, x2)
    except e:
        raise e^


def ceil_modulo(x1: BigUInt, x2: BigUInt) raises -> BigUInt:
    """Returns the remainder of two BigUInt numbers, rounding up.
    The remainder has the same sign as the dividend and satisfies:
    x1 = ceil_divide(x1, x2) * x2 + ceil_modulo(x1, x2).

    Args:
        x1: The dividend.
        x2: The divisor.

    Returns:
        The remainder of x1 being ceil-divided by x2.

    Raises:
        ZeroDivisionError: If the divisor is zero.
    """
    var remainder = BigUInt.zero_with_capacity(4)
    try:
        _ = floor_divide_modulo(x1, x2, remainder)
    except e:
        raise ZeroDivisionError(
            message="See the above exception.",
            function="ceil_modulo()",
            previous_error=e^,
        )

    # Rounding the quotient up instead of down moves the remainder to the far
    # side of the divisor. An exact division has nothing to move.
    if remainder.is_zero():
        debug_assert[assert_mode="none"](
            len(remainder.words) == 1, "ceil_modulo(): leading zero words"
        )
        return BigUInt.zero()
    return subtract(x2, remainder)


def floor_divide_modulo(
    x: BigUInt, y: BigUInt, mut remainder: BigUInt
) raises -> BigUInt:
    """Returns the quotient of two numbers, and sets the remainder.

    Args:
        x: The dividend.
        y: The divisor.
        remainder: Set to `x % y` on return.

    Returns:
        The quotient of x / y, truncated toward zero.

    Raises:
        ZeroDivisionError: If the divisor is zero.

    Notes:

    This mirrors the branches of `floor_divide()` one for one. Every one of
    them already computes the remainder on the way to the quotient - the
    scalar paths leave it in a carry, Knuth D leaves it in its running window,
    and Burnikel-Ziegler carries it from block to block - so this costs
    nothing over the quotient alone. The older version called `floor_divide()`
    and then rebuilt the remainder as `x - y * quotient`, a full
    multiplication and subtraction for something already in hand.
    """

    debug_assert[assert_mode="none"](
        (len(x.words) != 0) and (len(y.words) != 0),
        "biguint.arithmetics.floor_divide_modulo(): BigUInt x ",
        x,
        " and / or ",
        y,
        " is uninitialized!",
    )

    # CASE: y is zero
    if y.is_zero():
        raise ZeroDivisionError(
            function="floor_divide_modulo()",
            message="Division by zero",
        )

    # CASE: Dividend is zero
    if x.is_zero():
        overwrite_with_word(remainder, 0)
        return BigUInt.zero()

    # CASE: x is not greater than y
    var comparison_result: Int8 = x.compare(y)
    # SUB-CASE: dividend < divisor
    if comparison_result < 0:
        remainder = x.copy()  # The whole dividend is left over
        return BigUInt.zero()
    # SUB-CASE: dividend == divisor
    if comparison_result == 0:
        overwrite_with_word(remainder, 0)
        return BigUInt.one()

    # CASE: y is single word
    if len(y.words) == 1:
        # SUB-CASE: Division by one
        if y.words[0] == 1:
            overwrite_with_word(remainder, 0)
            return x.copy()
        # SUB-CASE: Single word // single word
        if len(x.words) == 1:
            overwrite_with_word(remainder, x.words[0] % y.words[0])
            return BigUInt.from_word_unsafe(x.words[0] // y.words[0])
        # SUB-CASE: Divisor is single word (<= 9 digits)
        var word_remainder = BigUInt.Word(0)
        var quotient = floor_divide_modulo_by_word(
            x, y.words[0], word_remainder
        )
        overwrite_with_word(remainder, word_remainder)
        return quotient^

    # A two-word divisor used to take a `UInt64` shortcut. Two words are now
    # `10^36`, which no `UInt64` holds, so it goes through Knuth D with
    # everything else. A single word still fits, and that path is above.

    # See `floor_divide()` for why three- and four-word divisors no longer
    # take a `UInt128` shortcut here.

    # CASE: Divisor is 10^n
    if y.is_power_of_10():
        var n = y.number_of_trailing_zeros()
        remainder = floor_modulo_by_power_of_ten(x, n)
        return floor_divide_by_power_of_ten(x, n)

    # CASE: Division of small numbers
    if (len(x.words) <= CUTOFF_BURNIKEL_ZIEGLER * 2) and (
        len(y.words) <= CUTOFF_BURNIKEL_ZIEGLER
    ):
        var ndigits_to_shift = calculate_ndigits_for_normalization(
            y.words[len(y.words) - 1]
        )

        if ndigits_to_shift == 0:
            return floor_divide_modulo_schoolbook(x, y, remainder)

        # Normalizing scales both operands by the same power of ten, which
        # leaves the quotient alone but scales the remainder with them. It
        # divides back out exactly.
        var normalized_x = multiply_by_power_of_ten(x, ndigits_to_shift)
        var normalized_y = multiply_by_power_of_ten(y, ndigits_to_shift)
        var quotient = floor_divide_modulo_schoolbook(
            normalized_x, normalized_y, remainder
        )
        floor_divide_by_power_of_ten_inplace(remainder, ndigits_to_shift)
        return quotient^

    # CASE: division of very, very large numbers
    return floor_divide_modulo_burnikel_ziegler(
        x, y, cut_off=BURNIKEL_ZIEGLER_BLOCK_WORDS, remainder=remainder
    )


def floor_divide_modulo(
    x1: BigUInt, x2: BigUInt
) raises -> Tuple[BigUInt, BigUInt]:
    """Returns the quotient and remainder of two numbers, truncating toward zero.

    Args:
        x1: The dividend.
        x2: The divisor.

    Returns:
        The quotient of x1 / x2, truncated toward zero and the remainder.

    Raises:
        ZeroDivisionError: If the divisor is zero.

    Notes:
        It is equal to truncated division for positive numbers.
    """

    var remainder = BigUInt.zero_with_capacity(4)
    var quotient = floor_divide_modulo(x1, x2, remainder)
    return (quotient^, remainder^)


# ===----------------------------------------------------------------------=== #
# Helper Functions
# ===----------------------------------------------------------------------=== #


def overwrite_with_word(mut x: BigUInt, value: BigUInt.Word):
    """Overwrites `x` with a single-word value, reusing its buffer.

    The remainder of a division is handed back through an argument, and that
    argument arrives holding a buffer already. Assigning a freshly built
    `BigUInt` to it would free that buffer and allocate another one, which on
    a short division is most of the cost of the division. Resizing to one word
    keeps the capacity, so this is a store.
    """
    x.words.resize(1, BigUInt.Word(0))
    x.words[0] = value


def normalize_carries_lt_2_bases(mut x: BigUInt):
    """Normalizes the values of words into valid range by carrying over.
    The initial values of the words should be in the range [0, BASE*2).

    Notes:

    If we adds two BigUInt numbers word-by-word, we may end up with
    a situation where some words are larger than BASE. This function
    normalizes the carries, ensuring that all words are within the valid range.
    It modifies the input BigUInt in-place.

    Args:
        x: The `BigUInt` to normalize, modified in place.
    """

    # Yuhao ZHU:
    # By construction, the words of x are in the range [0, BASE*2).
    # Thus, the carry can only be 0 or 1.
    var carry: BigUInt.Word = 0
    for ref word in x.words:
        if carry == 0:
            if word <= BigUInt.BASE_MAX:
                pass  # carry = 0
            else:
                word -= BigUInt.BASE
                carry = 1
        else:  # carry == 1
            if word < BigUInt.BASE_MAX:
                word += 1
                carry = 0
            else:
                word = word + 1 - BigUInt.BASE
                # carry = 1
    if carry > 0:
        # If there is still a carry, we need to add a new word
        x.words.append(BigUInt.Word(1))
    return


def power_of_10(n: Int) raises -> BigUInt:
    """Calculates 10^n efficiently for non-negative n.

    Args:
        n: The exponent, must be non-negative.

    Returns:
        A BigUInt representing 10 raised to the power of n.

    Raises:
        ValueError: If n is negative.
    """
    if n < 0:
        raise ValueError(
            function="power_of_10()",
            message="Negative exponent not supported",
        )

    if n == 0:
        return BigUInt.one()

    # Handle small powers directly
    if n < BigUInt.DIGITS_PER_WORD:
        var value: BigUInt.Word = 1
        for _ in range(n):
            value *= 10
        return BigUInt.from_word_unsafe(value)

    # For larger powers, split into whole words
    var words = n // BigUInt.DIGITS_PER_WORD
    var remainder = n % BigUInt.DIGITS_PER_WORD

    var result = BigUInt.zero()

    # Add leading zeros for the whole words below the highest one
    for _ in range(words):
        result.words.append(0)

    # Calculate partial power for the highest word
    var high_word: BigUInt.Word = 1
    for _ in range(remainder):
        high_word *= 10

    # Only add non-zero high word
    if high_word > 1:
        result.words.append(high_word)
    else:
        # Add a 1 in the next position
        result.words.append(1)

    result.assert_invariant("power_of_10")
    return result^


@always_inline
def calculate_ndigits_for_normalization(msw: BigUInt.Word) -> Int:
    """Calculates the number of digits to shift left for normalization.

    Args:
        msw: The most significant word of the number to normalize.

    Returns:
        The number of digits to shift left to normalize the number.

    Notes:

    This is a helper function for division algorithms. The normalized word
    should be as close to `BASE` as possible, so the answer is
    `DIGITS_PER_WORD - 1 - floor(log10(msw))`, and the loop below counts it.

    This used to be a hard-coded binary search over the nine decades a
    base-10^9 word has, returning 0 to 8. Nothing about its type said so, and
    at eighteen digits a word it silently under-normalised every divisor with
    more than nine digits -- which broke Burnikel-Ziegler and nothing else,
    because schoolbook tolerates a loose normalisation and BZ does not.
    """
    comptime TOP_DECADE = BigUInt.Word(BigUInt.BASE // 10)

    if msw == 0:
        return BigUInt.DIGITS_PER_WORD - 1

    var ndigits = 0
    var value = msw
    while value < TOP_DECADE:
        value *= 10
        ndigits += 1
    return ndigits
