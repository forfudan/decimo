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

from decimo.biguint.biguint import BigUInt
import decimo.biguint.comparison as biguint_comparison
from decimo.errors import (
    OverflowError,
    ValueError,
    ZeroDivisionError,
)
from decimo.rounding_mode import RoundingMode
from decimo.utility import alias_as_immutable_source

comptime CUTOFF_KARATSUBA = 256
"""The cutoff number of words for using Karatsuba multiplication.

Raised from 64 when the schoolbook base case became product-scanning. A Comba
column reduces base-10^9 once per result word instead of once per partial
product, which makes the quadratic kernel fast enough that Karatsuba's extra
`BigUInt` allocations and additions do not pay until much later.
"""
comptime CUTOFF_TOOM3 = 768
"""The cutoff number of words for using Toom-3 multiplication.

NOTE: Karatsuba is used for `CUTOFF_KARATSUBA < max_words <= CUTOFF_TOOM3`.
"""
comptime CUTOFF_BURNIKEL_ZIEGLER = 32
"""The cutoff number of words for using Burnikel-Ziegler division."""
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
# add_by_uint32_inplace(x: BigUInt, y: UInt32) -> None
#
# subtract(x1: BigUInt, x2: BigUInt) -> BigUInt
# subtract_carry_select(x1: BigUInt, x2: BigUInt) -> BigUInt
# subtract_inplace(x1: BigUInt, x2: BigUInt) -> None
# subtract_no_check_inplace(x1: BigUInt, x2: BigUInt) -> None
# subtract_by_uint32_inplace(x: BigUInt, y: UInt32) -> None
#
# multiply(x1: BigUInt, x2: BigUInt) -> BigUInt
# multiply_slices_schoolbook(x: BigUInt, y: BigUInt, start_x: Int, end_x: Int, start_y: Int, end_y: Int) -> BigUInt
# multiply_slices_karatsuba(x: BigUInt, y: BigUInt, start_x: Int, end_x: Int, start_y: Int, end_y: Int, cutoff_number_of_words: Int) -> BigUInt
# multiply_slices_toom3(x: BigUInt, y: BigUInt, bounds_x: Tuple[Int, Int], bounds_y: Tuple[Int, Int]) -> BigUInt
# multiply_by_uint32_inplace(x: BigUInt, y: UInt32) -> None
# multiply_by_power_of_ten(x: BigUInt, n: Int) -> BigUInt
# multiply_by_power_of_billion_inplace(mut x: BigUInt, n: Int)
# exact_divide_by_2_inplace(mut x: BigUInt)
# exact_divide_by_3_inplace(mut x: BigUInt)
#
# floor_divide(x1: BigUInt, x2: BigUInt) -> BigUInt
# floor_divide_schoolbook(x1: BigUInt, x2: BigUInt) -> BigUInt
# floor_divide_estimate_quotient(x1: BigUInt, x2: BigUInt, j: Int, m: Int) -> UInt64
# floor_divide_by_single_word_inplace(x1: BigUInt, x2: BigUInt) -> None
# floor_divide_by_double_words_inplace(x1: BigUInt, x2: BigUInt) -> None
# floor_divide_by_2_inplace(x: BigUInt) -> None
# floor_divide_by_power_of_ten(x: BigUInt, n: Int) -> BigUInt
# floor_divide_by_power_of_ten_inplace(x: BigUInt, n: Int) -> None
# floor_divide_by_power_of_billion(x: BigUInt, n: Int) -> BigUInt
# floor_divide_by_power_of_billion_inplace(x: BigUInt, n: Int) -> None
#
# truncate_divide(x1: BigUInt, x2: BigUInt) -> BigUInt
# ceil_divide(x1: BigUInt, x2: BigUInt) -> BigUInt
#
# floor_modulo(x1: BigUInt, x2: BigUInt) -> BigUInt
# ceil_modulo(x1: BigUInt, x2: BigUInt) -> BigUInt
# floor_divide_modulo(x1: BigUInt, x2: BigUInt) -> Tuple[BigUInt, BigUInt]
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
# Word-level carry-select kernels
#
# A base-10^9 word does not carry by overflowing, so the carry out of a word
# cannot be read off the hardware flags the way a base-2^32 one can: it is a
# comparison against `BASE`, and the comparison depends on the carry coming in.
# Written directly, that puts a compare on the loop-carried dependency chain.
#
# These kernels use the carry-select trick instead: both answers — the one for
# carry-in 0 and the one for carry-in 1 — are computed from the operands alone,
# off the critical path, and the incoming carry only picks between them. What
# remains loop-carried is a select, so the chain is roughly one cycle per word
# rather than the three or four an add-compare-branch chain costs.
#
# They also replace the older two-pass shape (a vectorized word-wise add over
# the whole operand, then `normalize_carries_lt_2_bases()` over the whole
# result). One pass touches the words once instead of twice, which is what the
# large sizes were actually paying for, and a carry that dies early now stops
# early instead of walking the rest of the accumulator.
# ===----------------------------------------------------------------------=== #


@always_inline
def _add_words_carry_select[
    o: Origin[mut=True],
    o_a: Origin[mut=False],
    o_b: Origin[mut=False],
](
    rp: Pointer[UInt32, o],
    ap: Pointer[UInt32, o_a],
    bp: Pointer[UInt32, o_b],
    n_words: Int,
    carry_in: UInt32,
) -> UInt32:
    """Adds `n_words` base-10^9 words: `r = a + b`, least significant first.

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
    var carry = carry_in
    for i in range(n_words):
        var raw = ap[unsafe_offset=i] + bp[unsafe_offset=i]
        var carry_if_0 = UInt32(raw >= BigUInt.BASE)
        var carry_if_1 = UInt32(raw >= BigUInt.BASE_MAX)
        var word_if_0 = raw - BigUInt.BASE if carry_if_0 != 0 else raw
        var word_if_1 = raw + 1 - BigUInt.BASE if carry_if_1 != 0 else raw + 1
        rp[unsafe_offset=i] = word_if_1 if carry != 0 else word_if_0
        carry = carry_if_1 if carry != 0 else carry_if_0
    return carry


@always_inline
def _subtract_words_borrow_select[
    o: Origin[mut=True],
    o_a: Origin[mut=False],
    o_b: Origin[mut=False],
](
    rp: Pointer[UInt32, o],
    ap: Pointer[UInt32, o_a],
    bp: Pointer[UInt32, o_b],
    n_words: Int,
    borrow_in: UInt32,
) -> UInt32:
    """Subtracts `n_words` base-10^9 words: `r = a - b`, least significant first.

    The borrow counterpart of `_add_words_carry_select()`, with the same
    aliasing freedom. The wrapped `a - b` is deliberate: it is the right answer
    modulo 2^32 once `BASE` is added back.

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
        var borrow_if_0 = UInt32(minuend < subtrahend)
        var borrow_if_1 = UInt32(minuend <= subtrahend)
        var word_if_0 = raw + BigUInt.BASE if borrow_if_0 != 0 else raw
        var word_if_1 = raw - 1 + BigUInt.BASE if borrow_if_1 != 0 else raw - 1
        rp[unsafe_offset=i] = word_if_1 if borrow != 0 else word_if_0
        borrow = borrow_if_1 if borrow != 0 else borrow_if_0
    return borrow


@always_inline
def _carry_into_tail[
    o: Origin[mut=True], o_a: Origin[mut=False]
](
    rp: Pointer[UInt32, o],
    ap: Pointer[UInt32, o_a],
    start: Int,
    end: Int,
    carry_in: UInt32,
) -> UInt32:
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
        carry = UInt32(raw >= BigUInt.BASE)
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
    rp: Pointer[UInt32, o],
    ap: Pointer[UInt32, o_a],
    start: Int,
    end: Int,
    borrow_in: UInt32,
) -> UInt32:
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
        borrow = UInt32(minuend == 0)
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
# add, add_inplace, add_by_uint32_inplace
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
            add_by_uint32_inplace(result, x.words[0])
            return result^

    if len(y.words) == 1:
        # If y is single-word, we can handle it with UInt32
        var result = x.copy()
        add_by_uint32_inplace(result, y.words[0])
        return result^

    # If both numbers are double-word, we can handle them with UInt64
    if len(x.words) <= 2 and len(y.words) <= 2:
        return BigUInt.from_unsigned_integral_scalar(
            x.to_uint64_with_first_2_words() + y.to_uint64_with_first_2_words()
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
            # If both numbers are single-word, we can handle them with UInt32
            return BigUInt.from_unsigned_integral_scalar(
                x.words[bounds_x[0]] + y.words[bounds_y[0]]
            )
        else:
            # If y slice is longer
            var result = BigUInt.from_slice(y, bounds_y)
            add_by_uint32_inplace(result, x.words[bounds_x[0]])
            return result^
    if n_words_y_slice == 1:
        if y.words[bounds_y[0]] == 0:
            return BigUInt.from_slice(x, bounds_x)
        else:
            # If x slice is longer
            var result = BigUInt.from_slice(x, bounds_x)
            add_by_uint32_inplace(result, y.words[bounds_y[0]])
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
    above `_add_words_carry_select()` for why the loop is shaped the way it is.
    """

    var n_words_x_slice = bounds_x[1] - bounds_x[0]
    var n_words_y_slice = bounds_y[1] - bounds_y[0]
    var n_words_longer = max(n_words_x_slice, n_words_y_slice)
    var n_words_shorter = min(n_words_x_slice, n_words_y_slice)

    var result = BigUInt(unsafe_uninit_length=n_words_longer)
    result.words.reserve(n_words_longer + 1)

    var xp = x.words.unsafe_ptr().unsafe_offset(bounds_x[0])
    var yp = y.words.unsafe_ptr().unsafe_offset(bounds_y[0])
    var rp = result.words.unsafe_ptr()

    var carry = _add_words_carry_select(rp, xp, yp, n_words_shorter, UInt32(0))
    var longer = xp if n_words_x_slice > n_words_y_slice else yp
    carry = _carry_into_tail(rp, longer, n_words_shorter, n_words_longer, carry)
    if carry != 0:
        result.words.append(UInt32(1))

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
        add_by_uint32_inplace(x, y.words[0])
        return

    # Normal cases
    if len(x.words) < len(y.words):
        x.words.resize(length=len(y.words), fill=UInt32(0))

    var xp = x.words.unsafe_ptr()
    var carry = _add_words_carry_select(
        xp,
        alias_as_immutable_source(xp),
        y.words.unsafe_ptr(),
        len(y.words),
        UInt32(0),
    )
    carry = _carry_into_tail(
        xp, alias_as_immutable_source(xp), len(y.words), len(x.words), carry
    )
    if carry != 0:
        x.words.append(UInt32(1))

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
        add_by_uint32_inplace(x, y.words[bounds_y[0]])
        return

    # Normal cases
    if len(x.words) < n_words_y_slice:
        x.words.resize(length=n_words_y_slice, fill=UInt32(0))

    var xp = x.words.unsafe_ptr()
    var carry = _add_words_carry_select(
        xp,
        alias_as_immutable_source(xp),
        y.words.unsafe_ptr().unsafe_offset(bounds_y[0]),
        n_words_y_slice,
        UInt32(0),
    )
    carry = _carry_into_tail(
        xp, alias_as_immutable_source(xp), n_words_y_slice, len(x.words), carry
    )
    if carry != 0:
        x.words.append(UInt32(1))

    return


def add_by_uint32_inplace(mut x: BigUInt, y: UInt32) -> None:
    """Increments a BigUInt number by a UInt32 value.

    Args:
        x: The `BigUInt` number to increment.
        y: The `UInt32` value to add.
    """
    var carry: UInt32 = y
    for i in range(len(x.words)):
        x.words[i] += carry
        if x.words[i] <= BigUInt.BASE_MAX:
            return  # No carry, we can stop early
        else:
            carry = 1  # Cannot be more than 1
            x.words[i] -= BigUInt.BASE
    else:
        x.words.append(UInt32(1))

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
    var borrow: UInt32 = 0  # Can either be 0 or 1

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
    `x`. See the kernel comment above `_add_words_carry_select()`.
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
    var borrow = _subtract_words_borrow_select(
        rp, xp, y.words.unsafe_ptr(), len(y.words), UInt32(0)
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
        x.words[0] = UInt32(0)  # Result is zero
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

    # If y is a single-word number, we can handle it with UInt32
    if len(y.words) == 1:
        subtract_by_uint32_inplace(x, y.words[0])
        return

    # Note that len(x.words) >= len(y.words) here
    var xp = x.words.unsafe_ptr()
    var borrow = _subtract_words_borrow_select(
        xp,
        alias_as_immutable_source(xp),
        y.words.unsafe_ptr(),
        len(y.words),
        UInt32(0),
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
    var borrow = _subtract_words_borrow_select(
        xp,
        alias_as_immutable_source(xp),
        y.words.unsafe_ptr(),
        len(y.words),
        UInt32(0),
    )
    _ = _borrow_into_tail(
        xp, alias_as_immutable_source(xp), len(y.words), len(x.words), borrow
    )

    x.remove_leading_empty_words()

    return


def subtract_by_uint32_inplace(mut x: BigUInt, y: UInt32) -> None:
    """Subtracts a UInt32 value from a BigUInt number in-place.

    Args:
        x: The BigUInt number to subtract from.
        y: The UInt32 value to subtract.

    Notes:
        This function assumes that x >= y, and it does not check for underflow.
        It is the caller's responsibility to ensure that x is greater than or
        equal to y before calling this function.
    """

    debug_assert[assert_mode="none"](
        (len(x.words) > 1) or (x.words[0] >= y),
        "subtract_by_uint32_inplace(): Underflow due to x < y.",
    )

    x.words[0] -= y

    if len(x.words) == 1:
        return
    else:  # len(x.words) > 1
        # We need to handle the borrow for the rest of the words
        var borrow: UInt32 = 0
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
        This function uses a three-tier dispatch based on operand size:
        schoolbook multiplication for small numbers (≤64 words), Karatsuba
        multiplication for medium numbers (65–256 words), and Toom-3
        multiplication for large numbers (>256 words).
    """

    debug_assert[assert_mode="none"](
        len(x.words) != 0, "BigUInt is uninitialized!"
    )
    debug_assert[assert_mode="none"](
        len(y.words) != 0, "BigUInt is uninitialized!"
    )

    # SPECIAL CASES
    # If x or y is a single-word number
    # We can use `multiply_by_uint32_inplace` because this is only one loop
    # No need to split the long number into two parts
    if len(x.words) == 1:
        var x_word = x.words[0]
        if x_word == 0:
            return BigUInt.zero()
        elif x_word == 1:
            return y.copy()
        else:
            var result = y.copy()
            multiply_by_uint32_inplace(result, x_word)
            return result^

    if len(y.words) == 1:
        var y_word = y.words[0]
        if y_word == 0:
            return BigUInt.zero()
        if y_word == 1:
            return x.copy()
        else:
            var result = x.copy()
            multiply_by_uint32_inplace(result, y_word)
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
    # Use Toom-3 multiplication for very large numbers
    elif max_words > CUTOFF_TOOM3:
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
        This function uses a three-tier dispatch based on operand size:
        schoolbook multiplication for small numbers (≤64 words), Karatsuba
        multiplication for medium numbers (65–256 words), and Toom-3
        multiplication for large numbers (>256 words).
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
    # Use Toom-3 multiplication for very large numbers
    elif max_words > CUTOFF_TOOM3:
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
            multiply_by_uint32_inplace(result, x_word)
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
            multiply_by_uint32_inplace(result, y_word)
            return result^

    # Product scanning (Comba): walk the result one word at a time, summing
    # the whole column `sum(x_i * y_j)` with `i + j == k` in a `UInt128`
    # accumulator before emitting a word.
    #
    # The operand-scanning form this replaces did a `% BASE` and a `// BASE`
    # on every one of the `n_x * n_y` partial products, and read and wrote the
    # result array on each of them too. Here the base-10^9 reduction happens
    # once per result word - `n_x + n_y` of them, not `n_x * n_y` - and the
    # column stays in registers. About 2.2x at 256 words, and ahead from two
    # words up, so there is no size gate any more.
    #
    # Overflow safety: each partial product is below `(10^9)^2 = 10^18 < 2^60`
    # and a column has at most `n_min` of them, so a `UInt128` accumulator
    # cannot overflow for any operand this library can allocate. The column is
    # unrolled over four independent accumulators because a single one
    # serialises on the 128-bit add.
    comptime BASE = UInt128(BigUInt.BASE)

    var result_length = n_words_x_slice + n_words_y_slice
    var result = BigUInt(unsafe_uninit_length=result_length)

    var start_x = bounds_x[0]
    var start_y = bounds_y[0]
    var x_words_ptr = x.words.unsafe_ptr()
    var y_words_ptr = y.words.unsafe_ptr()
    var result_ptr = result.words.unsafe_ptr()

    # `carry` is the part of the column sum at or above 10^9, which belongs to
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
            acc0 += UInt128(
                UInt64(x_words_ptr[unsafe_offset=start_x + i])
                * UInt64(y_words_ptr[unsafe_offset=start_y + k - i])
            )
            acc1 += UInt128(
                UInt64(x_words_ptr[unsafe_offset=start_x + i + 1])
                * UInt64(y_words_ptr[unsafe_offset=start_y + k - i - 1])
            )
            acc2 += UInt128(
                UInt64(x_words_ptr[unsafe_offset=start_x + i + 2])
                * UInt64(y_words_ptr[unsafe_offset=start_y + k - i - 2])
            )
            acc3 += UInt128(
                UInt64(x_words_ptr[unsafe_offset=start_x + i + 3])
                * UInt64(y_words_ptr[unsafe_offset=start_y + k - i - 3])
            )
            i += 4
        while i <= i_high:
            acc0 += UInt128(
                UInt64(x_words_ptr[unsafe_offset=start_x + i])
                * UInt64(y_words_ptr[unsafe_offset=start_y + k - i])
            )
            i += 1

        var column = (acc0 + acc1) + (acc2 + acc3)
        result_ptr[unsafe_offset=k] = UInt32(column % BASE)
        carry = column // BASE

    result_ptr[unsafe_offset=result_length - 1] = UInt32(carry % BASE)

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

        z1.multiply_by_power_of_billion_inplace(m)
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
        z1.multiply_by_power_of_billion_inplace(m)
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
        z2.multiply_by_power_of_billion_inplace(2 * m)
        z1.multiply_by_power_of_billion_inplace(m)
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
        multiply_by_uint32_inplace(px2, UInt32(2))
    else:
        px2 = BigUInt.zero()
    if has_x1:
        var x1_slice = BigUInt.from_slice(x, (sx1_start, sx1_end))
        add_inplace(px2, x1_slice)
    multiply_by_uint32_inplace(px2, UInt32(2))
    var x0_slice = BigUInt.from_slice(x, (sx0_start, sx0_end))
    add_inplace(px2, x0_slice)

    # --- Evaluate q(2) = y0 + 2*y1 + 4*y2 using Horner: (y2*2 + y1)*2 + y0
    var qy2: BigUInt
    if has_y2:
        qy2 = BigUInt.from_slice(y, (sy2_start, sy2_end))
        multiply_by_uint32_inplace(qy2, UInt32(2))
    else:
        qy2 = BigUInt.zero()
    if has_y1:
        var y1_slice = BigUInt.from_slice(y, (sy1_start, sy1_end))
        add_inplace(qy2, y1_slice)
    multiply_by_uint32_inplace(qy2, UInt32(2))
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
        multiply_by_uint32_inplace(vinf_16, UInt32(16))
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
            result.words[pos] = UInt32(s % UInt64(BigUInt.BASE))
            carry = s // UInt64(BigUInt.BASE)
        # Propagate remaining carry
        var pos = offset + len(value.words)
        while carry > 0 and pos < len(result.words):
            var s = UInt64(result.words[pos]) + carry
            result.words[pos] = UInt32(s % UInt64(BigUInt.BASE))
            carry = s // UInt64(BigUInt.BASE)
            pos += 1

    _add_at_offset(result, v0, 0)  # w0 at offset 0
    _add_at_offset(result, t1, m)  # w1 at offset m (stored in t1)
    _add_at_offset(result, w2, 2 * m)  # w2 at offset 2m
    _add_at_offset(result, t3, 3 * m)  # w3 at offset 3m (stored in t3)
    _add_at_offset(result, vinf, 4 * m)  # w4 at offset 4m

    result.remove_leading_empty_words()
    return result^


def multiply_by_uint32_inplace(mut x: BigUInt, y: UInt32):
    """Multiplies in-place a BigUInt by a UInt32 value.

    Args:
        x: The BigUInt value to multiply.
        y: The single word to multiply by.
    """
    # Short circuit cases when y is between 0 and 4
    # See `multiply_by_uint32_le_4_inplace()` for details
    # The performance is the best when `y <= 2`
    if y <= 2:
        multiply_by_uint32_le_4_inplace(x, y)
        return

    var y_as_uint64 = UInt64(y)
    var product: UInt64
    var carry: UInt64 = 0

    for i in range(len(x.words)):
        product = UInt64(x.words[i]) * y_as_uint64 + carry
        x.words[i] = UInt32(product % UInt64(BigUInt.BASE))
        carry = product // UInt64(BigUInt.BASE)

    if carry > 0:
        x.words.append(UInt32(carry))


def multiply_by_uint32_le_4_inplace(mut x: BigUInt, y: UInt32):
    """Multiplies in-place a BigUInt by a UInt32 value which is between 0 and 4.

    Args:
        x: The BigUInt value to multiply.
        y: The single word to multiply by. It must be between 0 and 4.

    Notes:

    This function will be used in the `multiply_by_uint32_inplace()` function.
    It is optimized for the case where y is between 0 and 4.

    When a valid word times 2, 3, or 4, the result is no larger than 4*10^9,
    which is less than 2^32-1. This means that we do not need to use UInt64 to
    store the product but use UInt32 directly. We can first use SIMD to do
    word-by-word multiplication, and then handle the carries.

    This function works the best when y is 0, 1, or 2. For y = 3 or 4, the
    normalization of carries is more expensive and may not compensate for the
    extra loop overhead.
    """

    # y is 0, x becomes 1
    if y == 0:
        x.words = [UInt32(0)]
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

    if y == 2:
        vectorize[BigUInt.VECTOR_WIDTH](len(x.words), vector_multiply_by_2)
        normalize_carries_lt_2_bases(x)
        return

    # y is 3, we can just multiply the digits of each word by 3
    def vector_multiply_by_3[simd_width: Int](i: Int) {mut x}:
        """Multiplies the digits of each word by 3."""
        x.words.unsafe_ptr().unsafe_store[width=simd_width](
            i, x.words.unsafe_ptr().unsafe_load[width=simd_width](i) * 3
        )

    if y == 3:
        vectorize[BigUInt.VECTOR_WIDTH](len(x.words), vector_multiply_by_3)
        normalize_carries_lt_4_bases(x)
        return

    # y is 4, we can just shift the digits of each word to the left by 2
    def vector_multiply_by_4[simd_width: Int](i: Int) {mut x}:
        """Shifts the digits of each word to the left by 2."""
        x.words.unsafe_ptr().unsafe_store[width=simd_width](
            i, x.words.unsafe_ptr().unsafe_load[width=simd_width](i) << 2
        )

    if y == 4:
        vectorize[BigUInt.VECTOR_WIDTH](len(x.words), vector_multiply_by_4)
        normalize_carries_lt_4_bases(x)
        return


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

    var number_of_zero_words = n // 9
    var number_of_remaining_digits = n % 9

    var result = BigUInt(
        uninitialized_capacity=number_of_zero_words + len(x.words) + 1
    )
    # Add zero words
    for _ in range(number_of_zero_words):
        result.words.append(UInt32(0))
    # Add the original words times 10^number_of_remaining_digits
    if number_of_remaining_digits == 0:
        for i in range(len(x.words)):
            result.words.append(x.words[i])
    else:  # number_of_remaining_digits > 0
        var carry = UInt64(0)
        var multiplier: UInt64
        var product: UInt64

        if number_of_remaining_digits == 1:
            multiplier = UInt64(10)
        elif number_of_remaining_digits == 2:
            multiplier = UInt64(100)
        elif number_of_remaining_digits == 3:
            multiplier = UInt64(1000)
        elif number_of_remaining_digits == 4:
            multiplier = UInt64(10_000)
        elif number_of_remaining_digits == 5:
            multiplier = UInt64(100_000)
        elif number_of_remaining_digits == 6:
            multiplier = UInt64(1_000_000)
        elif number_of_remaining_digits == 7:
            multiplier = UInt64(10_000_000)
        else:  # number_of_remaining_digits == 8
            multiplier = UInt64(100_000_000)

        for i in range(len(x.words)):
            product = UInt64(x.words[i]) * multiplier + carry
            result.words.append(UInt32(product % UInt64(BigUInt.BASE)))
            carry = product // UInt64(BigUInt.BASE)
        # Add the last carry if it exists
        if carry > 0:
            result.words.append(UInt32(carry))

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

    var number_of_zero_words = n // 9
    var number_of_remaining_digits = n % 9

    # SPECIAL CASE: If n is a multiple of 9
    if number_of_remaining_digits == 0:
        # If n is a multiple of 9, we just need to add zero words
        x.multiply_by_power_of_billion_inplace(number_of_zero_words)
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

        var carry = UInt64(0)
        var multiplier: UInt64
        var product: UInt64

        if number_of_remaining_digits == 1:
            multiplier = UInt64(10)
        elif number_of_remaining_digits == 2:
            multiplier = UInt64(100)
        elif number_of_remaining_digits == 3:
            multiplier = UInt64(1000)
        elif number_of_remaining_digits == 4:
            multiplier = UInt64(10_000)
        elif number_of_remaining_digits == 5:
            multiplier = UInt64(100_000)
        elif number_of_remaining_digits == 6:
            multiplier = UInt64(1_000_000)
        elif number_of_remaining_digits == 7:
            multiplier = UInt64(10_000_000)
        else:  # number_of_remaining_digits == 8
            multiplier = UInt64(100_000_000)

        for i in range(x_original_length):
            product = UInt64(x.words[i]) * multiplier + carry
            x.words[i] = UInt32(product % UInt64(BigUInt.BASE))
            carry = product // UInt64(BigUInt.BASE)

        # Add the last carry no matter it is 0 or not
        x.words[x_original_length] = UInt32(carry)

        # Now we shift the words to the right by number_of_zero_words
        for i in range(len(x.words) - 1, number_of_zero_words - 1, -1):
            x.words[i] = x.words[i - number_of_zero_words]

        # Fill the first number_of_zero_words with zeros
        for i in range(number_of_zero_words):
            x.words[i] = UInt32(0)

        # Remove the most significant zero word
        x.remove_leading_empty_words()
        return


def multiply_by_power_of_billion(x: BigUInt, n: Int) -> BigUInt:
    """Multiplies a BigUInt by (10^9)^n (n >= 0).
    This equals to adding 9n zeros (n words) to the end of the number.

    Args:
        x: The BigUInt value to multiply.
        n: The power of 10^9 to multiply by. Should be non-negative.

    Notes:

    In non-debug model, if n is less than or equal to 0, the function returns x
    unchanged. In debug mode, it asserts that n is non-negative.

    Returns:
        A new `BigUInt` containing the result of the multiplication.
    """
    debug_assert[assert_mode="none"](
        n >= 0,
        "multiply_by_power_of_billion(): n must be non-negative, got ",
        n,
    )

    if n <= 0:
        return x.copy()  # No change needed

    if x.is_zero():
        debug_assert[assert_mode="none"](
            len(x.words) == 1,
            "multiply_by_power_of_billion_inplace(): leading zero words",
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


def multiply_by_power_of_billion_inplace(mut x: BigUInt, n: Int):
    """Multiplies a BigUInt in-place by (10^9)^n (n >= 0).
    This equals to adding 9n zeros (n words) to the end of the number.

    Args:
        x: The BigUInt value to multiply.
        n: The power of 10^9 to multiply by. Should be non-negative.

    Notes:

    In non-debug model, if n is less than or equal to 0, the function returns x
    unchanged. In debug mode, it asserts that n is non-negative.
    """
    debug_assert[assert_mode="none"](
        n >= 0,
        "multiply_by_power_of_billion_inplace(): n must be non-negative, got ",
        n,
    )

    if n <= 0:
        return  # No change needed

    if x.is_zero():
        debug_assert[assert_mode="none"](
            len(x.words) == 1,
            "multiply_by_power_of_billion_inplace(): leading zero words",
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
        x.words[i] = UInt32(0)

    x.remove_leading_empty_words()
    return


def exact_divide_by_2_inplace(mut x: BigUInt):
    """Divides a BigUInt by 2 exactly, in-place.

    The caller must ensure that x is even (divisible by 2).
    Uses base-10^9 long division from MSB to LSB.

    Args:
        x: The `BigUInt` value to divide, modified in place.
    """
    var carry: UInt32 = 0
    for i in range(len(x.words) - 1, -1, -1):
        # carry is 0 or 1; carry * BASE + words[i] fits in UInt32
        # because max = 1 * 10^9 + 999_999_999 = 1_999_999_999 < 2^32
        var val = carry * UInt32(BigUInt.BASE) + x.words[i]
        x.words[i] = val // 2
        carry = val % 2
    x.remove_leading_empty_words()


def exact_divide_by_3_inplace(mut x: BigUInt):
    """Divides a BigUInt by 3 exactly, in-place.

    The caller must ensure that x is divisible by 3.
    Uses base-10^9 long division from MSB to LSB.

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

    Args:
        x: The `BigUInt` value to divide, modified in place.
    """
    comptime BASE_OVER_THREE = UInt32(333_333_333)  # (10^9 - 1) / 3

    var carry = UInt32(0)  # 0, 1 or 2
    var xp = x.words.unsafe_ptr()
    for i in range(len(x.words) - 1, -1, -1):
        var word = xp[unsafe_offset=i]
        var word_quotient = word // 3  # off the chain
        var word_remainder = word - 3 * word_quotient  # off the chain, 0..2
        var total = carry + word_remainder  # on the chain, 0..4
        var carried = UInt32(total >= 3)
        xp[unsafe_offset=i] = carry * BASE_OVER_THREE + word_quotient + carried
        carry = total - 3 * carried
    x.remove_leading_empty_words()


# ===----------------------------------------------------------------------=== #
# Division Algorithms
# floor_divide
# floor_divide_schoolbook
# floor_divide_burnikel_ziegler
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
            var result = BigUInt.from_uint32_unsafe(x.words[0] // y.words[0])
            return result^
        # SUB-CASE: Divisor is single word (<= 9 digits)
        else:
            return floor_divide_by_uint32(x, y.words[0])

    # CASE: y is double words
    if len(y.words) == 2:
        # Use `floor_divide_by_uint64` as it is more efficient
        return floor_divide_by_uint64(x, y.to_uint64_with_first_2_words())

    # CASE: y is triple or quadraple words
    if len(y.words) <= 4:
        # Use `floor_divide_by_uint128` as it is more efficient
        return floor_divide_by_uint128(x, y.to_uint128_with_first_4_words())

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
    return floor_divide_burnikel_ziegler(x, y, cut_off=CUTOFF_BURNIKEL_ZIEGLER)


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
        return BigUInt.zero()  # Return zero

    # CASE: x is not greater than y
    var comparison_result: Int8 = x.compare(y)
    # SUB-CASE: dividend < divisor
    if comparison_result < 0:
        return BigUInt.zero()  # Return zero
    # SUB-CASE: dividend == divisor
    if comparison_result == 0:
        return BigUInt.one()

    # CASE: y is single word
    if len(y.words) == 1:
        # SUB-CASE: Division by one
        if y.words[0] == 1:
            return x.copy()
        # SUB-CASE: Single word // single word
        if len(x.words) == 1:
            var result = BigUInt.from_uint32_unsafe(x.words[0] // y.words[0])
            return result^
        # SUB-CASE: Divisor is single word (<= 9 digits)
        else:
            return floor_divide_by_uint32(x, y.words[0])

    # CASE: y is double words
    if len(y.words) == 2:
        # Use `floor_divide_by_uint64` as it is more efficient
        return floor_divide_by_uint64(x, y.to_uint64_with_first_2_words())

    # CASE: y is triple or quadraple words
    if len(y.words) <= 4:
        # Use `floor_divide_by_uint128` as it is more efficient
        return floor_divide_by_uint128(x, y.to_uint128_with_first_4_words())

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
    var remainder = BigUInt(uninitialized_capacity=len(x.words) + 1)
    remainder.words = x.words.copy()
    remainder.words.append(UInt32(0))

    var y_ptr = y.words.unsafe_ptr()
    var r_ptr = remainder.words.unsafe_ptr()

    for index_of_word in range(n_words_diff, -1, -1):
        var quotient = floor_divide_estimate_quotient(
            remainder, y, index_of_word
        )

        # remainder[index .. index + n) -= quotient * y.
        #
        # `carry` carries both halves of the step: the high word of the
        # product, and the borrow, which is folded into it exactly one word
        # later - the same trick the base-2^32 Knuth D uses. Biasing the
        # difference by BASE keeps it non-negative, so the borrow is just
        # whether the biased value stayed below BASE.
        var carry = UInt64(0)
        for i in range(n):
            var product = (
                UInt64(quotient) * UInt64(y_ptr[unsafe_offset=i]) + carry
            )
            carry = product // BASE
            var biased = (
                UInt64(r_ptr[unsafe_offset=index_of_word + i])
                + BASE
                - (product % BASE)
            )
            r_ptr[unsafe_offset=index_of_word + i] = UInt32(biased % BASE)
            carry += 1 - biased // BASE

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
                    r_ptr[unsafe_offset=index_of_word + i] = UInt32(
                        total - BASE
                    )
                    add_carry = 1
                else:
                    r_ptr[unsafe_offset=index_of_word + i] = UInt32(total)
                    add_carry = 0
            top_value += add_carry
        r_ptr[unsafe_offset=top] = UInt32(top_value - carry)

        result.words[index_of_word] = quotient

    result.remove_leading_empty_words()
    return result^


def floor_divide_estimate_quotient(
    dividend: BigUInt, divisor: BigUInt, index_of_word: Int
) -> UInt32:
    """Estimates the quotient digit using 3-by-2 division.

    This function implements a 3-by-2 quotient estimation algorithm,
    which divides a 3-word dividend portion by a 2-word divisor to get
    an accurate quotient estimate.

    Args:
        dividend: The dividend BigUInt number.
        divisor: The divisor BigUInt number. Should be at least 2 words.
        index_of_word: The current position in the division algorithm.

    Returns:
        An estimated quotient digit (0 to 999_999_999).

    Notes:

    The function performs division of a 3-word number by a 2-word number:
    Dividend portion: R = r2 * 10^18 + r1 * 10^9 + r0.
    Divisor: D = d1 * 10^9 + d0.
    Goal: Estimate Q = R // D.
    """

    # Extract three highest words of relevant dividend portion
    # numerator = r2r1r0
    # Extract 3-word dividend portion using SIMD for better performance
    var numerator: UInt128
    var base_index = index_of_word + len(divisor.words) - 2

    # Ensure we don't read beyond bounds
    if base_index + 2 < len(dividend.words):
        # We can safely load 3 words: r0, r1, r2
        numerator = (
            dividend.words.unsafe_ptr()
            .unsafe_load[width=4](base_index)
            .cast[DType.uint128]()
            * SIMD[DType.uint128, 4](
                1, 1_000_000_000, 1_000_000_000_000_000_000, 0
            )
        ).reduce_add()
    elif base_index + 1 < len(dividend.words):
        # We can safely load 2 words: r0, r1 (r2 = 0)
        numerator = (
            dividend.words.unsafe_ptr()
            .unsafe_load[width=2](base_index)
            .cast[DType.uint128]()
            * SIMD[DType.uint128, 2](1, 1_000_000_000)
        ).reduce_add()
    elif base_index < len(dividend.words):
        # We can only load 1 word: r0 (r1 = r2 = 0)
        numerator = UInt128(dividend.words[base_index])
    else:
        # All words are zero
        numerator = UInt128(0)

    # Extract two highest words of divisor using SIMD
    var denominator: UInt128
    debug_assert[assert_mode="none"](
        len(divisor.words) >= 2,
        "biguint.arithmetics.floor_divide_estimate_quotient(): ",
        "Divisor must have at least 2 words by design.",
    )
    denominator = (
        divisor.words.unsafe_ptr()
        .unsafe_load[width=2](len(divisor.words) - 2)
        .cast[DType.uint128]()
        * SIMD[DType.uint128, 2](1, 1_000_000_000)
    ).reduce_add()

    # Use the SIMD-computed full dividend
    var quotient_128 = numerator // denominator

    # Convert back to UInt32
    var quotient = UInt32(quotient_128)

    # Ensure we don't exceed the maximum value for a single word
    return min(quotient, BigUInt.BASE_MAX)


def floor_divide_by_uint32(x: BigUInt, y: UInt32) -> BigUInt:
    """**[PRIVATE]** Divides a BigUInt by a UInt32 divisor.

    Args:
        x: The BigUInt value to divide by the divisor.
        y: The UInt32 divisor. Must be non-zero.

    Notes:

    This function is used internally for division by single word divisors.
    It is not intended for public use. You need to ensure that y is non-zero.

    Returns:
        The quotient of x divided by y.
    """
    debug_assert[assert_mode="none"](
        y != 0, "biguint.arithmetics.floor_divide_by_uint32(): Division by zero"
    )

    # Single-word dividend: O(1) exact result. This also guards the pointer
    # hoisting below — for a one-word `x` with `x.words[0] < y` the quotient is
    # 0, and without this path `result` would be built with zero words, making
    # `result.words.unsafe_ptr()` operate on an empty buffer and returning a
    # BigUInt that violates the non-empty-words invariant.
    if len(x.words) == 1:
        return BigUInt.from_uint32_unsafe(x.words[0] // y)

    # Most significant word of the dividend
    var dividend = UInt64(x.words[len(x.words) - 1] // y)
    var carry = UInt64(x.words[len(x.words) - 1] % y)
    var y_uint64 = UInt64(y)
    var result: BigUInt
    if dividend == 0:
        result = BigUInt(unsafe_uninit_length=len(x.words) - 1)
    else:
        result = BigUInt(unsafe_uninit_length=len(x.words))
        result.words[len(result.words) - 1] = UInt32(dividend)

    # Process the rest of the words.
    # Use raw data pointers for both buffers:
    # this loop reads `x.words[i]` and writes `result.words[i]` every iteration,
    # so the indexed form reloads two `List._data` fields per element.
    # Using both pointers once removes those reloads and is a stable
    # +4-8% at >=256 words.
    # Safety: neither buffer is resized inside the loop,
    # `x` is borrowed (owned by the caller) and `result` outlives the loop;
    # `unsafe_ptr()` is origin-tied so both Lists stay alive while the pointers
    # are used. Every index `i` is in `[0, len-2]`, provably in-bounds.
    var x_ptr = x.words.unsafe_ptr()
    var res_ptr = result.words.unsafe_ptr()
    for i in range(len(x.words) - 2, -1, -1):
        dividend = carry * UInt64(BigUInt.BASE) + UInt64(x_ptr[unsafe_offset=i])
        res_ptr[unsafe_offset=i] = UInt32(dividend // y_uint64)
        carry = dividend % y_uint64

    debug_assert[assert_mode="none"](
        (len(result.words) == 1) or (result.words[len(result.words) - 1] != 0),
        "biguint.arithmetics.floor_divide_by_uint32(): ",
        "Result has leading zero words",
    )
    result.assert_invariant("floor_divide_by_uint32")
    return result^


def floor_divide_by_uint32_inplace(mut x: BigUInt, y: UInt32) -> None:
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
        (
            "biguint.arithmetics.floor_divide_by_uint32_inplace(): Division by"
            " zero"
        ),
    )

    # Most significant word of the dividend. `top` is read before the value is
    # shortened below: the loop that follows walks down from `top - 1`, and
    # deriving that bound from `len(x.words)` after a `shrink()` would skip the
    # word just below the one that was dropped and leave it undivided.
    var top = len(x.words) - 1
    var dividend = UInt64(x.words[top] // y)
    var carry = UInt64(x.words[top] % y)
    var y_uint64 = UInt64(y)
    if dividend == 0:
        if top == 0:
            # A single-word dividend smaller than the divisor has a quotient of
            # zero, and `BigUInt` spells zero as one zero word. Shrinking here
            # would leave the value with no words at all, and every operation
            # that reaches for `words[len(words) - 1]` - comparison first among
            # them - then indexes out of bounds.
            x.words[0] = UInt32(0)
            return
        x.words.shrink(top)
    else:
        x.words[top] = UInt32(dividend)

    # Process the rest of the words
    for i in range(top - 1, -1, -1):
        dividend = carry * UInt64(BigUInt.BASE) + UInt64(x.words[i])
        x.words[i] = UInt32(dividend // y_uint64)
        carry = dividend % y_uint64


def floor_divide_by_uint64(x: BigUInt, y: UInt64) -> BigUInt:
    """Divides a BigUInt by UInt64.

    Args:
        x: The `BigUInt` dividend.
        y: The `UInt64` divisor. Must be smaller than 10^18.

    Returns:
        The quotient of x divided by y.
    """
    debug_assert[assert_mode="none"](
        y != 0,
        "biguint.arithmetics.floor_divide_by_uint64(): ",
        "Division by zero.",
    )

    var carry = UInt128(0)
    var y_uint128 = UInt128(y)
    var result: BigUInt
    if len(x.words) % 2 == 1:
        carry = UInt128(x.words[len(x.words) - 1])
        result = BigUInt(unsafe_uninit_length=len(x.words) - 1)
    else:
        result = BigUInt(unsafe_uninit_length=len(x.words))

    for i in range(len(result.words) - 1, -1, -2):
        var dividend = (
            carry * UInt128(1_000_000_000_000_000_000)
            + (
                x.words.unsafe_ptr()
                .unsafe_load[width=2](i - 1)
                .cast[DType.uint128]()
                * SIMD[DType.uint128, 2](1, 1_000_000_000)
            ).reduce_add()
        )
        var quotient = dividend // y_uint128
        result.words[i] = UInt32(quotient // UInt128(BigUInt.BASE))
        result.words[i - 1] = UInt32(quotient % UInt128(BigUInt.BASE))
        carry = dividend % y_uint128

    result.remove_leading_empty_words()
    return result^


def floor_divide_by_uint64_inplace(mut x: BigUInt, y: UInt64) -> None:
    """Divides a BigUInt by UInt64 in-place.

    Args:
        x: The BigUInt value to divide by the divisor.
        y: The UInt64 divisor. Must be smaller than 10^18.
    """
    debug_assert[assert_mode="none"](
        y != 0,
        "biguint.arithmetics.floor_divide_by_uint64_inplace(): ",
        "Division by zero.",
    )

    if len(x.words) == 1:
        # The loop below folds an odd top word into `carry` and shortens the
        # value by one word, which for a one-word value leaves it with no words
        # at all - not a valid `BigUInt`, and a fault in the first comparison
        # that reads `words[len(words) - 1]`. A one-word quotient needs no loop.
        x.words[0] = UInt32(UInt64(x.words[0]) // y)
        return

    var carry = UInt128(0)
    var y_uint128 = UInt128(y)
    if len(x.words) % 2 == 1:
        carry = UInt128(x.words[len(x.words) - 1])
        x.words.resize(len(x.words) - 1, UInt32(0))

    for i in range(len(x.words) - 1, -1, -2):
        var dividend = (
            carry * UInt128(1_000_000_000_000_000_000)
            + (
                x.words.unsafe_ptr()
                .unsafe_load[width=2](i - 1)
                .cast[DType.uint128]()
                * SIMD[DType.uint128, 2](1, 1_000_000_000)
            ).reduce_add()
        )
        var quotient = dividend // y_uint128
        x.words[i] = UInt32(quotient // UInt128(BigUInt.BASE))
        x.words[i - 1] = UInt32(quotient % UInt128(BigUInt.BASE))
        carry = dividend % y_uint128

    x.remove_leading_empty_words()
    return


def floor_divide_by_uint128(x: BigUInt, y: UInt128) -> BigUInt:
    """Divides a BigUInt by UInt128.

    Args:
        x: The `BigUInt` dividend.
        y: The `UInt128` divisor. Must be smaller than 10^36.

    Returns:
        The quotient of x divided by y.
    """
    debug_assert[assert_mode="none"](
        y != 0,
        "biguint.arithmetics.floor_divide_by_uint128(): ",
        "Division by zero.",
    )

    comptime BILLION = UInt256(1_000_000_000)

    var y_uint255 = UInt256(y)
    var n_words = len(x.words)
    var lead_words = n_words % 4
    var result = BigUInt(unsafe_uninit_length=n_words)
    var carry = UInt256(0)

    # The dividend is consumed four words at a time, so a word count that is
    # not a multiple of four leaves a short leading group.
    #
    # That group has a quotient of its own, and the previous version of this
    # function threw it away: it kept only `lead % y` as the carry and sized
    # the result at `n - lead_words` words. Two things went wrong. A quotient
    # that needed the dropped words came back too small - `y` of three words
    # against `x` of seven silently lost the top word, a factor of 10^9. And
    # when the dividend *was* the leading group, at three words or fewer, the
    # result was left with no words at all, which faults the first operation
    # that reads `words[len(words) - 1]`.
    if lead_words != 0:
        var lead = UInt256(0)
        for k in range(n_words - 1, n_words - lead_words - 1, -1):
            lead = lead * BILLION + UInt256(x.words[k])
        var lead_quotient = lead // y_uint255
        carry = lead % y_uint255
        for k in range(n_words - lead_words, n_words):
            result.words[k] = UInt32(lead_quotient % BILLION)
            lead_quotient //= BILLION

    for i in range(n_words - lead_words - 1, -1, -4):
        var dividend = (
            carry * UInt256(1_000_000_000_000_000_000_000_000_000_000_000_000)
            + (
                x.words.unsafe_ptr()
                .unsafe_load[width=4](i - 3)
                .cast[DType.uint256]()
                * SIMD[DType.uint256, 4](
                    1,
                    1_000_000_000,
                    1_000_000_000_000_000_000,
                    1_000_000_000_000_000_000_000_000_000,
                )
            ).reduce_add()
        )
        var quotient = dividend // y_uint255
        result.words[i] = UInt32(
            quotient // UInt256(1_000_000_000_000_000_000_000_000_000)
        )
        quotient %= UInt256(1_000_000_000_000_000_000_000_000_000)
        result.words[i - 1] = UInt32(
            quotient // UInt256(1_000_000_000_000_000_000)
        )
        quotient %= UInt256(1_000_000_000_000_000_000)
        result.words[i - 2] = UInt32(quotient // UInt256(1_000_000_000))
        quotient %= UInt256(1_000_000_000)
        result.words[i - 3] = UInt32(quotient)
        carry = dividend % y_uint255

    result.remove_leading_empty_words()
    return result^


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
    var base: UInt32 = BigUInt.BASE
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


# TODO: If n % 9 == 0, the in-place version can be optimized by
# delegating to `floor_divide_by_power_of_billion_inplace` directly.
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
    debug_assert[assert_mode="none"](
        n >= 0,
        (
            "biguint.arithmetics.floor_divide_by_power_of_ten(): "
            "n must be non-negative but got "
            + String(n)
        ),
    )

    if n <= 0:
        return x.copy()

    var word_shift = n // 9
    var digit_shift = n % 9

    # If we need to drop more words than exists, the result is zero.
    if word_shift >= len(x.words):
        return BigUInt.zero()

    # Whole-word divide: delegate to the cheaper specialised path.
    if digit_shift == 0:
        return floor_divide_by_power_of_billion(x, word_shift)

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
    Delegates to `floor_divide_by_power_of_billion_inplace` whenever
    `n` is a multiple of 9, which is the common case for word-aligned
    truncation. In debug mode, asserts that `n` is non-negative.
    """
    debug_assert[assert_mode="none"](
        n >= 0,
        (
            "biguint.arithmetics.floor_divide_by_power_of_ten_inplace(): "
            "n must be non-negative but got "
            + String(n)
        ),
    )

    if n <= 0:
        return

    var word_shift = n // 9
    var digit_shift = n % 9

    if word_shift >= len(x.words):
        x.words.shrink(0)
        x.words.append(UInt32(0))
        return

    if digit_shift == 0:
        floor_divide_by_power_of_billion_inplace(x, word_shift)
        return

    if word_shift > 0:
        # Forward shift is safe: dst index < src index, dst[i] is
        # written before src[i+1] is read.
        var keep = len(x.words) - word_shift
        for i in range(keep):
            x.words[i] = x.words[i + word_shift]
        x.words.shrink(keep)

    _shift_right_by_decimal_digits_inplace(x, digit_shift)


def _shift_right_by_decimal_digits_inplace(mut x: BigUInt, digit_shift: Int):
    """Divides `x` in place by `10^digit_shift`, where
    `1 <= digit_shift <= 8`. Assumes any whole-word shift has already
    been applied; this only performs the sub-word digit shift and
    canonicalises the result.
    """
    debug_assert[assert_mode="none"](
        digit_shift >= 1 and digit_shift <= 8,
        (
            "biguint.arithmetics._shift_right_by_decimal_digits_inplace(): "
            "digit_shift must be in [1, 8]"
        ),
    )
    var divisor: UInt32
    if digit_shift == 1:
        divisor = UInt32(10)
    elif digit_shift == 2:
        divisor = UInt32(100)
    elif digit_shift == 3:
        divisor = UInt32(1000)
    elif digit_shift == 4:
        divisor = UInt32(10000)
    elif digit_shift == 5:
        divisor = UInt32(100000)
    elif digit_shift == 6:
        divisor = UInt32(1000000)
    elif digit_shift == 7:
        divisor = UInt32(10000000)
    else:  # digit_shift == 8
        divisor = UInt32(100000000)
    var power_of_carry = BigUInt.BASE // divisor
    var carry = UInt32(0)
    for i in range(len(x.words) - 1, -1, -1):
        var quot = x.words[i] // divisor
        var rem = x.words[i] % divisor
        x.words[i] = quot + carry * power_of_carry
        carry = rem
    x.remove_leading_empty_words()


def floor_divide_by_power_of_billion(x: BigUInt, n: Int) -> BigUInt:
    """Floor divides a BigUInt by (10^9)^n (n>=0).
    This function is equivalent to removing the last n words of the number.

    Args:
        x: The BigUInt value to divide.
        n: The power of 10^9 to divide by. Should be non-negative.

    Returns:
        A new BigUInt containing the result of the division.

    Notes:

    In non-debug model, if n is less than or equal to 0, the function returns x
    unchanged. In debug mode, it asserts that n is non-negative.
    """
    debug_assert[assert_mode="none"](
        n >= 0,
        (
            "biguint.arithmetics.floor_divide_by_power_of_billion(): "
            "n must be non-negative but got "
            + String(n)
        ),
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


def floor_divide_by_power_of_billion_inplace(mut x: BigUInt, n: Int):
    """In-place version of `floor_divide_by_power_of_billion`. Drops
    the `n` lowest base-10^9 words of `x` directly inside its `words`
    storage, avoiding an allocation.

    Args:
        x: The BigUInt value to divide in place.
        n: The power of 10^9 to divide by. Should be non-negative.

    Notes:

    No-op when `n <= 0`. When `n` is at least the current word count,
    `x` becomes the canonical zero (a single word holding 0). In
    debug mode, asserts that `n` is non-negative.
    """
    debug_assert[assert_mode="none"](
        n >= 0,
        (
            "biguint.arithmetics.floor_divide_by_power_of_billion_inplace(): "
            "n must be non-negative but got "
            + String(n)
        ),
    )

    if n <= 0:
        return

    var keep = len(x.words) - n
    if keep <= 0:
        x.words.shrink(0)
        x.words.append(UInt32(0))
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
# floor_divide_three_by_two_uint32
# floor_divide_four_by_two_uint32
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

    var BLOCK_SIZE_OF_WORDS = cut_off

    # STEP 1:
    # Normalize the divisor b to n words so that
    # (1) it is of the form j*2^k and
    # (2) the most significant word is at least 500_000_000.

    var normalized_b = b.copy()
    var normalized_a = a.copy()
    var ndigits_to_shift: Int

    if normalized_b.words[len(normalized_b.words) - 1] < 500_000_000:
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
    ) * 9 + ndigits_to_shift

    multiply_by_power_of_ten_inplace(normalized_b, n_digits_to_scale_up)
    multiply_by_power_of_ten_inplace(normalized_a, n_digits_to_scale_up)

    # The normalized_b is now 9 digits, but may still be smaller than 500_000_000.
    var gap_ratio: UInt32
    if (
        normalized_b.words[len(normalized_b.words) - 1] >= 500_000_000
    ):  # Already normalized
        gap_ratio = 1
    elif (
        normalized_b.words[len(normalized_b.words) - 1] >= 250_000_000
    ):  # 2x is enough
        gap_ratio = 2
    else:  # The most significant word is in [100_000_000, 125_000_000)
        gap_ratio = (
            BigUInt.BASE_MAX // normalized_b.words[len(normalized_b.words) - 1]
        )

    if gap_ratio >= 2:
        multiply_by_uint32_inplace(normalized_b, gap_ratio)
        multiply_by_uint32_inplace(normalized_a, gap_ratio)

    # STEP 2: Split the normalized a into blocks of size n.
    # t is the number of blocks in the dividend.
    var t = math.ceildiv(len(normalized_a.words), n)
    if len(normalized_a.words) == t * n:
        # If the number of words in the dividend is already a multiple of n
        # We check if the most significant word is >= 500_000_000.
        # If it is, we need to add one more block to the dividend.
        # This ensures that the most significant word of the dividend
        # is smaller than 500_000_000.
        # In this sense, the first 2-by-1 division will generate a quotient
        # of either 0 or 1, which would otherwise exceed n-word capacity.
        #
        # The length tested is `normalized_a`'s, not `a`'s. `t` counts blocks
        # of the normalized dividend, and normalization scales it by the same
        # power of ten as the divisor, so it is usually the longer of the two:
        # `len(a.words)` and `t * n` could only agree by accident. `BigInt`'s
        # copy of this algorithm has always tested the normalized length.
        if normalized_a.words[len(normalized_a.words) - 1] >= 500_000_000:
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
            # TODO: Refine this when Mojo support move values of unpacked tuples
            # https://github.com/modular/modular/issues/5330
            var _tuple = floor_divide_slices_two_by_one(
                normalized_a,
                normalized_b,
                bounds_a=((t - 2) * n, len(normalized_a.words)),
                bounds_b=(0, len(normalized_b.words)),
                n=n,
                cut_off=cut_off,
            )
            q = _tuple[0].copy()
            z = _tuple[1].copy()
        else:
            var _tuple = floor_divide_slices_two_by_one(
                z,
                normalized_b,
                bounds_a=(0, len(z.words)),
                bounds_b=(0, len(normalized_b.words)),
                n=n,
                cut_off=cut_off,
            )
            q_i = _tuple[0].copy()
            z = _tuple[1].copy()
            multiply_by_power_of_billion_inplace(q, n)
            q += q_i

        if i > 0:
            multiply_by_power_of_billion_inplace(z, n)
            # z = r + a[(i - 1) * n : i * n]
            add_by_slice_inplace(
                z,
                normalized_a,
                bounds_y=((i - 1) * n, i * n),
            )

    q.remove_leading_empty_words()
    return q^


def floor_divide_two_by_one(
    a: BigUInt, b: BigUInt, n: Int, cut_off: Int
) raises -> Tuple[BigUInt, BigUInt]:
    """Divides a BigUInt by another BigUInt using a recursive approach.
    The divisor has n words and the dividend has 2n words.

    Args:
        a: The dividend as a BigUInt.
        b: The divisor as a BigUInt. The most significant word must be at least
           500_000_000.
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
        b.words[len(b.words) - 1] >= 500_000_000,
        "b[-1] must be at least 500_000_000",
    )

    if (n & 1 == 1) or (n <= cut_off):
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
        multiply_by_power_of_billion_inplace(q, n // 2)
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
        multiply_by_power_of_billion_inplace(a2a1, n)
        a2a1 += a1
    # TODO: Refine this when Mojo support move values of unpacked tuples
    var _tuple = floor_divide_two_by_one(a2a1, b1, n, cut_off)
    var q = _tuple[0].copy()
    ref c = _tuple[1]  # c is the carry
    var d = q * b0
    multiply_by_power_of_billion_inplace(c, n)
    var r = c + a0

    if r < d:
        var b = b1.copy()
        multiply_by_power_of_billion_inplace(b, n)
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
) raises -> Tuple[BigUInt, BigUInt]:
    """Divides a BigUInt by another BigUInt using a recursive approach.
    The divisor has n words and the dividend has 2n words.

    Args:
        a: The dividend.
        b: The divisor.
        bounds_a: The range of words in the dividend to consider [start, end).
        bounds_b: The range of words in the divisor to consider [start, end).
            The most significant word must be at least 500_000_000.
        n: The number of words in the divisor.
        cut_off: The minimum number of words for the recursive division.

    Returns:
        A tuple containing the quotient and the remainder as BigUInt.

    Notes:

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
        b.words[len(b.words) - 1] >= 500_000_000,
        "floor_divide_slices_two_by_one(): b[-1] must be at least 500_000_000",
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
        var a_slice = BigUInt.from_slice(a, bounds_a)
        var b_slice = BigUInt.from_slice(b, bounds_b)
        var q = floor_divide_schoolbook(a_slice, b_slice)
        # r = a_slice - q * b_slice
        # We use inplace subtraction to avoid copying
        a_slice -= multiply_slices(q, b, (0, len(q.words)), bounds_b)
        return (q^, a_slice^)

    elif (bounds_a[0] + n + n // 2 >= bounds_a[1]) or a.is_zero_in_bounds(
        bounds=(bounds_a[0] + n + n // 2, bounds_a[1])
    ):
        # If a3 is empty or zero
        # We just need to use three-by-two division once: a2a1a0 // b1b0
        # Note that the condition must be short-circuited to avoid slicing
        # an empty BigUInt.
        var _tuple = floor_divide_slices_three_by_two(
            a, b, bounds_a, bounds_b, n // 2, cut_off
        )
        # _tuple = (q, r)
        return _tuple^

    else:
        var bounds_a1a3 = (bounds_a[0] + n // 2, bounds_a[1])

        # We use the most significant three parts of the dividend
        # a3a2a1 // b1b0
        var _tuple = floor_divide_slices_three_by_two(
            a, b, bounds_a1a3, bounds_b, n // 2, cut_off
        )
        var q = _tuple[0].copy()  # q is q1
        ref r = _tuple[1]  # r is the carry

        multiply_by_power_of_billion_inplace(r, n // 2)
        add_by_slice_inplace(r, a, (bounds_a[0], bounds_a[0] + n // 2))
        _tuple = floor_divide_slices_three_by_two(
            r, b, (0, len(r.words)), bounds_b, n // 2, cut_off
        )
        ref q0 = _tuple[0]  # q0
        var s = _tuple[1].copy()  # s is the final remainder

        # q -> q1q0
        multiply_by_power_of_billion_inplace(q, n // 2)
        q += q0

        return (q^, s^)


def floor_divide_slices_three_by_two(
    a: BigUInt,
    b: BigUInt,
    bounds_a: Tuple[Int, Int],
    bounds_b: Tuple[Int, Int],
    n: Int,
    cut_off: Int,
) raises -> Tuple[BigUInt, BigUInt]:
    """Divides a 3n-word BigUInt slice by a 2n-word BigUInt slice.

    Args:
        a: The dividend.
        b: The divisor.
        bounds_a: The range of words in the dividend to consider [start, end).
        bounds_b: The range of words in the divisor to consider [start, end).
        n: The number of words in each part of the dividend and divisor.
        cut_off: The minimum number of words for the recursive division.

    Returns:
        A tuple containing the quotient and the remainder as BigUInt.

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
    # Because the most significant word of b1 is at least 500_000_000,
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
            return (BigUInt.one(), a_slice^)
        else:
            return (BigUInt.zero(), a_slice^)

    # Now we can safely assume that a2 is not empty.
    var bounds_a0 = (bounds_a[0], bounds_a[0] + n)
    var bounds_a2a1 = (bounds_a[0] + n, bounds_a[1])
    var bounds_b1 = (bounds_b[0] + n, bounds_b[1])
    var bounds_b0 = (bounds_b[0], bounds_b[0] + n)

    var _tuple = floor_divide_slices_two_by_one(
        a, b, bounds_a2a1, bounds_b1, n, cut_off
    )
    var q = _tuple[0].copy()
    ref c = _tuple[1]  # c is the carry

    var d = multiply_slices(q, b, (0, len(q.words)), bounds_b0)
    multiply_by_power_of_billion_inplace(c, n)
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
    return (q^, r^)


# Yuhao ZHU:
# The following functions are most granular implementations of the
# Burnikel-Ziegler algorithm, which divide a 3-word number by a 2-word number
# and a 4-word number by a 2-word number, respectively.
# They are not used because they are too granular and not efficient.
# When then size of the divisor is less than N, we switch to the schoolbook
# division algorithm.
# However, these functions are still valid and can be used if needed.
def floor_divide_three_by_two_uint32(
    a2: UInt32, a1: UInt32, a0: UInt32, b1: UInt32, b0: UInt32
) raises -> Tuple[UInt32, UInt32, UInt32]:
    """Divides a 3-word number by a 2-word number.
    b1 must be at least 500_000_000.

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
        ValueError: If b1 < 500_000_000.

    Notes:

    a = a2 * BASE^2 + a1 * BASE + a0.
    b = b1 * BASE + b0.
    """
    if b1 < 500_000_000:
        raise ValueError(
            message="b1 must be at least 500_000_000",
            function="floor_divide_three_by_two_uint32()",
        )

    var a2a1 = UInt64(a2) * 1_000_000_000 + UInt64(a1)

    var q: UInt64 = UInt64(a2a1) // UInt64(b1)
    var c = a2a1 - q * UInt64(b1)
    var d: UInt64 = q * UInt64(b0)
    var r = UInt64(c * 1_000_000_000) + UInt64(a0)

    if r < UInt64(d):
        var b = UInt64(b1) * 1_000_000_000 + UInt64(b0)
        q -= 1
        r += b
        if r < UInt64(d):
            q -= 1
            r += b

    r -= d
    var r1: UInt32 = UInt32(r // 1_000_000_000)
    var r0: UInt32 = UInt32(r % 1_000_000_000)

    return (UInt32(q), r1, r0)


def floor_divide_four_by_two_uint32(
    a3: UInt32,
    a2: UInt32,
    a1: UInt32,
    a0: UInt32,
    b1: UInt32,
    b0: UInt32,
) raises -> Tuple[UInt32, UInt32, UInt32, UInt32]:
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
        (1) the most significant word of the quotient (as UInt32)
        (2) the least significant word of the quotient (as UInt32)
        (3) the most significant word of the remainder (as UInt32)
        (4) the least significant word of the remainder (as UInt32).

    Raises:
        ValueError: If b1 < 500_000_000 or a >= b * 10^18.
    """

    if b1 < 500_000_000:
        raise ValueError(
            message="b1 must be at least 500_000_000",
            function="floor_divide_four_by_two_uint32()",
        )
    if a3 > b1:
        raise ValueError(
            message="a must be less than b * 10^18",
            function="floor_divide_four_by_two_uint32()",
        )
    elif a3 == b1:
        if a2 > b0:
            raise ValueError(
                message="a must be less than b * 10^18",
                function="floor_divide_four_by_two_uint32()",
            )
        elif a2 == b0:
            if a1 > 0:
                raise ValueError(
                    message="a must be less than b * 10^18",
                    function="floor_divide_four_by_two_uint32()",
                )
            elif a1 == 0:
                if a0 >= 0:
                    raise ValueError(
                        message="a must be less than b * 10^18",
                        function="floor_divide_four_by_two_uint32()",
                    )

    var q1, r1, r0 = floor_divide_three_by_two_uint32(a3, a2, a1, b1, b0)
    var q0, s1, s0 = floor_divide_three_by_two_uint32(r1, r0, a0, b1, b0)
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
        add_by_uint32_inplace(quotient, 1)
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
    """
    # CASE: Division by zero
    if x2.is_zero():
        debug_assert[assert_mode="none"](
            len(x2.words) == 1,
            "truncate_modulo(): leading zero words",
        )
        raise ZeroDivisionError(
            function="floor_modulo()",
            message="Division by zero",
        )

    # CASE: Dividend is zero
    if x1.is_zero():
        debug_assert[assert_mode="none"](
            len(x1.words) == 1, "truncate_modulo(): leading zero words"
        )
        return BigUInt.zero()  # Return zero

    # CASE: Divisor is one - no remainder
    if x2.is_one():
        return BigUInt.zero()  # Always divisible with no remainder

    # CASE: |dividend| < |divisor| - the remainder is the dividend itself
    if x1.compare(x2) < 0:
        return x1.copy()

    # Calculate quotient with truncation
    var quotient: BigUInt
    try:
        quotient = floor_divide(x1, x2)
    except e:
        raise ZeroDivisionError(
            message="See the above exception.",
            function="floor_modulo()",
            previous_error=e^,
        )

    # Calculate remainder: dividend - (divisor * quotient)
    var remainder: BigUInt
    try:
        remainder = subtract(x1, multiply(x2, quotient))
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
    # CASE: Division by zero
    if x2.is_zero():
        debug_assert[assert_mode="none"](
            len(x2.words) == 1, "ceil_modulo(): leading zero words"
        )
        raise ZeroDivisionError(
            message="Division by zero", function="ceil_modulo()"
        )

    # CASE: Dividend is zero
    if x1.is_zero():
        debug_assert[assert_mode="none"](
            len(x1.words) == 1, "ceil_modulo(): leading zero words"
        )
        return BigUInt.zero()  # Return zero

    # CASE: Divisor is one - no remainder
    if x2.is_one():
        return BigUInt.zero()  # Always divisible with no remainder

    # CASE: |dividend| < |divisor| - the remainder is the dividend itself
    if x1.compare(x2) < 0:
        return x1.copy()

    # Calculate quotient with truncation
    var quotient = floor_divide(x1, x2)
    # Calculate remainder: dividend - (divisor * quotient)
    var remainder = subtract(x1, multiply(x2, quotient))

    if remainder.is_zero():
        debug_assert[assert_mode="none"](
            len(remainder.words) == 1, "ceil_modulo(): leading zero words"
        )
        return BigUInt.zero()  # No remainder
    else:
        return subtract(x2, remainder)


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

    try:
        var quotient = floor_divide(x1, x2)
        var remainder = subtract(x1, multiply(x2, quotient))
        return (quotient^, remainder^)
    except e:
        raise ZeroDivisionError(
            message="See the above exception.",
            function="floor_divide_modulo()",
            previous_error=e^,
        )


# ===----------------------------------------------------------------------=== #
# Helper Functions
# ===----------------------------------------------------------------------=== #


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
    var carry: UInt32 = 0
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
        x.words.append(UInt32(1))
    return


def normalize_carries_lt_4_bases(mut x: BigUInt):
    """Normalizes the values of words into valid range by carrying over.
    The initial values of the words should be in the range [0, BASE * 4 - 4].

    Notes:

    If we multiply a BigUInt numbers word-by-word by 3 or 4, we may end up with
    a situation where some words are ge than BASE but le BASE * 4 - 4.
    This function normalizes the carries, ensuring that all words are within the
    valid range. It modifies the input BigUInt in-place.

    Args:
        x: The `BigUInt` to normalize, modified in place.
    """

    # Yuhao ZHU:
    # By construction, the words of x are in the range [0, BASE*4).
    # Thus, the carry can only be 0, 1, 2, or 3.
    var carry: UInt32 = 0
    for ref word in x.words:
        if carry == 0:
            if word <= UInt32(999_999_999):
                pass  # carry = 0
            elif word <= UInt32(1_999_999_999):
                word -= UInt32(1_000_000_000)
                carry = 1
            elif word <= UInt32(2_999_999_999):
                word -= UInt32(2_000_000_000)
                carry = 2
            else:  # 3_000_000_000 <= word <= 3_999_999_996
                word -= UInt32(3_000_000_000)
                carry = 3
        elif carry == 1:
            if word <= UInt32(999_999_998):
                word += 1
                carry = 0
            elif word <= UInt32(1_999_999_998):
                word = word + 1 - UInt32(1_000_000_000)
                carry = 1
            elif word <= UInt32(2_999_999_998):
                word = word + 1 - UInt32(2_000_000_000)
                carry = 2
            else:  # 2_999_999_999 <= word <= 3_999_999_996
                word = word + 1 - UInt32(3_000_000_000)
                carry = 3
        elif carry == 2:
            if word <= UInt32(999_999_997):
                word += 2
                carry = 0
            elif word <= UInt32(1_999_999_997):
                word = word + 2 - UInt32(1_000_000_000)
                carry = 1
            elif word <= UInt32(2_999_999_997):
                word = word + 2 - UInt32(2_000_000_000)
                carry = 2
            else:  # 2_999_999_998 <= word <= 3_999_999_996
                word = word + 2 - UInt32(3_000_000_000)
                carry = 3
        else:  # carry == 3
            if word <= UInt32(999_999_996):
                word += 3
                carry = 0
            elif word <= UInt32(1_999_999_996):
                word = word + 3 - UInt32(1_000_000_000)
                carry = 1
            elif word <= UInt32(2_999_999_996):
                word = word + 3 - UInt32(2_000_000_000)
                carry = 2
            else:  # 2_999_999_997 <= word <= 3_999_999_996
                word = word + 3 - UInt32(3_000_000_000)
                carry = 3
    if carry > 0:
        # If there is still a carry, we need to add a new word
        x.words.append(UInt32(carry))
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
    if n < 9:
        var value: UInt32 = 1
        for _ in range(n):
            value *= 10
        return BigUInt.from_uint32_unsafe(value)

    # For larger powers, split into groups of 9 digits
    var words = n // 9
    var remainder = n % 9

    var result = BigUInt.zero()

    # Add leading zeros for full power-of-billion words
    for _ in range(words):
        result.words.append(0)

    # Calculate partial power for the highest word
    var high_word: UInt32 = 1
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
def calculate_ndigits_for_normalization(msw: UInt32) -> Int:
    """Calculates the number of digits to shift left for normalization.

    Args:
        msw: The most significant word of the number to normalize.

    Returns:
        The number of digits to shift left to normalize the number.

    Notes:

    This is a helper function for division algorithms.
    The normalized word should be as close to BASE as possible.
    """
    var ndigits: Int
    if msw < 10_000:
        if msw < 100:
            if msw < 10:
                ndigits = 8  # Shift by 8 digits
            else:  # 10 <= msw < 100
                ndigits = 7  # Shift by 7 digits
        else:  # 100 <= msw < 10_000
            if msw < 1_000:  # 100 <= msw < 1_000
                ndigits = 6  # Shift by 6 digits
            else:  # 1_000 <= msw < 10_000:
                ndigits = 5  # Shift by 5 digits
    elif msw < 100_000_000:  # 10_000 <= msw < 100_000_000
        if msw < 1_000_000:
            if msw < 100_000:  # 10_000 <= msw < 100_000
                ndigits = 4  # Shift by 4 digits
            else:  # 100_000 <= msw < 1_000_000
                ndigits = 3  # Shift by 3 digits
        else:  # 1_000_000 <= msw < 100_000_000
            if msw < 10_000_000:  # 1_000_000 <= msw < 10_000_000
                ndigits = 2  # Shift by 2 digits
            else:  # 10_000_000 <= msw < 100_000_000
                ndigits = 1  # Shift by 1 digit
    else:  # 100_000_000 <= msw < 1_000_000_000
        ndigits = 0  # No shift needed

    return ndigits


def to_uint64_with_2_words(a: BigUInt, bounds_x: Tuple[Int, Int]) -> UInt64:
    """Convert two words at given index of the BigUInt to UInt64.

    Args:
        a: The `BigUInt` containing the words to convert.
        bounds_x: A tuple of (start, end) indices specifying the word slice.

    Returns:
        The `UInt64` representation of the specified words.
    """
    var n_words = bounds_x[1] - bounds_x[0]
    if n_words == 1:
        return (
            a.words.unsafe_ptr()
            .unsafe_load[width=1](bounds_x[0])
            .cast[DType.uint64]()
        )
    else:
        return (
            a.words.unsafe_ptr()
            .unsafe_load[width=2](bounds_x[0])
            .cast[DType.uint64]()
            * SIMD[DType.uint64, 2](1, 1_000_000_000)
        ).reduce_add()


def to_uint128_with_2_words(a: BigUInt, bounds_x: Tuple[Int, Int]) -> UInt128:
    """Convert two words at given index of the BigUInt to UInt128.

    Args:
        a: The `BigUInt` containing the words to convert.
        bounds_x: A tuple of (start, end) indices specifying the word slice.

    Returns:
        The `UInt128` representation of the specified words.
    """
    var n_words = bounds_x[1] - bounds_x[0]
    if n_words == 1:
        return (
            a.words.unsafe_ptr()
            .unsafe_load[width=1](bounds_x[0])
            .cast[DType.uint128]()
        )
    else:
        return (
            a.words.unsafe_ptr()
            .unsafe_load[width=2](bounds_x[0])
            .cast[DType.uint128]()
            * SIMD[DType.uint128, 2](1, 1_000_000_000)
        ).reduce_add()


def to_uint128_with_4_words(a: BigUInt, bounds_x: Tuple[Int, Int]) -> UInt128:
    """Convert four words at given index of the BigUInt to UInt128.

    Args:
        a: The `BigUInt` containing the words to convert.
        bounds_x: A tuple of (start, end) indices specifying the word slice.

    Returns:
        The `UInt128` representation of the specified words.
    """
    var n_words = bounds_x[1] - bounds_x[0]
    if n_words == 1:
        return (
            a.words.unsafe_ptr()
            .unsafe_load[width=1](bounds_x[0])
            .cast[DType.uint128]()
        )
    elif n_words == 2:
        return (
            a.words.unsafe_ptr()
            .unsafe_load[width=2](bounds_x[0])
            .cast[DType.uint128]()
            * SIMD[DType.uint128, 2](1, 1_000_000_000)
        ).reduce_add()
    elif n_words == 3:
        return (
            a.words.unsafe_ptr()
            .unsafe_load[width=4](bounds_x[0])
            .cast[DType.uint128]()
            * SIMD[DType.uint128, 4](
                1, 1_000_000_000, 1_000_000_000_000_000_000, 0
            )
        ).reduce_add()
    else:  # len(self.words) == 4
        return (
            a.words.unsafe_ptr()
            .unsafe_load[width=4](bounds_x[0])
            .cast[DType.uint128]()
            * SIMD[DType.uint128, 4](
                1,
                1_000_000_000,
                1_000_000_000_000_000_000,
                1_000_000_000_000_000_000_000_000_000,
            )
        ).reduce_add()
