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
Implements functions for comparison operations on BigDecimal objects.
"""

from decimo.bigdecimal.bigdecimal import BigDecimal


def compare_absolute(x1: BigDecimal, x2: BigDecimal) -> Int8:
    """Compares the absolute values of two numbers.

    Args:
        x1: First number.
        x2: Second number.

    Returns:
        Ternary value indicating the comparison result:
        (1)  1 if |x1| > |x2|.
        (2)  0 if |x1| = |x2|.
        (3) -1 if |x1| < |x2|.
    """
    # Handle zero cases
    if x1.coefficient.is_zero() and x2.coefficient.is_zero():
        return 0
    if x1.coefficient.is_zero():
        return -1
    if x2.coefficient.is_zero():
        return 1

    # If scales are equal, compare coefficients directly
    if x1.scale == x2.scale:
        return x1.coefficient.compare(x2.coefficient)

    # Compare number of digits before the decimal point (integer part)
    var x1_int_digits = x1.coefficient.number_of_digits() - x1.scale
    var x2_int_digits = x2.coefficient.number_of_digits() - x2.scale

    # If integer parts have different lengths, larger integer part wins
    if x1_int_digits > x2_int_digits:
        return 1
    if x1_int_digits < x2_int_digits:
        return -1

    # Integer parts have same length, need to compare digit by digit
    # Scale up the number with smaller scale to match the other's scale
    var scale_diff = x1.scale - x2.scale

    if scale_diff > 0:
        # x1 has larger scale (more decimal places)
        var scaled_x2 = x2.coefficient.multiply_by_power_of_ten(scale_diff)
        return x1.coefficient.compare(scaled_x2^)
    else:
        # x2 has larger scale (more decimal places)
        var scaled_x1 = x1.coefficient.multiply_by_power_of_ten(-scale_diff)
        return scaled_x1.compare(x2.coefficient)


def compare(x1: BigDecimal, x2: BigDecimal) -> Int8:
    """Compares two BigDecimal numbers.

    Args:
        x1: First number.
        x2: Second number.

    Returns:
        Ternary value indicating the comparison result:
        (1)  1 if x1 > x2.
        (2)  0 if x1 = x2.
        (3) -1 if x1 < x2.
    """
    # Handle zero cases first
    if x1.coefficient.is_zero() and x2.coefficient.is_zero():
        return 0

    if x1.coefficient.is_zero():
        return Int8(1) if x2.sign else Int8(-1)  # 0 > negative, 0 < positive
    if x2.coefficient.is_zero():
        return Int8(-1) if x1.sign else Int8(1)  # negative < 0, positive > 0

    # If signs differ, the positive one is greater
    if not x1.sign and x2.sign:  # x1 is positive, x2 is negative
        return Int8(1)
    if x1.sign and not x2.sign:  # x1 is negative, x2 is positive
        return Int8(-1)

    # Same sign - compare absolute values
    var abs_comparison = compare_absolute(x1, x2)

    # For negative numbers, reverse the comparison result
    if x1.sign:  # Both are negative
        return -abs_comparison  # Negate the result for negative numbers
    else:  # Both are positive
        return abs_comparison


def equal(x1: BigDecimal, x2: BigDecimal) -> Bool:
    """Returns whether x1 equals x2.

    Args:
        x1: The first operand.
        x2: The second operand.

    Returns:
        True if x1 equals x2, False otherwise.
    """
    return compare(x1, x2) == 0


def not_equal(x1: BigDecimal, x2: BigDecimal) -> Bool:
    """Returns whether x1 does not equal x2.

    Args:
        x1: The first operand.
        x2: The second operand.

    Returns:
        True if x1 does not equal x2, False otherwise.
    """
    return compare(x1, x2) != 0


def less(x1: BigDecimal, x2: BigDecimal) -> Bool:
    """Returns whether x1 is less than x2.

    Args:
        x1: The first operand.
        x2: The second operand.

    Returns:
        True if x1 is less than x2, False otherwise.
    """
    return compare(x1, x2) < 0


def less_equal(x1: BigDecimal, x2: BigDecimal) -> Bool:
    """Returns whether x1 is less than or equal to x2.

    Args:
        x1: The first operand.
        x2: The second operand.

    Returns:
        True if x1 is less than or equal to x2, False otherwise.
    """
    return compare(x1, x2) <= 0


def greater(x1: BigDecimal, x2: BigDecimal) -> Bool:
    """Returns whether x1 is greater than x2.

    Args:
        x1: The first operand.
        x2: The second operand.

    Returns:
        True if x1 is greater than x2, False otherwise.
    """
    return compare(x1, x2) > 0


def greater_equal(x1: BigDecimal, x2: BigDecimal) -> Bool:
    """Returns whether x1 is greater than or equal to x2.

    Args:
        x1: The first operand.
        x2: The second operand.

    Returns:
        True if x1 is greater than or equal to x2, False otherwise.
    """
    return compare(x1, x2) >= 0


def max(x1: BigDecimal, x2: BigDecimal) -> BigDecimal:
    """Returns the maximum of x1 and x2.

    Args:
        x1: The first operand.
        x2: The second operand.

    Returns:
        The larger of the two values. When the two are numerically equal but
        written differently, the one that comes later in `compare_total()`
        is returned, which is the specification's rule: `max(12.0, 12)` is
        `12` and `max(-12.0, -12)` is `-12.0`.
    """
    var order = compare(x1, x2)
    if order > 0:
        return x1.copy()
    if order < 0:
        return x2.copy()
    if compare_total(x1, x2) >= 0:
        return x1.copy()
    return x2.copy()


def min(x1: BigDecimal, x2: BigDecimal) -> BigDecimal:
    """Returns the minimum of x1 and x2.

    Args:
        x1: The first operand.
        x2: The second operand.

    Returns:
        The smaller of the two values. When the two are numerically equal but
        written differently, the one that comes first in `compare_total()` is
        returned: `min(12.0, 12)` is `12.0` and `min(-12.0, -12)` is `-12`.
    """
    var order = compare(x1, x2)
    if order < 0:
        return x1.copy()
    if order > 0:
        return x2.copy()
    if compare_total(x1, x2) <= 0:
        return x1.copy()
    return x2.copy()


def compare_total(x1: BigDecimal, x2: BigDecimal) -> Int8:
    """Compares two values in the specification's total order.

    Args:
        x1: The first operand.
        x2: The second operand.

    Returns:
        `-1`, `0` or `1`. Unlike `compare()` this separates values that are
        numerically equal but written differently: `1.0` comes before `1`,
        because the longer form has the smaller exponent, and the order flips
        for negative values. Only two values written identically compare
        equal, which is what makes it a total order.
    """
    if x1.sign != x2.sign:
        return -1 if x1.sign else 1
    var order = compare(x1, x2)
    if order != 0:
        return order
    if x1.scale == x2.scale:
        return 0
    # A larger scale is a smaller exponent, which comes first among positive
    # values and last among negative ones.
    var left_first = x1.scale > x2.scale
    if x1.sign:
        return 1 if left_first else -1
    return -1 if left_first else 1


def compare_total_absolute(x1: BigDecimal, x2: BigDecimal) -> Int8:
    """Compares the magnitudes of two values in the total order.

    Args:
        x1: The first operand.
        x2: The second operand.

    Returns:
        `compare_total()` of the two absolute values.
    """
    return compare_total(abs(x1), abs(x2))
