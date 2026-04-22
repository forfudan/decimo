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
#
# Implements comparison operations for the Decimal128 type
#
# ===----------------------------------------------------------------------=== #
#
# List of functions in this module:
#
# compare(x: Decimal128, y: Decimal128) -> Int8: Compares two Decimals
# compare_absolute(x: Decimal128, y: Decimal128) -> Int8: Compares absolute values of two Decimals
# greater(a: Decimal128, b: Decimal128) -> Bool: Returns True if a > b
# less(a: Decimal128, b: Decimal128) -> Bool: Returns True if a < b
# greater_equal(a: Decimal128, b: Decimal128) -> Bool: Returns True if a >= b
# less_equal(a: Decimal128, b: Decimal128) -> Bool: Returns True if a <= b
# equal(a: Decimal128, b: Decimal128) -> Bool: Returns True if a == b
# not_equal(a: Decimal128, b: Decimal128) -> Bool: Returns True if a != b
#
# List of internal functions in this module:
#
# _compare_abs(a: Decimal128, b: Decimal128) -> Int: Compares absolute values of two Decimals
#
# ===----------------------------------------------------------------------=== #

"""
Implements functions for comparison operations on Decimal128 objects.
"""

from std import testing

from decimo.decimal128.decimal128 import Decimal128
import decimo.decimal128.utility


def compare(x: Decimal128, y: Decimal128) -> Int8:
    """
    Compares the values of two Decimal128 numbers and returns the result.

    Args:
        x: First Decimal128 value.
        y: Second Decimal128 value.

    Returns:
        Terinary value indicating the comparison result:
        (1)  1 if x > y.
        (2)  0 if x = y.
        (3) -1 if x < y.
    """

    # If both are zero, they are equal regardless of scale or sign
    if x.is_zero() and y.is_zero():
        return 0

    # If x is zero, it is less than any non-zero number
    elif x.is_zero():
        return Int8(1) if y.is_negative() else Int8(-1)

    # If y is zero, it is less than any non-zero number
    elif y.is_zero():
        return Int8(-1) if x.is_negative() else Int8(1)

    # If signs differ, the positive one is greater
    elif x.is_negative() != y.is_negative():
        return Int8(-1) if x.is_negative() else Int8(1)

    # If they have the same sign, compare the absolute values
    elif x.is_negative():
        return -compare_absolute(x, y)

    else:
        return compare_absolute(x, y)


def compare_absolute(x: Decimal128, y: Decimal128) -> Int8:
    """
    Compares the absolute values of two Decimal128 numbers and returns the result.

    Args:
        x: First Decimal128 value.
        y: Second Decimal128 value.

    Returns:
        Terinary value indicating the comparison result:
        (1)  1 if |x| > |y|.
        (2)  0 if |x| = |y|.
        (3) -1 if |x| < |y|.
    """

    var x_coef: UInt128 = x.coefficient()
    var y_coef: UInt128 = y.coefficient()
    var x_scale: Int = x.scale()
    var y_scale: Int = y.scale()

    # CASE: The scales are the same
    # Compare the coefficients directly
    if x_scale == y_scale and x_coef == y_coef:
        return 0
    if x_scale == y_scale:
        return Int8((Int(x_coef > y_coef)) - (Int(x_coef < y_coef)))

    # CASE: The scales are different
    # Compare the integral part first
    # If the integral part is the same, compare the fractional part
    else:
        # Early return if integer parts have different lengths
        # Get number of integer digits
        var x_int_digits = (
            decimo.decimal128.utility.number_of_digits(x_coef) - x_scale
        )
        var y_int_digits = (
            decimo.decimal128.utility.number_of_digits(y_coef) - y_scale
        )
        if x_int_digits > y_int_digits:
            return 1
        if x_int_digits < y_int_digits:
            return -1

        # If interger parts have the same length, compare the integer parts
        var x_scale_power = decimo.decimal128.utility.power_of_10_unsafe[
            DType.uint128
        ](Int(x_scale))
        var y_scale_power = decimo.decimal128.utility.power_of_10_unsafe[
            DType.uint128
        ](Int(y_scale))
        var x_int = x_coef // x_scale_power
        var y_int = y_coef // y_scale_power

        if x_int > y_int:
            return 1
        elif x_int < y_int:
            return -1
        else:
            var x_frac = x_coef % x_scale_power
            var y_frac = y_coef % y_scale_power

            # Adjust the fractional part to have the same scale.
            # Bounds: `x_frac < 10^x_scale` and `y_frac < 10^y_scale`, both
            # ≤ 10^28. After scaling the smaller-scale fraction by
            # `10^|scale_diff|` (≤ 10^28), the result is still
            # < 10^max(x_scale, y_scale) ≤ 10^28, well within UInt128
            # (max ≈ 3.4 × 10^38). No widening required.
            var scale_diff = x_scale - y_scale
            if scale_diff > 0:
                y_frac *= decimo.decimal128.utility.power_of_10_unsafe[
                    DType.uint128
                ](Int(scale_diff))
            else:
                x_frac *= decimo.decimal128.utility.power_of_10_unsafe[
                    DType.uint128
                ](Int(-scale_diff))

            if x_frac > y_frac:
                return 1
            elif x_frac < y_frac:
                return -1
            else:
                return 0


def greater(a: Decimal128, b: Decimal128) -> Bool:
    """
    Returns True if a > b.

    Args:
        a: First Decimal128 value.
        b: Second Decimal128 value.

    Returns:
        True if a is greater than b, False otherwise.
    """

    return compare(a, b) == 1


def less(a: Decimal128, b: Decimal128) -> Bool:
    """
    Returns True if a < b.

    Args:
        a: First Decimal128 value.
        b: Second Decimal128 value.

    Returns:
        True if a is less than b, False otherwise.
    """

    return compare(a, b) == -1


def greater_equal(a: Decimal128, b: Decimal128) -> Bool:
    """
    Returns True if a >= b.

    Args:
        a: First Decimal128 value.
        b: Second Decimal128 value.

    Returns:
        True if a is greater than or equal to b, False otherwise.
    """

    return compare(a, b) >= 0


def less_equal(a: Decimal128, b: Decimal128) -> Bool:
    """
    Returns True if a <= b.

    Args:
        a: First Decimal128 value.
        b: Second Decimal128 value.

    Returns:
        True if a is less than or equal to b, False otherwise.
    """

    return not greater(a, b)


def equal(a: Decimal128, b: Decimal128) -> Bool:
    """
    Returns True if a == b.

    Args:
        a: First Decimal128 value.
        b: Second Decimal128 value.

    Returns:
        True if a equals b, False otherwise.
    """

    return compare(a, b) == 0


def not_equal(a: Decimal128, b: Decimal128) -> Bool:
    """
    Returns True if a != b.

    Args:
        a: First Decimal128 value.
        b: Second Decimal128 value.

    Returns:
        True if a is not equal to b, False otherwise.
    """

    return compare(a, b) != 0
