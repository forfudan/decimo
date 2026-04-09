# ===----------------------------------------------------------------------=== #
# Copyright 2025 Yuhao Zhu
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

This module provides integer square root using CPython's precision-doubling
algorithm with a UInt64 fast path for early iterations, leveraging BigInt's
base-2^32 representation for efficient bit-level operations.
"""

from std import math

from decimo.bigint.bigint import BigInt
import decimo.bigint.arithmetics
from decimo.errors import ValueError


# ===----------------------------------------------------------------------=== #
# Word-list helper functions for sqrt
# ===----------------------------------------------------------------------=== #


def _extract_uint64_from_words(words: List[UInt32], bit_shift: Int) -> UInt64:
    """Extracts up to 64 bits from a magnitude at a given bit offset.

    Computes floor(value(words) >> bit_shift) mod 2^64, reading only the
    2-3 words that overlap with the 64-bit window. O(1) with no allocation.

    Args:
        words: The magnitude as little-endian UInt32 words.
        bit_shift: The number of bits to shift right before extracting.

    Returns:
        The extracted 64-bit value.
    """
    var wi = bit_shift // 32
    var bi = bit_shift % 32
    var n = len(words)

    if wi >= n:
        return 0

    if bi == 0:
        var result = UInt64(words[wi])
        if wi + 1 < n:
            result |= UInt64(words[wi + 1]) << 32
        return result

    # bi > 0: need up to 3 consecutive words to cover 64 bits at alignment
    var result = UInt64(words[wi]) >> UInt64(bi)
    if wi + 1 < n:
        result |= UInt64(words[wi + 1]) << UInt64(32 - bi)
    if wi + 2 < n:
        result |= UInt64(words[wi + 2]) << UInt64(64 - bi)
    return result


def _uint64_to_words(val: UInt64) -> List[UInt32]:
    """Converts a UInt64 value to a magnitude word list.

    Args:
        val: The UInt64 value to convert.

    Returns:
        A List[UInt32] representing the magnitude in little-endian order.
    """
    if val == 0:
        var result: List[UInt32] = [UInt32(0)]
        return result^

    var lo = UInt32(val & 0xFFFF_FFFF)
    var hi = UInt32(val >> 32)
    if hi == 0:
        var result: List[UInt32] = [lo]
        return result^

    var result = List[UInt32](capacity=2)
    result.append(lo)
    result.append(hi)
    return result^


def _extract_uint128_from_words(words: List[UInt32], bit_shift: Int) -> UInt128:
    """Extracts up to 128 bits from a magnitude at a given bit offset.

    Similar to _extract_uint64_from_words but returns UInt128.
    Reads only the 4-5 words that overlap with the 128-bit window.

    Args:
        words: The magnitude as little-endian UInt32 words.
        bit_shift: The number of bits to shift right before extracting.

    Returns:
        The extracted 128-bit value.
    """
    var wi = bit_shift // 32
    var bi = bit_shift % 32
    var n = len(words)

    if wi >= n:
        return UInt128(0)

    if bi == 0:
        # Aligned: read exactly 4 words
        var result = UInt128(0)
        for k in range(min(4, n - wi)):
            result |= UInt128(words[wi + k]) << UInt128(k * 32)
        return result

    # Unaligned: need bits [bi..bi+127] from words[wi..wi+4]
    # Build result by placing each word's contribution at the correct position
    var result = UInt128(words[wi]) >> UInt128(bi)
    if wi + 1 < n:
        result |= UInt128(words[wi + 1]) << UInt128(32 - bi)
    if wi + 2 < n:
        result |= UInt128(words[wi + 2]) << UInt128(64 - bi)
    if wi + 3 < n:
        result |= UInt128(words[wi + 3]) << UInt128(96 - bi)
    if wi + 4 < n:
        result |= UInt128(words[wi + 4]) << UInt128(128 - bi)
    return result


def _uint128_to_words(val: UInt128) -> List[UInt32]:
    """Converts a UInt128 value to a magnitude word list.

    Args:
        val: The UInt128 value to convert.

    Returns:
        A List[UInt32] representing the magnitude in little-endian order.
    """
    if val == 0:
        var result: List[UInt32] = [UInt32(0)]
        return result^

    var result = List[UInt32](capacity=4)
    var remaining = val
    while remaining != 0:
        result.append(UInt32(remaining & 0xFFFF_FFFF))
        remaining >>= 32

    return result^


def _left_shift_magnitude_bits(a: List[UInt32], shift: Int) -> List[UInt32]:
    """Shifts a magnitude left by an arbitrary number of bits.

    Handles both whole-word and sub-word shifts in a single pass.

    Args:
        a: The magnitude to shift (little-endian UInt32 words).
        shift: The number of bits to shift left (must be >= 0).

    Returns:
        The shifted magnitude as a new word list.
    """
    if shift == 0 or (len(a) == 1 and a[0] == 0):
        var copy = List[UInt32](capacity=len(a))
        for word in a:
            copy.append(word)
        return copy^

    var word_shift = shift // 32
    var bit_shift = shift % 32
    var n = len(a)
    var new_len = n + word_shift + (1 if bit_shift > 0 else 0)
    var result = List[UInt32](capacity=new_len)

    # Prepend zero words for the whole-word shift
    for _ in range(word_shift):
        result.append(UInt32(0))

    # Shift the existing words with sub-word carry
    if bit_shift == 0:
        for i in range(n):
            result.append(a[i])
    else:
        var carry: UInt32 = 0
        for i in range(n):
            var shifted = UInt64(a[i]) << UInt64(bit_shift)
            result.append(UInt32(shifted & 0xFFFF_FFFF) | carry)
            carry = UInt32(shifted >> 32)
        if carry > 0:
            result.append(carry)

    return result^


def _right_shift_magnitude_bits(a: List[UInt32], shift: Int) -> List[UInt32]:
    """Shifts a magnitude right by an arbitrary number of bits.

    Efficiently skips lower words that would be entirely shifted out,
    only processing the relevant upper portion.

    Args:
        a: The magnitude to shift (little-endian UInt32 words).
        shift: The number of bits to shift right (must be >= 0).

    Returns:
        The shifted magnitude as a new word list, normalized.
    """
    var word_shift = shift // 32
    var bit_shift = shift % 32
    var n = len(a)

    if word_shift >= n:
        var zero: List[UInt32] = [UInt32(0)]
        return zero^

    var new_len = n - word_shift
    var result = List[UInt32](capacity=new_len)

    if bit_shift == 0:
        for i in range(word_shift, n):
            result.append(a[i])
    else:
        for i in range(word_shift, n):
            var lo = UInt64(a[i]) >> UInt64(bit_shift)
            var hi: UInt64 = 0
            if i + 1 < n:
                hi = (UInt64(a[i + 1]) << UInt64(32 - bit_shift)) & UInt64(
                    0xFFFF_FFFF
                )
            result.append(UInt32(lo | hi))

    # Strip leading zeros
    while len(result) > 1 and result[-1] == 0:
        result.shrink(len(result) - 1)
    if len(result) == 0:
        result.append(UInt32(0))

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
        Error: If x is negative.

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

    # Special case: single word — use hardware sqrt
    if len(x.words) == 1:
        if x.words[0] <= 1:
            return x.copy()
        var val = x.words[0]
        var guess = UInt32(math.sqrt(val))
        # Refine: ensure guess^2 <= val < (guess+1)^2
        while guess * guess > val:
            guess -= 1
        while (guess + 1) * (guess + 1) <= val:
            guess += 1
        return BigInt.from_int(Int(guess))

    # Special case: two words — compute via UInt64 sqrt
    if len(x.words) == 2:
        var val = UInt64(x.words[0]) + (UInt64(x.words[1]) << 32)
        var guess = UInt64(math.sqrt(val))
        # Refine: ensure guess^2 <= val < (guess+1)^2
        while guess * guess > val:
            guess -= 1
        while (guess + 1) * (guess + 1) <= val:
            guess += 1
        return BigInt.from_integral_scalar(guess)

    # For all larger inputs: optimized precision-doubling with UInt64 fast path
    return _sqrt_precision_doubling_fast(x)


def _sqrt_precision_doubling_fast(x: BigInt) raises -> BigInt:
    """Optimized precision-doubling integer sqrt with UInt64 fast path.

    Args:
        x: The BigInt value (must be positive, >= 3 words).

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
    operates directly on List[UInt32] word lists, bypassing BigInt
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
        var a_sq = decimo.bigint.arithmetics._multiply_magnitudes(
            a_words, a_words
        )
        if decimo.bigint.arithmetics._compare_word_lists(a_sq, x.words) > 0:
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
        var a_sq = decimo.bigint.arithmetics._multiply_magnitudes(
            a_words, a_words
        )
        if decimo.bigint.arithmetics._compare_word_lists(a_sq, x.words) > 0:
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

        # Divide n_shifted by current a (before shifting)
        var div_result = decimo.bigint.arithmetics._divmod_magnitudes(
            n_shifted, a_words
        )

        # Shift a left, then add quotient in-place (saves 2 allocations)
        a_words = _left_shift_magnitude_bits(a_words, shift_a)
        decimo.bigint.arithmetics._add_magnitudes_inplace(
            a_words, div_result[0]
        )

    # Final check: a -= 1 if a*a > x
    var a_sq = decimo.bigint.arithmetics._multiply_magnitudes(a_words, a_words)
    if decimo.bigint.arithmetics._compare_word_lists(a_sq, x.words) > 0:
        # Decrement a_words by 1 in-place
        var borrow: UInt64 = 1
        for i in range(len(a_words)):
            var val = UInt64(a_words[i])
            if val >= borrow:
                a_words[i] = UInt32(val - borrow)
                _ = borrow
                break
            else:
                a_words[i] = UInt32(0xFFFF_FFFF)
                borrow = 1
        # Strip leading zeros
        while len(a_words) > 1 and a_words[-1] == 0:
            a_words.shrink(len(a_words) - 1)

    return BigInt(raw_words=a_words^, sign=False)


def isqrt(x: BigInt) raises -> BigInt:
    """Calculates the integer square root of a BigInt.
    Equivalent to `sqrt()`.

    Args:
        x: The BigInt to calculate the integer square root of.

    Returns:
        The integer square root of x.

    Raises:
        Error: If x is negative.
    """
    return sqrt(x)
