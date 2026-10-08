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

"""Implements exponential functions for the BigInt type.

This module provides the integer square root. A one-word value is answered by
hardware; up to `CUTOFF_SQRT_RECURSIVE` words the value goes through CPython's
precision-doubling algorithm, with a `UInt64` and `UInt128` fast path for the
early iterations; above it, through Zimmermann's recursion. It also provides
the fixed-point reciprocal square root that `BigDecimal` builds on.
"""

from std import math

import decimo.bigint.arithmetics as bigint_arithmetics
from decimo.bigint.bigint import BigInt, Magnitude
import decimo.biguint.exponential as biguint_exponential
from decimo.errors import ValueError
from decimo.utility import isqrt_uint128, isqrt_uint64


# ===----------------------------------------------------------------------=== #
# Word-list helper functions for sqrt
# ===----------------------------------------------------------------------=== #


def _extract_uint64_from_words(words: Magnitude, bit_shift: Int) -> UInt64:
    """Extracts up to 64 bits from a magnitude at a given bit offset.

    Computes floor(value(words) >> bit_shift) mod 2^64, reading only the
    one or two words that overlap with the window. O(1) with no allocation.

    Args:
        words: The magnitude as little-endian UInt64 words.
        bit_shift: The number of bits to shift right before extracting.

    Returns:
        The extracted 64-bit value.
    """
    var wi = bit_shift // 64
    var bi = bit_shift % 64
    var n = len(words)

    if wi >= n:
        return 0

    # A 64-bit window aligned to a word is exactly that word; unaligned it
    # straddles two, and never more.
    if bi == 0:
        return words[wi]

    var result = words[wi] >> UInt64(bi)
    if wi + 1 < n:
        result |= words[wi + 1] << UInt64(64 - bi)
    return result


def _uint64_to_words(val: UInt64) -> Magnitude:
    """Converts a UInt64 value to a magnitude word list.

    Args:
        val: The UInt64 value to convert.

    Returns:
        A Magnitude representing the magnitude in little-endian order.
    """
    var result: Magnitude = [val]
    return result^


def _extract_uint128_from_words(words: Magnitude, bit_shift: Int) -> UInt128:
    """Extracts up to 128 bits from a magnitude at a given bit offset.

    Similar to _extract_uint64_from_words but returns UInt128.
    Reads only the two or three words that overlap with the window.

    Args:
        words: The magnitude as little-endian UInt64 words.
        bit_shift: The number of bits to shift right before extracting.

    Returns:
        The extracted 128-bit value.
    """
    var wi = bit_shift // 64
    var bi = bit_shift % 64
    var n = len(words)

    if wi >= n:
        return UInt128(0)

    if bi == 0:
        # Aligned: exactly two words
        var result = UInt128(words[wi])
        if wi + 1 < n:
            result |= UInt128(words[wi + 1]) << 64
        return result

    # Unaligned: bits [bi .. bi+127] span three words
    var result = UInt128(words[wi]) >> UInt128(bi)
    if wi + 1 < n:
        result |= UInt128(words[wi + 1]) << UInt128(64 - bi)
    if wi + 2 < n:
        result |= UInt128(words[wi + 2]) << UInt128(128 - bi)
    return result


def _uint128_to_words(val: UInt128) -> Magnitude:
    """Converts a UInt128 value to a magnitude word list.

    Args:
        val: The UInt128 value to convert.

    Returns:
        A Magnitude representing the magnitude in little-endian order.
    """
    if val == 0:
        var result: Magnitude = [UInt64(0)]
        return result^

    var result = Magnitude(capacity=2)
    var remaining = val
    while remaining != 0:
        result.append(UInt64(remaining))
        remaining >>= 64

    return result^


def _left_shift_magnitude_bits(a: Magnitude, shift: Int) -> Magnitude:
    """Shifts a magnitude left by an arbitrary number of bits.

    Handles both whole-word and sub-word shifts in a single pass.

    Args:
        a: The magnitude to shift (little-endian UInt64 words).
        shift: The number of bits to shift left (must be >= 0).

    Returns:
        The shifted magnitude as a new word list.
    """
    if shift == 0 or (len(a) == 1 and a[0] == 0):
        var copy = Magnitude(capacity=len(a))
        for word in a:
            copy.append(word)
        return copy^

    var word_shift = shift // 64
    var bit_shift = shift % 64
    var n = len(a)
    var new_len = n + word_shift + (1 if bit_shift > 0 else 0)
    var result = Magnitude(capacity=new_len)

    # Prepend zero words for the whole-word shift
    for _ in range(word_shift):
        result.append(UInt64(0))

    # Shift the existing words with sub-word carry
    if bit_shift == 0:
        for i in range(n):
            result.append(a[i])
    else:
        var carry: UInt64 = 0
        var carry_shift = UInt64(64 - bit_shift)
        for i in range(n):
            var word = a[i]
            result.append((word << UInt64(bit_shift)) | carry)
            carry = word >> carry_shift
        if carry > 0:
            result.append(carry)

    return result^


def _right_shift_magnitude_bits(a: Magnitude, shift: Int) -> Magnitude:
    """Shifts a magnitude right by an arbitrary number of bits.

    Efficiently skips lower words that would be entirely shifted out,
    only processing the relevant upper portion.

    Args:
        a: The magnitude to shift (little-endian UInt64 words).
        shift: The number of bits to shift right (must be >= 0).

    Returns:
        The shifted magnitude as a new word list, normalized.
    """
    var word_shift = shift // 64
    var bit_shift = shift % 64
    var n = len(a)

    if word_shift >= n:
        var zero: Magnitude = [UInt64(0)]
        return zero^

    var new_len = n - word_shift
    var result = Magnitude(capacity=new_len)

    if bit_shift == 0:
        for i in range(word_shift, n):
            result.append(a[i])
    else:
        for i in range(word_shift, n):
            var lo = a[i] >> UInt64(bit_shift)
            var hi: UInt64 = 0
            if i + 1 < n:
                hi = a[i + 1] << UInt64(64 - bit_shift)
            result.append(lo | hi)

    # Strip leading zeros
    while len(result) > 1 and result[len(result) - 1] == 0:
        result.shrink(len(result) - 1)
    if len(result) == 0:
        result.append(UInt64(0))

    return result^


# ===----------------------------------------------------------------------=== #
# Square Root
# ===----------------------------------------------------------------------=== #


def sqrt(x: BigInt) raises -> BigInt:
    """Calculates the integer square root of a BigInt.

    Args:
        x: The BigInt to calculate the square root of. Must be non-negative.

    Returns:
        The integer square root of x.

    Raises:
        ValueError: If x is negative.

    Notes:

    The result is the largest integer y such that y * y <= x
    (for non-negative x).

    Algorithm (CPython precision-doubling, adapted from Modules/mathmodule.c):
    Uses a series of precision-doubling steps starting from a 1-bit
    approximation. At each step, the approximation doubles in precision
    via a division of the appropriate size. Total work is dominated by
    the last step, giving O(M(n)) total where M(n) is multiplication
    cost, rather than O(M(n) * log n) for standard Newton's method.

    For small inputs (1-2 words), uses hardware sqrt directly.
    For all larger inputs, uses an optimized precision-doubling algorithm
    with a UInt64 fast path that handles the first 5-7 iterations using
    native 64-bit arithmetic (no heap allocation, O(1) per iteration).
    """
    if x.is_negative():
        raise ValueError(
            function="sqrt()",
            message="Cannot compute square root of a negative number",
        )

    if x.is_zero():
        return BigInt()

    # One word: the value fits a UInt64 and hardware can answer it. Two used
    # to as well, back when a word was half as wide.
    if len(x.words) == 1:
        if x.words[0] <= 1:
            return x.copy()
        return BigInt.from_integral_scalar(isqrt_uint64(x.words[0]))

    # Past the crossover, Zimmermann's recursion: its division is half the
    # width of the one precision-doubling finishes on, and it carries its
    # remainder rather than recovering it with a full-width squaring.
    if len(x.words) > CUTOFF_SQRT_RECURSIVE:
        return _sqrt_karatsuba(x)

    # For all larger inputs: optimized precision-doubling with UInt64 fast path
    return _sqrt_precision_doubling_fast(x)


def _sqrt_precision_doubling_fast(x: BigInt) raises -> BigInt:
    """Precision-doubling integer sqrt with a UInt64 fast path.

    Args:
        x: The BigInt value (must be positive, at least two words).

    Returns:
        The integer square root.

    Notes:

    Adapted from CPython Modules/mathmodule.c. Each iteration doubles
    the precision of the approximation. Total cost is O(M(n)).

    Phase 1 (UInt64):
    Uses hardware UInt64 arithmetic for early iterations where all
    intermediate values (a, n_shifted, quotient) fit in 64-bit
    machine words. Extracts bits directly from x.words in O(1)
    without creating any intermediate word lists. This eliminates
    5-7 iterations of word-list operations for typical input sizes.

    Phase 2 (word-lists):
    For the final 1-3 iterations where values exceed 64 bits,
    operates directly on Magnitude word lists, bypassing BigInt
    wrapper overhead (no sign handling, no error checking, no
    BigInt object allocation/deallocation).
    """
    var bit_len = x.bit_length()
    var c = (bit_len - 1) // 2

    if c == 0:
        return BigInt(1)

    # Compute c.bit_length()
    var c_bits = 0
    var tmp = c
    while tmp > 0:
        c_bits += 1
        tmp >>= 1

    # --- Phase 1: Native UInt64 arithmetic ---
    # Process iterations while n_shifted fits in UInt64 (e + d_new <= 62).
    var a_val: UInt64 = 1
    var d: Int = 0
    var phase1_end: Int = -1  # s value where phase 2 starts (-1 = all done)

    for s in range(c_bits - 1, -1, -1):
        var e = d
        var d_new = c >> s

        # n_shifted has ~(e + d_new + 1) bits. For UInt64 safety: e+d_new <= 62
        if e + d_new > 62:
            phase1_end = s
            break

        d = d_new
        var shift_a = d - e - 1
        var shift_n = 2 * c - e - d + 1

        # Save old a for division, then shift a
        var old_a = a_val
        a_val <<= UInt64(shift_a)

        # Extract n_shifted directly from x.words as UInt64 — O(1), no alloc
        var n_val = _extract_uint64_from_words(x.words, shift_n)

        # Native UInt64 division and addition
        var quotient = n_val // old_a
        a_val += quotient

    if phase1_end == -1:
        # All iterations completed natively
        # Final check: a -= 1 if a*a > x
        var a_words = _uint64_to_words(a_val)
        var a_sq = bigint_arithmetics._multiply_magnitudes(a_words, a_words)
        if bigint_arithmetics._compare_word_lists(a_sq, x.words) > 0:
            a_val -= 1
        return BigInt.from_integral_scalar(a_val)

    # --- Phase 1.5: UInt128 arithmetic for 1-2 more iterations ---
    # Extends the native phase to cover e+d up to ~126 bits, avoiding
    # word-list operations for 1-2 additional iterations.
    var a128 = UInt128(a_val)
    var phase15_end: Int = -1

    for s in range(phase1_end, -1, -1):
        var e = d
        var d_new = c >> s

        # n_shifted has ~(e + d_new + 1) bits. For UInt128: e+d_new <= 126
        if e + d_new > 126:
            phase15_end = s
            break

        d = d_new
        var shift_a = d - e - 1
        var shift_n = 2 * c - e - d + 1

        var old_a128 = a128
        a128 <<= UInt128(shift_a)

        # Extract n_shifted as UInt128 from x.words (O(1))
        var n128 = _extract_uint128_from_words(x.words, shift_n)

        var quotient128 = n128 // old_a128
        a128 += quotient128

    if phase15_end == -1:
        # All iterations completed natively (UInt64 + UInt128)
        var a_words = _uint128_to_words(a128)
        var a_sq = bigint_arithmetics._multiply_magnitudes(a_words, a_words)
        if bigint_arithmetics._compare_word_lists(a_sq, x.words) > 0:
            if a128 > 0:
                a128 -= 1
            a_words = _uint128_to_words(a128)
        return BigInt(raw_words=a_words^, sign=False)

    # --- Phase 2: Word-list operations (no BigInt wrapper overhead) ---
    var a_words = _uint128_to_words(a128)

    for s in range(phase15_end, -1, -1):
        var e = d
        d = c >> s

        var shift_a = d - e - 1
        var shift_n = 2 * c - e - d + 1

        # Shift x right (skips lower words efficiently)
        var n_shifted = _right_shift_magnitude_bits(x.words, shift_n)

        # Divide n_shifted by current a (before shifting). Only the quotient
        # is wanted here; the remainder goes into a value that is dropped.
        var discarded_remainder = Magnitude()
        var quotient = bigint_arithmetics._divmod_magnitudes(
            n_shifted, a_words, discarded_remainder
        )

        # Shift a left, then add quotient in-place (saves 2 allocations)
        a_words = _left_shift_magnitude_bits(a_words, shift_a)
        bigint_arithmetics._add_magnitudes_inplace(a_words, quotient)

    # Final check: a -= 1 if a*a > x
    var a_sq = bigint_arithmetics._multiply_magnitudes(a_words, a_words)
    if bigint_arithmetics._compare_word_lists(a_sq, x.words) > 0:
        # Decrement a_words by 1 in-place
        var borrow: UInt64 = 1
        for i in range(len(a_words)):
            var val = UInt64(a_words[i])
            if val >= borrow:
                a_words[i] = UInt64(val - borrow)
                _ = borrow
                break
            else:
                a_words[i] = ~UInt64(0)
                borrow = 1
        # Strip leading zeros
        while len(a_words) > 1 and a_words[len(a_words) - 1] == 0:
            a_words.shrink(len(a_words) - 1)

    return BigInt(raw_words=a_words^, sign=False)


comptime _NEWTON_GUARD_BITS: Int = 4
"""Bits of slack per Newton step in `reciprocal_sqrt_fixed_point()`.

Each step truncates twice - once in the shift that forms the correction, once
in the shift that rescales `r` - so the doubling of correct bits falls a little
short of exact. Four bits per step covers that with room to spare, and costs
four bits of width on operands tens of thousands of bits wide.
"""


def sqrt_rem(x: BigInt) raises -> Tuple[BigInt, BigInt]:
    """Returns the integer square root of `x` and what it leaves behind.

    Args:
        x: The value to take the root of. Must be non-negative.

    Returns:
        A tuple `(s, r)` with `s * s + r == x` and `0 <= r <= 2 * s`, which
        is the pair GMP calls `mpz_sqrtrem`.

    Raises:
        ValueError: If `x` is negative.
        Error: Propagated from the square root.

    Notes:

    The root comes from `sqrt()` and the remainder from one squaring.

    `_sqrtrem()` does carry a remainder of its own, and reaching for it
    directly would save the squaring -- but only for the inputs that reach
    the Karatsuba recursion, and only after the normalization that
    `_sqrt_karatsuba()` performs: an even word count and a top word of at
    least `2^62`. Handing it an unnormalized magnitude answers wrongly, which
    a sweep of 348 values above `CUTOFF_SQRT_BASE` showed on 68 of them. The
    smaller inputs would not gain anyway, since `_sqrtrem_small()` recovers
    its remainder by squaring the root exactly as this does.
    """
    if x.sign:
        raise ValueError(
            message="Square root of a negative number is not real.",
            function="sqrt_rem()",
        )
    if x.is_zero():
        return (BigInt.zero(), BigInt.zero())

    var root = sqrt(x)
    var remainder = x - root * root
    return (root^, remainder^)


def root(x: BigInt, n: Int) raises -> BigInt:
    """Returns the integer `n`-th root of `x`, truncated toward zero.

    Args:
        x: The value to take the root of.
        n: The degree of the root, which must be positive.

    Returns:
        The root with the sign of `x`, truncated toward zero: the cube root
        of -9 is -2, since -2 cubed is -8 and -3 cubed is past -9.

    Raises:
        ValueError: If `n` is not positive, or if `x` is negative and `n` is
            even, where no real root exists.
        Error: Propagated from the arithmetic.

    Notes:

    Truncation toward zero rather than downward is what makes the sign a
    matter of taking the root of the magnitude and putting the sign back. The
    magnitude's root is `BigUInt`'s.
    """
    if n <= 0:
        raise ValueError(
            message="The degree of a root must be positive.",
            function="root()",
        )
    if x.sign and n % 2 == 0:
        raise ValueError(
            message=(
                "An even root of a negative number is not real; use an odd"
                " degree or a non-negative value."
            ),
            function="root()",
        )
    var magnitude = biguint_exponential.root(x.to_biguint(), n)
    return BigInt.from_biguint(magnitude^, sign=x.sign)


def isqrt(x: BigInt) raises -> BigInt:
    """Calculates the integer square root of a BigInt.
    Equivalent to `sqrt()`.

    Args:
        x: The BigInt to calculate the integer square root of.

    Returns:
        The integer square root of x.

    Raises:
        ValueError: If x is negative.
    """
    return sqrt(x)


def reciprocal_sqrt_fixed_point(
    x: UInt64, fractional_bits: Int
) raises -> BigInt:
    """Returns `2^fractional_bits / sqrt(x)` as a binary fixed-point integer.

    The result `r` satisfies `r ~= 2^fractional_bits / sqrt(x)` to within a few
    units in the last place, so it carries about
    `fractional_bits - bit_length(x) / 2` correct significant bits. Note that
    this returns the *reciprocal* of the root, where
    `bigdecimal.exponential.sqrt_via_reciprocal_iteration()` merely reaches
    the root through one and returns the root.

    It exists because a `BigDecimal` holds its coefficient in a decimal base,
    the same multiplication costs about 2.8x what it did in the base-2^32
    `BigInt` that figure was measured against. `BigInt` is base 2^64 now and
    multiplies 1.0x to 1.4x faster again, so the gap only widened.

    The iteration is Newton's for the reciprocal square root, written around
    the residual so that no step ever multiplies at the full target width:

        e     = 2^(2f) - x * r^2                 (r at scale 2^f)
        r_new = (r << (g - f)) + (r * e) >> (3f + 1 - g)

    `r` and `e` are both about `f` bits, so a step from scale `f` to scale
    `g <= 2f` costs two multiplications of `f`-bit operands. Halving the scale
    on the way down means the last step - the only one at half the target
    width - dominates, and the whole function costs about 1.1 multiplications
    at the target width.

    `x` is a machine word rather than a `BigInt` because the only caller needs
    `1 / sqrt(10005)`. Generalising means normalising `x` to an even power of
    two before seeding, and nothing else here changes.

    Args:
        x: The value to take the reciprocal square root of. Must be non-zero.
        fractional_bits: The number of fractional bits in the result. Must be
            non-negative.

    Returns:
        `2^fractional_bits / sqrt(x)`, truncated to an integer.

    Raises:
        ValueError: If `x` is zero or `fractional_bits` is negative.
    """
    if x == 0:
        raise ValueError(
            message="Cannot compute the reciprocal square root of zero.",
            function="reciprocal_sqrt_fixed_point()",
        )
    if fractional_bits < 0:
        raise ValueError(
            message="Number of fractional bits must be non-negative.",
            function="reciprocal_sqrt_fixed_point()",
        )

    # Bit length of `x`, and half of it rounded up: `r` is about
    # `2^(scale - half_bits)`, so `half_bits` is the gap between the scale of
    # `r` and the number of significant bits it actually carries.
    var bits = 0
    var probe = x
    while probe != 0:
        probe >>= 1
        bits += 1
    var half_bits = (bits + 1) // 2

    # Seed from `Float64`, placed so the value lands near 2^48 whatever `x` is.
    # One `sqrt` and one divide leave it good to about 51 bits; 44 is the
    # conservative credit the schedule below is built on.
    var seed_scale = 48 + half_bits
    var seed_credit = 44 + half_bits
    var seed = BigInt(
        Int(Float64(2.0) ** Float64(seed_scale) / math.sqrt(Float64(x)))
    )

    if fractional_bits <= seed_credit:
        return seed >> (seed_scale - fractional_bits)

    # Newton doubles the correct significant bits, so a step lands at
    # `g = 2f - half_bits - 2 * _NEWTON_GUARD_BITS`; inverting that gives the
    # scale each step has to start from. Building the schedule downwards from
    # the target is what keeps the final step at half the target width.
    var schedule = List[Int]()
    var f = fractional_bits
    while f > seed_credit:
        schedule.append(f)
        f = (f + half_bits) // 2 + _NEWTON_GUARD_BITS

    var r = seed >> (seed_scale - f)
    var current = f
    # Built from the words rather than through `Int(x)`, which wraps to a
    # negative value for `x >= 2^63`.
    var bx = BigInt(raw_words=_uint64_to_words(x), sign=False)

    for i in range(len(schedule) - 1, -1, -1):
        var target = schedule[i]
        # The subtraction is a near-total cancellation, exact in integers:
        # `x * r^2` agrees with `2^(2f)` to within about `f` bits.
        var residual = (BigInt.one() << (2 * current)) - bx * (r * r)
        r = (r << (target - current)) + (
            (r * residual) >> (3 * current + 1 - target)
        )
        current = target

    return r^


# ===----------------------------------------------------------------------=== #
# Karatsuba square root
# ===----------------------------------------------------------------------=== #

comptime CUTOFF_SQRT_RECURSIVE: Int = 64
"""Words above which `sqrt()` uses Zimmermann's recursion.

Below it the precision-doubling path wins because it spends its early
iterations in `UInt64` and `UInt128` registers, where the recursion is
already allocating word lists; above it the recursion wins because its
division is half the width. The two on their own, neither one used as the
other's base case, best of seven (us):

    digits            500    1000    2000    3000    5000    8000
    precision-doubling 1.78   3.83   10.00   16.51   36.08   67.78
    Zimmermann         2.27   3.90    8.16   11.89   21.59   38.93

That is not the choice, though, because the shipped recursion stops at
`CUTOFF_SQRT_BASE` and finishes in the older path. Sweeping this constant
with that in place, `-D ASSERT=none` (us):

    digits           200    300    500    700   1000   1500   5000   10000
    cutoff 16       0.42   0.60   1.44   1.85   2.27   2.96  10.24   27.82
    cutoff 32       0.41   0.60   1.08   1.85   2.11   2.76   9.94   27.88
    cutoff 64       0.43   0.60   1.08   1.59   2.17   2.97   9.34   27.31

It reads better than the two-way table because one level of recursion halves
the division and then hands the tail to the path that is best at that width.
Re-measured twice since: after Knuth D went to 64-bit limbs, and again after
the magnitude did. Neither moved it, which is not a coincidence -- the two
paths it chooses between both scale with the value, not the word count.
"""

comptime CUTOFF_SQRT_BASE: Int = 32
"""Words below which `_sqrtrem()` stops recursing and doubles precision.

The recursion needs a remainder and the older path does not produce one, so
the base case pays for a squaring to recover it. That is cheap at these sizes
and buys back the register-resident early iterations.

It went 32 -> 16 when Knuth D's multiply-subtract moved to 64-bit limbs, and
back to 32 when the magnitude itself did -- the same number of words is twice
the value now, so the base case is back where it was in bits. Two passes, best
of five within each (us):

    digits           200    300    500    700   1000   1500   5000   10000
    cutoff  8       0.43   0.60   1.07   1.64   2.02   2.70   9.81   26.21
    cutoff 16       0.43   0.57   1.07   1.67   2.18   2.97   9.35   27.65
    cutoff 32       0.42   0.53   1.01   1.55   1.98   2.74   9.08   25.57

48 ties with 32 and 8 and 16 are behind it at most widths, so this is the
bottom of a shallow basin rather than a peak.
"""


def _sqrtrem_two_words(
    n: ImmSpan[UInt64, _], mut remainder: Magnitude
) -> Magnitude:
    """Square root of a one- or two-word magnitude, with its remainder.

    Two words is 128 bits now, so the hardware cannot be asked directly any
    more; the root still fits one word, and `isqrt_uint128()` finds it.

    Args:
        n: The magnitude, one or two words.
        remainder: Set to `n - s * s` on return.

    Returns:
        The integer square root, one word.
    """
    var value = UInt128(n[0])
    if len(n) > 1:
        value |= UInt128(n[1]) << 64
    var root = isqrt_uint128(value)
    var left = value - UInt128(root) * UInt128(root)
    # The remainder is at most `2 * root`, so it can need a second word.
    remainder = [UInt64(left)]
    var high = UInt64(left >> 64)
    if high != 0:
        remainder.append(high)
    var out: Magnitude = [root]
    return out^


def _sqrtrem_small(
    n: ImmSpan[UInt64, _], mut remainder: Magnitude
) raises -> Magnitude:
    """The recursion's base case: precision-doubling, then one squaring.

    Below the crossover the older algorithm is simply better -- it spends its
    early iterations in `UInt64` and `UInt128` registers where this one is
    already allocating word lists. It does not produce a remainder, so one is
    recovered with a squaring, which is cheap at these sizes and is what the
    recursion above needs.

    Args:
        n: The magnitude, at least three words.
        remainder: Set to `n - s * s` on return.

    Returns:
        The integer square root.

    Raises:
        Error: Propagated from the precision-doubling path.
    """
    var value = bigint_arithmetics._normalized_copy(n)
    var root = _sqrt_precision_doubling_fast(
        BigInt(raw_words=value.copy(), sign=False)
    )
    var root_words = root.words.copy()
    remainder = bigint_arithmetics._subtract_magnitudes(
        value, bigint_arithmetics._multiply_magnitudes(root_words, root_words)
    )
    return root_words^


def _sqrtrem(
    n: ImmSpan[UInt64, _], mut remainder: Magnitude
) raises -> Magnitude:
    """Karatsuba square root: returns `s`, and sets `remainder` to `n - s*s`.

    Zimmermann's recursion (INRIA RR-3805). Writing `n` as
    `a3*b^3 + a2*b^2 + a1*b + a0` with `b = B^l`, the root of the top half
    gives most of the answer and one division supplies the rest:

        (s', r') = sqrt(a3*b + a2)
        (q,  u ) = divmod(r'*b + a1, 2*s')
        s = s'*b + q
        r = u*b + a0 - q^2        and if r < 0, r += 2s - 1 and s -= 1

    The division here is half the width of the one CPython's
    precision-doubling ends on, which is where the time goes, and the
    remainder comes out of the recursion rather than being recovered with a
    full-width squaring afterwards.

    `n` is a slice rather than a list so that the recursion does not copy the
    top half of its input at every level, which was O(n) a level and the
    largest single cost here after the division itself.

    The caller must normalize: `len(n)` even, and the top word at least
    `2^62`, which is Zimmermann's `a3 >= b/4`. Both survive the recursion --
    the top slice keeps `n`'s own top word, and its length is even by
    construction -- so this is checked once, in `sqrt()`.

    Args:
        n: The magnitude, normalized as described.
        remainder: Set to `n - s * s` on return.

    Returns:
        The integer square root.

    Raises:
        Error: Propagated from the inner division, which cannot divide by
            zero because the top word is normalized and so `s'` is non-zero.
    """
    var m = len(n)
    if m <= 2:
        return _sqrtrem_two_words(n, remainder)
    if m <= CUTOFF_SQRT_BASE:
        return _sqrtrem_small(n, remainder)

    var half = m >> 1
    var l = half >> 1

    # The top 2*(half - l) words. Its top word is `n`'s, so it is normalized
    # already.
    var r_hi = Magnitude()
    var s_hi = _sqrtrem(bigint_arithmetics._subspan(n, 2 * l, m), r_hi)

    var divisor = s_hi.copy()
    bigint_arithmetics._double_inplace(divisor)

    var dividend = r_hi^
    bigint_arithmetics._shift_left_words_inplace(dividend, l)
    bigint_arithmetics._add_from_slice_inplace(
        dividend, bigint_arithmetics._subspan(n, l, 2 * l)
    )

    var u = Magnitude()
    var q = bigint_arithmetics._divmod_magnitudes(dividend, divisor, u)

    # `q` is at most `B^l`, and the equality case would not fit the `l` words
    # the next step gives it. Clamp and recover the remainder by hand; this
    # costs one multiplication and happens almost never.
    if len(q) > l:
        q = Magnitude(capacity=l)
        for _ in range(l):
            q.append(~UInt64(0))
        u = bigint_arithmetics._subtract_magnitudes(
            dividend, bigint_arithmetics._multiply_magnitudes(q, divisor)
        )

    var s = s_hi^
    bigint_arithmetics._shift_left_words_inplace(s, l)
    bigint_arithmetics._add_magnitudes_inplace(s, q)

    var t = u^
    bigint_arithmetics._shift_left_words_inplace(t, l)
    bigint_arithmetics._add_from_slice_inplace(
        t, bigint_arithmetics._subspan(n, 0, l)
    )

    var q_squared = bigint_arithmetics._multiply_magnitudes(q, q)
    if bigint_arithmetics._compare_word_lists(t, q_squared) < 0:
        # One correction is always enough, which is what `a3 >= b/4` buys.
        var correction = s.copy()
        bigint_arithmetics._double_inplace(correction)
        bigint_arithmetics._decrement_inplace(correction)
        bigint_arithmetics._add_magnitudes_inplace(t, correction)
        bigint_arithmetics._decrement_inplace(s)
        bigint_arithmetics._strip_leading_zeros_inplace(s)

    remainder = bigint_arithmetics._subtract_magnitudes(t, q_squared)
    return s^


def _sqrt_karatsuba(x: BigInt) raises -> BigInt:
    """Integer square root through `_sqrtrem()`, with the normalization.

    `_sqrtrem()` wants an even word count and a top word of at least `2^62`.
    Both are bought with a left shift, and a shift by an even number of bits
    scales the root by a known power of two, which the final shift undoes:
    `floor(sqrt(x * 2^2k)) >> k` is `floor(sqrt(x))` exactly.

    Padding an odd word count costs a whole word, which is 64 bits and so
    even, and leaves the top word alone. The two shifts together never exceed
    126 bits, so undoing them is a single sub-word shift.

    Args:
        x: A positive value.

    Returns:
        The integer square root.

    Raises:
        Error: Propagated from the division inside the recursion.
    """
    var leading = bigint_arithmetics._count_leading_zeros(
        x.words[len(x.words) - 1]
    )
    var shift = leading if (leading & 1) == 0 else leading - 1
    var value = bigint_arithmetics._shift_left_words(x.words, shift)
    var total = shift
    if (len(value) & 1) == 1:
        bigint_arithmetics._shift_left_words_inplace(value, 1)
        total += 64

    var remainder = Magnitude()
    var root = _sqrtrem(value.as_span(), remainder)

    var back = total >> 1
    if back > 0:
        bigint_arithmetics._shift_right_words_inplace(root, back, len(root))
    return BigInt(raw_words=root^, sign=False)


comptime _SQUARE_RESIDUES_MOD_64: UInt64 = 144_680_414_395_695_635
"""Bit `r` is set when `r` is a square modulo 64.

The twelve residues are 0, 1, 4, 9, 16, 17, 25, 33, 36, 41, 49 and 57. A
value whose low six bits land anywhere else cannot be a square, which rejects
about five non-squares in six for the cost of one shift and one mask.
"""


def is_perfect_square(x: BigInt) raises -> Bool:
    """Returns whether `x` is the square of an integer.

    Args:
        x: The value to test.

    Returns:
        True if some integer squared gives `x`. Zero and one are squares; a
        negative value is not, since no integer squares to it.

    Raises:
        Error: Propagated from the square root.

    Notes:

    The answer comes from `sqrt_rem()`: the root leaves nothing behind exactly
    when the value is a square. The root is the expensive part, so the low six
    bits are checked first against the squares modulo 64, which turns away
    most of the values that would have gone on to fail.
    """
    if x.sign:
        return False
    if x.is_zero():
        return True
    if not ((_SQUARE_RESIDUES_MOD_64 >> (x.words[0] & 63)) & 1):
        return False
    var root_and_remainder = sqrt_rem(x)
    return root_and_remainder[1].is_zero()


def _is_small_prime(n: Int) -> Bool:
    """Returns whether a small positive `Int` is prime, by trial division.

    Args:
        n: The number to test.

    Returns:
        True if `n` is prime.

    Notes:

    This screens candidate exponents in `perfect_power()` and nothing else.
    The exponents there are bounded by a bit length, and the division it saves
    -- an `n`-th root of a big integer -- costs orders of magnitude more than
    the screening, so trial division is the right tool at this size. A public
    sieve belongs on the type, not here.
    """
    if n < 2:
        return False
    if n < 4:
        return True
    if n % 2 == 0:
        return False
    var divisor = 3
    while divisor * divisor <= n:
        if n % divisor == 0:
            return False
        divisor += 2
    return True


def perfect_power(x: BigInt) raises -> Tuple[BigInt, Int]:
    """Writes `x` as `base ** exponent` with the exponent as large as it goes.

    Args:
        x: The value to decompose.

    Returns:
        A pair `(base, exponent)` with `base ** exponent == x` and the
        exponent the largest one possible. A value that is no integer's power
        comes back as `(x, 1)`, since every value is itself to the first.

    Raises:
        Error: Propagated from the roots.

    Notes:

    The base and the exponent come out together because finding the exponent
    means computing the base: a predicate that threw the base away would make
    every caller that wants it take the roots a second time. `is_perfect_power()`
    is the predicate, and it asks this.

    Zero, one and minus one are every exponent's power, so there is no largest
    one and the pair reports the smallest that works -- `2` for the first two
    and `3` for minus one, an even power of a negative value being positive.

    Candidate exponents run upward from two, and each one is divided out as
    far as it goes before the next is tried. That is what makes the exponent
    maximal and also what makes a composite candidate free of charge: by the
    time `6` comes round, the `2`s and the `3`s are gone, so no sixth power
    remains for it to find. The exponents are screened for primality anyway,
    since skipping five candidates in six is worth a handful of divisions
    against the `n`-th root each one would otherwise cost.

    The work is one `n`-th root per prime up to `x`'s bit length, so it grows
    with the size of the value and not with the size of the answer. That is
    comfortable for the integers anyone writes down and slow for one with a
    million digits; it is not a tuned implementation.
    """
    if x.is_zero():
        return (BigInt.zero(), 2)
    if x.is_one():
        return (BigInt.one(), 2)
    if x.is_one_or_minus_one():
        # Minus one, the only remaining value of magnitude one. An even power
        # cannot be negative, so three is the smallest exponent that works.
        return (BigInt(-1), 3)

    var remaining = x.copy()
    var exponent = 1
    var limit = x.bit_length()
    var candidate = 2
    while candidate <= limit:
        if _is_small_prime(candidate) and not (
            remaining.sign and candidate % 2 == 0
        ):
            while True:
                var base = root(remaining, candidate)
                if base.power(candidate) != remaining:
                    break
                remaining = base^
                exponent *= candidate
                limit = remaining.bit_length()
                if limit < 2:
                    break
        candidate += 1
    return (remaining^, exponent)


def is_perfect_power(x: BigInt) raises -> Bool:
    """Returns whether `x` is `base ** exponent` for some exponent above one.

    Args:
        x: The value to test.

    Returns:
        True if `x` is an integer power with an exponent of at least two.
        Zero, one and minus one are, every exponent over.

    Raises:
        Error: Propagated from the roots.

    Notes:

    This is `perfect_power()` asked for its exponent. Use that one when the
    base is wanted too, which it usually is.
    """
    var decomposition = perfect_power(x)
    return decomposition[1] > 1
