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
Implements basic arithmetic functions for the BigInt type.

BigInt uses base-2^64 representation with UInt64 words in little-endian order.
Unlike the BigInt10 (base-10^9) type which delegates magnitude operations to
BigUInt, BigInt implements all magnitude arithmetic directly since there is
no separate unsigned counterpart.

Algorithms:
- Addition/Subtraction: Schoolbook with carry/borrow propagation (O(n)).
  Uses SIMD vectorized operations for parallel word processing.
- Multiplication: Karatsuba O(n^1.585) for large operands, with schoolbook
  O(n*m) fallback for small operands (< CUTOFF_KARATSUBA words).
  All operations use zero-copy slice bounds to avoid intermediate allocations.
- Division: Burnikel-Ziegler O(n^1.585) for large operands, with Knuth's
  Algorithm D (schoolbook O(n^2)) fallback for small operands
  (< CUTOFF_BURNIKEL_ZIEGLER words). Single-word fast path for UInt64 divisors.
"""

from std.bit import count_leading_zeros
from std.sys import is_little_endian
from std.memory import unsafe_memcpy, unsafe_memset_zero

from decimo.bigint.bigint import BigInt, Magnitude
from decimo.utility import alias_as_immutable_source
from decimo.bigint.comparison import compare_magnitudes
import decimo.bigint.ntt as bigint_ntt
from decimo.errors import ValueError, ZeroDivisionError


# Karatsuba cutoff: operands with this many words or fewer use schoolbook.
# Tuned for Apple Silicon arm64. Adjust if benchmarking shows a better value.
#
# It was 256 while a word was 32 bits, and fell to 64 with the wider word --
# which is a bigger move than the halving of the word count alone accounts
# for. Schoolbook pays twice per word product now (`MUL` plus `UMULH`, and a
# column that no longer fits one accumulator), while what Karatsuba adds on
# top is additions and shifts, and those got cheaper per bit. So the crossover
# moved down in digits as well as in words. Best of five (microseconds):
#
#     words          64     96    128    192    256    384    512    768
#     cutoff  64   1.56   3.15   5.50  10.54  17.64  33.15  54.58  102.1
#     cutoff 128   1.58   3.32   6.07  10.95  18.44  35.00  53.16  107.2
#     cutoff 256   1.51   3.34   5.97  13.35  22.54  41.68  65.77  128.0
#
# 96 ties with 64 and 48 is worse at every width above 64, so this is the
# bottom of a shallow basin rather than a peak.
comptime RADIX = UInt128(1) << 64
"""The base of the magnitude representation, where it has to be written down.

Only Knuth D needs it as a value: its quotient estimate compares against `b`
and its refinement stops there, both a word wider than the words themselves.
"""

comptime CUTOFF_KARATSUBA: Int = 64
"""The minimum number of words above which Karatsuba multiplication is used."""

# Toom-3 cutoff: operands with this many words or fewer use Karatsuba.
# Toom-3 splits into three parts and does five recursive multiplications
# instead of Karatsuba's three on halves, trading a lower exponent
# (log_3(5) = 1.465 against log_2(3) = 1.585) for a much heavier evaluation
# and interpolation step. The extra additions, the two exact divisions and
# the five sub-results only pay for themselves once the operands are large.
#
# The crossover is soft rather than sharp, and it moves every time the base
# case changes. It was 768 with a 32-bit word and is 256 with a 64-bit one,
# for the same reason `CUTOFF_KARATSUBA` fell: what Toom-3 adds is linear work
# on a magnitude that is now half as many words. Two passes, best of five
# within each (microseconds):
#
#     words           256    384    512    768   1024   1536   2048
#     cutoff 256    17.46  30.90  45.45  92.52  130.1  256.4  367.7
#     cutoff 512    16.93  31.38  54.60  99.14  149.0  255.6  393.0
#
# The sizes that separate them are 512 and 1024, and 256 takes both by about
# 10%. Adjust if benchmarking on another target shows a better value.
comptime CUTOFF_TOOM3: Int = 256
"""The minimum number of words above which Toom-3 multiplication is used."""

# Burnikel-Ziegler cutoff: divisors with this many words or fewer use
# Knuth D (schoolbook). Must be even for the recursive halving to work.
#
# It moved 64 -> 96 when Knuth D's multiply-subtract went to 64-bit limbs and
# got about 2x faster: a cheaper base case is worth more of, so the recursion
# should stop sooner. The floor is broad -- 96, 112 and 128 are within the 1.5%
# noise of each other everywhere -- and the only sizes that tell them apart are
# the divisors between 97 and 128 words, which is where 96 is ahead:
#
#     digits          1000   1200   1500   3000   10000   100000
#     cutoff  96       3.46   4.67   6.48  18.05  120.09  4066.78
#     cutoff 128       3.64   4.81   6.40  17.83  120.69  4054.31
#
# (microseconds, 2n-by-n). 160 is worse at 1500 and 3000 and does not come
# back at 100 000, so the top of the range is where it stops paying.
comptime CUTOFF_BURNIKEL_ZIEGLER: Int = 96
"""The minimum number of words above which Burnikel-Ziegler division is used."""


# ===----------------------------------------------------------------------=== #
# Internal magnitude helpers
# These operate on raw word lists and do not handle signs.
# ===----------------------------------------------------------------------=== #


@always_inline
def _add_words[
    o: Origin[mut=True],
    o_a: Origin[mut=False],
    o_b: Origin[mut=False],
](
    rp: Pointer[UInt64, o],
    ap: Pointer[UInt64, o_a],
    bp: Pointer[UInt64, o_b],
    n: Int,
    carry_in: UInt64,
) -> UInt64:
    """Adds `n` words of two magnitudes: `r = a + b`, LSB first.

    The carry out of a word is the unsigned overflow of the add, which a
    comparison recovers without the shift and mask a narrower word needs.
    `r` may alias `a` or `b` exactly.

    Args:
        rp: Destination, at least `n` words.
        ap: First summand, at least `n` words.
        bp: Second summand, at least `n` words.
        n: Number of words to add.
        carry_in: Carry into the lowest word, 0 or 1.

    Returns:
        The carry out of the highest word, 0 or 1.
    """
    var carry = carry_in
    for i in range(n):
        var x = ap[unsafe_offset=i]
        var y = bp[unsafe_offset=i]
        var sum_xy = x + y
        var carried = UInt64(sum_xy < x)
        var total = sum_xy + carry
        rp[unsafe_offset=i] = total
        carry = carried | UInt64(total < sum_xy)
    return carry


@always_inline
def _subtract_words[
    o: Origin[mut=True],
    o_a: Origin[mut=False],
    o_b: Origin[mut=False],
](
    rp: Pointer[UInt64, o],
    ap: Pointer[UInt64, o_a],
    bp: Pointer[UInt64, o_b],
    n: Int,
    borrow_in: UInt64,
) -> UInt64:
    """Subtracts `n` words: `r = a - b`, LSB first.

    The borrow counterpart of `_add_words()`, with the same aliasing freedom.
    A word borrows exactly when its subtraction wraps, so the borrow is again
    a comparison rather than a mask.

    Args:
        rp: Destination, at least `n` words.
        ap: Minuend, at least `n` words.
        bp: Subtrahend, at least `n` words.
        n: Number of words to subtract.
        borrow_in: Borrow into the lowest word, 0 or 1.

    Returns:
        The borrow out of the highest word, 0 or 1.
    """
    var borrow = borrow_in
    for i in range(n):
        var x = ap[unsafe_offset=i]
        var y = bp[unsafe_offset=i]
        var difference = x - y
        var borrowed = UInt64(x < y)
        var total = difference - borrow
        rp[unsafe_offset=i] = total
        borrow = borrowed | UInt64(difference < borrow)
    return borrow


@always_inline
def _submul_words[
    o: Origin[mut=True],
    o_b: Origin[mut=False],
](
    up: Pointer[UInt64, o],
    bp: Pointer[UInt64, o_b],
    n: Int,
    q: UInt64,
) -> UInt64:
    """Knuth D step D4: `u[0..n-1] -= q * b[0..n-1]`, LSB first.

    `q * word` is one 64x64 product -- `MUL` plus `UMULH` on arm64 -- whose
    high half is what the next word owes. What comes back is that debt out of
    the top word, which the caller subtracts from `u[n]`; it is at most `2^64`
    minus one plus a borrow, and the caller's own bound keeps it inside a word.

    The debt is taken off in two steps rather than summed first, to keep
    everything that does not need the last word's answer off the loop-carried
    chain: the product, the borrow it causes, and their sum all compute while
    the previous word is still finishing. What is left in the chain is a
    subtract, the borrow it sets, and one add.

    Args:
        up: The dividend window, at least `n` words, modified in place.
        bp: The divisor, at least `n` words.
        n: Number of words.
        q: The trial quotient digit.

    Returns:
        The amount still owed at word `n`.
    """
    var owed_high = UInt64(0)
    for i in range(n):
        var product = UInt128(q) * UInt128(bp[unsafe_offset=i])
        var current = up[unsafe_offset=i]
        var low = UInt64(product)
        var partial = current - low
        var owed = UInt64(product >> 64) + UInt64(current < low)
        up[unsafe_offset=i] = partial - owed_high
        owed_high = owed + UInt64(partial < owed_high)
    return owed_high


@always_inline
def _reciprocal_word(d: UInt64) -> UInt64:
    """Precomputes `floor((2^128 - 1) / d) - 2^64` for a normalized `d`.

    The companion of `_divide_two_by_one()`. `d` has its high bit set, so the
    quotient is below `2^65` and what comes back fits in a word. This is a
    128-by-64 divide and so a software helper, but it runs once per division
    where the thing it replaces would run once per quotient word.

    Args:
        d: The normalized divisor word, `2^63 <= d < 2^64`.

    Returns:
        The reciprocal.
    """
    return UInt64((~UInt128(0)) // UInt128(d) - (UInt128(1) << 64))


@always_inline
def _divide_two_by_one(
    n_high: UInt64, n_low: UInt64, d: UInt64, reciprocal: UInt64
) -> Tuple[UInt64, UInt64]:
    """Divides a two-word value by one normalized word, without dividing.

    Moller and Granlund's `udiv_qrnnd_preinv`. The trial quotient is one
    multiply by the precomputed reciprocal and two corrections settle it.

    At a 32-bit limb this was pure loss, because 64-by-32 is a single `UDIV`
    on arm64 and cheaper than the corrections. At 64 bits there is no such
    instruction -- neither arm64 nor x86-64 divides 128 by 64 -- so the
    alternative is a call to a software helper, and this is not optional.

    Args:
        n_high: High word of the dividend, strictly below `d`.
        n_low: Low word of the dividend.
        d: The divisor, normalized to `2^63 <= d < 2^64`.
        reciprocal: The value `_reciprocal_word(d)` returned.

    Returns:
        The quotient and the remainder.
    """
    debug_assert(
        n_high < d, "_divide_two_by_one() needs a quotient that fits a word"
    )

    # A two-word intermediate that wraps at 2^128, exactly as the one-word
    # pieces wrap at 2^64.
    var estimate = (
        UInt128(reciprocal) * UInt128(n_high)
        + ((UInt128(n_high) + 1) << 64)
        + UInt128(n_low)
    )
    var quotient = UInt64(estimate >> 64)
    var estimate_low = UInt64(estimate)
    var remainder = n_low - quotient * d
    if remainder > estimate_low:
        quotient -= 1
        remainder += d
    if remainder >= d:
        remainder -= d
        quotient += 1
    return (quotient, remainder)


def _add_magnitudes(a: Magnitude, b: Magnitude) -> Magnitude:
    """Adds two unsigned magnitudes represented as little-endian UInt64 words.

    Uses UInt64 accumulation to handle carries naturally via bit shift.

    Args:
        a: First magnitude (little-endian UInt64 words).
        b: Second magnitude (little-endian UInt64 words).

    Returns:
        The sum magnitude as a new word list.
    """
    var len_a = len(a)
    var len_b = len(b)
    var len_max = max(len_a, len_b)
    var len_min = min(len_a, len_b)
    var result = Magnitude(capacity=len_max + 1)
    result.resize(unsafe_uninit_length=len_max)

    var ap = a.unsafe_ptr()
    var bp = b.unsafe_ptr()
    var rp = result.unsafe_ptr()

    var carry = _add_words(rp, ap, bp, len_min, UInt64(0))
    var i = len_min

    # Only the longer operand is left: absorb the carry, then copy the rest.
    var longer = ap if len_a > len_b else bp
    while i < len_max and carry != 0:
        var s = longer[unsafe_offset=i] + carry
        rp[unsafe_offset=i] = s
        carry = UInt64(s < carry)
        i += 1
    if i < len_max:
        unsafe_memcpy(
            dest=rp.unsafe_offset(i),
            src=longer.unsafe_offset(i),
            count=len_max - i,
        )

    if carry > 0:
        result.append(UInt64(carry))

    return result^


def _add_magnitudes(a: Magnitude, b: UInt64) -> Magnitude:
    """Adds a single-word magnitude to a magnitude: a + b.

    Overload of the two-list version for the common `a + small` case. It
    avoids heap-allocating a one-element list for `b` and drops the
    per-word bounds test that the general version needs.

    Args:
        a: The magnitude (little-endian UInt64 words).
        b: The single-word value to add.

    Returns:
        The sum magnitude as a new word list.
    """
    var len_a = len(a)
    var result = Magnitude(capacity=len_a + 1)
    result.resize(unsafe_uninit_length=len_a)

    var carry = UInt64(b)
    for i in range(len_a):
        var s = a[i] + carry
        result[i] = s
        carry = UInt64(s < carry)

    if carry > 0:
        result.append(UInt64(carry))

    return result^


def _subtract_magnitudes(a: Magnitude, b: Magnitude) -> Magnitude:
    """Subtracts magnitude b from magnitude a, assuming |a| >= |b|.

    The caller MUST ensure |a| >= |b|; otherwise the result is undefined.

    Args:
        a: The larger magnitude (minuend), little-endian UInt64 words.
        b: The smaller magnitude (subtrahend), little-endian UInt64 words.

    Returns:
        The difference magnitude (a - b), normalized (no leading zeros).
    """
    var len_a = len(a)
    var len_b = len(b)
    var result = Magnitude(capacity=len_a)
    result.resize(unsafe_uninit_length=len_a)

    var ap = a.unsafe_ptr()
    var bp = b.unsafe_ptr()
    var rp = result.unsafe_ptr()

    var borrow = _subtract_words(rp, ap, bp, len_b, UInt64(0))
    var i = len_b

    # Only the minuend is left: absorb the borrow, then copy the rest.
    while i < len_a and borrow != 0:
        var ai = ap[unsafe_offset=i]
        rp[unsafe_offset=i] = ai - UInt64(1)
        borrow = UInt64(ai == 0)
        i += 1
    if i < len_a:
        unsafe_memcpy(
            dest=rp.unsafe_offset(i),
            src=ap.unsafe_offset(i),
            count=len_a - i,
        )

    _strip_leading_zeros_inplace(result)

    return result^


def _multiply_magnitudes(a: Magnitude, b: Magnitude) -> Magnitude:
    """Multiplies two unsigned magnitudes, dispatching to the best algorithm.

    A number-theoretic transform O(n log n) where its cost model beats Toom-3's
    (see `ntt.should_multiply_ntt()`), Toom-3 O(n^1.465) above `CUTOFF_TOOM3`,
    Karatsuba O(n^1.585) above `CUTOFF_KARATSUBA`, product-scanning schoolbook
    O(n*m) below it. The
    schoolbook base case accumulates in `UInt128` over packed 64-bit limbs,
    or in `UInt64` over 32-bit words when the operands are too small to repay
    the packing - see `_multiply_magnitudes_schoolbook()`.

    Args:
        a: First magnitude (little-endian UInt64 words).
        b: Second magnitude (little-endian UInt64 words).

    Returns:
        The product magnitude as a new word list.
    """
    var len_a = len(a)
    var len_b = len(b)

    # Zero check
    if len_a == 0 or len_b == 0:
        var zero: Magnitude = [UInt64(0)]
        return zero^

    # Single-word fast paths
    if len_a == 1 and a[0] == 0:
        var zero: Magnitude = [UInt64(0)]
        return zero^
    if len_b == 1 and b[0] == 0:
        var zero: Magnitude = [UInt64(0)]
        return zero^

    if len_a == 1:
        return _multiply_magnitude_by_word(b.as_span(), a[0])
    if len_b == 1:
        return _multiply_magnitude_by_word(a.as_span(), b[0])

    # Dispatch based on size
    var len_max = max(len_a, len_b)
    if len_max <= CUTOFF_KARATSUBA:
        return _multiply_magnitudes_schoolbook(a.as_span(), b.as_span())
    elif len_max > CUTOFF_TOOM3:
        if bigint_ntt.should_multiply_ntt(len_a, len_b):
            return bigint_ntt.multiply_magnitudes_ntt(a.as_span(), b.as_span())
        return _multiply_magnitudes_toom3(a.as_span(), b.as_span())
    else:
        return _multiply_magnitudes_karatsuba(a.as_span(), b.as_span())


def _multiply_magnitude_by_word(a: ImmSpan[UInt64, _], w: UInt64) -> Magnitude:
    """Multiplies a magnitude slice by a single UInt64 word.

    Args:
        a: The magnitude.
        w: The single-word multiplier.

    Returns:
        The product magnitude as a new word list.
    """
    if w == 0:
        var zero: Magnitude = [UInt64(0)]
        return zero^
    if w == 1:
        var result = Magnitude(capacity=len(a))
        for i in range(len(a)):
            result.append(a[i])
        return result^

    var len_a = len(a)
    var result = Magnitude(capacity=len_a + 1)
    result.resize(unsafe_uninit_length=len_a + 1)

    var carry = UInt64(0)
    var w128 = UInt128(w)
    var ap = a.unsafe_ptr()
    var rp = result.unsafe_ptr()
    for i in range(len_a):
        var product = UInt128(ap[unsafe_offset=i]) * w128 + UInt128(carry)
        rp[unsafe_offset=i] = UInt64(product)
        carry = UInt64(product >> 64)
    rp[unsafe_offset=len_a] = carry

    # Strip leading zeros
    var rlen = len_a + 1
    while rlen > 1 and result[rlen - 1] == 0:
        rlen -= 1
    while len(result) > rlen:
        result.shrink(len(result) - 1)

    return result^


def _multiply_magnitudes_schoolbook(
    a: ImmSpan[UInt64, _], b: ImmSpan[UInt64, _]
) -> Magnitude:
    """Product-scanning (Comba) multiplication on magnitude slices.

    Walks the result one word at a time, summing the whole column
    `sum(a[i] * b[k-i])` before writing it out, so each result word is stored
    once and no partial product is ever re-read.

    A column of 64-bit products does not fit in 128 bits, and the usual answer
    -- a three-word accumulator with an explicit carry chain -- gives most of
    the gain back. Instead each product is split at the word boundary and the
    two halves go into separate `UInt128` accumulators: every half is below
    `2^64`, so neither can overflow until a column is `2^64` words long. On
    arm64 the split is free, since `MUL` and `UMULH` already deliver the two
    halves in separate registers. Recombining is one add per column, not one
    per product.

    The columns are unrolled over two independent accumulator pairs because a
    single one serialises on the 128-bit add.

    This used to pack pairs of 32-bit words into base-2^64 limbs first, with a
    separate unpacked kernel below the area where the packing paid for itself.
    Both are gone: the words are the limbs now.

    Operates on borrowed views of the operands without copying the input data.

    Args:
        a: First magnitude.
        b: Second magnitude.

    Returns:
        The product magnitude as a new word list.
    """
    var len_a = len(a)
    var len_b = len(b)

    if len_a == 0 or len_b == 0:
        var zero: Magnitude = [UInt64(0)]
        return zero^

    comptime LOW_HALF = UInt128(0xFFFF_FFFF_FFFF_FFFF)

    var ap = a.unsafe_ptr()
    var bp = b.unsafe_ptr()

    var result_len = len_a + len_b
    var result = Magnitude(capacity=result_len)
    result.resize(unsafe_uninit_length=result_len)
    var rp = result.unsafe_ptr()

    # `carry` is the part of the column sum above 64 bits, which belongs to
    # the next column. The last column leaves it holding the top word.
    var carry = UInt128(0)
    for k in range(result_len - 1):
        var i_low = 0 if k < len_b else k - len_b + 1
        var i_high = k if k < len_a else len_a - 1

        var low0 = carry
        var high0 = UInt128(0)
        var low1 = UInt128(0)
        var high1 = UInt128(0)

        var i = i_low
        while i + 1 <= i_high:
            var product0 = UInt128(ap[unsafe_offset=i]) * UInt128(
                bp[unsafe_offset=k - i]
            )
            low0 += product0 & LOW_HALF
            high0 += product0 >> 64
            var product1 = UInt128(ap[unsafe_offset=i + 1]) * UInt128(
                bp[unsafe_offset=k - i - 1]
            )
            low1 += product1 & LOW_HALF
            high1 += product1 >> 64
            i += 2
        if i <= i_high:
            var product = UInt128(ap[unsafe_offset=i]) * UInt128(
                bp[unsafe_offset=k - i]
            )
            low0 += product & LOW_HALF
            high0 += product >> 64

        var low = low0 + low1
        rp[unsafe_offset=k] = UInt64(low & LOW_HALF)
        carry = (high0 + high1) + (low >> 64)

    rp[unsafe_offset=result_len - 1] = UInt64(carry & LOW_HALF)

    # Strip leading zeros
    var rlen = result_len
    while rlen > 1 and result[rlen - 1] == 0:
        rlen -= 1
    while len(result) > rlen:
        result.shrink(len(result) - 1)

    return result^


def _multiply_magnitudes_karatsuba(
    a: ImmSpan[UInt64, _], b: ImmSpan[UInt64, _]
) -> Magnitude:
    """Karatsuba multiplication on magnitude slices.

    Uses divide-and-conquer with three sub-multiplications instead of four:
        x = x1 * B^m + x0
        y = y1 * B^m + y0
        z0 = x0 * y0
        z2 = x1 * y1
        z1 = (x0 + x1) * (y0 + y1) - z0 - z2
        result = z2 * B^(2m) + z1 * B^m + z0

    In base-2^64, B^m shift = prepending m zero words (memcpy + memset_zero).

    Operates on borrowed views to avoid copying the original input data.
    Falls back to schoolbook for small operands.

    Args:
        a: First magnitude.
        b: Second magnitude.

    Returns:
        The product magnitude as a new word list.
    """
    var len_a = len(a)
    var len_b = len(b)

    # Base case: fall back to schoolbook
    if len_a == 0 or len_b == 0:
        var zero: Magnitude = [UInt64(0)]
        return zero^
    if len_a == 1:
        return _multiply_magnitude_by_word(b, a[0])
    if len_b == 1:
        return _multiply_magnitude_by_word(a, b[0])

    var len_max = max(len_a, len_b)
    if len_max <= CUTOFF_KARATSUBA:
        return _multiply_magnitudes_schoolbook(a, b)

    # Split point: half of the larger operand
    var m = len_max // 2

    # Case 1: a is shorter than m — split only b
    if len_a <= m:
        # a × b = a × b_low + (a × b_high) * B^m
        var z0 = _multiply_magnitudes_karatsuba(a, b[:m])
        var z1 = _multiply_magnitudes_karatsuba(a, b[m:])
        # Allocate result, add z0 at offset 0, z1 at offset m
        var rlen = len_a + len_b
        var result = Magnitude(capacity=rlen)
        result.resize(unsafe_uninit_length=rlen)
        unsafe_memset_zero(ptr=result.unsafe_ptr(), count=rlen)
        _add_at_offset_inplace(result, z0, 0)
        _add_at_offset_inplace(result, z1, m)
        while rlen > 1 and result[rlen - 1] == 0:
            rlen -= 1
        while len(result) > rlen:
            result.shrink(len(result) - 1)
        return result^

    # Case 2: b is shorter than m — split only a
    if len_b <= m:
        var z0 = _multiply_magnitudes_karatsuba(a[:m], b)
        var z1 = _multiply_magnitudes_karatsuba(a[m:], b)
        var rlen = len_a + len_b
        var result = Magnitude(capacity=rlen)
        result.resize(unsafe_uninit_length=rlen)
        unsafe_memset_zero(ptr=result.unsafe_ptr(), count=rlen)
        _add_at_offset_inplace(result, z0, 0)
        _add_at_offset_inplace(result, z1, m)
        while rlen > 1 and result[rlen - 1] == 0:
            rlen -= 1
        while len(result) > rlen:
            result.shrink(len(result) - 1)
        return result^

    # Case 3: Normal Karatsuba — both operands split at m
    # x = x1 * B^m + x0, y = y1 * B^m + y0

    # z0 = x0 * y0
    var z0 = _multiply_magnitudes_karatsuba(a[:m], b[:m])

    # z2 = x1 * y1
    var z2 = _multiply_magnitudes_karatsuba(a[m:], b[m:])

    # z1 = (x0 + x1) * (y0 + y1) - z0 - z2
    var x0_plus_x1 = _add_slices(a[:m], a[m:])
    var y0_plus_y1 = _add_slices(b[:m], b[m:])
    var z1 = _multiply_magnitudes_karatsuba(
        x0_plus_x1.as_span(), y0_plus_y1.as_span()
    )

    # z1 = z1 - z2 - z0 (z1 >= z2 + z0 by construction)
    _subtract_magnitudes_inplace(z1, z2)
    _subtract_magnitudes_inplace(z1, z0)

    # result = z2 * B^(2m) + z1 * B^m + z0
    # Instead of shifting then adding, allocate result and add at offsets.
    var result_len = len_a + len_b
    var result = Magnitude(capacity=result_len)
    result.resize(unsafe_uninit_length=result_len)
    unsafe_memset_zero(ptr=result.unsafe_ptr(), count=result_len)

    # Add z0 at offset 0
    _add_at_offset_inplace(result, z0, 0)
    # Add z1 at offset m
    _add_at_offset_inplace(result, z1, m)
    # Add z2 at offset 2*m
    _add_at_offset_inplace(result, z2, 2 * m)

    # Strip leading zeros
    while result_len > 1 and result[result_len - 1] == 0:
        result_len -= 1
    while len(result) > result_len:
        result.shrink(len(result) - 1)

    return result^


def _strip_leading_zeros_inplace(mut a: Magnitude):
    """Drops high-order zero words, leaving at least one word.

    Args:
        a: The magnitude to normalize in-place.
    """
    var length = len(a)
    while length > 1 and a[length - 1] == 0:
        length -= 1
    while len(a) > length:
        a.shrink(len(a) - 1)


def _double_inplace(mut a: Magnitude):
    """Doubles a magnitude in-place: a *= 2.

    A one-bit left shift, appending a word if the top bit carries out.

    Args:
        a: The magnitude to double in-place.
    """
    var carry: UInt64 = 0
    var ap = a.unsafe_ptr()
    for i in range(len(a)):
        var word = ap[unsafe_offset=i]
        ap[unsafe_offset=i] = (word << 1) | carry
        carry = word >> 63
    if carry != 0:
        a.append(carry)


def _exact_divide_by_2_inplace(mut a: Magnitude):
    """Halves a magnitude in-place, assuming it is even.

    A one-bit right shift. The caller guarantees divisibility; a stray low
    bit is simply discarded rather than reported.

    Args:
        a: The magnitude to halve in-place. Must be even.
    """
    var carry: UInt64 = 0
    var ap = a.unsafe_ptr()
    for i in range(len(a) - 1, -1, -1):
        var word = ap[unsafe_offset=i]
        ap[unsafe_offset=i] = (word >> 1) | (carry << 63)
        carry = word & 1
    _strip_leading_zeros_inplace(a)


def _exact_divide_by_3_inplace(mut a: Magnitude):
    """Divides a magnitude by three in-place, assuming it is a multiple of 3.

    Walks the words from the top down carrying the remainder, which is zero
    once the last word is consumed. Toom-3's interpolation is the only caller
    and its dividend is exactly divisible by construction.

    The straightforward form — build `remainder * 2^64 + word`, divide it, take
    the modulus — puts *two* dependent multiplications on the loop-carried
    chain, because a compiler turns both the division and the modulus by a
    constant into multiply-high. That cost about nine cycles per word, roughly
    nine times what the neighbouring word-at-a-time helpers cost.

    The division comes off the chain by splitting it. Since `2^64 = 3 * T + 1`
    with `T = 0x5555_5555_5555_5555`, writing `word = 3 * d + m`:

        remainder * 2^64 + word = 3 * (remainder * T + d) + (remainder + m)

    so, with `remainder + m <= 4`,

        quotient      = remainder * T + d + (remainder + m >= 3)
        new remainder = (remainder + m) mod 3

    `d` and `m` depend only on `word`, so the one division left is off the
    chain; what stays on it is an add and a reduction of a value below five.

    Args:
        a: The magnitude to divide in-place. Must be a multiple of three.
    """
    comptime BASE_OVER_THREE = UInt64(0x5555_5555_5555_5555)  # (2^64 - 1) / 3

    var remainder = UInt64(0)  # 0, 1 or 2
    var ap = a.unsafe_ptr()
    for i in range(len(a) - 1, -1, -1):
        var word = ap[unsafe_offset=i]
        var word_quotient = word // 3  # off the chain
        var word_remainder = word - 3 * word_quotient  # off the chain, 0..2
        var total = remainder + word_remainder  # on the chain, 0..4
        var carried = UInt64(total >= 3)
        ap[unsafe_offset=i] = (
            remainder * BASE_OVER_THREE + word_quotient + carried
        )
        remainder = total - 3 * carried
    _strip_leading_zeros_inplace(a)


def _multiply_magnitudes_toom3(
    a: ImmSpan[UInt64, _], b: ImmSpan[UInt64, _]
) -> Magnitude:
    """Toom-Cook 3-way multiplication on magnitude slices.

    Splits each operand into three limbs of `m` words, evaluates both as
    polynomials at `0`, `1`, `-1`, `2` and `inf`, multiplies the five pairs of
    values, and interpolates the five coefficients of the product polynomial:

        a = a2 * B^(2m) + a1 * B^m + a0
        b = b2 * B^(2m) + b1 * B^m + b0
        a*b = w4 * B^(4m) + w3 * B^(3m) + w2 * B^(2m) + w1 * B^m + w0

    Five sub-multiplications on third-length operands instead of Karatsuba's
    three on half-length ones: `O(n^log_3(5))` = `O(n^1.465)` against
    `O(n^1.585)`. Falls back to Karatsuba when the longer operand is at or
    below `CUTOFF_TOOM3`, or the shorter one is at or below
    `CUTOFF_KARATSUBA` - the second is the guard against lopsided pairs,
    where a three-way split of the long operand leaves the short one with
    empty limbs and Karatsuba's one-sided split is the better shape. Pairs
    that are lopsided but still have both operands above their cutoff do run
    here.

    Only `a(-1)` and `b(-1)` can be negative, so a single sign flag on each
    stands in for signed arithmetic; every other intermediate, including all
    five coefficients, is non-negative.

    Args:
        a: First magnitude.
        b: Second magnitude.

    Returns:
        The product magnitude as a new word list.
    """
    var len_a = len(a)
    var len_b = len(b)
    var len_max = max(len_a, len_b)
    var len_min = min(len_a, len_b)

    if len_max <= CUTOFF_TOOM3 or len_min <= CUTOFF_KARATSUBA:
        return _multiply_magnitudes_karatsuba(a, b)

    var m = (len_max + 2) // 3  # ceil(len_max / 3)

    # The limbs. `_subspan()` clamps, so the high limbs of the shorter operand
    # come back empty rather than out of range, and the code below treats an
    # empty limb as a zero coefficient throughout.
    var a0 = _subspan(a, 0, m)
    var a1 = _subspan(a, m, 2 * m)
    var a2 = _subspan(a, 2 * m, len_a)
    var b0 = _subspan(b, 0, m)
    var b1 = _subspan(b, m, 2 * m)
    var b2 = _subspan(b, 2 * m, len_b)

    # ---- Evaluation ---------------------------------------------------- #

    # `a0 + a2` is shared between a(1) and a(-1); likewise `b0 + b2`.
    var a0_plus_a2 = _add_slices(a0, a2)
    _strip_leading_zeros_inplace(a0_plus_a2)
    var b0_plus_b2 = _add_slices(b0, b2)
    _strip_leading_zeros_inplace(b0_plus_b2)

    # a(1) = (a0 + a2) + a1, b(1) = (b0 + b2) + b1
    var a_at_1 = a0_plus_a2.copy()
    _add_from_slice_inplace(a_at_1, a1)
    var b_at_1 = b0_plus_b2.copy()
    _add_from_slice_inplace(b_at_1, b1)

    # a(-1) = (a0 + a2) - a1, kept as magnitude plus sign.
    var a1_words = _normalized_copy(a1)
    var a_at_m1: Magnitude
    var a_at_m1_negative: Bool
    if _compare_word_lists(a0_plus_a2, a1_words) >= 0:
        a_at_m1 = a0_plus_a2.copy()
        _subtract_magnitudes_inplace(a_at_m1, a1_words)
        a_at_m1_negative = False
    else:
        a_at_m1 = a1_words.copy()
        _subtract_magnitudes_inplace(a_at_m1, a0_plus_a2)
        a_at_m1_negative = True

    # b(-1) = (b0 + b2) - b1
    var b1_words = _normalized_copy(b1)
    var b_at_m1: Magnitude
    var b_at_m1_negative: Bool
    if _compare_word_lists(b0_plus_b2, b1_words) >= 0:
        b_at_m1 = b0_plus_b2.copy()
        _subtract_magnitudes_inplace(b_at_m1, b1_words)
        b_at_m1_negative = False
    else:
        b_at_m1 = b1_words.copy()
        _subtract_magnitudes_inplace(b_at_m1, b0_plus_b2)
        b_at_m1_negative = True

    # a(2) = a0 + 2*a1 + 4*a2, by Horner: ((a2 * 2) + a1) * 2 + a0.
    var a_at_2 = _normalized_copy(a2)
    _double_inplace(a_at_2)
    _add_from_slice_inplace(a_at_2, a1)
    _double_inplace(a_at_2)
    _add_from_slice_inplace(a_at_2, a0)

    # b(2) = b0 + 2*b1 + 4*b2
    var b_at_2 = _normalized_copy(b2)
    _double_inplace(b_at_2)
    _add_from_slice_inplace(b_at_2, b1)
    _double_inplace(b_at_2)
    _add_from_slice_inplace(b_at_2, b0)

    # ---- The five sub-multiplications ---------------------------------- #

    # v0 and vinf multiply the original slices directly - no copy needed.
    var v0 = _multiply_magnitudes_slices(a0, b0)

    var v_inf: Magnitude
    if len(a2) > 0 and len(b2) > 0:
        v_inf = _multiply_magnitudes_slices(a2, b2)
    else:
        v_inf = [UInt64(0)]

    var v1 = _multiply_magnitudes(a_at_1, b_at_1)
    var v_m1 = _multiply_magnitudes(a_at_m1, b_at_m1)
    var v_m1_negative = a_at_m1_negative != b_at_m1_negative
    var v2 = _multiply_magnitudes(a_at_2, b_at_2)

    # ---- Interpolation -------------------------------------------------- #
    #
    # With r(t) = w0 + w1*t + w2*t^2 + w3*t^3 + w4*t^4:
    #   v0   = r(0)   = w0
    #   v1   = r(1)   = w0 + w1 + w2 + w3 + w4
    #   v_m1 = r(-1)  = w0 - w1 + w2 - w3 + w4
    #   v2   = r(2)   = w0 + 2*w1 + 4*w2 + 8*w3 + 16*w4
    #   vinf = r(inf) = w4
    #
    # so, in the order evaluated below,
    #   t1 = (v1 - v_m1) / 2               = w1 + w3
    #   w2 = (v1 + v_m1) / 2 - w0 - w4
    #   t3 = (v2 - w0 - 16*w4) / 2         = w1 + 2*w2 + 4*w3
    #   w3 = (t3 - 2*w2 - t1) / 3
    #   w1 = t1 - w3
    #
    # Every division here is exact, and every value is non-negative, so the
    # unsigned in-place subtractions below never underflow.

    # t1 = (v1 - v_m1) / 2
    var t1: Magnitude
    if v_m1_negative:
        t1 = _add_magnitudes(v1, v_m1)
    else:
        t1 = v1.copy()
        _subtract_magnitudes_inplace(t1, v_m1)
    _exact_divide_by_2_inplace(t1)

    # w2 = (v1 + v_m1) / 2 - w0 - w4
    var w2: Magnitude
    if v_m1_negative:
        w2 = v1.copy()
        _subtract_magnitudes_inplace(w2, v_m1)
    else:
        w2 = _add_magnitudes(v1, v_m1)
    _exact_divide_by_2_inplace(w2)
    _subtract_magnitudes_inplace(w2, v0)
    _subtract_magnitudes_inplace(w2, v_inf)

    # t3 = (v2 - w0 - 16*w4) / 2, then w3 = (t3 - 2*w2 - t1) / 3.
    # `w2` is subtracted twice rather than doubled into a temporary.
    var t3 = v2^
    _subtract_magnitudes_inplace(t3, v0)
    if not (len(v_inf) == 1 and v_inf[0] == 0):
        var v_inf_16 = _multiply_magnitude_by_word(v_inf.as_span(), UInt64(16))
        _subtract_magnitudes_inplace(t3, v_inf_16)
    _exact_divide_by_2_inplace(t3)
    _subtract_magnitudes_inplace(t3, w2)
    _subtract_magnitudes_inplace(t3, w2)
    _subtract_magnitudes_inplace(t3, t1)
    _exact_divide_by_3_inplace(t3)  # t3 now holds w3

    # w1 = t1 - w3
    _subtract_magnitudes_inplace(t1, t3)  # t1 now holds w1

    # ---- Recomposition -------------------------------------------------- #
    #
    # The five coefficients are non-negative and normalized, and they sum to
    # the product, so `k*m + len(w_k)` never exceeds `len_a + len_b` and each
    # `_add_at_offset_inplace()` stays inside the buffer.

    var result_len = len_a + len_b
    var result = Magnitude(capacity=result_len)
    result.resize(unsafe_uninit_length=result_len)
    unsafe_memset_zero(ptr=result.unsafe_ptr(), count=result_len)

    _add_at_offset_inplace(result, v0, 0)
    _add_at_offset_inplace(result, t1, m)  # w1
    _add_at_offset_inplace(result, w2, 2 * m)
    _add_at_offset_inplace(result, t3, 3 * m)  # w3

    # `w4` is the one coefficient whose offset is not covered by the argument
    # above. A zero `BigInt` magnitude is one zero word, not an empty list, so
    # an empty high limb still presents a length-1 value to add at `4 * m` -
    # and for a lopsided pair `4 * m` can be past the end of `result`
    # (`len_a = 513`, `len_b = 129` gives `4 * m = 684` against 642 words).
    # Adding zero changes nothing, so skip it.
    if not (len(v_inf) == 1 and v_inf[0] == 0):
        _add_at_offset_inplace(result, v_inf, 4 * m)

    _strip_leading_zeros_inplace(result)
    return result^


# ===----------------------------------------------------------------------=== #
# In-place magnitude helpers for Karatsuba
# ===----------------------------------------------------------------------=== #


def _add_slices(a: ImmSpan[UInt64, _], b: ImmSpan[UInt64, _]) -> Magnitude:
    """Adds two magnitude slices, returning a new word list.

    Used by Karatsuba to compute (x0 + x1) and (y0 + y1) without copying
    the full operands.

    Args:
        a: First magnitude.
        b: Second magnitude.

    Returns:
        The sum as a new word list.
    """
    var len_a = len(a)
    var len_b = len(b)
    var len_max = max(len_a, len_b)
    var len_min = min(len_a, len_b)
    var result = Magnitude(capacity=len_max + 1)
    result.resize(unsafe_uninit_length=len_max + 1)

    var ap = a.unsafe_ptr()
    var bp = b.unsafe_ptr()
    var rp = result.unsafe_ptr()

    var carry = _add_words(rp, ap, bp, len_min, UInt64(0))
    var i = len_min

    var longer = ap if len_a > len_b else bp
    while i < len_max and carry != 0:
        var s = longer[unsafe_offset=i] + carry
        rp[unsafe_offset=i] = s
        carry = UInt64(s < carry)
        i += 1
    if i < len_max:
        unsafe_memcpy(
            dest=rp.unsafe_offset(i),
            src=longer.unsafe_offset(i),
            count=len_max - i,
        )

    if carry > 0:
        rp[unsafe_offset=len_max] = UInt64(carry)
    else:
        while len(result) > len_max:
            result.shrink(len(result) - 1)

    return result^


def _add_magnitudes_inplace(mut a: Magnitude, imm b: Magnitude):
    """Adds magnitude b into a in-place: a += b.

    Grows a if needed to accommodate the sum.

    Args:
        a: The accumulator magnitude (modified in-place).
        b: The magnitude to add.
    """
    var len_a = len(a)
    var len_b = len(b)
    var len_max = max(len_a, len_b)

    # Ensure a has enough space
    if len_a < len_max + 1:
        a.resize(unsafe_uninit_length=len_max + 1)
        # Zero the newly added words
        for i in range(len_a, len_max + 1):
            a[i] = UInt64(0)

    # `a` is now `len_max + 1` words long with a zero on top, so the sum and
    # its carry both fit and every word of `b` has a counterpart in `a`.
    var ap = a.unsafe_ptr()
    var bp = b.unsafe_ptr()

    var carry = _add_words(
        ap, alias_as_immutable_source(ap), bp, len_b, UInt64(0)
    )
    var i = len_b
    while carry != 0:
        var s = ap[unsafe_offset=i] + carry
        ap[unsafe_offset=i] = s
        carry = UInt64(s < carry)
        i += 1

    _strip_leading_zeros_inplace(a)


def _add_magnitudes_inplace(mut a: Magnitude, b: UInt64):
    """Adds a single-word magnitude into a in-place: a += b.

    Overload of the two-list version for the common `a += small` case. Beyond
    skipping the one-element list allocation, it stops as soon as the carry is
    absorbed instead of walking all of `a`.

    Args:
        a: The accumulator magnitude (modified in-place).
        b: The single-word value to add.
    """
    var len_a = len(a)
    var carry = UInt64(b)
    var i = 0
    while carry > 0 and i < len_a:
        var s = a[i] + carry
        a[i] = s
        carry = UInt64(s < carry)
        i += 1

    if carry > 0:
        a.append(UInt64(carry))
        return

    # Trim trailing zero words, matching the two-list overload.
    var alen = len(a)
    while alen > 1 and a[alen - 1] == 0:
        alen -= 1
    while len(a) > alen:
        a.shrink(len(a) - 1)


def _add_at_offset_inplace(mut a: Magnitude, imm b: Magnitude, offset: Int):
    """Adds magnitude b into a at a word offset: a[offset:] += b.

    Equivalent to a += b * B^offset, but without shifting b.
    Assumes a is pre-allocated large enough.

    Args:
        a: The accumulator magnitude (modified in-place).
        b: The magnitude to add.
        offset: Word offset at which to start adding b into a. `offset +
            len(b)` must not exceed `len(a)`: the loop below is unchecked.
    """
    var len_b = len(b)
    debug_assert(
        offset + len_b <= len(a),
        "_add_at_offset_inplace(): writes past the end of the accumulator",
    )
    var ap = a.unsafe_ptr().unsafe_offset(offset)
    var bp = b.unsafe_ptr()
    var carry = _add_words(
        ap, alias_as_immutable_source(ap), bp, len_b, UInt64(0)
    )
    # Propagate remaining carry
    var j = len_b
    while carry > 0 and (offset + j) < len(a):
        var s = a[offset + j] + carry
        a[offset + j] = s
        carry = UInt64(s < carry)
        j += 1


def _subtract_magnitudes_inplace(mut a: Magnitude, imm b: Magnitude):
    """Subtracts magnitude b from a in-place: a -= b.

    Assumes a >= b. Used by Karatsuba where this is guaranteed by construction.

    Args:
        a: The accumulator magnitude (modified in-place). Must be >= b.
        b: The magnitude to subtract.
    """
    var len_a = len(a)
    var len_b = len(b)

    var ap = a.unsafe_ptr()
    var bp = b.unsafe_ptr()

    var borrow = _subtract_words(
        ap, alias_as_immutable_source(ap), bp, len_b, UInt64(0)
    )
    var i = len_b
    while i < len_a and borrow != 0:
        var ai = ap[unsafe_offset=i]
        ap[unsafe_offset=i] = ai - UInt64(1)
        borrow = UInt64(ai == 0)
        i += 1

    _strip_leading_zeros_inplace(a)


def _shift_left_words_inplace(mut a: Magnitude, n: Int):
    """Shifts a magnitude left by n whole words in-place (multiply by B^n).

    This is equivalent to prepending n zero words. In base-2^64, B^n shift
    is a pure memory operation — no arithmetic needed.

    Args:
        a: The magnitude to shift (modified in-place).
        n: Number of words to shift by (must be >= 0).
    """
    if n <= 0:
        return

    # Check for zero
    if len(a) == 1 and a[0] == 0:
        return

    var old_len = len(a)
    var new_len = old_len + n
    a.resize(unsafe_uninit_length=new_len)

    # Move existing words right by n positions using backward copy
    # (destination is always at higher address, so backward is overlap-safe)
    var p = a.unsafe_ptr()
    for i in range(old_len - 1, -1, -1):
        p[unsafe_offset=i + n] = p[unsafe_offset=i]

    # Fill the first n words with zeros
    unsafe_memset_zero(ptr=a.unsafe_ptr(), count=n)


def _divmod_single_word(
    a: Magnitude, d: UInt64, mut remainder: UInt64
) -> Magnitude:
    """Divides a magnitude by a single UInt64 word.

    This is the fast path for division when the divisor fits in one word.

    Args:
        a: The dividend magnitude (little-endian UInt64 words).
        d: The single-word divisor (must be non-zero).
        remainder: Set to `a % d` on return.

    Returns:
        The quotient words.
    """
    var n = len(a)
    var quotient = Magnitude(capacity=n)
    quotient.resize(unsafe_uninit_length=n)

    # `_divide_two_by_one()` wants a normalized divisor, and normalizing means
    # shifting the dividend by the same amount -- which is done a word at a
    # time here rather than materialized, since each step only needs the two
    # words straddling the boundary. The quotient is unchanged by the scaling
    # and the remainder comes back out of it at the end.
    var shift = _count_leading_zeros(d)
    var divisor = d << UInt64(shift)
    var reciprocal = _reciprocal_word(divisor)
    var word_remainder = UInt64(0)

    if shift == 0:
        for i in range(n - 1, -1, -1):
            var step = _divide_two_by_one(
                word_remainder, a[i], divisor, reciprocal
            )
            quotient[i] = step[0]
            word_remainder = step[1]
    else:
        var carry_shift = UInt64(64 - shift)
        # The top word of the scaled dividend is what `a`'s top word shifts
        # out, which is below `2^shift <= 2^63` and so below the divisor.
        word_remainder = a[n - 1] >> carry_shift
        for i in range(n - 1, -1, -1):
            var below = a[i - 1] >> carry_shift if i > 0 else UInt64(0)
            var step = _divide_two_by_one(
                word_remainder,
                (a[i] << UInt64(shift)) | below,
                divisor,
                reciprocal,
            )
            quotient[i] = step[0]
            word_remainder = step[1]
        word_remainder >>= UInt64(shift)

    # Strip leading zeros from quotient
    while len(quotient) > 1 and quotient[len(quotient) - 1] == 0:
        quotient.shrink(len(quotient) - 1)

    remainder = UInt64(word_remainder)
    return quotient^


def _divmod_magnitudes(
    a: Magnitude, b: Magnitude, mut remainder: Magnitude
) raises -> Magnitude:
    """Divides magnitude a by magnitude b, returning the quotient.

    Implements Knuth's Algorithm D (The Art of Computer Programming, Vol 2,
    Section 4.3.1) for multi-word division in base 2^64.

    Args:
        a: The dividend magnitude (little-endian UInt64 words).
        b: The divisor magnitude (little-endian UInt64 words, must be non-zero).
        remainder: Set to the normalized remainder on return.

    Returns:
        The normalized quotient words.

    Raises:
        Error: If divisor is zero.

    Notes:
        The remainder comes back through an argument rather than in a tuple,
        because a `List` cannot be moved out of a returned tuple yet
        (modular/modular#5330), so every caller had to copy it.
    """
    var len_a = len(a)
    var len_b = len(b)

    # Check for zero divisor
    var divisor_is_zero = True
    for word in b:
        if word != 0:
            divisor_is_zero = False
            break
    if divisor_is_zero:
        raise ZeroDivisionError(
            function="_divmod_magnitudes()",
            message="Division by zero.",
        )

    # Compare magnitudes to handle trivial cases
    # If |a| < |b|, quotient = 0, remainder = a
    var cmp = _compare_word_lists(a, b)
    if cmp < 0:
        var rem_copy = Magnitude(capacity=len_a)
        for word in a:
            rem_copy.append(word)
        remainder = rem_copy^
        return [UInt64(0)]
    if cmp == 0:
        remainder = [UInt64(0)]
        return [UInt64(1)]

    # Single-word divisor: use fast path
    if len_b == 1:
        var r_word = UInt64(0)
        var q = _divmod_single_word(a, b[0], r_word)
        remainder = [r_word]
        return q^

    # Burnikel-Ziegler for large divisors (slice-based, avoids excessive allocation)
    if len_b > CUTOFF_BURNIKEL_ZIEGLER:
        return _divmod_burnikel_ziegler(a, b, remainder)

    # ===--- Knuth's Algorithm D ---=== #
    # Step D1: Normalize
    # Shift so that the leading bit of the divisor's MSW is set.
    # This ensures the trial quotient estimate is accurate.
    var shift = _count_leading_zeros(b[len_b - 1])

    # Create normalized copies
    var u = _shift_left_words(a, shift)
    var v = _shift_left_words(b, shift)

    # Ensure u has an extra leading word (Algorithm D requires m+n+1 words)
    var n = len(v)  # normalized divisor length
    var m = len(u) - n  # number of quotient words

    if len(u) <= m + n:
        u.append(UInt64(0))

    var quotient = Magnitude(capacity=m + 1)
    quotient.resize(unsafe_uninit_length=m + 1)
    unsafe_memset_zero(ptr=quotient.unsafe_ptr(), count=m + 1)

    var v_n_minus_1 = UInt64(v[n - 1])
    var v_n_minus_2 = UInt64(v[n - 2])
    var reciprocal = _reciprocal_word(v_n_minus_1)

    # Step D2-D7: main loop. The same kernel as
    # `_divmod_knuth_d_from_slices()`, and for the same reasons: every index
    # here is provably in bounds, so none of them is checked, and the three
    # buffers are borrowed through raw pointers because a `List[i]` reads the
    # list's storage field again on every element.
    #
    # `u` was grown to `m + n + 1` words above, `j` runs down from `m`, and
    # `i` stays under `n`, so `j + i <= m + n - 1` and `j + n <= m + n`. A
    # single-word divisor was handled earlier, so `n >= 2` and `j + n - 2`
    # cannot go negative. Nothing is resized while these pointers are live.
    var u_ptr = u.unsafe_ptr()
    var v_ptr = v.unsafe_ptr()
    var quotient_ptr = quotient.unsafe_ptr()

    for j in range(m, -1, -1):
        # Step D3: calculate the trial quotient q_hat.
        var u_jn = UInt64(u_ptr[unsafe_offset=j + n])
        var u_jn_minus_1 = UInt64(u_ptr[unsafe_offset=j + n - 1])
        var u_jn_minus_2 = UInt64(u_ptr[unsafe_offset=j + n - 2])

        # Knuth's step D3. The estimate is exact when the top dividend word is
        # below the top divisor word; where they are equal, `b - 1` is the
        # answer Knuth names directly and no division is needed for it either.
        # `r_hat` is two words wide because that case can carry it past `b`,
        # which is also where the refinement stops.
        var q_hat: UInt64
        var r_hat: UInt128
        if u_jn < v_n_minus_1:
            var estimate = _divide_two_by_one(
                u_jn, u_jn_minus_1, v_n_minus_1, reciprocal
            )
            q_hat = estimate[0]
            r_hat = UInt128(estimate[1])
        else:
            q_hat = ~UInt64(0)
            r_hat = UInt128(u_jn_minus_1) + UInt128(v_n_minus_1)

        while r_hat < RADIX and (
            UInt128(q_hat) * UInt128(v_n_minus_2)
            > (r_hat << 64) + UInt128(u_jn_minus_2)
        ):
            q_hat -= 1
            r_hat += UInt128(v_n_minus_1)

        # Step D4: multiply and subtract, u[j..j+n] -= q_hat * v[0..n-1].
        # Two words at a time; see `_submul_words()`.
        var carry = _submul_words(u_ptr.unsafe_offset(j), v_ptr, n, q_hat)

        # Step D5. Taking the debt off the top word wraps exactly when the
        # estimate was one too large, which is the borrow the old base-2^32
        # form spelled as `BASE + u - carry`.
        var jn = j + n
        var top = u_ptr[unsafe_offset=jn]
        u_ptr[unsafe_offset=jn] = top - carry
        if top < carry:
            # Step D6: add back -- q_hat was one too large.
            q_hat -= 1
            var window = u_ptr.unsafe_offset(j)
            var add_carry = _add_words(
                window,
                alias_as_immutable_source(window),
                v_ptr,
                n,
                UInt64(0),
            )
            u_ptr[unsafe_offset=jn] = u_ptr[unsafe_offset=jn] + add_carry

        quotient_ptr[unsafe_offset=j] = UInt64(q_hat)

    # Strip leading zeros from quotient
    while len(quotient) > 1 and quotient[len(quotient) - 1] == 0:
        quotient.shrink(len(quotient) - 1)

    # Step D8: unnormalize the remainder, in the buffer it is already in.
    _shift_right_words_inplace(u, shift, n)
    remainder = u^

    return quotient^


def _compare_word_lists(a: Magnitude, b: Magnitude) -> Int8:
    """Compares two unsigned magnitude word lists.

    Args:
        a: First magnitude.
        b: Second magnitude.

    Returns:
        1 if a > b, 0 if a == b, -1 if a < b.
    """
    var len_a = len(a)
    var len_b = len(b)
    if len_a != len_b:
        return Int8(1) if len_a > len_b else Int8(-1)
    for i in range(len_a - 1, -1, -1):
        if a[i] != b[i]:
            return Int8(1) if a[i] > b[i] else Int8(-1)
    return 0


def _count_leading_zeros(word: UInt64) -> Int:
    """Counts the number of leading zero bits in a UInt64 word.

    Args:
        word: The word to count leading zeros of.

    Returns:
        The number of leading zero bits (0-64).
    """
    # `std.bit.count_leading_zeros` lowers to a single hardware `clz`
    # instruction, and already returns 64 for a zero input.
    return Int(count_leading_zeros(word))


def _shift_left_words(a: Magnitude, shift: Int) -> Magnitude:
    """Shifts a magnitude left by `shift` bits (0 <= shift < 64).

    Args:
        a: The magnitude to shift.
        shift: The number of bits to shift left (must be < 64).

    Returns:
        The shifted magnitude as a new word list.
    """
    var n = len(a)
    if shift == 0:
        var copy = Magnitude(capacity=n)
        copy.resize(unsafe_uninit_length=n)
        unsafe_memcpy(dest=copy.unsafe_ptr(), src=a.unsafe_ptr(), count=n)
        return copy^

    # Sized once, then written through pointers. Appending word by word costs
    # a capacity test per word and re-reads the list's storage field on every
    # `a[i]`: 48 ns to copy 22 words, against 8 for the memcpy above.
    var result = Magnitude(capacity=n + 1)
    result.resize(unsafe_uninit_length=n)
    var ap = a.unsafe_ptr()
    var rp = result.unsafe_ptr()
    # `shift` is between 1 and 63 here, the zero case having returned above,
    # so neither shift below is the undefined full-word one.
    var carry: UInt64 = 0
    var carry_shift = UInt64(64 - shift)
    for i in range(n):
        var word = ap[unsafe_offset=i]
        rp[unsafe_offset=i] = (word << UInt64(shift)) | carry
        carry = word >> carry_shift
    if carry > 0:
        result.append(carry)

    return result^


def _shift_right_words(a: Magnitude, shift: Int, num_words: Int) -> Magnitude:
    """Shifts the first `num_words` of a magnitude right by `shift` bits.

    Used to unnormalize the remainder after Knuth's Algorithm D.

    Args:
        a: The magnitude to shift.
        shift: The number of bits to shift right (must be < 64).
        num_words: The number of words to consider from `a`.

    Returns:
        The shifted magnitude as a new word list, normalized.
    """
    var n = min(num_words, len(a))
    if n <= 0:
        var zero: Magnitude = [UInt64(0)]
        return zero^

    var result = Magnitude(capacity=n)
    result.resize(unsafe_uninit_length=n)
    var ap = a.unsafe_ptr()
    var rp = result.unsafe_ptr()

    if shift == 0:
        unsafe_memcpy(dest=rp, src=ap, count=n)
    else:
        # The top word has nothing above it to pull down, so it is peeled off
        # rather than tested for inside the loop.
        var carry_shift = UInt64(64 - shift)
        for i in range(n - 1):
            rp[unsafe_offset=i] = (ap[unsafe_offset=i] >> UInt64(shift)) | (
                ap[unsafe_offset=i + 1] << carry_shift
            )
        rp[unsafe_offset=n - 1] = ap[unsafe_offset=n - 1] >> UInt64(shift)

    while len(result) > 1 and result[len(result) - 1] == 0:
        result.shrink(len(result) - 1)
    return result^


def _shift_right_words_inplace(mut a: Magnitude, shift: Int, num_words: Int):
    """Keeps the first `num_words` of a magnitude, shifted right `shift` bits.

    The in-place form of `_shift_right_words()`, for the callers that own
    their input and are finished with it: both divisions unnormalizing a
    remainder out of the buffer they computed it in. Doing it in place lets
    that buffer *become* the remainder, which takes Knuth D from four heap
    allocations to three -- worth 37 ns a call, which is a quarter of a
    100-digit division.

    The pass runs low to high and a word is written only after the word above
    it has been read, so writing over the source is safe.

    Args:
        a: The magnitude, truncated and shifted in place.
        shift: The number of bits to shift right (must be < 64).
        num_words: How many words of `a` to keep.
    """
    var n = min(num_words, len(a))
    if n <= 0:
        a = [UInt64(0)]
        return

    if shift != 0:
        var ap = a.unsafe_ptr()
        var carry_shift = UInt64(64 - shift)
        for i in range(n - 1):
            ap[unsafe_offset=i] = (ap[unsafe_offset=i] >> UInt64(shift)) | (
                ap[unsafe_offset=i + 1] << carry_shift
            )
        ap[unsafe_offset=n - 1] = ap[unsafe_offset=n - 1] >> UInt64(shift)

    while len(a) > n:
        a.shrink(len(a) - 1)
    while len(a) > 1 and a[len(a) - 1] == 0:
        a.shrink(len(a) - 1)


# ===----------------------------------------------------------------------=== #
# Burnikel-Ziegler division (slice-based)
# Recursive divide-and-conquer for large operands.
# Passes word-list bounds through the recursion to avoid copying the large
# inputs until the Knuth D (schoolbook) base case.
# ===----------------------------------------------------------------------=== #


def _subspan[
    origin: ImmOrigin, //
](s: ImmSpan[UInt64, origin], start: Int, end: Int) -> ImmSpan[UInt64, origin]:
    """Returns `s[start:end]`, clamped to the bounds of `s`.

    The Burnikel-Ziegler recursion routinely computes block bounds that run
    past the end of a padded operand, and treats the missing high words as
    implicit zeros. This helper reproduces that: `end` is clamped to
    `len(s)`, and a start at or past the clamped end yields an empty span.

    Parameters:
        origin: The origin of the source span.

    Args:
        s: The span to take a sub-range of.
        start: Start index (inclusive).
        end: End index (exclusive), clamped to `len(s)`.

    Returns:
        The clamped sub-span, possibly empty.
    """
    var actual_end = min(end, len(s))
    if start >= actual_end:
        return s[0:0]
    return s[start:actual_end]


def _normalized_copy(a: ImmSpan[UInt64, _]) -> Magnitude:
    """Copies a magnitude slice into a new list, stripping leading zeros.

    Returns [0] for an empty slice.

    Args:
        a: The source magnitude (little-endian UInt64 words).

    Returns:
        A new word list containing the slice, normalized.
    """
    var len_slice = len(a)
    if len_slice == 0:
        var zero: Magnitude = [UInt64(0)]
        return zero^
    var result = Magnitude(capacity=len_slice)
    result.resize(unsafe_uninit_length=len_slice)
    unsafe_memcpy(dest=result.unsafe_ptr(), src=a.unsafe_ptr(), count=len_slice)
    # Strip leading zeros
    while len(result) > 1 and result[len(result) - 1] == 0:
        result.shrink(len(result) - 1)
    return result^


def _is_zero_slice(a: ImmSpan[UInt64, _]) -> Bool:
    """Checks whether every word in a magnitude slice is zero.

    Args:
        a: The word slice.

    Returns:
        True if the slice is empty or all zeros.
    """
    for i in range(len(a)):
        if a[i] != 0:
            return False
    return True


def _add_from_slice_inplace(mut a: Magnitude, b: ImmSpan[UInt64, _]):
    """Adds a magnitude slice into a in-place: a += b.

    Grows a if needed. An empty b is a no-op.

    Args:
        a: The accumulator (modified in-place).
        b: The source slice.
    """
    var len_b_slice = len(b)
    if len_b_slice == 0:
        return
    var len_a = len(a)
    var len_max = max(len_a, len_b_slice)

    # Ensure a has enough space
    if len_a < len_max + 1:
        a.resize(unsafe_uninit_length=len_max + 1)
        for i in range(len_a, len_max + 1):
            a[i] = UInt64(0)

    # As in `_add_magnitudes_inplace()`, `a` now has `len_max + 1` words with a
    # zero on top, so the carry always lands inside it.
    var ap = a.unsafe_ptr()
    var bp = b.unsafe_ptr()

    var carry = _add_words(
        ap, alias_as_immutable_source(ap), bp, len_b_slice, UInt64(0)
    )
    var i = len_b_slice
    while carry != 0:
        var s = ap[unsafe_offset=i] + carry
        ap[unsafe_offset=i] = s
        carry = UInt64(s < carry)
        i += 1

    _strip_leading_zeros_inplace(a)


def _multiply_magnitudes_slices(
    a: ImmSpan[UInt64, _], b: ImmSpan[UInt64, _]
) -> Magnitude:
    """Multiplies two magnitude slices, dispatching to the best algorithm.

    The same ladder as `_multiply_magnitudes()`, over slices rather than owned
    lists. Burnikel-Ziegler division reaches its multiplications only through
    here, so leaving the transform out of this one would keep division - and
    the base conversion built on it - on Toom-3 however large the operands got.

    Args:
        a: First magnitude.
        b: Second magnitude.

    Returns:
        The product magnitude as a new word list.
    """
    var len_a = len(a)
    var len_b = len(b)
    if len_a <= 0 or len_b <= 0:
        var zero: Magnitude = [UInt64(0)]
        return zero^
    if len_a == 1:
        return _multiply_magnitude_by_word(b, a[0])
    if len_b == 1:
        return _multiply_magnitude_by_word(a, b[0])
    var len_max = max(len_a, len_b)
    if len_max <= CUTOFF_KARATSUBA:
        return _multiply_magnitudes_schoolbook(a, b)
    if len_max > CUTOFF_TOOM3:
        if bigint_ntt.should_multiply_ntt(len_a, len_b):
            return bigint_ntt.multiply_magnitudes_ntt(a, b)
        return _multiply_magnitudes_toom3(a, b)
    return _multiply_magnitudes_karatsuba(a, b)


def _decrement_inplace(mut a: Magnitude):
    """Subtracts 1 from a magnitude in-place. Assumes a > 0."""
    for i in range(len(a)):
        if a[i] > 0:
            a[i] -= 1
            return
        a[i] = ~UInt64(0)


def _divmod_knuth_d_from_slices(
    a: ImmSpan[UInt64, _],
    b: ImmSpan[UInt64, _],
    mut remainder: Magnitude,
) raises -> Magnitude:
    """Knuth Algorithm D operating directly on pre-normalized slices.

    Optimized for the B-Z base case: skips normalization/unnormalization
    since the B-Z top-level already ensures MSB of divisor's top word is set.
    Copies each slice exactly once (vs 2-3 copies in the general path).

    Args:
        a: Dividend slice (pre-normalized).
        b: Divisor slice (pre-normalized, MSB of top word set).
        remainder: Set to the normalized remainder on return.

    Returns:
        The normalized quotient words.
    """
    # Effective lengths after stripping leading zero words
    var len_a_eff = len(a)
    while len_a_eff > 0 and a[len_a_eff - 1] == 0:
        len_a_eff -= 1
    var len_b_eff = len(b)
    while len_b_eff > 0 and b[len_b_eff - 1] == 0:
        len_b_eff -= 1

    if len_a_eff <= 0:
        remainder = [UInt64(0)]
        return [UInt64(0)]
    if len_b_eff <= 0:
        raise ZeroDivisionError(
            function="_divmod_knuth_d_from_slices()",
            message="Division by zero in B-Z base case",
        )

    # Single-word divisor fast path
    if len_b_eff == 1:
        var a_slice = _normalized_copy(a[:len_a_eff])
        var r_word = UInt64(0)
        var q = _divmod_single_word(a_slice, b[0], r_word)
        remainder = [r_word]
        return q^

    # Compare magnitudes
    var cmp_len_diff = len_a_eff - len_b_eff
    if cmp_len_diff < 0:
        remainder = _normalized_copy(a[:len_a_eff])
        return [UInt64(0)]
    if cmp_len_diff == 0:
        # Same length — compare words from top
        var cmp = 0
        for i in range(len_a_eff - 1, -1, -1):
            var wa = a[i]
            var wb = b[i]
            if wa > wb:
                cmp = 1
                break
            elif wa < wb:
                cmp = -1
                break
        if cmp < 0:
            remainder = _normalized_copy(a[:len_a_eff])
            return [UInt64(0)]
        if cmp == 0:
            remainder = [UInt64(0)]
            return [UInt64(1)]

    # Copy a slice into u (single copy — u is modified in-place by Knuth D)
    var n = len_b_eff
    var m = len_a_eff - n
    var u = Magnitude(capacity=len_a_eff + 1)
    u.resize(unsafe_uninit_length=len_a_eff)
    unsafe_memcpy(dest=u.unsafe_ptr(), src=a.unsafe_ptr(), count=len_a_eff)
    # Ensure u has an extra leading word
    if len(u) <= m + n:
        u.append(UInt64(0))

    var quotient = Magnitude(capacity=m + 1)
    quotient.resize(unsafe_uninit_length=m + 1)
    unsafe_memset_zero(ptr=quotient.unsafe_ptr(), count=m + 1)

    # v_n_minus_1 and v_n_minus_2 read directly from b via offset
    var v_n_minus_1 = UInt64(b[n - 1])
    var v_n_minus_2 = UInt64(b[n - 2]) if n >= 2 else UInt64(0)
    debug_assert(
        v_n_minus_1 >= (UInt64(1) << 63),
        (
            "_divmod_knuth_d_from_slices() was handed an unnormalized divisor;"
            " the quotient estimate needs the top bit set"
        ),
    )
    var reciprocal = _reciprocal_word(v_n_minus_1)

    # Knuth D main loop.
    #
    # Every index below is provably in bounds, so none of them is checked:
    # `u` was grown to `m + n + 1` words above, `j` runs down from `m`, and
    # `i` stays under `n`, so `j + i <= m + n - 1` and `j + n <= m + n`. The
    # single-word divisor was handled earlier, so `n >= 2` and `j + n - 2`
    # cannot go negative either. The three buffers are borrowed through raw
    # pointers for the same reason the multiply kernels are: a `List[i]` reads
    # the list's `_data` field again on every element (Lesson 7). None of them
    # is resized while these pointers are live.
    var u_ptr = u.unsafe_ptr()
    var b_ptr = b.unsafe_ptr()
    var quotient_ptr = quotient.unsafe_ptr()

    for j in range(m, -1, -1):
        var u_jn = UInt64(u_ptr[unsafe_offset=j + n])
        var u_jn_minus_1 = UInt64(u_ptr[unsafe_offset=j + n - 1])
        var u_jn_minus_2 = UInt64(u_ptr[unsafe_offset=j + n - 2])

        # Knuth's step D3. The estimate is exact when the top dividend word is
        # below the top divisor word; where they are equal, `b - 1` is the
        # answer Knuth names directly and no division is needed for it either.
        # `r_hat` is two words wide because that case can carry it past `b`,
        # which is also where the refinement stops.
        var q_hat: UInt64
        var r_hat: UInt128
        if u_jn < v_n_minus_1:
            var estimate = _divide_two_by_one(
                u_jn, u_jn_minus_1, v_n_minus_1, reciprocal
            )
            q_hat = estimate[0]
            r_hat = UInt128(estimate[1])
        else:
            q_hat = ~UInt64(0)
            r_hat = UInt128(u_jn_minus_1) + UInt128(v_n_minus_1)

        while r_hat < RADIX and (
            UInt128(q_hat) * UInt128(v_n_minus_2)
            > (r_hat << 64) + UInt128(u_jn_minus_2)
        ):
            q_hat -= 1
            r_hat += UInt128(v_n_minus_1)

        # Multiply and subtract: u[j..j+n] -= q_hat * v[0..n-1]. This is where
        # division spends its time, so it has its own kernel; see
        # `_submul_words()`.
        var carry = _submul_words(u_ptr.unsafe_offset(j), b_ptr, n, q_hat)

        # Step D5. Taking the debt off the top word wraps exactly when the
        # estimate was one too large, which is the borrow the old base-2^32
        # form spelled as `BASE + u - carry`.
        var jn = j + n
        var top = u_ptr[unsafe_offset=jn]
        u_ptr[unsafe_offset=jn] = top - carry
        if top < carry:
            # Step D6, add back: u[j..j+n-1] += v
            q_hat -= 1
            var window = u_ptr.unsafe_offset(j)
            var add_carry = _add_words(
                window,
                alias_as_immutable_source(window),
                b_ptr,
                n,
                UInt64(0),
            )
            u_ptr[unsafe_offset=jn] = u_ptr[unsafe_offset=jn] + add_carry

        quotient_ptr[unsafe_offset=j] = UInt64(q_hat)

    # Extract remainder: first n words of u (no shift needed)
    while len(u) > n:
        u.shrink(len(u) - 1)
    # Strip leading zeros
    while len(quotient) > 1 and quotient[len(quotient) - 1] == 0:
        quotient.shrink(len(quotient) - 1)
    while len(u) > 1 and u[len(u) - 1] == 0:
        u.shrink(len(u) - 1)

    remainder = u^
    return quotient^


def _divmod_burnikel_ziegler(
    a: Magnitude, b: Magnitude, mut remainder: Magnitude
) raises -> Magnitude:
    """Divides magnitude a by magnitude b using Burnikel-Ziegler algorithm.

    Slice-based implementation: passes word-list bounds through the recursion
    to avoid copying the large inputs until the Knuth D base case.

    In base-2^64, normalization is a simple bit-shift (unlike base-10^9
    where multiplication by a normalization factor is needed).

    Args:
        a: The dividend magnitude (little-endian UInt64 words).
        b: The divisor magnitude (little-endian UInt64 words, non-zero).
        remainder: Set to the normalized remainder on return.

    Returns:
        The normalized quotient words.

    Raises:
        Error: If divisor is zero (should not happen; caller checks).
    """
    var block_size = CUTOFF_BURNIKEL_ZIEGLER

    # STEP 1: Normalize — bit-shift so the MSB of b's top word is set.
    var len_b = len(b)
    var bit_shift = _count_leading_zeros(b[len_b - 1])
    var norm_b = _shift_left_words(b, bit_shift)
    var norm_a = _shift_left_words(a, bit_shift)

    # STEP 2: Set n = number of words for the divisor block.
    #
    # `n` has to survive every halving the recursion performs, not just the
    # first one: `_bz_two_by_one_slices()` drops to Knuth D the moment it is
    # handed an odd block size, and Knuth D is O(n^2). Rounding up to even is
    # not enough, because evenness does not survive halving - a 20 762-word
    # divisor is even, but its half is 10 381, so the first recursive step
    # lands on a 10 381-word schoolbook division and the whole point of
    # Burnikel-Ziegler is lost. (Measured: a 100 000-digit division took
    # 81 ms this way against 26 ms for the same operands one power of two
    # smaller.)
    #
    # Pick `n = j * 2^k` instead, with `2^k` the smallest power of two that
    # brings `j` down to the cutoff. Halving then stays even until it reaches
    # `j`, which is small enough that Knuth D is the right answer. The padding
    # this costs is under one part in `CUTOFF_BURNIKEL_ZIEGLER`, far from the
    # round-up-to-`2^k * cutoff` scheme that would take 520 words to 1024.
    var len_norm_b = len(norm_b)
    var block_pow2 = 1
    while (len_norm_b + block_pow2 - 1) // block_pow2 > CUTOFF_BURNIKEL_ZIEGLER:
        block_pow2 <<= 1
    var n = ((len_norm_b + block_pow2 - 1) // block_pow2) * block_pow2

    # Pad both by prepending zeros (multiply by B^word_pad).
    var word_pad = n - len_norm_b
    if word_pad > 0:
        _shift_left_words_inplace(norm_b, word_pad)
        _shift_left_words_inplace(norm_a, word_pad)

    # STEP 3: Determine number of n-word blocks in the dividend.
    var len_norm_a = len(norm_a)
    var t = (len_norm_a + n - 1) // n
    if t < 2:
        t = 2

    if len_norm_a == t * n:
        if len_norm_a > 0 and (norm_a[len_norm_a - 1] & 0x80000000) != 0:
            t += 1

    # Pad norm_a to exactly t * n words.
    var target_len_a = t * n
    if len_norm_a < target_len_a:
        norm_a.resize(unsafe_uninit_length=target_len_a)
        for i in range(len_norm_a, target_len_a):
            norm_a[i] = UInt64(0)

    # STEP 4: Long division with n-word blocks (slice-based).
    # Pre-allocate quotient array: at most (t-1)*n words.
    var q_total_words = (t - 1) * n
    var quotient = Magnitude(capacity=q_total_words + 1)
    quotient.resize(unsafe_uninit_length=q_total_words)
    unsafe_memset_zero(ptr=quotient.unsafe_ptr(), count=q_total_words)

    # First iteration: divide top 2n words by norm_b.
    var z = Magnitude()
    var q_block = _bz_two_by_one_slices(
        _subspan(norm_a.as_span(), (t - 2) * n, t * n),
        _subspan(norm_b.as_span(), 0, n),
        n,
        block_size,
        z,
    )

    # Place first quotient digit at its position.
    _add_at_offset_inplace(quotient, q_block, (t - 2) * n)

    # Process remaining blocks from high to low.
    for i in range(t - 3, -1, -1):
        # z = z * B^n + block[i]
        _shift_left_words_inplace(z, n)
        _add_from_slice_inplace(
            z, _subspan(norm_a.as_span(), i * n, (i + 1) * n)
        )

        # Divide z by norm_b (slice-based). `z` is both the dividend and
        # where the next remainder goes, and it cannot be borrowed two ways at
        # once, so the new remainder lands beside it and is moved back over.
        var next_z = Magnitude()
        var q_i = _bz_two_by_one_slices(
            z.as_span(), _subspan(norm_b.as_span(), 0, n), n, block_size, next_z
        )
        z = next_z^

        # Place quotient digit at offset i*n
        _add_at_offset_inplace(quotient, q_i, i * n)

    # STEP 5: Un-normalize the remainder.
    if word_pad > 0:
        var r_stripped = _normalized_copy(
            _subspan(z.as_span(), word_pad, len(z))
        )
        _shift_right_words_inplace(r_stripped, bit_shift, len(r_stripped))
        remainder = r_stripped^
    else:
        _shift_right_words_inplace(z, bit_shift, len(z))
        remainder = z^

    # Normalize results
    while len(quotient) > 1 and quotient[len(quotient) - 1] == 0:
        quotient.shrink(len(quotient) - 1)
    while len(remainder) > 1 and remainder[len(remainder) - 1] == 0:
        remainder.shrink(len(remainder) - 1)

    return quotient^


def _bz_two_by_one_slices(
    a: ImmSpan[UInt64, _],
    b: ImmSpan[UInt64, _],
    n: Int,
    cutoff: Int,
    mut remainder: Magnitude,
) raises -> Magnitude:
    """Divides a (at most 2n words) by b (n words).

    Slice-based: a and b are borrowed views, not copied until the base case.
    Recursively splits into two 3-by-2 sub-problems.

    Args:
        a: The dividend slice.
        b: The divisor slice.
        n: Block size (number of words in the divisor slice).
        cutoff: Threshold for fallback to schoolbook.
        remainder: Set to the remainder of the division on return.

    Returns:
        The quotient words.
    """
    # Base case: use prenormalized Knuth D directly on slices (avoids
    # redundant normalization and reduces copies from 5 to 1).
    if (n & 1 == 1) or (n <= cutoff):
        return _divmod_knuth_d_from_slices(a, b, remainder)

    var half = n // 2

    # If a3 (top quarter, words n+half..2n) is zero or empty, the dividend
    # fits in 3*half words — use a single 3-by-2 division directly.
    if len(a) <= n + half or _is_zero_slice(a[n + half :]):
        return _bz_three_by_two_slices(a, b, half, cutoff, remainder)

    # First 3-by-2: divide a[half:] (= a3a2a1, 3*half words)
    # by b (= b1b0, 2*half words).
    var r = Magnitude()
    var q1 = _bz_three_by_two_slices(a[half:], b, half, cutoff, r)

    # Second 3-by-2: divide (r * B^half + a0) by b, where a0 = a[:half]
    _shift_left_words_inplace(r, half)
    _add_from_slice_inplace(r, _subspan(a, 0, half))

    # The final remainder is written straight into the caller's argument.
    var q0 = _bz_three_by_two_slices(r.as_span(), b, half, cutoff, remainder)

    # Combine: q = q1 * B^half + q0
    _shift_left_words_inplace(q1, half)
    _add_magnitudes_inplace(q1, q0)

    return q1^


def _bz_three_by_two_slices(
    a: ImmSpan[UInt64, _],
    b: ImmSpan[UInt64, _],
    n: Int,
    cutoff: Int,
    mut remainder: Magnitude,
) raises -> Magnitude:
    """Divides a 3n-word slice by a 2n-word slice.

    a = a2 * B^(2n) + a1 * B^n + a0  (at most 3n words)
    b = b1 * B^n + b0                (2n words)

    Uses one 2n-by-n division and one n-by-n multiplication.
    The correction loop (at most 2 iterations) ensures the remainder is
    non-negative.

    Args:
        a: Dividend slice.
        b: Divisor slice.
        n: Block size (number of words in each sub-part).
        cutoff: Threshold for fallback to schoolbook.
        remainder: Set to the remainder of the division on return.

    Returns:
        The quotient words.
    """
    # Sub-part views (no data copying here, just pointer/length arithmetic).
    # The high parts may run past the end of a short operand, in which case
    # the missing words are implicitly zero — hence `_subspan`.
    var b1 = _subspan(b, n, len(b))
    var b0 = _subspan(b, 0, n)
    var a0 = _subspan(a, 0, n)
    var a2a1 = _subspan(a, n, len(a))

    # (q, c) = divmod(a2a1, b1) — 2n-by-n division via recursion
    var c = Magnitude()
    var q = _bz_two_by_one_slices(a2a1, b1, n, cutoff, c)

    # d = q * b0 (multiply materialized q by slice of b — no b copy)
    var d = _multiply_magnitudes_slices(q.as_span(), b0)

    # r = c * B^n + a0 (shift c, then add slice of a — no a copy)
    _shift_left_words_inplace(c, n)
    _add_from_slice_inplace(c, a0)

    # Correction: if r < d, quotient was overestimated (at most by 2).
    if _compare_word_lists(c, d) < 0:
        # First correction: q -= 1, r += b_full
        _decrement_inplace(q)
        _add_from_slice_inplace(c, b)

        # Second correction if still r < d
        if _compare_word_lists(c, d) < 0:
            _decrement_inplace(q)
            _add_from_slice_inplace(c, b)

    # r -= d (now guaranteed r >= d)
    _subtract_magnitudes_inplace(c, d)

    # Strip leading zeros
    while len(q) > 1 and q[len(q) - 1] == 0:
        q.shrink(len(q) - 1)
    while len(c) > 1 and c[len(c) - 1] == 0:
        c.shrink(len(c) - 1)

    remainder = c^
    return q^


# ===----------------------------------------------------------------------=== #
# Public signed arithmetic functions
# ===----------------------------------------------------------------------=== #


def add(x1: BigInt, x2: BigInt) -> BigInt:
    """Returns the sum of two BigInt numbers.

    Args:
        x1: The first operand.
        x2: The second operand.

    Returns:
        The sum of the two BigInt numbers.
    """
    # Same sign: add magnitudes, preserve sign. First, because it is both the
    # common case and the one that does no comparison.
    if x1.sign == x2.sign:
        if x1.is_zero():
            return x2.copy()
        if x2.is_zero():
            return x1.copy()
        var result_words = _add_magnitudes(x1.words, x2.words)
        return BigInt(raw_words=result_words^, sign=x1.sign)

    # If one of the numbers is zero, return the other
    if x1.is_zero():
        return x2.copy()
    if x2.is_zero():
        return x1.copy()

    # Opposite signs: the magnitudes cancel, and the larger one wins the sign.
    # Done here rather than as `subtract(x1, -x2)` so that negating `x2` does
    # not copy its whole magnitude first.
    var cmp = compare_magnitudes(x1, x2)
    if cmp == 0:
        return BigInt()
    if cmp > 0:
        var result_words = _subtract_magnitudes(x1.words, x2.words)
        return BigInt(raw_words=result_words^, sign=x1.sign)
    var result_words = _subtract_magnitudes(x2.words, x1.words)
    return BigInt(raw_words=result_words^, sign=x2.sign)


def subtract(x1: BigInt, x2: BigInt) -> BigInt:
    """Returns the difference of two BigInt numbers.

    Args:
        x1: The first number (minuend).
        x2: The second number (subtrahend).

    Returns:
        The result of subtracting x2 from x1.
    """
    # If the subtrahend is zero, return the minuend
    if x2.is_zero():
        return x1.copy()
    # If the minuend is zero, return the negated subtrahend
    if x1.is_zero():
        return -x2

    # Different signs: a - (-b) = a + b, with a's sign. Inlined rather than
    # routed through `add(x1, -x2)` so that negating `x2` does not copy its
    # whole magnitude first.
    if x1.sign != x2.sign:
        var sum_words = _add_magnitudes(x1.words, x2.words)
        return BigInt(raw_words=sum_words^, sign=x1.sign)

    # Same sign: compare magnitudes to determine result sign
    var cmp = compare_magnitudes(x1, x2)

    if cmp == 0:
        return BigInt()  # Equal magnitudes → zero

    if cmp > 0:
        # |x1| > |x2|: subtract smaller from larger, keep x1's sign
        var result_words = _subtract_magnitudes(x1.words, x2.words)
        return BigInt(raw_words=result_words^, sign=x1.sign)
    else:
        # |x1| < |x2|: subtract larger from smaller, flip sign
        var result_words = _subtract_magnitudes(x2.words, x1.words)
        return BigInt(raw_words=result_words^, sign=not x1.sign)


def negative(x: BigInt) -> BigInt:
    """Returns the negative of a BigInt number.

    Args:
        x: The BigInt value to negate.

    Returns:
        A new BigInt containing the negative of x.
    """
    if x.is_zero():
        return BigInt()
    var result = x.copy()
    result.sign = not result.sign
    return result^


def absolute(x: BigInt) -> BigInt:
    """Returns the absolute value of a BigInt number.

    Args:
        x: The BigInt value to compute the absolute value of.

    Returns:
        A new BigInt containing |x|.
    """
    if x.sign:
        return -x
    else:
        return x.copy()


def multiply(x1: BigInt, x2: BigInt) -> BigInt:
    """Returns the product of two BigInt numbers.

    Dispatches on operand size through `_multiply_magnitudes()`: Toom-3,
    Karatsuba, or a product-scanning schoolbook base case.

    Args:
        x1: The first operand (multiplicand).
        x2: The second operand (multiplier).

    Returns:
        The product of the two BigInt numbers.
    """
    # Zero check
    if x1.is_zero() or x2.is_zero():
        return BigInt()

    var result_words = _multiply_magnitudes(x1.words, x2.words)
    return BigInt(raw_words=result_words^, sign=x1.sign != x2.sign)


# ===----------------------------------------------------------------------=== #
# True in-place signed arithmetic functions
# These modify the first operand directly without allocating a new BigInt.
# ===----------------------------------------------------------------------=== #


def _compare_magnitudes_words(imm a: Magnitude, imm b: Magnitude) -> Int8:
    """Compares the magnitudes of two word lists.

    Returns:
        1 if a > b, 0 if a == b, -1 if a < b.
    """
    var n_a = len(a)
    var n_b = len(b)
    if n_a != n_b:
        return Int8(1) if n_a > n_b else Int8(-1)
    for i in range(n_a - 1, -1, -1):
        if a[i] != b[i]:
            return Int8(1) if a[i] > b[i] else Int8(-1)
    return 0


def add_inplace(mut x: BigInt, imm other: BigInt):
    """Performs x += other by mutating x.words directly.

    Avoids allocating a new BigInt. Uses the existing _add_magnitudes_inplace
    and _subtract_magnitudes_inplace helpers for the magnitude operations.

    Args:
        x: The accumulator (modified in-place).
        other: The value to add.
    """
    # x += 0 is a no-op
    if other.is_zero():
        return

    # 0 += other → copy other into x
    if x.is_zero():
        x.words = other.words.copy()
        x.sign = other.sign
        return

    if x.sign == other.sign:
        # Same sign: add magnitudes, preserve sign
        _add_magnitudes_inplace(x.words, other.words)
    else:
        # Different signs: subtract smaller magnitude from larger
        var cmp = _compare_magnitudes_words(x.words, other.words)
        if cmp == 0:
            # Equal magnitudes → result is zero
            x.words.clear()
            x.words.append(UInt64(0))
            x.sign = False
        elif cmp > 0:
            # |x| > |other|: x.words -= other.words, keep x.sign
            _subtract_magnitudes_inplace(x.words, other.words)
        else:
            # |x| < |other|: result = other.words - x.words, flip sign
            # We need a temporary since _subtract_magnitudes_inplace
            # requires a >= b
            var result = _subtract_magnitudes(other.words, x.words)
            x.words = result^
            x.sign = other.sign


def add_int_inplace(mut x: BigInt, value: Int):
    """Performs x += value (Int) by mutating x.words directly.

    Optimized for adding a small integer: avoids constructing a full BigInt.
    Handles the common cases of adding +1, -1, or any Int-sized value.

    Args:
        x: The accumulator (modified in-place).
        value: The integer value to add.
    """
    if value == 0:
        return

    # For zero x, just set the value
    if x.is_zero():
        var magnitude: UInt
        if value < 0:
            x.sign = True
            if value == Int.MIN:
                magnitude = UInt(Int.MAX) + 1
            else:
                magnitude = UInt(-value)
        else:
            x.sign = False
            magnitude = UInt(value)
        # One word holds the whole magnitude of any `Int`, so there is no
        # loop to run -- and a loop here would not terminate anyway: shifting
        # a 64-bit value right by 64 is undefined, and on arm64 the shift
        # amount is taken modulo the width, so `>>= 64` leaves it unchanged.
        x.words.clear()
        x.words.append(UInt64(magnitude))
        return

    # Determine other's sign and magnitude words
    var other_sign: Bool
    var other_magnitude: UInt
    if value < 0:
        other_sign = True
        if value == Int.MIN:
            other_magnitude = UInt(Int.MAX) + 1
        else:
            other_magnitude = UInt(-value)
    else:
        other_sign = False
        other_magnitude = UInt(value)

    # One word holds the whole magnitude of any `Int`; see above for why this
    # must not be written as a shift loop.
    var other_words = Magnitude(capacity=1)
    other_words.append(UInt64(other_magnitude))

    if x.sign == other_sign:
        # Same sign: add magnitudes
        _add_magnitudes_inplace(x.words, other_words)
    else:
        # Different signs: subtract
        var cmp = _compare_magnitudes_words(x.words, other_words)
        if cmp == 0:
            x.words.clear()
            x.words.append(UInt64(0))
            x.sign = False
        elif cmp > 0:
            _subtract_magnitudes_inplace(x.words, other_words)
        else:
            var result = _subtract_magnitudes(other_words, x.words)
            x.words = result^
            x.sign = other_sign


def subtract_inplace(mut x: BigInt, imm other: BigInt):
    """Performs x -= other by mutating x.words directly.

    Avoids allocating a new BigInt. Leverages the relationship:
    x -= other is equivalent to x += (-other), i.e., flip other's sign
    and apply add_inplace logic.

    Args:
        x: The accumulator (modified in-place).
        other: The value to subtract.
    """
    # x -= 0 is a no-op
    if other.is_zero():
        return

    # 0 -= other → negate other into x
    if x.is_zero():
        x.words = other.words.copy()
        x.sign = not other.sign
        # Normalize -0
        if x.is_zero():
            x.sign = False
        return

    # x -= other with same sign is like subtracting magnitudes
    # x -= other with different signs is like adding magnitudes
    # (equivalent to x += (-other))
    var effective_other_sign = not other.sign

    if x.sign == effective_other_sign:
        # Same effective sign: add magnitudes, preserve sign
        _add_magnitudes_inplace(x.words, other.words)
    else:
        # Different effective signs: subtract smaller from larger
        var cmp = _compare_magnitudes_words(x.words, other.words)
        if cmp == 0:
            x.words.clear()
            x.words.append(UInt64(0))
            x.sign = False
        elif cmp > 0:
            _subtract_magnitudes_inplace(x.words, other.words)
        else:
            var result = _subtract_magnitudes(other.words, x.words)
            x.words = result^
            x.sign = effective_other_sign


def multiply_inplace(mut x: BigInt, imm other: BigInt):
    """Performs x *= other by computing the product and moving the result
    into x.words.

    Multiplication cannot be done truly in-place (input words are read
    during output computation), so this computes a new word list and moves
    it into x. This still avoids the overhead of constructing a full BigInt
    object with its __init__ validation.

    Args:
        x: The accumulator (modified in-place).
        other: The multiplier.
    """
    # Zero check
    if x.is_zero():
        return
    if other.is_zero():
        x.words.clear()
        x.words.append(UInt64(0))
        x.sign = False
        return

    var result_words = _multiply_magnitudes(x.words, other.words)
    x.words = result_words^
    x.sign = x.sign != other.sign


def multiply_by_word_inplace(mut x: BigInt, word: UInt64):
    """Multiplies a BigInt in place by a single UInt64 word.

    Only the magnitude is scaled; the sign is preserved (a zero result is
    normalized to non-negative). Unlike `_multiply_magnitude_by_word`, no new
    list is allocated, which makes this cheap to call repeatedly (e.g.
    accumulating a product of small factors).

    Args:
        x: The accumulator (modified in-place).
        word: The single-word multiplier.
    """
    # Keep the magnitude non-empty so the BigInt invariant holds even if an
    # uninitialized value is passed in.
    if len(x.words) == 0:
        x.words.append(UInt64(0))
    if word == 0:
        # Anything times zero is zero, in canonical single-word form.
        x.words.clear()
        x.words.append(UInt64(0))
        x.sign = False
        return
    if word == 1:
        return
    var multiplier = UInt128(word)
    var carry: UInt64 = 0
    for j in range(len(x.words)):
        var product = UInt128(x.words[j]) * multiplier + UInt128(carry)
        x.words[j] = UInt64(product)
        carry = UInt64(product >> 64)
    if carry != 0:
        x.words.append(UInt64(carry))


def left_shift_inplace(mut x: BigInt, shift: Int):
    """Performs x <<= shift by writing straight into x.words.

    Shifts left by `shift` bits, which is a multiplication by 2^shift.

    Args:
        x: The value to shift (modified in-place).
        shift: The number of bits to shift left.

    Notes:

    This is `left_shift()` written a second time, and it is deliberate. A left
    shift lengthens the value, so both forms allocate a fresh `Magnitude` and
    the delegating version looks free -- but `Magnitude` keeps small values
    inside the struct, so assigning the returned `BigInt` copies that inline
    buffer rather than moving a pointer. Measured, ns per `<<=` and `>>` pair,
    two runs each:

    | words | delegating  | this   |
    | ----- | ----------- | ------ |
    |     2 | 28.4, 31.1  | 18.6, 22.7 |
    |     8 | 154.8, 140.2| 145.6, 150.6 |
    |    32 | 210.5, 187.7| 197.8, 204.2 |

    Small values pay about 1.4x for the delegation, and everything above that
    is noise. Small values are the common case here, so the copy stays.
    """
    if x.is_zero() or shift == 0:
        return

    if shift < 0:
        right_shift_inplace(x, -shift)
        return

    # Split shift into whole-word and sub-word parts
    var word_shift = shift // 64
    var bit_shift = shift % 64

    var n = len(x.words)
    var new_len = n + word_shift + (1 if bit_shift > 0 else 0)
    var new_words = Magnitude(capacity=new_len)

    # Prepend zero words for the whole-word shift
    for _ in range(word_shift):
        new_words.append(UInt64(0))

    # Shift existing words (low to high, with carry propagation)
    if bit_shift == 0:
        for i in range(n):
            new_words.append(x.words[i])
    else:
        var carry: UInt64 = 0
        var carry_shift = UInt64(64 - bit_shift)
        for i in range(n):
            var word = x.words[i]
            new_words.append((word << UInt64(bit_shift)) | carry)
            carry = word >> carry_shift
        if carry > 0:
            new_words.append(carry)

    x.words = new_words^


def right_shift_inplace(mut x: BigInt, shift: Int):
    """Performs x >>= shift by mutating x.words directly.

    For negative numbers, performs arithmetic right shift (rounds toward
    negative infinity), consistent with Python's behavior.

    Args:
        x: The value to shift (modified in-place).
        shift: The number of bits to shift right.
    """
    if x.is_zero() or shift == 0:
        return

    if shift < 0:
        left_shift_inplace(x, -shift)
        return

    var word_shift = shift // 64
    var bit_shift = shift % 64
    var n = len(x.words)

    # If shifting by more words than we have, result is 0 or -1
    if word_shift >= n:
        if x.sign:
            # -1
            x.words.clear()
            x.words.append(UInt64(1))
            # sign stays True
        else:
            x.words.clear()
            x.words.append(UInt64(0))
            x.sign = False
        return

    # For negative numbers, check if any bits will be lost (for rounding)
    var any_bits_lost = False
    if x.sign:
        # Check sub-word bits of the boundary word
        if bit_shift > 0:
            var mask = UInt64((1 << bit_shift) - 1)
            if (x.words[word_shift] & mask) != 0:
                any_bits_lost = True
        # Check fully-shifted-out words
        if not any_bits_lost:
            for i in range(min(word_shift, n)):
                if x.words[i] != 0:
                    any_bits_lost = True
                    break

    # Perform the shift in-place
    var new_len = n - word_shift
    if bit_shift == 0:
        for i in range(new_len):
            x.words[i] = x.words[i + word_shift]
    else:
        for i in range(new_len):
            var lo = x.words[i + word_shift] >> UInt64(bit_shift)
            var hi: UInt64 = 0
            if i + word_shift + 1 < n:
                hi = x.words[i + word_shift + 1] << UInt64(64 - bit_shift)
            x.words[i] = UInt64(lo | hi)

    # Truncate to new length in a single shrink call
    if len(x.words) > new_len:
        x.words.shrink(new_len)

    # Leading zero words are left for the `_normalize()` below. Adding one to
    # the magnitude carries from the bottom word, so it does not care.

    # For negative numbers with lost bits, round toward negative infinity
    if x.sign and any_bits_lost:
        var carry: UInt64 = 1
        for i in range(len(x.words)):
            var s = x.words[i] + carry
            x.words[i] = s
            carry = UInt64(s < carry)
            if carry == 0:
                break
        if carry > 0:
            x.words.append(UInt64(carry))

    x._normalize()


def floor_divide_inplace(mut x: BigInt, imm other: BigInt) raises:
    """Performs x //= other by computing the quotient and moving the result
    into x.words.

    Division cannot be done truly in-place due to the nature of the algorithm,
    so this computes the quotient word list and moves it into x. This avoids
    the overhead of constructing a full BigInt object.

    Args:
        x: The dividend (modified in-place to hold the quotient).
        other: The divisor.

    Raises:
        ZeroDivisionError: If the divisor is zero.
    """
    var r_words = Magnitude()
    var q_words = _divmod_magnitudes(x.words, other.words, r_words)

    # Check if remainder is zero
    var r_is_zero = True
    for word in r_words:
        if word != 0:
            r_is_zero = False
            break

    if x.sign == other.sign:
        # Same signs → positive quotient (floor = truncate)
        x.words = q_words^
        x.sign = False
    else:
        # Different signs → negative quotient
        if r_is_zero:
            var q_is_zero = True
            for word in q_words:
                if word != 0:
                    q_is_zero = False
                    break
            x.words = q_words^
            x.sign = not q_is_zero
        else:
            # Non-exact: floor division rounds away from zero for negative
            _add_magnitudes_inplace(q_words, UInt64(1))
            x.words = q_words^
            x.sign = True

    x._normalize()


def floor_modulo_inplace(mut x: BigInt, imm other: BigInt) raises:
    """Performs x %= other by computing the remainder and moving the result
    into x.words.

    Args:
        x: The dividend (modified in-place to hold the remainder).
        other: The divisor.

    Raises:
        ZeroDivisionError: If the divisor is zero.
    """
    var r_words = Magnitude()
    _ = _divmod_magnitudes(x.words, other.words, r_words)

    # Check if remainder is zero
    var r_is_zero = True
    for word in r_words:
        if word != 0:
            r_is_zero = False
            break

    if r_is_zero:
        x.words.clear()
        x.words.append(UInt64(0))
        x.sign = False
        return

    if x.sign == other.sign:
        # Same signs: remainder has the same sign as x1 (and x2)
        x.words = r_words^
        # x.sign stays the same (already equals other.sign)
    else:
        # Different signs: floor_mod = |divisor| - |remainder|
        var adjusted = _subtract_magnitudes(other.words, r_words)
        x.words = adjusted^
        x.sign = other.sign

    x._normalize()


def floor_divide(x1: BigInt, x2: BigInt) raises -> BigInt:
    """Returns the quotient of two BigInt numbers, rounding toward negative
    infinity.

    The result satisfies: x1 = floor_divide(x1, x2) * x2 + floor_modulo(x1, x2).

    For same signs, this is the same as truncated division.
    For different signs with a non-zero remainder, the quotient is one less
    (more negative) than the truncated quotient.

    Args:
        x1: The dividend.
        x2: The divisor.

    Returns:
        The quotient of x1 / x2, rounded toward negative infinity.

    Raises:
        ZeroDivisionError: If the divisor is zero.
    """
    var r_words = Magnitude()
    var q_words = _divmod_magnitudes(x1.words, x2.words, r_words)

    # Check if remainder is zero
    var r_is_zero = True
    for word in r_words:
        if word != 0:
            r_is_zero = False
            break

    if x1.sign == x2.sign:
        # Same signs → positive quotient (floor = truncate)
        return BigInt(raw_words=q_words^, sign=False)
    else:
        # Different signs → negative quotient
        if r_is_zero:
            # Exact division: check if quotient is zero (no -0)
            var q_is_zero = True
            for word in q_words:
                if word != 0:
                    q_is_zero = False
                    break
            return BigInt(raw_words=q_words^, sign=not q_is_zero)
        else:
            # Non-exact: floor division rounds away from zero for negative
            # results, so quotient = -(|q| + 1)
            var q_plus_one = _add_magnitudes(q_words, UInt64(1))
            return BigInt(raw_words=q_plus_one^, sign=True)


def truncate_divide(x1: BigInt, x2: BigInt) raises -> BigInt:
    """Returns the quotient of two BigInt numbers, truncating toward zero.

    The result satisfies: x1 = truncate_divide(x1, x2) * x2 + truncate_modulo(x1, x2).

    Args:
        x1: The dividend.
        x2: The divisor.

    Returns:
        The quotient of x1 / x2, truncated toward zero.

    Raises:
        ZeroDivisionError: If the divisor is zero.
    """
    var discarded_remainder = Magnitude()
    var q_words = _divmod_magnitudes(x1.words, x2.words, discarded_remainder)

    # Sign is XOR of operand signs (positive if same, negative if different)
    # But if quotient is zero, sign should be positive
    var q_is_zero = True
    for word in q_words:
        if word != 0:
            q_is_zero = False
            break

    var sign = False if q_is_zero else (x1.sign != x2.sign)
    return BigInt(raw_words=q_words^, sign=sign)


def floor_modulo(x1: BigInt, x2: BigInt) raises -> BigInt:
    """Returns the floor modulo (remainder) of two BigInt numbers.

    The result has the same sign as the divisor and satisfies:
    x1 = floor_divide(x1, x2) * x2 + floor_modulo(x1, x2).

    Args:
        x1: The dividend.
        x2: The divisor.

    Returns:
        The remainder with the same sign as x2.

    Raises:
        ZeroDivisionError: If the divisor is zero.
    """
    var r_words = Magnitude()
    _ = _divmod_magnitudes(x1.words, x2.words, r_words)

    # Check if remainder is zero
    var r_is_zero = True
    for word in r_words:
        if word != 0:
            r_is_zero = False
            break

    if r_is_zero:
        return BigInt()

    if x1.sign == x2.sign:
        # Same signs: remainder has the same sign as x1 (and x2)
        return BigInt(raw_words=r_words^, sign=x1.sign)
    else:
        # Different signs: floor_mod = |divisor| - |remainder|
        # and the result has the sign of the divisor
        var adjusted = _subtract_magnitudes(x2.words, r_words)
        return BigInt(raw_words=adjusted^, sign=x2.sign)


def truncate_modulo(x1: BigInt, x2: BigInt) raises -> BigInt:
    """Returns the truncate modulo (remainder) of two BigInt numbers.

    The result has the same sign as the dividend and satisfies:
    x1 = truncate_divide(x1, x2) * x2 + truncate_modulo(x1, x2).

    Args:
        x1: The dividend.
        x2: The divisor.

    Returns:
        The remainder with the same sign as x1.

    Raises:
        ZeroDivisionError: If the divisor is zero.
    """
    var r_words = Magnitude()
    _ = _divmod_magnitudes(x1.words, x2.words, r_words)

    # Check if remainder is zero
    var r_is_zero = True
    for word in r_words:
        if word != 0:
            r_is_zero = False
            break

    if r_is_zero:
        return BigInt()

    # Truncate modulo: remainder has the same sign as the dividend
    return BigInt(raw_words=r_words^, sign=x1.sign)


def floor_divmod(x1: BigInt, x2: BigInt) raises -> Tuple[BigInt, BigInt]:
    """Returns both the floor quotient and floor remainder.

    The result satisfies: x1 = q * x2 + r, where r has same sign as x2.

    Args:
        x1: The dividend.
        x2: The divisor.

    Returns:
        A tuple of (quotient, remainder).

    Raises:
        ZeroDivisionError: If the divisor is zero.
    """
    var r_words = Magnitude()
    var q_words = _divmod_magnitudes(x1.words, x2.words, r_words)

    # Check if remainder is zero
    var r_is_zero = True
    for word in r_words:
        if word != 0:
            r_is_zero = False
            break

    if x1.sign == x2.sign:
        # Same signs → positive quotient (floor = truncate)
        var q = BigInt(raw_words=q_words^, sign=False)
        if r_is_zero:
            return (q^, BigInt())
        return (q^, BigInt(raw_words=r_words^, sign=x1.sign))
    else:
        # Different signs → negative quotient
        if r_is_zero:
            var q_is_zero = True
            for word in q_words:
                if word != 0:
                    q_is_zero = False
                    break
            return (BigInt(raw_words=q_words^, sign=not q_is_zero), BigInt())
        else:
            # floor_div rounds toward negative infinity, mod has sign of divisor
            var q_plus_one = _add_magnitudes(q_words, UInt64(1))
            var adjusted = _subtract_magnitudes(x2.words, r_words)
            return (
                BigInt(raw_words=q_plus_one^, sign=True),
                BigInt(raw_words=adjusted^, sign=x2.sign),
            )


def power(base: BigInt, exponent: Int) raises -> BigInt:
    """Raises a BigInt to the power of a non-negative integer exponent.

    Uses binary exponentiation (exponentiation by squaring) for O(log n)
    multiplications.

    Args:
        base: The `BigInt` to raise to a power.
        exponent: The non-negative exponent.

    Returns:
        The result of base raised to the given exponent.

    Raises:
        ValueError: If the exponent is negative.
        ValueError: If the exponent is too large (>= 1_000_000_000).
    """
    if exponent < 0:
        raise ValueError(
            function="power()",
            message=(
                "The exponent "
                + String(exponent)
                + " is negative.\n"
                + "Consider using a non-negative exponent."
            ),
        )

    if exponent == 0:
        return BigInt(1)

    if exponent >= 1_000_000_000:
        raise ValueError(
            function="power()",
            message=(
                "The exponent "
                + String(exponent)
                + " is too large.\n"
                + "Consider using an exponent below 1_000_000_000."
            ),
        )

    if base.is_zero():
        return BigInt()

    if base.is_one():
        return BigInt(1)

    # Fast path: base = ±2, use left shift
    if len(base.words) == 1 and base.words[0] == 2:
        var result_sign = base.sign and (exponent % 2 == 1)
        var result = left_shift(BigInt(1), exponent)
        result.sign = result_sign
        return result^

    # Determine result sign: negative only if base is negative and exp is odd
    var result_sign = base.sign and (exponent % 2 == 1)

    # Binary exponentiation on the magnitude
    var result_words: Magnitude = [UInt64(1)]
    var base_words = Magnitude(capacity=len(base.words))
    for word in base.words:
        base_words.append(word)

    var exp = exponent
    while exp > 0:
        if exp & 1 == 1:
            result_words = _multiply_magnitudes(result_words, base_words)
        exp >>= 1
        if exp > 0:
            base_words = _multiply_magnitudes(base_words, base_words)

    return BigInt(raw_words=result_words^, sign=result_sign)


def left_shift(x: BigInt, shift: Int) -> BigInt:
    """Shifts a BigInt left by `shift` bits (multiply by 2^shift).

    This is an efficient operation for base-2^64 representation since it
    operates directly on the word boundaries.

    Args:
        x: The value to shift.
        shift: The number of bits to shift left (must be non-negative).

    Returns:
        The result of shifting x left by shift bits.
    """
    if x.is_zero() or shift == 0:
        return x.copy()

    if shift < 0:
        return right_shift(x, -shift)

    # Split shift into whole-word and sub-word parts
    var word_shift = shift // 64
    var bit_shift = shift % 64

    var n = len(x.words)
    var new_len = n + word_shift + (1 if bit_shift > 0 else 0)
    var result = Magnitude(capacity=new_len)

    # Prepend zero words for the whole-word shift
    for _ in range(word_shift):
        result.append(UInt64(0))

    # Shift the existing words
    if bit_shift == 0:
        for i in range(n):
            result.append(x.words[i])
    else:
        var carry: UInt64 = 0
        var carry_shift = UInt64(64 - bit_shift)
        for i in range(n):
            var word = x.words[i]
            result.append((word << UInt64(bit_shift)) | carry)
            carry = word >> carry_shift
        if carry > 0:
            result.append(carry)

    return BigInt(raw_words=result^, sign=x.sign)


def right_shift(x: BigInt, shift: Int) -> BigInt:
    """Shifts a BigInt right by `shift` bits (floor divide by 2^shift).

    For negative numbers, this performs an arithmetic right shift (rounds
    toward negative infinity), consistent with Python's behavior.

    Args:
        x: The value to shift.
        shift: The number of bits to shift right (must be non-negative).

    Returns:
        The result of shifting x right by shift bits (floor division).
    """
    if x.is_zero() or shift == 0:
        return x.copy()

    if shift < 0:
        return left_shift(x, -shift)

    # Split shift into whole-word and sub-word parts
    var word_shift = shift // 64
    var bit_shift = shift % 64

    var n = len(x.words)

    # If shifting by more words than we have, result is 0 or -1
    if word_shift >= n:
        if x.sign:
            return BigInt.negative_one()
        return BigInt()

    var new_len = n - word_shift
    var result = Magnitude(capacity=new_len)

    if bit_shift == 0:
        for i in range(word_shift, n):
            result.append(x.words[i])
    else:
        for i in range(word_shift, n):
            var lo = x.words[i] >> UInt64(bit_shift)
            var hi: UInt64 = 0
            if i + 1 < n:
                hi = x.words[i + 1] << UInt64(64 - bit_shift)
            result.append(lo | hi)

    # Leading zero words are left for the `_normalize()` below.
    var shifted = BigInt(raw_words=result^, sign=x.sign)

    # For negative numbers, if any shifted-out bits were set, round toward
    # negative infinity (subtract 1 from the result)
    if x.sign:
        var any_bits_lost = False
        # Check sub-word bits of the first skipped word. `word_shift < n`
        # here, or the early return above would have taken it.
        if bit_shift > 0:
            var mask = UInt64((1 << bit_shift) - 1)
            if (x.words[word_shift] & mask) != 0:
                any_bits_lost = True
        # Check fully-shifted-out words
        if not any_bits_lost:
            for i in range(min(word_shift, n)):
                if x.words[i] != 0:
                    any_bits_lost = True
                    break

        if any_bits_lost:
            # Round toward negative infinity by adding 1 to the magnitude
            var carry: UInt64 = 1
            for i in range(len(shifted.words)):
                var s = shifted.words[i] + carry
                shifted.words[i] = s
                carry = UInt64(s < carry)
                if carry == 0:
                    break
            if carry > 0:
                shifted.words.append(UInt64(carry))

    shifted._normalize()
    return shifted^
