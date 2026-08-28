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

import decimo.biguint.arithmetics as biguint_arithmetics
from decimo.biguint.biguint import BigUInt
from decimo.bigdecimal.bigdecimal import BigDecimal
from decimo.bigdecimal.rounding import round_to_precision_inplace
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

    Raises:
        Error: If an arithmetic error occurs during computation.
    """
    if precision > 0:
        var result = add(x1, x2, precision=0)
        round_to_precision_inplace(
            result,
            precision,
            RoundingMode.ROUND_HALF_EVEN,
            remove_extra_digit_due_to_rounding=True,
            fill_zeros_to_precision=False,
        )
        return result^

    # Hot path: same scale and same sign → straight coefficient add.
    # Skips scale alignment, zero-operand probes, and sign branch entirely.
    if x1.scale == x2.scale and x1.sign == x2.sign:
        var coef = x1.coefficient + x2.coefficient
        return BigDecimal(
            coefficient=coef^,
            scale=x1.scale,
            sign=False if coef.is_zero() else x1.sign,
        )

    # Cold tail: differing scale and/or differing sign.
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

    # `max_scale` is one of the two scales, so at least one of the two scale
    # factors is zero, and `multiply_by_power_of_ten(0)` is a plain copy: a
    # whole coefficient allocated and memcpy'd to produce the value we were
    # already holding. Scale only the operand that needs it and fold the other
    # one in by reference, which costs one allocation on this path instead of
    # two. At these sizes that is most of the operation -- a small `BigUInt`
    # allocation is ~32 ns against ~4 ns of actual arithmetic.
    if scale_factor2 == 0:
        return _combine_scaled_coefficients(
            x1.coefficient.multiply_by_power_of_ten(scale_factor1),
            x2.coefficient,
            x1.sign,
            x2.sign,
            max_scale,
        )
    return _combine_scaled_coefficients(
        x2.coefficient.multiply_by_power_of_ten(scale_factor2),
        x1.coefficient,
        x2.sign,
        x1.sign,
        max_scale,
    )


@always_inline
def _combine_scaled_coefficients(
    var scaled: BigUInt,
    other: BigUInt,
    scaled_sign: Bool,
    other_sign: Bool,
    scale: Int,
) raises -> BigDecimal:
    """Combines a coefficient we own with one we only borrow.

    Both coefficients are already at `scale`. `scaled` is owned, so the
    same-sign sum and the `scaled > other` difference both run in place and
    allocate nothing further. Only the `other > scaled` difference has to
    build a new magnitude, because the larger operand is the borrowed one.

    Args:
        scaled: The owned coefficient, consumed by this call.
        other: The borrowed coefficient, at the same scale as `scaled`.
        scaled_sign: Sign of the operand `scaled` came from.
        other_sign: Sign of the operand `other` came from.
        scale: Scale shared by both coefficients, and of the result.

    Returns:
        The combined value.
    """
    if scaled_sign == other_sign:
        scaled += other
        return BigDecimal(coefficient=scaled^, scale=scale, sign=scaled_sign)

    if scaled > other:
        scaled -= other
        return BigDecimal(coefficient=scaled^, scale=scale, sign=scaled_sign)

    if other > scaled:
        return BigDecimal(
            coefficient=biguint_arithmetics.subtract(other, scaled),
            scale=scale,
            sign=other_sign,
        )

    # Equal magnitudes with opposite signs.
    return BigDecimal(coefficient=BigUInt.zero(), scale=scale, sign=False)


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

    Raises:
        Error: If an arithmetic error occurs during computation.
    """
    if precision > 0:
        var result = subtract(x1, x2, precision=0)
        round_to_precision_inplace(
            result,
            precision,
            RoundingMode.ROUND_HALF_EVEN,
            remove_extra_digit_due_to_rounding=True,
            fill_zeros_to_precision=False,
        )
        return result^

    # Hot path: same scale → handle without alignment.
    # - Different signs: x1 - (-x2) = x1 + x2 (with sign of x1).
    # - Same sign: subtract smaller magnitude from larger.
    if x1.scale == x2.scale:
        if x1.sign != x2.sign:
            var coef = x1.coefficient + x2.coefficient
            return BigDecimal(
                coefficient=coef^,
                scale=x1.scale,
                sign=False if coef.is_zero() else x1.sign,
            )
        # Same sign: actual subtraction. The comparison below settles which
        # way round it goes, so `subtract_greater()` is told rather than asked
        # -- `-` would compare the pair a second time to decide whether to
        # raise, for a case this branch has just ruled out.
        if x1.coefficient > x2.coefficient:
            var coef = biguint_arithmetics.subtract_greater(
                x1.coefficient, x2.coefficient
            )
            return BigDecimal(coefficient=coef^, scale=x1.scale, sign=x1.sign)
        elif x2.coefficient > x1.coefficient:
            var coef = biguint_arithmetics.subtract_greater(
                x2.coefficient, x1.coefficient
            )
            return BigDecimal(
                coefficient=coef^, scale=x1.scale, sign=not x1.sign
            )
        else:
            # |x1| == |x2|, result is +0
            return BigDecimal(
                coefficient=BigUInt.zero(), scale=x1.scale, sign=False
            )

    # Cold tail: differing scale.
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

    # `x1 - x2` is `x1 + (-x2)`, so this is the same combination `add()` does
    # with `x2`'s sign flipped, and it avoids the same wasted allocation: only
    # one of the two scale factors can be non-zero, and scaling by zero is a
    # plain copy. See `_combine_scaled_coefficients()`.
    if scale_factor2 == 0:
        return _combine_scaled_coefficients(
            x1.coefficient.multiply_by_power_of_ten(scale_factor1),
            x2.coefficient,
            x1.sign,
            not x2.sign,
            max_scale,
        )
    return _combine_scaled_coefficients(
        x2.coefficient.multiply_by_power_of_ten(scale_factor2),
        x1.coefficient,
        not x2.sign,
        x1.sign,
        max_scale,
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

    Raises:
        Error: If an arithmetic error occurs during computation.
    """
    # Always compute the exact coefficient product first and then round.
    # If we first round the operands to the target precision and then multiply,
    # we may lose accuracy.
    var result = BigDecimal(
        coefficient=x1.coefficient * x2.coefficient,
        scale=x1.scale + x2.scale,
        sign=x1.sign != x2.sign,
    )

    if precision > 0:
        round_to_precision_inplace(
            result,
            precision,
            RoundingMode.ROUND_HALF_EVEN,
            remove_extra_digit_due_to_rounding=True,
            fill_zeros_to_precision=False,
        )

    return result^


def multiply_inplace(
    mut x1: BigDecimal, x2: BigDecimal, precision: Int = 0
) raises:
    """Multiplies x1 by x2 in place, avoiding full BigDecimal construction.

    This computes the product and moves the result words into x1,
    avoiding the overhead of constructing a new BigDecimal object.

    Args:
        x1: The first operand (modified in place to hold the result).
        x2: The second operand (multiplier).
        precision: Optional target significant-digit precision for the
            result. When `0` (default) the in-place product is exact.
            When `>0` the exact product is computed and then rounded
            in place to `precision` significant digits via HALF_EVEN.

    Raises:
        Error: If an arithmetic error occurs during computation.
    """
    if x1.coefficient.is_zero() or x2.coefficient.is_zero():
        x1.coefficient = BigUInt.zero()
        x1.scale = x1.scale + x2.scale
        x1.sign = x1.sign != x2.sign
        return

    x1.coefficient = x1.coefficient * x2.coefficient
    x1.scale = x1.scale + x2.scale
    x1.sign = x1.sign != x2.sign

    if precision > 0:
        round_to_precision_inplace(
            x1,
            precision,
            RoundingMode.ROUND_HALF_EVEN,
            remove_extra_digit_due_to_rounding=True,
            fill_zeros_to_precision=False,
        )


def add_inplace(mut x1: BigDecimal, x2: BigDecimal, precision: Int = 0) raises:
    """Adds x2 to x1 in place.

    This avoids constructing a new BigDecimal for the result.
    Uses BigUInt inplace operations where possible.

    Args:
        x1: The accumulator (modified in place to hold x1 + x2).
        x2: The value to add.
        precision: Optional target significant-digit precision for the
            result. When `0` (default) the in-place sum is exact.
            When `>0` the exact sum is computed and then rounded in
            place to `precision` significant digits via HALF_EVEN.

    Raises:
        Error: If an arithmetic error occurs during computation.
    """
    var max_scale = max(x1.scale, x2.scale)
    var scale_factor1 = (max_scale - x1.scale) if x1.scale < max_scale else 0
    var scale_factor2 = (max_scale - x2.scale) if x2.scale < max_scale else 0

    # Handle zero operands
    if x1.coefficient.is_zero():
        if x2.coefficient.is_zero():
            x1.scale = max_scale
            x1.sign = False
        else:
            x1.coefficient = x2.coefficient.multiply_by_power_of_ten(
                scale_factor2
            )
            x1.scale = max_scale
            x1.sign = x2.sign
    elif x2.coefficient.is_zero():
        if scale_factor1 > 0:
            x1.coefficient.multiply_by_power_of_ten_inplace(scale_factor1)
        x1.scale = max_scale
    else:
        # Scale x1 in place if needed
        if scale_factor1 > 0:
            x1.coefficient.multiply_by_power_of_ten_inplace(scale_factor1)

        if x1.sign == x2.sign:
            # Same sign: add magnitudes (use inplace add on x1's coefficient)
            if scale_factor2 == 0:
                biguint_arithmetics.add_inplace(x1.coefficient, x2.coefficient)
            else:
                var coef2 = x2.coefficient.multiply_by_power_of_ten(
                    scale_factor2
                )
                biguint_arithmetics.add_inplace(x1.coefficient, coef2)
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
                biguint_arithmetics.subtract_inplace(x1.coefficient, coef2)
                x1.scale = max_scale
            elif coef2 > x1.coefficient:
                biguint_arithmetics.subtract_inplace(coef2, x1.coefficient)
                x1.coefficient = coef2^
                x1.scale = max_scale
                x1.sign = x2.sign
            else:
                x1.coefficient = BigUInt.zero()
                x1.scale = max_scale
                x1.sign = False

    if precision > 0:
        round_to_precision_inplace(
            x1,
            precision,
            RoundingMode.ROUND_HALF_EVEN,
            remove_extra_digit_due_to_rounding=True,
            fill_zeros_to_precision=False,
        )


def subtract_inplace(
    mut x1: BigDecimal, x2: BigDecimal, precision: Int = 0
) raises:
    """Subtracts x2 from x1 in place.

    This avoids constructing a new BigDecimal for the result.

    Args:
        x1: The accumulator (modified in place to hold x1 - x2).
        x2: The value to subtract.
        precision: Optional target significant-digit precision for the
            result. When `0` (default) the in-place difference is
            exact. When `>0` the exact difference is computed and
            then rounded in place to `precision` significant digits
            via HALF_EVEN.

    Raises:
        Error: If an arithmetic error occurs during computation.
    """
    # Create a negated view of x2 and use add_inplace
    var neg_x2 = BigDecimal(
        coefficient=x2.coefficient.copy(),
        scale=x2.scale,
        sign=not x2.sign,
    )
    add_inplace(x1, neg_x2, precision)


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
    # Note that this function already considers extra buffer digits.
    # Short divisors are already routed by `BigUInt.floor_divide` to
    # `floor_divide_by_word`, so the fast path is active end-to-end here
    # without a dedicated `BigDecimal` branch.
    return true_divide_general(x, y, precision)


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

    Raises:
        Error: If an arithmetic error occurs during computation.
    """

    # Yuhao Zhu:
    # x = a * 10*(-m)
    # y = b * 10*(-n)
    # Let s = extra digits to ensure precision
    # x / y = x * 10^s / y / 10^s = (a * 10^s // b) * 10*(-(m + s - n))
    # We need to ensure that a * 10^s // b has more significant digits than p.
    # A quicker way is to add whole empty words to the dividend.
    # Let n_diff = len(a.words) - len(b.words).
    # We compute extra_words = ceil(precision / DIGITS_PER_WORD) + 2 - n_diff.
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
    # with relative error < 10^(-DIGITS_PER_WORD * remaining_words), well
    # below precision + guard.
    # Early-return to avoid extra copies on the common (small-operand) path.
    comptime TRUNCATION_GUARD = 4
    var needed_divisor_words = (
        math.ceildiv(precision, BigUInt.DIGITS_PER_WORD) + 2 + TRUNCATION_GUARD
    )

    if len(y.coefficient.words) > needed_divisor_words:
        return _true_divide_general_truncated(
            x, y, precision, needed_divisor_words
        )

    # --- Standard path (no truncation, no extra copies) ---
    #
    # How far to pad the dividend. Dividing a `dx`-digit number by a
    # `dy`-digit one gives a quotient of `dx - dy` or `dx - dy + 1` digits, so
    # padding with `s` zeros guarantees at least `dx + s - dy`. We want
    # `precision` significant digits plus a couple to round on.
    #
    # This used to be counted in whole words -- `ceildiv(precision,
    # DIGITS_PER_WORD) + 2` words, ignoring how many digits the operands
    # actually had. At nine digits a word, where it was measured, the default
    # precision of 28 padded a four-word dividend out to ten words and produced
    # a 54-digit quotient to keep 28 of, roughly twice the necessary work, and
    # pushed every intermediate past the point where `BigUInt` keeps its words
    # inline. Counting in digits still wins at eighteen.
    comptime GUARD_DIGITS = 2
    var digits_x = x.coefficient.number_of_digits()
    var digits_y = y.coefficient.number_of_digits()
    var extra_words = math.ceildiv(
        precision + GUARD_DIGITS - digits_x + digits_y, BigUInt.DIGITS_PER_WORD
    )
    var extra_digits = extra_words * BigUInt.DIGITS_PER_WORD

    var coef_x: BigUInt
    # Whether anything was thrown away below the digits we kept. It is not the
    # same question as whether the division came out exact, and rounding needs
    # both -- see the sticky digit below.
    var dropped_something = False
    if extra_words > 0:
        coef_x = biguint_arithmetics.multiply_by_power_of_base(
            x.coefficient, extra_words
        )
    elif extra_words < 0:
        # Dividend already has more than enough words for the desired precision.
        # Truncate low-order words to avoid computing unnecessary quotient
        # digits -- but remember whether they were zero. A dividend that
        # divides exactly once truncated can have been inexact before it, and
        # then a tie in the kept digits has to round up rather than to even.
        for index in range(-extra_words):
            if x.coefficient.words[index] != 0:
                dropped_something = True
                break
        coef_x = biguint_arithmetics.floor_divide_by_power_of_base(
            x.coefficient, -extra_words
        )
    else:
        coef_x = x.coefficient.copy()

    # The division tells us whether it came out exact: the remainder is zero.
    # This used to be answered with `coef * y.coefficient == coef_x`, a whole
    # multiplication at quotient-by-divisor width plus a comparison, for
    # something the division had already worked out and discarded.
    #
    # When `extra_words < 0` we have thrown low-order digits away, so the
    # question is meaningless and the remainder is not worth keeping.
    var remainder = BigUInt.zero_with_capacity(4)
    var coef = biguint_arithmetics.floor_divide_modulo(
        coef_x, y.coefficient, remainder
    )

    # Two guard digits are only enough if the discarded tail can be told from
    # an exact tie. The true quotient is strictly greater than the one we
    # computed whenever anything was left below it -- either a non-zero
    # remainder, or dividend digits dropped before the division ran -- so a
    # tail that reads exactly 5000...0 should round up rather than to even.
    # Nudging the last computed digit off zero says so: it can only ever break
    # a tie, because half is the one tail ending in a zero that a rounding
    # decision balances on.
    #
    # Both halves are needed. A truncated dividend can divide exactly, leaving
    # a zero remainder for a division that was not exact at all:
    # `19058000000000000000000009 / 762320` at precision 1 is just above the
    # tie at 2.5E+19 and must give 3E+19, and reading only the remainder gave
    # 2E+19.
    #
    # Without this the wide padding above was doing the same job by accident,
    # making a false tie merely improbable rather than impossible.
    if dropped_something or not remainder.is_zero():
        var lowest = coef.words[0]
        if lowest % 10 == 0:
            coef.words[0] = lowest + 1

    if extra_words >= 0 and remainder.is_zero():
        # The division is exact, so we need to remove the extra trailing zeros
        # so that the final scale is at least (x.scale - y.scale).
        # If x.scale - y.scale < 0, we can safely remove all trailing zeros.
        # Otherwise, we can remove at most extra digits added.
        var num_digits_to_remove = min(
            extra_digits, coef.number_of_trailing_zeros()
        )
        biguint_arithmetics.floor_divide_by_power_of_ten_inplace(
            coef, num_digits_to_remove
        )
        extra_digits -= num_digits_to_remove

    var scale = x.scale + extra_digits - y.scale
    var result = BigDecimal(
        coefficient=coef^,
        scale=scale,
        sign=x.sign != y.sign,
    )
    result.round_to_precision_inplace(
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

    # The dividend has to keep as many words as the divisor does. What bounds
    # the error of the truncation is how many significant digits each operand
    # keeps, not how many words came off, and this used to cap the dividend at
    # `len(words) - 1` -- one word, whose leading word can hold as little as a
    # single digit. `368.3881690356602195` divided by a two-hundred-digit
    # number kept the `3` and nothing else, and the quotient was right to one
    # digit out of nineteen.
    #
    # Removing less from the dividend only moves the work to `y_only_remove`,
    # which the scale adjustment below already compensates for, so the bound
    # on the operand sizes is unchanged.
    var common_remove = min(
        total_y_remove,
        max(len(x.coefficient.words) - needed_divisor_words, 0),
    )
    var y_only_remove = total_y_remove - common_remove

    var y_coef_tr = biguint_arithmetics.floor_divide_by_power_of_base(
        y.coefficient, total_y_remove
    )
    var x_coef_tr: BigUInt
    if common_remove > 0:
        x_coef_tr = biguint_arithmetics.floor_divide_by_power_of_base(
            x.coefficient, common_remove
        )
    else:
        x_coef_tr = x.coefficient.copy()

    var scale_adjust_digits = y_only_remove * BigUInt.DIGITS_PER_WORD

    var diff_n_words = len(x_coef_tr.words) - len(y_coef_tr.words)
    var extra_words = (
        math.ceildiv(precision, BigUInt.DIGITS_PER_WORD) + 2 - diff_n_words
    )
    var extra_digits = (
        extra_words * BigUInt.DIGITS_PER_WORD + scale_adjust_digits
    )

    var coef_x: BigUInt
    if extra_words > 0:
        coef_x = biguint_arithmetics.multiply_by_power_of_base(
            x_coef_tr, extra_words
        )
    elif extra_words < 0:
        coef_x = biguint_arithmetics.floor_divide_by_power_of_base(
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
    result.round_to_precision_inplace(
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
                biguint_arithmetics.floor_divide_by_power_of_ten(
                    result.coefficient, allowed_tz
                )
            )
            var stripped = BigDecimal(
                coefficient=stripped_coef^,
                scale=result.scale - allowed_tz,
                sign=result.sign,
            )
            # Verify: stripped * y == x (using original, untruncated operands)
            var product = multiply(stripped, y)
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
        math.ceildiv(number_of_significant_digits, BigUInt.DIGITS_PER_WORD)
        + 2
        + TRUNCATION_GUARD
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
        quotient.remove_trailing_digits_with_rounding_inplace(
            digits_to_remove,
            RoundingMode.down(),
            remove_extra_digit_due_to_rounding=False,
            ndigits_before_removal=result_digits,
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

    # The dividend keeps as many words as the divisor, for the reason spelled
    # out in `_true_divide_general_truncated()`: a leading word can hold a
    # single digit, so capping at `len(words) - 1` left the division one
    # significant digit to work from. Same defect, same shape, sibling
    # function -- and this one feeds `root()`, where a short answer is silent.
    var common_remove = min(
        total_y_remove,
        max(len(x1.coefficient.words) - needed_divisor_words, 0),
    )
    var y_only_remove = total_y_remove - common_remove

    var x2_coef_tr = biguint_arithmetics.floor_divide_by_power_of_base(
        x2.coefficient, total_y_remove
    )
    var x1_coef_tr: BigUInt
    if common_remove > 0:
        x1_coef_tr = biguint_arithmetics.floor_divide_by_power_of_base(
            x1.coefficient, common_remove
        )
    else:
        x1_coef_tr = x1.coefficient.copy()

    var scale_adjust_digits = y_only_remove * BigUInt.DIGITS_PER_WORD

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
        quotient.remove_trailing_digits_with_rounding_inplace(
            digits_to_remove,
            RoundingMode.down(),
            remove_extra_digit_due_to_rounding=False,
            ndigits_before_removal=result_digits,
        )
        result_scale -= digits_to_remove

    return BigDecimal(
        coefficient=quotient^,
        scale=result_scale,
        sign=x1.sign != x2.sign,
    )


def true_divide_inexact_by_word(
    x1: BigDecimal, y: BigUInt.Word, number_of_significant_digits: Int
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

    Raises:
        Error: If an arithmetic error occurs during computation.
    """
    debug_assert[assert_mode="none"](
        y != 0,
        (
            "bigdecimal.arithmetics.true_divide_inexact_by_word(): Division"
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
    var quotient = biguint_arithmetics.floor_divide_by_word(scaled_x1, y)
    var result_scale = buffer_digits + x1.scale

    var result_digits = quotient.number_of_digits()
    if result_digits > number_of_significant_digits:
        var digits_to_remove = result_digits - number_of_significant_digits
        quotient.remove_trailing_digits_with_rounding_inplace(
            digits_to_remove,
            RoundingMode.down(),
            remove_extra_digit_due_to_rounding=False,
            ndigits_before_removal=result_digits,
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
