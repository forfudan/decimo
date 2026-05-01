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
Implements functions for mathematical operations on BigDecimal objects.
"""

from std import math

from decimo.bigdecimal.rounding import round_to_precision
from decimo.errors import ZeroDivisionError
from decimo.rounding_mode import RoundingMode

# ===----------------------------------------------------------------------=== #
# Arithmetic operations on BigDecimal objects
# add(x1, x2, precision=0)
# subtract(x1, x2, precision=0)
# multiply(x1, x2, precision=0)
# true_divide(x1, x2, precision)
# true_divide_inexact(x1, x2, number_of_significant_digits)
# ===----------------------------------------------------------------------=== #


def add(
    x1: BigDecimal, x2: BigDecimal, precision: Int = 0
) raises -> BigDecimal:
    """Returns the sum of two numbers.

    Args:
        x1: The first operand.
        x2: The second operand.
        precision: Optional target significant-digit precision for the
            result. When `0` (default) the function returns the exact
            sum. When `>0` the exact sum is computed and then rounded
            to `precision` significant digits via HALF_EVEN.

    Returns:
        The sum of x1 and x2 (exact when `precision == 0`, otherwise
        rounded to `precision` significant digits).

    Notes:

    Rules for addition:
    - When `precision == 0`, the result is exact and its scale is the
      maximum of the two operands' scales.
    - The result's sign is determined by the signs of the operands.
    """
    if precision > 0:
        var result = add(x1, x2, precision=0)
        round_to_precision(
            result,
            precision,
            RoundingMode.ROUND_HALF_EVEN,
            remove_extra_digit_due_to_rounding=False,
            fill_zeros_to_precision=False,
        )
        return result^

    var max_scale = max(x1.scale, x2.scale)
    var scale_factor1 = (max_scale - x1.scale) if x1.scale < max_scale else 0
    var scale_factor2 = (max_scale - x2.scale) if x2.scale < max_scale else 0

    # Handle zero operands as special cases for efficiency
    if x1.coefficient.is_zero():
        if x2.coefficient.is_zero():
            return BigDecimal(
                coefficient=BigUInt.zero(),
                scale=max_scale,
                sign=False,
            )
        else:
            return x2.extend_precision(scale_factor2)
    if x2.coefficient.is_zero():
        return x1.extend_precision(scale_factor1)

    # Scale coefficients to match
    var coef1 = x1.coefficient.multiply_by_power_of_ten(scale_factor1)
    var coef2 = x2.coefficient.multiply_by_power_of_ten(scale_factor2)

    # Handle addition based on signs
    if x1.sign == x2.sign:
        # Same sign: Add coefficients, keep sign
        coef1 += coef2
        return BigDecimal(coefficient=coef1^, scale=max_scale, sign=x1.sign)
    # Different signs: Subtract smaller coefficient from larger
    if coef1 > coef2:
        # |x1| > |x2|, result sign is x1's sign
        coef1 -= coef2
        return BigDecimal(coefficient=coef1^, scale=max_scale, sign=x1.sign)
    elif coef2 > coef1:
        # |x2| > |x1|, result sign is x2's sign
        coef2 -= coef1
        return BigDecimal(coefficient=coef2^, scale=max_scale, sign=x2.sign)
    else:
        # |x1| == |x2|, signs differ, result is 0
        return BigDecimal(
            coefficient=BigUInt.zero(), scale=max_scale, sign=False
        )


def subtract(
    x1: BigDecimal, x2: BigDecimal, precision: Int = 0
) raises -> BigDecimal:
    """Returns the difference of two numbers.

    Args:
        x1: The first operand (minuend).
        x2: The second operand (subtrahend).
        precision: Optional target significant-digit precision for the
            result. When `0` (default) the function returns the exact
            difference. When `>0` the exact difference is computed
            and then rounded to `precision` significant digits via
            HALF_EVEN.

    Returns:
        The difference of x1 and x2 (x1 - x2). Exact when
        `precision == 0`, otherwise rounded to `precision` digits.

    Notes:

    - When `precision == 0`, the result is exact and its scale is the
      maximum of the two operands' scales.
    - The result's sign is determined by the signs of the operands.
    """
    if precision > 0:
        var result = subtract(x1, x2, precision=0)
        round_to_precision(
            result,
            precision,
            RoundingMode.ROUND_HALF_EVEN,
            remove_extra_digit_due_to_rounding=False,
            fill_zeros_to_precision=False,
        )
        return result^

    var max_scale = max(x1.scale, x2.scale)
    var scale_factor1 = (max_scale - x1.scale) if x1.scale < max_scale else 0
    var scale_factor2 = (max_scale - x2.scale) if x2.scale < max_scale else 0

    # Handle zero operands as special cases for efficiency
    if x2.coefficient.is_zero():
        if x1.coefficient.is_zero():
            return BigDecimal(
                coefficient=BigUInt.zero(),
                scale=max_scale,
                sign=False,
            )
        else:
            return x1.extend_precision(scale_factor1)
    if x1.coefficient.is_zero():
        var result = x2.extend_precision(scale_factor2)
        result.sign = not result.sign
        return result^

    # Scale coefficients to match
    var coef1 = x1.coefficient.multiply_by_power_of_ten(scale_factor1)
    var coef2 = x2.coefficient.multiply_by_power_of_ten(scale_factor2)

    # Handle subtraction based on signs
    if x1.sign != x2.sign:
        # Different signs: x1 - (-x2) = x1 + x2, or (-x1) - x2 = -(x1 + x2)
        coef1 += coef2
        return BigDecimal(coefficient=coef1^, scale=max_scale, sign=x1.sign)

    # Same signs: Must perform actual subtraction
    if coef1 > coef2:
        # |x1| > |x2|, result sign is x1's sign
        coef1 -= coef2
        return BigDecimal(coefficient=coef1^, scale=max_scale, sign=x1.sign)
    elif coef2 > coef1:
        # |x1| < |x2|, result sign is opposite of x1's sign
        coef2 -= coef1
        return BigDecimal(coefficient=coef2^, scale=max_scale, sign=not x1.sign)
    else:
        # |x1| == |x2|, result is 0
        return BigDecimal(
            coefficient=BigUInt.zero(), scale=max_scale, sign=False
        )


def multiply(
    x1: BigDecimal, x2: BigDecimal, precision: Int = 0
) raises -> BigDecimal:
    """Returns the product of two numbers.

    Args:
        x1: The first operand (multiplicand).
        x2: The second operand (multiplier).
        precision: Optional target significant-digit precision for the
            result. When `0` (default) the function returns the exact
            product. When `>0` the exact product is computed and then
            rounded to `precision` significant digits via HALF_EVEN.

    Returns:
        The product of x1 and x2. Exact when `precision == 0`,
        otherwise rounded to `precision` digits.

    Notes:

    - When `precision == 0`, the result is exact and its scale is the
      sum of the two operands' scales (except for zero).
    - The result's sign follows the standard sign rules for multiplication.
    """
    if precision > 0:
        var result = multiply(x1, x2, precision=0)
        round_to_precision(
            result,
            precision,
            RoundingMode.ROUND_HALF_EVEN,
            remove_extra_digit_due_to_rounding=False,
            fill_zeros_to_precision=False,
        )
        return result^

    # Handle zero operands as special cases for efficiency
    if x1.coefficient.is_zero() or x2.coefficient.is_zero():
        return BigDecimal(
            coefficient=BigUInt.zero(),
            scale=x1.scale + x2.scale,
            sign=x1.sign != x2.sign,
        )

    return BigDecimal(
        coefficient=x1.coefficient * x2.coefficient,
        scale=x1.scale + x2.scale,
        sign=x1.sign != x2.sign,
    )


def multiply_inplace(mut x1: BigDecimal, x2: BigDecimal):
    """Multiplies x1 by x2 in place, avoiding full BigDecimal construction.

    This computes the product and moves the result words into x1,
    avoiding the overhead of constructing a new BigDecimal object.

    Args:
        x1: The first operand (modified in place to hold the result).
        x2: The second operand (multiplier).
    """
    if x1.coefficient.is_zero() or x2.coefficient.is_zero():
        x1.coefficient = BigUInt.zero()
        x1.scale = x1.scale + x2.scale
        x1.sign = x1.sign != x2.sign
        return

    x1.coefficient = x1.coefficient * x2.coefficient
    x1.scale = x1.scale + x2.scale
    x1.sign = x1.sign != x2.sign


def add_inplace(mut x1: BigDecimal, x2: BigDecimal) raises:
    """Adds x2 to x1 in place.

    This avoids constructing a new BigDecimal for the result.
    Uses BigUInt inplace operations where possible.

    Args:
        x1: The accumulator (modified in place to hold x1 + x2).
        x2: The value to add.
    """
    var max_scale = max(x1.scale, x2.scale)
    var scale_factor1 = (max_scale - x1.scale) if x1.scale < max_scale else 0
    var scale_factor2 = (max_scale - x2.scale) if x2.scale < max_scale else 0

    # Handle zero operands
    if x1.coefficient.is_zero():
        if x2.coefficient.is_zero():
            x1.scale = max_scale
            x1.sign = False
            return
        else:
            x1.coefficient = x2.coefficient.multiply_by_power_of_ten(
                scale_factor2
            )
            x1.scale = max_scale
            x1.sign = x2.sign
            return
    if x2.coefficient.is_zero():
        if scale_factor1 > 0:
            x1.coefficient.multiply_by_power_of_ten_inplace(scale_factor1)
        x1.scale = max_scale
        return

    # Scale x1 in place if needed
    if scale_factor1 > 0:
        x1.coefficient.multiply_by_power_of_ten_inplace(scale_factor1)

    if x1.sign == x2.sign:
        # Same sign: add magnitudes (use inplace add on x1's coefficient)
        if scale_factor2 == 0:
            decimo.biguint.arithmetics.add_inplace(
                x1.coefficient, x2.coefficient
            )
        else:
            var coef2 = x2.coefficient.multiply_by_power_of_ten(scale_factor2)
            decimo.biguint.arithmetics.add_inplace(x1.coefficient, coef2)
        x1.scale = max_scale
    else:
        # Different signs: subtract magnitudes
        var coef2 = (
            x2.coefficient.multiply_by_power_of_ten(
                scale_factor2
            ) if scale_factor2
            > 0 else x2.coefficient.copy()
        )

        if x1.coefficient > coef2:
            decimo.biguint.arithmetics.subtract_inplace(x1.coefficient, coef2)
            x1.scale = max_scale
        elif coef2 > x1.coefficient:
            decimo.biguint.arithmetics.subtract_inplace(coef2, x1.coefficient)
            x1.coefficient = coef2^
            x1.scale = max_scale
            x1.sign = x2.sign
        else:
            x1.coefficient = BigUInt.zero()
            x1.scale = max_scale
            x1.sign = False


def subtract_inplace(mut x1: BigDecimal, x2: BigDecimal) raises:
    """Subtracts x2 from x1 in place.

    This avoids constructing a new BigDecimal for the result.

    Args:
        x1: The accumulator (modified in place to hold x1 - x2).
        x2: The value to subtract.
    """
    # Create a negated view of x2 and use add_inplace
    var neg_x2 = BigDecimal(
        coefficient=x2.coefficient.copy(),
        scale=x2.scale,
        sign=not x2.sign,
    )
    add_inplace(x1, neg_x2)


def true_divide(
    x: BigDecimal, y: BigDecimal, precision: Int
) raises -> BigDecimal:
    """Returns the quotient of two numbers with specified precision.

    Args:
        x: The first operand (dividend).
        y: The second operand (divisor).
        precision: The number of significant digits in the result.

    Returns:
        The quotient of x and y, with precision up to `precision`
        significant digits.

    Raises:
        ZeroDivisionError: If the divisor is zero.

    Notes:

    - If the coefficients can be divided exactly, the number of digits after
        the decimal point is the difference of the scales of the two operands.
    - If the coefficients cannot be divided exactly, the number of digits after
        the decimal point is precision.
    - If the division is not exact, the number of digits after the decimal
        point is calcuated to precision + BUFFER_DIGITS, and the result is
        rounded to precision according to the specified rules.
    """
    # Check for division by zero
    if y.coefficient.is_zero():
        raise ZeroDivisionError(
            message="Division by zero.",
            function="true_divide()",
        )

    # Handle dividend of zero
    if x.coefficient.is_zero():
        return BigDecimal(
            coefficient=BigUInt.zero(),
            scale=x.scale - y.scale,
            sign=x.sign != y.sign,
        )

    # For other cases, we use `true_divide_general()` to handle the division
    # Note that this functiona already considers extra buffer digits
    return true_divide_general(x, y, precision)


def true_divide_fast(
    x: BigDecimal, y: BigDecimal, minimum_precision: Int
) raises -> BigDecimal:
    """Returns the quotient of two numbers.

    Args:
        x: The first operand (dividend).
        y: The second operand (divisor).
        minimum_precision: The minimum number of significant digits in the
            result. Should be greater than 0.

    Returns:
        The quotient of x and y with at least `minimum_precision`
        significant digits.

    Notes:

    This function conduct a quick division that:
    (1) does not round the result to the specified precision.
    (2) does not check the exact division nor remove extra trailing zeros.
    """

    # Yuhao Zhu:
    # x = a * 10*(-m)
    # y = b * 10*(-n)
    # Let s = extra digits to ensure precision
    # x / y = x * 10^s / y / 10^s = (a * 10^s // b) * 10*(-(m + s - n))
    # We need to ensure that a * 10^s // b has more significant digits than p.
    # A quicker way is to add whole empty words to the dividend.
    # Let n_diff = len(a.words) - len(b.words).
    # We add ceil(precision // 9) + 1 - n_diff empty words to the dividend.
    # This ensures that we always have at least 9 extra digits in the dividend.

    debug_assert[assert_mode="none"](
        minimum_precision > 0,
        "Minimum precision should be greater than 0",
    )

    # --- Truncation optimization for oversized operands ---
    # When the divisor is much larger than needed for the requested precision,
    # truncate both operands to avoid expensive division on huge numbers.
    # x/y ≈ (x/10^k) / (y/10^k) — the low-order digits cancel.
    # Early-return to avoid extra copies on the common (small-operand) path.
    comptime TRUNCATION_GUARD = 4
    var needed_divisor_words = (
        math.ceildiv(minimum_precision, 9) + 2 + TRUNCATION_GUARD
    )

    if len(y.coefficient.words) > needed_divisor_words:
        return _true_divide_fast_truncated(
            x, y, minimum_precision, needed_divisor_words
        )

    # --- Standard path (no truncation, no extra copies) ---
    var diff_n_words = len(x.coefficient.words) - len(y.coefficient.words)
    var extra_words = math.ceildiv(minimum_precision, 9) + 2 - diff_n_words
    var extra_digits = extra_words * 9

    var coef_x: BigUInt
    if extra_words > 0:
        coef_x = decimo.biguint.arithmetics.multiply_by_power_of_billion(
            x.coefficient, extra_words
        )
    elif extra_words < 0:
        coef_x = decimo.biguint.arithmetics.floor_divide_by_power_of_billion(
            x.coefficient, -extra_words
        )
    else:
        coef_x = x.coefficient.copy()

    var coef = coef_x // y.coefficient
    var scale = x.scale + extra_digits - y.scale
    return BigDecimal(
        coefficient=coef^,
        scale=scale,
        sign=x.sign != y.sign,
    )


def _true_divide_fast_truncated(
    x: BigDecimal,
    y: BigDecimal,
    minimum_precision: Int,
    needed_divisor_words: Int,
) raises -> BigDecimal:
    """Internal: fast division with truncated oversized operands."""
    var total_y_remove = len(y.coefficient.words) - needed_divisor_words
    var common_remove = min(
        total_y_remove, max(len(x.coefficient.words) - 1, 0)
    )
    var y_only_remove = total_y_remove - common_remove

    var y_coef_tr = decimo.biguint.arithmetics.floor_divide_by_power_of_billion(
        y.coefficient, total_y_remove
    )
    var x_coef_tr: BigUInt
    if common_remove > 0:
        x_coef_tr = decimo.biguint.arithmetics.floor_divide_by_power_of_billion(
            x.coefficient, common_remove
        )
    else:
        x_coef_tr = x.coefficient.copy()

    var scale_adjust_digits = y_only_remove * 9

    var diff_n_words = len(x_coef_tr.words) - len(y_coef_tr.words)
    var extra_words = math.ceildiv(minimum_precision, 9) + 2 - diff_n_words
    var extra_digits = extra_words * 9 + scale_adjust_digits

    var coef_x: BigUInt
    if extra_words > 0:
        coef_x = decimo.biguint.arithmetics.multiply_by_power_of_billion(
            x_coef_tr, extra_words
        )
    elif extra_words < 0:
        coef_x = decimo.biguint.arithmetics.floor_divide_by_power_of_billion(
            x_coef_tr, -extra_words
        )
    else:
        coef_x = x_coef_tr^

    var coef = coef_x // y_coef_tr
    var scale = x.scale + extra_digits - y.scale
    return BigDecimal(
        coefficient=coef^,
        scale=scale,
        sign=x.sign != y.sign,
    )


def true_divide_general(
    x: BigDecimal, y: BigDecimal, precision: Int
) raises -> BigDecimal:
    """Returns the quotient of two numbers with the specified precision.

    Args:
        x: The first operand (dividend).
        y: The second operand (divisor).
        precision: The minimum number of significant digits in the
            result. Should be greater than 0.

    Returns:
        The quotient of x and y with the specified precision.

    Notes:

    This function conduct a division that:
    (1) rounds the result to the specified precision,
    (2) checks the exact division and remove extra trailing zeros.
    """

    # Yuhao Zhu:
    # x = a * 10*(-m)
    # y = b * 10*(-n)
    # Let s = extra digits to ensure precision
    # x / y = x * 10^s / y / 10^s = (a * 10^s // b) * 10*(-(m + s - n))
    # We need to ensure that a * 10^s // b has more significant digits than p.
    # A quicker way is to add whole empty words to the dividend.
    # Let n_diff = len(a.words) - len(b.words).
    # We compute extra_words = ceil(precision / 9) + 2 - n_diff.
    # When n_diff > 0 (dividend larger): fewer extra words needed (may be negative,
    #   meaning we truncate the dividend to avoid computing excess quotient digits).
    # When n_diff < 0 (dividend smaller): more extra words needed to pad up.

    debug_assert[assert_mode="none"](
        precision > 0,
        "Precision should be greater than 0",
    )

    # --- Truncation optimization for oversized operands ---
    # When the divisor is much larger than needed for the requested precision,
    # truncate both operands to avoid expensive division on huge numbers.
    # Example: 262144w / 262144w at precision=50 only needs ~14-word operands.
    # Correctness: x/y ≈ (x/10^k) / (y/10^k); the low-order digits cancel,
    # with relative error < 10^(-9*remaining_words), well below precision+guard.
    # Early-return to avoid extra copies on the common (small-operand) path.
    comptime TRUNCATION_GUARD = 4
    var needed_divisor_words = math.ceildiv(precision, 9) + 2 + TRUNCATION_GUARD

    if len(y.coefficient.words) > needed_divisor_words:
        return _true_divide_general_truncated(
            x, y, precision, needed_divisor_words
        )

    # --- Standard path (no truncation, no extra copies) ---
    var diff_n_words = len(x.coefficient.words) - len(y.coefficient.words)
    var extra_words = math.ceildiv(precision, 9) + 2 - diff_n_words
    var extra_digits = extra_words * 9

    var coef_x: BigUInt
    if extra_words > 0:
        coef_x = decimo.biguint.arithmetics.multiply_by_power_of_billion(
            x.coefficient, extra_words
        )
    elif extra_words < 0:
        # Dividend already has more than enough words for the desired precision.
        # Truncate low-order words to avoid computing unnecessary quotient digits.
        coef_x = decimo.biguint.arithmetics.floor_divide_by_power_of_billion(
            x.coefficient, -extra_words
        )
    else:
        coef_x = x.coefficient.copy()

    var coef = coef_x // y.coefficient

    # Only check for exact division when we haven't truncated the dividend.
    # When extra_words < 0, we've discarded low-order digits so the exact
    # check would be meaningless.
    if extra_words >= 0 and coef * y.coefficient == coef_x:
        # The division is exact, so we need to remove the extra trailing zeros
        # so that the final scale is at least (x.scale - y.scale).
        # If x.scale - y.scale < 0, we can safely remove all trailing zeros.
        # Otherwise, we can remove at most extra digits added.
        var num_digits_to_remove = min(
            extra_digits, coef.number_of_trailing_zeros()
        )
        # TODO: Make a in-place version of this
        coef = decimo.biguint.arithmetics.floor_divide_by_power_of_ten(
            coef, num_digits_to_remove
        )
        extra_digits -= num_digits_to_remove

    var scale = x.scale + extra_digits - y.scale
    var result = BigDecimal(
        coefficient=coef^,
        scale=scale,
        sign=x.sign != y.sign,
    )
    result.round_to_precision(
        precision,
        RoundingMode.half_even(),
        remove_extra_digit_due_to_rounding=True,
        fill_zeros_to_precision=False,
    )
    return result^


def _true_divide_general_truncated(
    x: BigDecimal,
    y: BigDecimal,
    precision: Int,
    needed_divisor_words: Int,
) raises -> BigDecimal:
    """Internal: division with truncated oversized operands."""
    var total_y_remove = len(y.coefficient.words) - needed_divisor_words
    var common_remove = min(
        total_y_remove, max(len(x.coefficient.words) - 1, 0)
    )
    var y_only_remove = total_y_remove - common_remove

    var y_coef_tr = decimo.biguint.arithmetics.floor_divide_by_power_of_billion(
        y.coefficient, total_y_remove
    )
    var x_coef_tr: BigUInt
    if common_remove > 0:
        x_coef_tr = decimo.biguint.arithmetics.floor_divide_by_power_of_billion(
            x.coefficient, common_remove
        )
    else:
        x_coef_tr = x.coefficient.copy()

    var scale_adjust_digits = y_only_remove * 9

    var diff_n_words = len(x_coef_tr.words) - len(y_coef_tr.words)
    var extra_words = math.ceildiv(precision, 9) + 2 - diff_n_words
    var extra_digits = extra_words * 9 + scale_adjust_digits

    var coef_x: BigUInt
    if extra_words > 0:
        coef_x = decimo.biguint.arithmetics.multiply_by_power_of_billion(
            x_coef_tr, extra_words
        )
    elif extra_words < 0:
        coef_x = decimo.biguint.arithmetics.floor_divide_by_power_of_billion(
            x_coef_tr, -extra_words
        )
    else:
        coef_x = x_coef_tr^

    var coef = coef_x // y_coef_tr

    # Truncation discards low-order digits, so we cannot detect exact division
    # by checking coef * y_coef_tr == coef_x (the truncated values).
    # Instead, after rounding, we verify exactness by multiplying the stripped
    # candidate back by the ORIGINAL y and comparing with the ORIGINAL x.
    # This is O(n) for small_quotient × large_y + O(n) comparison.

    var scale = x.scale + extra_digits - y.scale
    var result = BigDecimal(
        coefficient=coef^,
        scale=scale,
        sign=x.sign != y.sign,
    )
    result.round_to_precision(
        precision,
        RoundingMode.half_even(),
        remove_extra_digit_due_to_rounding=True,
        fill_zeros_to_precision=False,
    )

    # Post-rounding exact division check: if the rounded result has trailing
    # zeros, strip them and verify by multiplying back against the original y.
    var tz = result.coefficient.number_of_trailing_zeros()
    if tz > 0:
        # Do not strip zeros that would reduce the scale below the natural
        # quotient scale (x.scale - y.scale) when that value is non-negative.
        # Stripping too far could produce e.g. "2E+1" instead of "20".
        var min_scale = x.scale - y.scale
        var allowed_tz = tz
        if min_scale >= 0:
            var max_strip = result.scale - min_scale
            if max_strip <= 0:
                allowed_tz = 0
            elif tz > max_strip:
                allowed_tz = max_strip

        if allowed_tz > 0:
            var stripped_coef = (
                decimo.biguint.arithmetics.floor_divide_by_power_of_ten(
                    result.coefficient, allowed_tz
                )
            )
            var stripped = BigDecimal(
                coefficient=stripped_coef^,
                scale=result.scale - allowed_tz,
                sign=result.sign,
            )
            # Verify: stripped * y == x (using original, untruncated operands)
            var product = decimo.bigdecimal.arithmetics.multiply(stripped, y)
            if product == x:
                return stripped^

    return result^


def true_divide_inexact(
    x1: BigDecimal, x2: BigDecimal, number_of_significant_digits: Int
) raises -> BigDecimal:
    """Returns the quotient of two numbers with number of significant digits.
    This function is a faster version of true_divide, but it does not
    return the exact result of the division since no extra buffer digits are
    added to the dividend during calculation.
    It is recommended to use this function when you already know the dividend
    has enough digits to produce a result with the desired precision. Then
    use rounding to get the result with the desired precision.

    Args:
        x1: The first operand (dividend).
        x2: The second operand (divisor).
        number_of_significant_digits: The number of significant digits in the
            result.

    Returns:
        The quotient of x1 and x2.

    Raises:
        ZeroDivisionError: If the divisor is zero.
    """

    # Check for division by zero
    if x2.coefficient.is_zero():
        raise ZeroDivisionError(
            message="Division by zero.",
            function="true_divide_inexact()",
        )

    # Handle dividend of zero
    if x1.coefficient.is_zero():
        return BigDecimal(
            coefficient=BigUInt.zero(),
            scale=number_of_significant_digits,
            sign=x1.sign != x2.sign,
        )

    # --- Truncation optimization for oversized operands ---
    comptime TRUNCATION_GUARD = 4
    var needed_divisor_words = (
        math.ceildiv(number_of_significant_digits, 9) + 2 + TRUNCATION_GUARD
    )

    if len(x2.coefficient.words) > needed_divisor_words:
        return _true_divide_inexact_truncated(
            x1, x2, number_of_significant_digits, needed_divisor_words
        )

    # --- Standard path (no truncation, no extra copies) ---
    # First estimate the number of significant digits needed in the dividend
    # to produce a result with precision significant digits
    var x1_digits = x1.coefficient.number_of_digits()
    var x2_digits = x2.coefficient.number_of_digits()

    # Calculate how many digits we need in the dividend
    # We want: x1_digits - x2_digits >= mininum_precision
    var buffer_digits = number_of_significant_digits - (x1_digits - x2_digits)
    buffer_digits = max(0, buffer_digits)

    # Scale up the dividend to ensure sufficient precision
    var scaled_x1 = x1.coefficient.copy()
    if buffer_digits > 0:
        scaled_x1.multiply_by_power_of_ten_inplace(buffer_digits)

    # Perform division
    var quotient: BigUInt = scaled_x1 // x2.coefficient
    var result_scale = buffer_digits + x1.scale - x2.scale

    var result_digits = quotient.number_of_digits()
    if result_digits > number_of_significant_digits:
        var digits_to_remove = result_digits - number_of_significant_digits
        quotient = quotient.remove_trailing_digits_with_rounding(
            digits_to_remove,
            RoundingMode.down(),
            remove_extra_digit_due_to_rounding=False,
        )
        # Adjust the scale accordingly
        result_scale -= digits_to_remove

    return BigDecimal(
        coefficient=quotient^,
        scale=result_scale,
        sign=x1.sign != x2.sign,
    )


def _true_divide_inexact_truncated(
    x1: BigDecimal,
    x2: BigDecimal,
    number_of_significant_digits: Int,
    needed_divisor_words: Int,
) raises -> BigDecimal:
    """Internal: inexact division with truncated oversized operands."""
    var total_y_remove = len(x2.coefficient.words) - needed_divisor_words
    var common_remove = min(
        total_y_remove, max(len(x1.coefficient.words) - 1, 0)
    )
    var y_only_remove = total_y_remove - common_remove

    var x2_coef_tr = (
        decimo.biguint.arithmetics.floor_divide_by_power_of_billion(
            x2.coefficient, total_y_remove
        )
    )
    var x1_coef_tr: BigUInt
    if common_remove > 0:
        x1_coef_tr = (
            decimo.biguint.arithmetics.floor_divide_by_power_of_billion(
                x1.coefficient, common_remove
            )
        )
    else:
        x1_coef_tr = x1.coefficient.copy()

    var scale_adjust_digits = y_only_remove * 9

    var x1_digits = x1_coef_tr.number_of_digits()
    var x2_digits = x2_coef_tr.number_of_digits()

    var buffer_digits = number_of_significant_digits - (x1_digits - x2_digits)
    buffer_digits = max(0, buffer_digits)

    var scaled_x1 = x1_coef_tr^
    if buffer_digits > 0:
        scaled_x1.multiply_by_power_of_ten_inplace(buffer_digits)

    var quotient: BigUInt = scaled_x1 // x2_coef_tr
    var result_scale = buffer_digits + scale_adjust_digits + x1.scale - x2.scale

    var result_digits = quotient.number_of_digits()
    if result_digits > number_of_significant_digits:
        var digits_to_remove = result_digits - number_of_significant_digits
        quotient = quotient.remove_trailing_digits_with_rounding(
            digits_to_remove,
            RoundingMode.down(),
            remove_extra_digit_due_to_rounding=False,
        )
        result_scale -= digits_to_remove

    return BigDecimal(
        coefficient=quotient^,
        scale=result_scale,
        sign=x1.sign != x2.sign,
    )


def true_divide_inexact_by_uint32(
    x1: BigDecimal, y: UInt32, number_of_significant_digits: Int
) raises -> BigDecimal:
    """Returns the quotient of a BigDecimal divided by a small UInt32 integer.

    This is much faster than full BigDecimal division for small divisors,
    using O(n) single-word division instead of O(n²) schoolbook division.

    The divisor y is treated as a positive integer with scale=0. The result
    preserves the sign of x1.

    Args:
        x1: The dividend.
        y: The divisor (must be non-zero).
        number_of_significant_digits: The desired precision.

    Returns:
        The quotient x1 / y with the specified precision.
    """
    debug_assert[assert_mode="none"](
        y != 0,
        (
            "bigdecimal.arithmetics.true_divide_inexact_by_uint32(): Division"
            " by zero"
        ),
    )

    if x1.coefficient.is_zero():
        return BigDecimal(
            coefficient=BigUInt.zero(),
            scale=number_of_significant_digits,
            sign=x1.sign,
        )

    var x1_digits = x1.coefficient.number_of_digits()

    # Calculate number of digits in y
    var y_digits = 1
    var temp = y
    while temp >= 10:
        temp //= 10
        y_digits += 1

    # Calculate how many digits we need in the dividend
    var buffer_digits = number_of_significant_digits - (x1_digits - y_digits)
    buffer_digits = max(0, buffer_digits)

    # Scale up the dividend to ensure sufficient precision
    var scaled_x1 = x1.coefficient.copy()
    if buffer_digits > 0:
        scaled_x1.multiply_by_power_of_ten_inplace(buffer_digits)

    # O(n) division by single word — the key speedup
    var quotient = decimo.biguint.arithmetics.floor_divide_by_uint32(
        scaled_x1, y
    )
    var result_scale = buffer_digits + x1.scale

    var result_digits = quotient.number_of_digits()
    if result_digits > number_of_significant_digits:
        var digits_to_remove = result_digits - number_of_significant_digits
        quotient = quotient.remove_trailing_digits_with_rounding(
            digits_to_remove,
            RoundingMode.down(),
            remove_extra_digit_due_to_rounding=False,
        )
        result_scale -= digits_to_remove

    return BigDecimal(
        coefficient=quotient^,
        scale=result_scale,
        sign=x1.sign,
    )


def truncate_divide(x1: BigDecimal, x2: BigDecimal) raises -> BigDecimal:
    """Returns the quotient of two numbers truncated to zeros.

    Args:
        x1: The first operand (dividend).
        x2: The second operand (divisor).

    Returns:
        The quotient of x1 and x2, truncated to zeros.

    Raises:
        ZeroDivisionError: If division by zero is attempted.

    Notes:
        This function performs integer division that truncates toward zero.
        For example: 7//4 = 1, -7//4 = -1, 7//(-4) = -1, (-7)//(-4) = 1.
    """
    # Check for division by zero
    if x2.coefficient.is_zero():
        raise ZeroDivisionError(
            message="Division by zero.",
            function="truncate_divide()",
        )

    # Handle dividend of zero
    if x1.coefficient.is_zero():
        return BigDecimal(BigUInt.zero(), 0, False)

    # Calculate adjusted scales to align decimal points
    var scale_diff = x1.scale - x2.scale

    # If scale_diff is positive, we need to scale up the dividend
    # If scale_diff is negative, we need to scale up the divisor
    if scale_diff > 0:
        var divisor = x2.coefficient.multiply_by_power_of_ten(scale_diff)
        var quotient = x1.coefficient.truncate_divide(divisor)
        return BigDecimal(quotient^, 0, x1.sign != x2.sign)

    else:  # scale_diff < 0
        var dividend = x1.coefficient.multiply_by_power_of_ten(-scale_diff)
        var quotient = dividend.truncate_divide(x2.coefficient)
        return BigDecimal(quotient^, 0, x1.sign != x2.sign)


def truncate_modulo(
    x1: BigDecimal, x2: BigDecimal, precision: Int
) raises -> BigDecimal:
    """Returns the trucated modulo of two numbers.

    Args:
        x1: The first operand (dividend).
        x2: The second operand (divisor).
        precision: The number of significant digits in the result.

    Returns:
        The truncated modulo of x1 and x2.

    Raises:
        ZeroDivisionError: If division by zero is attempted.
    """
    # Check for division by zero
    if x2.coefficient.is_zero():
        raise ZeroDivisionError(
            message="Division by zero.",
            function="truncate_modulo()",
        )

    return subtract(
        x1,
        multiply(
            truncate_divide(x1, x2),
            x2,
        ),
    )
