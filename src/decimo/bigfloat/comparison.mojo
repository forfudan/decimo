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


"""Comparison of binary floats.

Three things make this more than comparing two numbers. A NaN is unordered:
it is not less than, equal to or greater than anything, including itself, so
every predicate that asks about order answers no and `not_equal()` is the one
that answers yes. The two zeros are different values that compare equal. And
two floats of different precisions can hold the same number, so the
comparison is of values and never of fields.

The order of two finite values is settled by their leading bits first --
`exponent + precision - 1` is where the top bit sits -- and only when those
agree does anything look at the significands. The leading bit is not computed
as that sum, because an exponent near the ends of `Int` overflows it; the
comparison is arranged so that every subtraction it makes is one that fits.

For sorting, where an unordered answer is of no use, `compare_total()` gives
a total order over every value, NaNs and both zeros included.
"""

from decimo.bigfloat.bigfloat import BigFloat
from decimo.errors import ValueError


def _compare_leading_bit(
    exponent1: Int, precision1: Int, exponent2: Int, precision2: Int
) -> Int8:
    """Compares where the top bits of two finite non-zero values sit.

    Args:
        exponent1: The first value's exponent.
        precision1: The first value's precision, at least one.
        exponent2: The second value's exponent.
        precision2: The second value's precision, at least one.

    Returns:
        `1`, `0` or `-1` as the first leading bit is above, level with, or
        below the second.

    Notes:

    The positions are `exponent + precision - 1` each, and comparing them is
    comparing `exponent1 - exponent2` against `precision2 - precision1`. The
    right side always fits, because both precisions are positive. The left
    side can overflow, and when it would, it has already decided the answer:
    a gap wider than `Int.MAX` is wider than any difference of two precisions
    can be.
    """
    var room1 = precision1 - 1
    var room2 = precision2 - 1
    if exponent1 == exponent2:
        return Int8(1) if room1 > room2 else (
            Int8(-1) if room1 < room2 else Int8(0)
        )

    if exponent1 > exponent2:
        if exponent2 < 0 and exponent1 > Int.MAX + exponent2:
            return Int8(1)
        var gap = exponent1 - exponent2
        var deficit = room2 - room1
        return Int8(1) if gap > deficit else (
            Int8(-1) if gap < deficit else Int8(0)
        )

    if exponent1 < 0 and exponent2 > Int.MAX + exponent1:
        return Int8(-1)
    var gap = exponent2 - exponent1
    var deficit = room1 - room2
    return Int8(-1) if gap > deficit else (
        Int8(1) if gap < deficit else Int8(0)
    )


def _raise_on_nan(x1: BigFloat, x2: BigFloat, function: String) raises:
    """Refuses a NaN, which has no place in an order.

    Args:
        x1: The first operand.
        x2: The second operand.
        function: The caller, for the message.

    Raises:
        ValueError: If either value is a NaN.
    """
    if x1.is_nan() or x2.is_nan():
        raise ValueError(
            message=(
                "A NaN is unordered, so it has no comparison. Ask"
                " is_unordered() whether that is the case, or compare_total()"
                " for an order that covers it."
            ),
            function=function,
        )


def _compare_absolute_ordered(x1: BigFloat, x2: BigFloat) -> Int8:
    """Compares the magnitudes of two values that are not NaNs.

    Args:
        x1: The first operand, not a NaN.
        x2: The second operand, not a NaN.

    Returns:
        `1`, `0` or `-1` as the first magnitude is larger than, equal to or
        smaller than the second. Both zeros have the same magnitude, and so
        do both infinities.
    """
    if x1.is_infinite() or x2.is_infinite():
        if x1.is_infinite() and x2.is_infinite():
            return Int8(0)
        return Int8(1) if x1.is_infinite() else Int8(-1)

    if x1.is_zero() or x2.is_zero():
        if x1.is_zero() and x2.is_zero():
            return Int8(0)
        return Int8(-1) if x1.is_zero() else Int8(1)

    var leading = _compare_leading_bit(
        x1.exponent, x1.precision, x2.exponent, x2.precision
    )
    if leading != 0:
        return leading

    # The top bits are level, so widening the narrower significand to the
    # other's precision lines the two up bit for bit and leaves an integer
    # comparison. Equal precisions, which is the usual case, shift nothing.
    var widen = x1.precision - x2.precision
    if widen == 0:
        return Int8(1) if x1.significand > x2.significand else (
            Int8(-1) if x1.significand < x2.significand else Int8(0)
        )
    if widen > 0:
        var widened = x2.significand << widen
        return Int8(1) if x1.significand > widened else (
            Int8(-1) if x1.significand < widened else Int8(0)
        )
    var widened = x1.significand << -widen
    return Int8(1) if widened > x2.significand else (
        Int8(-1) if widened < x2.significand else Int8(0)
    )


def _compare_ordered(x1: BigFloat, x2: BigFloat) -> Int8:
    """Compares two values that are not NaNs.

    Args:
        x1: The first operand, not a NaN.
        x2: The second operand, not a NaN.

    Returns:
        `1`, `0` or `-1` as the first value is greater than, equal to or less
        than the second. The two zeros compare equal.
    """
    # Before the signs, because the zeros' signs are not to be read here.
    if x1.is_zero() and x2.is_zero():
        return Int8(0)

    if x1.sign != x2.sign:
        return Int8(-1) if x1.sign else Int8(1)

    var magnitude = _compare_absolute_ordered(x1, x2)
    return -magnitude if x1.sign else magnitude


def compare(x1: BigFloat, x2: BigFloat) raises -> Int8:
    """Compares two values.

    Args:
        x1: The first operand.
        x2: The second operand.

    Returns:
        `1`, `0` or `-1` as the first value is greater than, equal to or less
        than the second. The two zeros compare equal.

    Raises:
        ValueError: If either value is a NaN, which is unordered.
    """
    _raise_on_nan(x1, x2, "compare()")
    return _compare_ordered(x1, x2)


def compare_absolute(x1: BigFloat, x2: BigFloat) raises -> Int8:
    """Compares the magnitudes of two values.

    Args:
        x1: The first operand.
        x2: The second operand.

    Returns:
        `1`, `0` or `-1` as the first magnitude is larger than, equal to or
        smaller than the second. Both zeros have the same magnitude, and so
        do both infinities.

    Raises:
        ValueError: If either value is a NaN.
    """
    _raise_on_nan(x1, x2, "compare_absolute()")
    return _compare_absolute_ordered(x1, x2)


def is_unordered(x1: BigFloat, x2: BigFloat) -> Bool:
    """Returns whether the two have no order, which is to say either is a NaN.

    Args:
        x1: The first operand.
        x2: The second operand.

    Returns:
        True if either value is a NaN.
    """
    return x1.is_nan() or x2.is_nan()


def equal(x1: BigFloat, x2: BigFloat) -> Bool:
    """Returns whether x1 equals x2.

    Args:
        x1: The first operand.
        x2: The second operand.

    Returns:
        True if the two are the same number. A NaN equals nothing, itself
        included; the two zeros equal each other.

    """
    if is_unordered(x1, x2):
        return False
    return _compare_ordered(x1, x2) == 0


def not_equal(x1: BigFloat, x2: BigFloat) -> Bool:
    """Returns whether x1 does not equal x2.

    Args:
        x1: The first operand.
        x2: The second operand.

    Returns:
        True unless the two are the same number. This is the one predicate a
        NaN answers yes to, and it is why it is not `not equal()` written out.

    """
    if is_unordered(x1, x2):
        return True
    return _compare_ordered(x1, x2) != 0


def less(x1: BigFloat, x2: BigFloat) -> Bool:
    """Returns whether x1 is less than x2.

    Args:
        x1: The first operand.
        x2: The second operand.

    Returns:
        True if x1 is below x2, and False if either is a NaN.

    """
    if is_unordered(x1, x2):
        return False
    return _compare_ordered(x1, x2) < 0


def less_equal(x1: BigFloat, x2: BigFloat) -> Bool:
    """Returns whether x1 is less than or equal to x2.

    Args:
        x1: The first operand.
        x2: The second operand.

    Returns:
        True if x1 is below or level with x2, and False if either is a NaN.

    """
    if is_unordered(x1, x2):
        return False
    return _compare_ordered(x1, x2) <= 0


def greater(x1: BigFloat, x2: BigFloat) -> Bool:
    """Returns whether x1 is greater than x2.

    Args:
        x1: The first operand.
        x2: The second operand.

    Returns:
        True if x1 is above x2, and False if either is a NaN.

    """
    if is_unordered(x1, x2):
        return False
    return _compare_ordered(x1, x2) > 0


def greater_equal(x1: BigFloat, x2: BigFloat) -> Bool:
    """Returns whether x1 is greater than or equal to x2.

    Args:
        x1: The first operand.
        x2: The second operand.

    Returns:
        True if x1 is above or level with x2, and False if either is a NaN.

    """
    if is_unordered(x1, x2):
        return False
    return _compare_ordered(x1, x2) >= 0


def max(x1: BigFloat, x2: BigFloat) -> BigFloat:
    """Returns the larger of two values.

    Args:
        x1: The first operand.
        x2: The second operand.

    Returns:
        The larger value. A NaN is passed over rather than returned, so one
        NaN gives the other operand and two give a NaN. Between the two zeros
        the positive one comes back.

    """
    if x1.is_nan():
        return x2.copy() if not x2.is_nan() else x1.copy()
    if x2.is_nan():
        return x1.copy()
    if x1.is_zero() and x2.is_zero():
        return x2.copy() if x1.sign else x1.copy()
    return x1.copy() if _compare_ordered(x1, x2) >= 0 else x2.copy()


def min(x1: BigFloat, x2: BigFloat) -> BigFloat:
    """Returns the smaller of two values.

    Args:
        x1: The first operand.
        x2: The second operand.

    Returns:
        The smaller value. A NaN is passed over rather than returned, so one
        NaN gives the other operand and two give a NaN. Between the two zeros
        the negative one comes back.

    """
    if x1.is_nan():
        return x2.copy() if not x2.is_nan() else x1.copy()
    if x2.is_nan():
        return x1.copy()
    if x1.is_zero() and x2.is_zero():
        return x1.copy() if x1.sign else x2.copy()
    return x1.copy() if _compare_ordered(x1, x2) <= 0 else x2.copy()


def compare_total(x1: BigFloat, x2: BigFloat) -> Int8:
    """Compares two values in a total order, NaNs included.

    Args:
        x1: The first operand.
        x2: The second operand.

    Returns:
        `-1`, `0` or `1`, with every pair of values ordered: the order runs
        from `-Infinity` up to `+Infinity` with the NaN after it, `-0` comes
        before `+0`, and two values that are numerically equal are separated
        by their precisions. This is what to sort by, since `compare()` has
        nothing to say about a NaN.

    Notes:

    Among equal numbers the one with more precision comes first, the way
    `BigDecimal`'s total order puts the larger scale first. The tie is broken
    on the precision rather than on the exponent, and for a non-zero value
    those are the same rule read two ways -- the same number in more bits is
    the same leading bit over a smaller exponent -- but a zero carries no
    exponent to tell them apart and the precision still does. Negative values
    take the reverse, so that negating a sorted sequence reverses it.
    """
    # The NaN first, and without reading its sign: there is one NaN in this
    # type, not a pair of them, so it has no side to be on and goes last.
    if x1.is_nan() or x2.is_nan():
        if x1.is_nan() and x2.is_nan():
            return Int8(0)
        return Int8(1) if x1.is_nan() else Int8(-1)

    if x1.sign != x2.sign:
        return Int8(-1) if x1.sign else Int8(1)

    var order = _compare_ordered(x1, x2)
    if order != 0:
        return order
    if x1.precision == x2.precision:
        return Int8(0)
    var left_first = x1.precision > x2.precision
    if x1.sign:
        return Int8(1) if left_first else Int8(-1)
    return Int8(-1) if left_first else Int8(1)


def compare_total_absolute(x1: BigFloat, x2: BigFloat) -> Int8:
    """Compares the magnitudes of two values in the total order.

    Args:
        x1: The first operand.
        x2: The second operand.

    Returns:
        `compare_total()` of the two absolute values.

    """
    return compare_total(abs(x1), abs(x2))
