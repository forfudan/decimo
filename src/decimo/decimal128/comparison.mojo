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
# max(a: Decimal128, b: Decimal128) -> Decimal128: Returns the larger of two Decimals
# min(a: Decimal128, b: Decimal128) -> Decimal128: Returns the smaller of two Decimals
# clamp(x: Decimal128, lower: Decimal128, upper: Decimal128) -> Decimal128: Clamps x into [lower, upper]
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
from decimo.errors import ValueError


def compare(x: Decimal128, y: Decimal128) -> Int8:
    """Compares the values of two Decimal128 numbers and returns the result.

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
    """Compares the absolute values of two Decimal128 numbers and returns the result.

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

    # CASE: same scale -> direct UInt128 compare.
    if x_scale == y_scale:
        if x_coef == y_coef:
            return 0
        return Int8(1) if x_coef > y_coef else Int8(-1)

    # CASE: different scales -> scale up the smaller-scale side and
    # compare. One multiply + one compare beats the previous
    # number_of_digits / integer-and-fraction split (which spent 2
    # `number_of_digits`, 4 `power_of_10_unsafe`, 2 wide divisions and
    # 2 wide modulos before any compare).
    #
    # Fast path (scale_diff <= 9): 10^9 < 2^30; coefficient < 2^96, so
    # the product fits in UInt128.
    # Wider path: 10^28 < 2^94, max coefficient < 2^96, so the product
    # is at most ~2^190 and we widen to UInt256.
    if x_scale > y_scale:
        var scale_diff = x_scale - y_scale
        if scale_diff <= 9:
            var y_scaled = (
                y_coef
                * decimo.decimal128.utility.power_of_10_unsafe[DType.uint128](
                    scale_diff
                )
            )
            if x_coef == y_scaled:
                return 0
            return Int8(1) if x_coef > y_scaled else Int8(-1)
        var y_scaled_w = UInt256(
            y_coef
        ) * decimo.decimal128.utility.power_of_10_unsafe[DType.uint256](
            scale_diff
        )
        var x_wide = UInt256(x_coef)
        if x_wide == y_scaled_w:
            return 0
        return Int8(1) if x_wide > y_scaled_w else Int8(-1)

    # x_scale < y_scale: scale up x.
    var scale_diff = y_scale - x_scale
    if scale_diff <= 9:
        var x_scaled = x_coef * decimo.decimal128.utility.power_of_10_unsafe[
            DType.uint128
        ](scale_diff)
        if x_scaled == y_coef:
            return 0
        return Int8(1) if x_scaled > y_coef else Int8(-1)
    var x_scaled_w = UInt256(
        x_coef
    ) * decimo.decimal128.utility.power_of_10_unsafe[DType.uint256](scale_diff)
    var y_wide = UInt256(y_coef)
    if x_scaled_w == y_wide:
        return 0
    return Int8(1) if x_scaled_w > y_wide else Int8(-1)


def greater(a: Decimal128, b: Decimal128) -> Bool:
    """Returns True if a > b.

    Args:
        a: First Decimal128 value.
        b: Second Decimal128 value.

    Returns:
        True if a is greater than b, False otherwise.
    """

    return compare(a, b) == 1


def less(a: Decimal128, b: Decimal128) -> Bool:
    """Returns True if a < b.

    Args:
        a: First Decimal128 value.
        b: Second Decimal128 value.

    Returns:
        True if a is less than b, False otherwise.
    """

    return compare(a, b) == -1


def greater_equal(a: Decimal128, b: Decimal128) -> Bool:
    """Returns True if a >= b.

    Args:
        a: First Decimal128 value.
        b: Second Decimal128 value.

    Returns:
        True if a is greater than or equal to b, False otherwise.
    """

    return compare(a, b) >= 0


def less_equal(a: Decimal128, b: Decimal128) -> Bool:
    """Returns True if a <= b.

    Args:
        a: First Decimal128 value.
        b: Second Decimal128 value.

    Returns:
        True if a is less than or equal to b, False otherwise.
    """

    return not greater(a, b)


def equal(a: Decimal128, b: Decimal128) -> Bool:
    """Returns True if a == b.

    Args:
        a: First Decimal128 value.
        b: Second Decimal128 value.

    Returns:
        True if a equals b, False otherwise.
    """

    return compare(a, b) == 0


def not_equal(a: Decimal128, b: Decimal128) -> Bool:
    """Returns True if a != b.

    Args:
        a: First Decimal128 value.
        b: Second Decimal128 value.

    Returns:
        True if a is not equal to b, False otherwise.
    """

    return compare(a, b) != 0


def max(a: Decimal128, b: Decimal128) -> Decimal128:
    """Returns the larger of two Decimal128 values.

    When the two values compare equal, `a` is returned. Sign and
    scale follow the operand that is returned (e.g. `max(0, 0.00) == 0`).

    Args:
        a: First Decimal128 value.
        b: Second Decimal128 value.

    Returns:
        `a` if `a >= b`, otherwise `b`.
    """

    return a if compare(a, b) >= 0 else b


def min(a: Decimal128, b: Decimal128) -> Decimal128:
    """Returns the smaller of two Decimal128 values.

    When the two values compare equal, `a` is returned. Sign and
    scale follow the operand that is returned.

    Args:
        a: First Decimal128 value.
        b: Second Decimal128 value.

    Returns:
        `a` if `a <= b`, otherwise `b`.
    """

    return a if compare(a, b) <= 0 else b


def clamp(
    x: Decimal128, lower: Decimal128, upper: Decimal128
) raises -> Decimal128:
    """Clamps `x` into the closed interval `[lower, upper]`.

    Args:
        x:     The value to clamp.
        lower: The inclusive lower bound.
        upper: The inclusive upper bound.

    Returns:
        `lower` if `x < lower`, `upper` if `x > upper`, otherwise `x`.

    Raises:
        ValueError: If `lower > upper`.
    """

    if compare(lower, upper) > 0:
        raise ValueError(
            message="`lower` must be less than or equal to `upper`.",
            function="clamp()",
        )
    if compare(x, lower) < 0:
        return lower
    if compare(x, upper) > 0:
        return upper
    return x


def compare_total(a: Decimal128, b: Decimal128) -> Int8:
    """Returns the IBM GDA total ordering (`§5.5.13 compare-total`) of `a`
    vs `b`. Unlike `compare()` (which treats `1.0 == 1.00` and collapses
    every zero into a single equivalence class), `compare_total` produces a
    *strict* total order on the representation, so numerically equal values
    that differ in scale or signed-zero status receive a deterministic
    order.

    Ordering rules:

    1. Negatives precede positives, including signed zero (`-0 < +0`).
    2. Among same-sign non-zero values: usual numeric order.
    3. Among numerically equal values (incl. same-signed zeros), the
       *lower* scale comes first for positives; reversed for negatives, so
       the global sequence stays monotonic across the zero boundary:
       `... -0.00 < -0.0 < -0 < +0 < +0.0 < +0.00 < ... < 1.0 < 1.00 ...`.

    Args:
        a: First Decimal128 value.
        b: Second Decimal128 value.

    Returns:
        `-1` if `a` precedes `b`, `0` if identical representations,
        `+1` otherwise.
    """

    # Dual-zero case must be handled BEFORE delegating to `compare()` —
    # `compare()` returns 0 for any two zeros regardless of sign or scale,
    # which would collapse the four representations `{-0, +0} × {scale...}`
    # into a single equivalence class, contradicting the total-order
    # contract. Order by sign first (negative zero precedes positive zero),
    # then fall through to the same scale tie-break as the non-zero arm.
    var a_zero = a.is_zero()
    var b_zero = b.is_zero()
    if a_zero and b_zero:
        var a_neg = a.is_negative()
        var b_neg = b.is_negative()
        if a_neg != b_neg:
            return Int8(-1) if a_neg else Int8(1)
        # Same-signed zeros: scale tie-break (rule 3).
        var s_a_z = a.scale()
        var s_b_z = b.scale()
        if s_a_z == s_b_z:
            return Int8(0)
        if a_neg:
            return Int8(-1) if s_a_z > s_b_z else Int8(1)
        return Int8(-1) if s_a_z < s_b_z else Int8(1)

    var c = compare(a, b)
    if c != 0:
        return c

    # Numerically equal non-zero values (same sign, same magnitude, possibly
    # different scale). For positives, lower scale wins. For negatives,
    # higher scale wins so the sequence stays monotonic across the sign
    # boundary (... -1.00 < -1.0 < -1 < ... < 1 < 1.0 < 1.00 ...).
    var s_a = a.scale()
    var s_b = b.scale()
    if s_a == s_b:
        return Int8(0)
    if a.is_negative():
        return Int8(-1) if s_a > s_b else Int8(1)
    return Int8(-1) if s_a < s_b else Int8(1)
