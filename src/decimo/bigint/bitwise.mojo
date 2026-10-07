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

"""Bitwise operations for BigInt: AND, OR, XOR, NOT.

All operations follow Python's semantics for arbitrary-precision integers,
treating negative numbers as having an infinite-width two's complement
representation. That is:

    -x  is conceptually represented as  ...111111 (flip all bits of x-1)

This means:
    ~x  = -(x + 1)         for all x
    -1  = ...11111111       (all bits set)
    -2  = ...11111110
    -3  = ...11111101

For binary operations (AND, OR, XOR), the algorithm is:
1. Convert negative operands to two's complement form:
   negate magnitude: subtract 1, then invert all words.
   The "sign extension" is implicitly all-1s for negative numbers.
2. Perform word-by-word bitwise operation, extending shorter operand
   with its sign-extension fill (all-zero words for non-negative, all-one
   words for negative).
3. Determine the result sign from the operation on the sign-extension bits.
4. If the result is negative (in two's complement), convert back to
   sign-magnitude: invert all words, then add 1 to the magnitude.

Performance note: For the common case of two non-negative operands, no
two's complement conversion is needed — just word-by-word operation.
"""

from decimo.bigint.bigint import BigInt, Magnitude
from decimo.bigint.number_theory import _count_trailing_zeros
from decimo.errors import ValueError


# ===----------------------------------------------------------------------=== #
# Core helper: word-by-word binary bitwise operation
# ===----------------------------------------------------------------------=== #


def _binary_bitwise_op[op: StringLiteral](a: BigInt, b: BigInt) -> BigInt:
    """Performs a word-by-word binary bitwise operation on two BigInt values.

    The operation is determined by the `op` parameter:
    - "and": bitwise AND
    - "or":  bitwise OR
    - "xor": bitwise XOR

    Uses Python-compatible two's complement semantics for negative numbers.
    """

    # Determine fills (sign extension for infinite-width two's complement)
    var a_fill = ~UInt64(0) if a.sign else UInt64(0)
    var b_fill = ~UInt64(0) if b.sign else UInt64(0)

    # Determine result sign from operation on sign-extension bits
    var result_negative: Bool

    comptime if op == "and":
        result_negative = a.sign and b.sign
    elif op == "or":
        result_negative = a.sign or b.sign
    elif op == "xor":
        result_negative = a.sign != b.sign
    else:
        comptime assert False, "op must be 'and', 'or', or 'xor'"

    # Fast path: both non-negative
    if not a.sign and not b.sign:
        comptime if op == "and":
            # AND with zeros → zeros, so result is at most min_len words
            var min_len = min(len(a.words), len(b.words))
            var result_words = Magnitude(capacity=min_len)
            for i in range(min_len):
                result_words.append(
                    a.words.unsafe_get(i) & b.words.unsafe_get(i)
                )
            while (
                len(result_words) > 1
                and result_words.unsafe_get(len(result_words) - 1) == 0
            ):
                result_words.shrink(len(result_words) - 1)
            return BigInt(raw_words=result_words^, sign=False)
        elif op == "or":
            var max_len = max(len(a.words), len(b.words))
            var result_words = Magnitude(capacity=max_len)
            for i in range(max_len):
                var wa = UInt64(0) if i >= len(a.words) else a.words.unsafe_get(
                    i
                )
                var wb = UInt64(0) if i >= len(b.words) else b.words.unsafe_get(
                    i
                )
                result_words.append(wa | wb)
            while (
                len(result_words) > 1
                and result_words.unsafe_get(len(result_words) - 1) == 0
            ):
                result_words.shrink(len(result_words) - 1)
            return BigInt(raw_words=result_words^, sign=False)
        else:  # xor
            var max_len = max(len(a.words), len(b.words))
            var result_words = Magnitude(capacity=max_len)
            for i in range(max_len):
                var wa = UInt64(0) if i >= len(a.words) else a.words.unsafe_get(
                    i
                )
                var wb = UInt64(0) if i >= len(b.words) else b.words.unsafe_get(
                    i
                )
                result_words.append(wa ^ wb)
            while (
                len(result_words) > 1
                and result_words.unsafe_get(len(result_words) - 1) == 0
            ):
                result_words.shrink(len(result_words) - 1)
            return BigInt(raw_words=result_words^, sign=False)

    # General path: convert negative operands to two's complement inline
    var a_n = len(a.words)
    var b_n = len(b.words)
    var max_len = max(a_n, b_n)
    # Negative results may need an extra word for the conversion back
    if result_negative:
        max_len += 1

    # Pre-compute a's TC words: for negative, TC = ~(|a| - 1)
    var a_tc = Magnitude(capacity=a_n)
    if a.sign:
        var borrow: UInt64 = 1
        for i in range(a_n):
            var word = a.words.unsafe_get(i)
            a_tc.append(~(word - borrow))
            borrow = UInt64(word < borrow)
    else:
        for i in range(a_n):
            a_tc.append(a.words.unsafe_get(i))

    # Pre-compute b's TC words
    var b_tc = Magnitude(capacity=b_n)
    if b.sign:
        var borrow: UInt64 = 1
        for i in range(b_n):
            var word = b.words.unsafe_get(i)
            b_tc.append(~(word - borrow))
            borrow = UInt64(word < borrow)
    else:
        for i in range(b_n):
            b_tc.append(b.words.unsafe_get(i))

    # Perform the operation word-by-word
    var result_tc = Magnitude(capacity=max_len)
    for i in range(max_len):
        var wa = a_fill if i >= len(a_tc) else a_tc[i]
        var wb = b_fill if i >= len(b_tc) else b_tc[i]

        comptime if op == "and":
            result_tc.append(wa & wb)
        elif op == "or":
            result_tc.append(wa | wb)
        else:  # xor
            result_tc.append(wa ^ wb)

    # Convert result back from two's complement if negative
    if not result_negative:
        # Non-negative: result_tc is the magnitude
        while len(result_tc) > 1 and result_tc[len(result_tc) - 1] == 0:
            result_tc.shrink(len(result_tc) - 1)
        if len(result_tc) == 1 and result_tc[0] == 0:
            return BigInt()
        return BigInt(raw_words=result_tc^, sign=False)
    else:
        # Negative: magnitude = ~result_tc + 1
        var n = len(result_tc)
        var mag = Magnitude(capacity=n)
        for i in range(n):
            mag.append(~result_tc[i])
        var carry: UInt64 = 1
        for i in range(len(mag)):
            var s = UInt64(mag[i]) + carry
            mag[i] = s
            carry = UInt64(s < carry)
            if carry == 0:
                break
        if carry > 0:
            mag.append(UInt64(carry))
        # Strip leading zeros
        while len(mag) > 1 and mag[len(mag) - 1] == 0:
            mag.shrink(len(mag) - 1)
        if len(mag) == 1 and mag[0] == 0:
            return BigInt()
        return BigInt(raw_words=mag^, sign=True)


# ===----------------------------------------------------------------------=== #
# Core helper: in-place word-by-word binary bitwise operation
# ===----------------------------------------------------------------------=== #


def _binary_bitwise_op_inplace[op: StringLiteral](mut a: BigInt, imm b: BigInt):
    """Performs a word-by-word binary bitwise operation on `a` in-place.

    Computes the result word list and moves it into a.words, avoiding
    full BigInt construction.

    The operation is determined by the `op` parameter:
    - "and": bitwise AND
    - "or":  bitwise OR
    - "xor": bitwise XOR
    """

    # Determine fills (sign extension for infinite-width two's complement)
    var a_fill = ~UInt64(0) if a.sign else UInt64(0)
    var b_fill = ~UInt64(0) if b.sign else UInt64(0)

    # Determine result sign from operation on sign-extension bits
    var result_negative: Bool

    comptime if op == "and":
        result_negative = a.sign and b.sign
    elif op == "or":
        result_negative = a.sign or b.sign
    elif op == "xor":
        result_negative = a.sign != b.sign
    else:
        comptime assert False, "op must be 'and', 'or', or 'xor'"

    # Fast path: both non-negative
    if not a.sign and not b.sign:
        comptime if op == "and":
            var min_len = min(len(a.words), len(b.words))
            # We can modify a.words in-place for AND (result <= min_len)
            for i in range(min_len):
                a.words.unsafe_set(
                    i, a.words.unsafe_get(i) & b.words.unsafe_get(i)
                )
            # Truncate to min_len in a single shrink call
            if len(a.words) > min_len:
                a.words.shrink(min_len)
            # Strip leading zeros
            while len(a.words) > 1 and a.words[len(a.words) - 1] == 0:
                a.words.shrink(len(a.words) - 1)
            return
        elif op == "or":
            var b_len = len(b.words)
            # Extend a if b is longer
            while len(a.words) < b_len:
                a.words.append(UInt64(0))
            for i in range(b_len):
                a.words.unsafe_set(
                    i, a.words.unsafe_get(i) | b.words.unsafe_get(i)
                )
            # Words beyond b_len remain as-is (OR with 0)
            while len(a.words) > 1 and a.words[len(a.words) - 1] == 0:
                a.words.shrink(len(a.words) - 1)
            return
        else:  # xor
            var b_len = len(b.words)
            while len(a.words) < b_len:
                a.words.append(UInt64(0))
            for i in range(b_len):
                a.words.unsafe_set(
                    i, a.words.unsafe_get(i) ^ b.words.unsafe_get(i)
                )
            # Words beyond b_len remain as-is (XOR with 0)
            while len(a.words) > 1 and a.words[len(a.words) - 1] == 0:
                a.words.shrink(len(a.words) - 1)
            return

    # General path: convert negative operands to two's complement
    var a_n = len(a.words)
    var b_n = len(b.words)
    var max_len = max(a_n, b_n)
    if result_negative:
        max_len += 1

    # Pre-compute a's TC words
    var a_tc = Magnitude(capacity=a_n)
    if a.sign:
        var borrow: UInt64 = 1
        for i in range(a_n):
            var word = a.words.unsafe_get(i)
            a_tc.append(~(word - borrow))
            borrow = UInt64(word < borrow)
    else:
        for i in range(a_n):
            a_tc.append(a.words.unsafe_get(i))

    # Pre-compute b's TC words
    var b_tc = Magnitude(capacity=b_n)
    if b.sign:
        var borrow: UInt64 = 1
        for i in range(b_n):
            var word = b.words.unsafe_get(i)
            b_tc.append(~(word - borrow))
            borrow = UInt64(word < borrow)
    else:
        for i in range(b_n):
            b_tc.append(b.words.unsafe_get(i))

    # Perform the operation word-by-word into a new list
    var result_tc = Magnitude(capacity=max_len)
    for i in range(max_len):
        var wa = a_fill if i >= len(a_tc) else a_tc[i]
        var wb = b_fill if i >= len(b_tc) else b_tc[i]

        comptime if op == "and":
            result_tc.append(wa & wb)
        elif op == "or":
            result_tc.append(wa | wb)
        else:  # xor
            result_tc.append(wa ^ wb)

    # Convert result back from two's complement if negative
    if not result_negative:
        while len(result_tc) > 1 and result_tc[len(result_tc) - 1] == 0:
            result_tc.shrink(len(result_tc) - 1)
        if len(result_tc) == 1 and result_tc[0] == 0:
            a.words.clear()
            a.words.append(UInt64(0))
            a.sign = False
        else:
            a.words = result_tc^
            a.sign = False
    else:
        var n = len(result_tc)
        var mag = Magnitude(capacity=n)
        for i in range(n):
            mag.append(~result_tc[i])
        var carry: UInt64 = 1
        for i in range(len(mag)):
            var s = UInt64(mag[i]) + carry
            mag[i] = s
            carry = UInt64(s < carry)
            if carry == 0:
                break
        if carry > 0:
            mag.append(UInt64(carry))
        while len(mag) > 1 and mag[len(mag) - 1] == 0:
            mag.shrink(len(mag) - 1)
        if len(mag) == 1 and mag[0] == 0:
            a.words.clear()
            a.words.append(UInt64(0))
            a.sign = False
        else:
            a.words = mag^
            a.sign = True


# ===----------------------------------------------------------------------=== #
# Public API
# ===----------------------------------------------------------------------=== #


def bitwise_and(a: BigInt, b: BigInt) -> BigInt:
    """Returns a & b using Python-compatible two's complement semantics.

    Args:
        a: The first operand.
        b: The second operand.

    Returns:
        The bitwise AND of the two values.
    """
    return _binary_bitwise_op["and"](a, b)


def bitwise_or(a: BigInt, b: BigInt) -> BigInt:
    """Returns a | b using Python-compatible two's complement semantics.

    Args:
        a: The first operand.
        b: The second operand.

    Returns:
        The bitwise OR of the two values.
    """
    return _binary_bitwise_op["or"](a, b)


def bitwise_xor(a: BigInt, b: BigInt) -> BigInt:
    """Returns a ^ b using Python-compatible two's complement semantics.

    Args:
        a: The first operand.
        b: The second operand.

    Returns:
        The bitwise XOR of the two values.
    """
    return _binary_bitwise_op["xor"](a, b)


def bitwise_not(x: BigInt) -> BigInt:
    """Returns ~x using Python-compatible two's complement semantics.

    ~x = -(x + 1)

    For non-negative x: result is -(x+1), always negative (except ~(-1) = 0).
    For negative x (x = -|x|): result is |x| - 1, always non-negative.

    Args:
        x: The value to invert.

    Returns:
        The bitwise complement.
    """
    if not x.sign:
        # ~non_negative = -(x + 1)
        var n = len(x.words)
        var result_words = Magnitude(capacity=n + 1)
        var carry: UInt64 = 1
        for i in range(n):
            var s = UInt64(x.words.unsafe_get(i)) + carry
            result_words.append(s)
            carry = UInt64(s < carry)
        if carry > 0:
            result_words.append(UInt64(carry))
        return BigInt(raw_words=result_words^, sign=True)
    else:
        # ~negative = |x| - 1
        var n = len(x.words)
        var result_words = Magnitude(capacity=n)
        var borrow: UInt64 = 1
        for i in range(n):
            var word = x.words.unsafe_get(i)
            result_words.append(word - borrow)
            borrow = UInt64(word < borrow)
        # Strip leading zeros
        while (
            len(result_words) > 1
            and result_words.unsafe_get(len(result_words) - 1) == 0
        ):
            result_words.shrink(len(result_words) - 1)
        if len(result_words) == 1 and result_words[0] == 0:
            return BigInt()
        return BigInt(raw_words=result_words^, sign=False)


# ===----------------------------------------------------------------------=== #
# Public in-place API
# ===----------------------------------------------------------------------=== #


def bitwise_and_inplace(mut a: BigInt, imm b: BigInt):
    """Performs `a &= b` in-place using Python-compatible two's complement semantics.

    Args:
        a: The left-hand side operand, modified in place.
        b: The right-hand side operand.
    """
    _binary_bitwise_op_inplace["and"](a, b)


def bitwise_or_inplace(mut a: BigInt, imm b: BigInt):
    """Performs `a |= b` in-place using Python-compatible two's complement semantics.

    Args:
        a: The left-hand side operand, modified in place.
        b: The right-hand side operand.
    """
    _binary_bitwise_op_inplace["or"](a, b)


def bitwise_xor_inplace(mut a: BigInt, imm b: BigInt):
    """Performs `a ^= b` in-place using Python-compatible two's complement semantics.

    Args:
        a: The left-hand side operand, modified in place.
        b: The right-hand side operand.
    """
    _binary_bitwise_op_inplace["xor"](a, b)


# ===----------------------------------------------------------------------=== #
# Bit-level access
#
# A negative value is read as an infinite-width two's complement, which is the
# view the operators above already present and the one Python, GMP and Java
# share. The alternative -- reading the magnitude and keeping the sign aside --
# would make `test_bit(-3, 1)` disagree with `-3 & 2` on the same type.
#
# `set_bit`, `clear_bit` and `flip_bit` are written as the operators they
# correspond to rather than by reaching into the words. That is slower by one
# temporary, and it is how they are guaranteed to agree with `&`, `|` and `^`
# instead of merely intended to.
# ===----------------------------------------------------------------------=== #


def _magnitude_bit(words: Magnitude, index: Int) -> Int:
    """Returns bit `index` of a magnitude, or zero past its top."""
    var word = index // 64
    if word >= len(words):
        return 0
    return Int((words[word] >> UInt64(index % 64)) & 1)


def test_bit(x: BigInt, index: Int) raises -> Bool:
    """Returns whether bit `index` of `x` is set.

    Args:
        x: The value to read.
        index: Which bit, counted from zero at the least significant end.

    Returns:
        The bit, with a negative `x` read as an infinite-width two's
        complement: every bit of `-1` is set, and the bits of `-8` above the
        third are too.

    Raises:
        ValueError: If `index` is negative.

    Notes:

    For a negative value the bits come from `-m = ~(m - 1)`, which says bit
    `k` of the result is the complement of bit `k` of `m - 1`. Rather than
    form `m - 1`, the same thing is read off the trailing zeros `t` of `m`:
    below `t` the borrow leaves zeros, at `t` it leaves a one, and above it
    the bits are the complement of the magnitude's own.
    """
    if index < 0:
        raise ValueError(
            message="A bit index cannot be negative.",
            function="test_bit()",
        )
    if not x.sign:
        return _magnitude_bit(x.words, index) == 1

    var trailing = _count_trailing_zeros(x.words)
    if index < trailing:
        return False
    if index == trailing:
        return True
    return _magnitude_bit(x.words, index) == 0


def set_bit(x: BigInt, index: Int) raises -> BigInt:
    """Returns `x` with bit `index` set.

    Args:
        x: The value.
        index: Which bit to set.

    Returns:
        `x | (1 << index)`, which is what the operator gives and therefore
        what this does.

    Raises:
        ValueError: If `index` is negative.
    """
    if index < 0:
        raise ValueError(
            message="A bit index cannot be negative.",
            function="set_bit()",
        )
    return x | (BigInt.one() << index)


def clear_bit(x: BigInt, index: Int) raises -> BigInt:
    """Returns `x` with bit `index` cleared.

    Args:
        x: The value.
        index: Which bit to clear.

    Returns:
        `x & ~(1 << index)`.

    Raises:
        ValueError: If `index` is negative.
    """
    if index < 0:
        raise ValueError(
            message="A bit index cannot be negative.",
            function="clear_bit()",
        )
    return x & ~(BigInt.one() << index)


def flip_bit(x: BigInt, index: Int) raises -> BigInt:
    """Returns `x` with bit `index` inverted.

    Args:
        x: The value.
        index: Which bit to invert.

    Returns:
        `x ^ (1 << index)`.

    Raises:
        ValueError: If `index` is negative.
    """
    if index < 0:
        raise ValueError(
            message="A bit index cannot be negative.",
            function="flip_bit()",
        )
    return x ^ (BigInt.one() << index)


def trailing_zeros(x: BigInt) -> Int:
    """Returns the number of trailing zero bits of `x`.

    Args:
        x: The value.

    Returns:
        The index of the lowest set bit, or -1 when `x` is zero, which is
        what Java's `getLowestSetBit` answers there.

    Notes:

    The sign does not enter: `-m` has as many trailing zeros as `m`, since
    the borrow that forms it stops at the lowest set bit.
    """
    if x.is_zero():
        return -1
    return _count_trailing_zeros(x.words)


def bit_scan1(x: BigInt, start: Int) raises -> Int:
    """Returns the index of the first set bit at or above `start`.

    Args:
        x: The value to scan.
        start: Where to start looking.

    Returns:
        The index, or -1 when there is none, which can only happen for a
        non-negative `x`: above the magnitude every bit of a negative value
        is set.

    Raises:
        ValueError: If `start` is negative.
    """
    return _bit_scan(x, start, True, "bit_scan1()")


def bit_scan0(x: BigInt, start: Int) raises -> Int:
    """Returns the index of the first clear bit at or above `start`.

    Args:
        x: The value to scan.
        start: Where to start looking.

    Returns:
        The index, or -1 when there is none, which can only happen for a
        negative `x`: above the magnitude every bit of a non-negative value
        is clear.

    Raises:
        ValueError: If `start` is negative.
    """
    return _bit_scan(x, start, False, "bit_scan0()")


def _bit_scan(
    x: BigInt, start: Int, wanted: Bool, function: String
) raises -> Int:
    """Scans upwards from `start` for a bit equal to `wanted`.

    Args:
        x: The value to scan.
        start: Where to start looking.
        wanted: The bit value to stop at.
        function: The name to report in an error.

    Returns:
        The index, or -1 when the scan runs past the point where every
        remaining bit is the sign's.

    Raises:
        ValueError: If `start` is negative.

    Notes:

    Past `bit_length()` every bit is the sign bit, so the scan is bounded:
    when `wanted` is that bit the answer is at or below the bound, and when
    it is not, there is no answer at all.
    """
    if start < 0:
        raise ValueError(
            message="A bit index cannot be negative.",
            function=function,
        )
    var bound = x.bit_length() + 1
    if start > bound:
        bound = start
    for index in range(start, bound + 1):
        if test_bit(x, index) == wanted:
            return index
    return -1


def hamming_distance(x: BigInt, y: BigInt) raises -> Int:
    """Returns the number of bit positions where `x` and `y` differ.

    Args:
        x: One value.
        y: The other.

    Returns:
        The count, which is `popcount(x ^ y)`.

    Raises:
        ValueError: If the signs differ, where the two agree on no bit above
            their magnitudes and the distance is therefore unbounded. GMP
            calls the same case undefined.
    """
    if x.sign != y.sign:
        raise ValueError(
            message=(
                "The Hamming distance between a negative and a non-negative"
                " value is unbounded: they differ in every bit above their"
                " magnitudes."
            ),
            function="hamming_distance()",
        )
    return (x ^ y).bit_count()
