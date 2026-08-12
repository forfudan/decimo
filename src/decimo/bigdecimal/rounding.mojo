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
Implements functions for mathematical operations on Decimal objects.
"""

from decimo.biguint.biguint import BigUInt
from decimo.bigdecimal.bigdecimal import BigDecimal
from decimo.rounding_mode import RoundingMode

# ===------------------------------------------------------------------------===#
# Rounding
# ===------------------------------------------------------------------------===#


def round(
    number: BigDecimal,
    ndigits: Int,
    rounding_mode: RoundingMode,
) raises -> BigDecimal:
    """Rounds the number to the specified number of decimal places.

    Args:
        number: The number to round.
        ndigits: Number of decimal places to round to.
        rounding_mode: Rounding mode to use.
            RoundingMode.ROUND_DOWN: Round toward zero.
            RoundingMode.ROUND_UP: Round away from zero.
            RoundingMode.ROUND_HALF_UP: Round half away from zero.
            RoundingMode.ROUND_HALF_DOWN: Round half toward zero.
            RoundingMode.ROUND_HALF_EVEN: Round half to even (banker's).
            RoundingMode.ROUND_CEILING: Round toward positive infinity.
            RoundingMode.ROUND_FLOOR: Round toward negative infinity.

    Notes:
        If `ndigits` is negative, the last `ndigits` digits of the integer part of
        the number will be dropped and the scale will be `ndigits`.
        Examples:
            round(123.456, 2) -> 123.46
            round(123.456, -1) -> 12E+1
            round(123.456, -2) -> 1E+2
            round(123.456, -3) -> 0E+3
            round(678.890, -3) -> 1E+3

    Returns:
        A new `BigDecimal` rounded to the specified number of decimal places.

    Raises:
        Error: If an arithmetic error occurs during computation.
    """

    var ndigits_to_remove = number.scale - ndigits
    if ndigits_to_remove == 0:
        return number.copy()
    if ndigits_to_remove < 0:
        # Add trailing zeros to the number
        return number.extend_precision(precision_diff=-ndigits_to_remove)
    else:  # ndigits_to_remove > 0
        # Remove trailing digits from the number
        var ndigits_coefficient = number.coefficient.number_of_digits()
        if ndigits_to_remove > ndigits_coefficient:
            # All significant digits are removed. For ROUND_DOWN this is
            # always 0. For ROUND_UP (away from zero), any non-zero value
            # rounds to 1 at the target scale. For ROUND_HALF_UP /
            # ROUND_HALF_EVEN, it depends on whether the removed value is
            # >= 0.5 at the target scale (it can't be when all digits are
            # below the target precision), so it's 0.
            #
            # For CEILING: round up if positive and non-zero.
            # For FLOOR: round up if negative and non-zero.
            var rounds_away = (
                rounding_mode == RoundingMode.up()
                or (rounding_mode == RoundingMode.ceiling() and not number.sign)
                or (rounding_mode == RoundingMode.floor() and number.sign)
            )
            if rounds_away and number.coefficient != BigUInt.zero():
                return BigDecimal(
                    coefficient=BigUInt.one(),
                    scale=ndigits,
                    sign=number.sign,
                )
            return BigDecimal(
                coefficient=BigUInt.zero(),
                scale=ndigits,
                sign=number.sign,
            )
        # Copy once, then mutate in place via the single shared rounding
        # path. Keeps `round()` (out-of-place public API) and
        # `round_to_precision_inplace` from drifting in behaviour.
        var result = number.copy()
        result.coefficient.remove_trailing_digits_with_rounding_inplace(
            ndigits_to_remove=ndigits_to_remove,
            rounding_mode=rounding_mode,
            remove_extra_digit_due_to_rounding=False,
            sign=number.sign,
            ndigits_before_removal=ndigits_coefficient,
        )
        result.scale = ndigits
        return result^


def round_to_precision_inplace(
    mut number: BigDecimal,
    precision: Int,
    rounding_mode: RoundingMode,
    remove_extra_digit_due_to_rounding: Bool,
    fill_zeros_to_precision: Bool,
) raises:
    """Rounds the number to the specified precision in-place.

    Args:
        number: The number to round.
        precision: Number of precision digits to round to.
            Defaults to 28.
        rounding_mode: Rounding mode to use.
            RoundingMode.ROUND_DOWN: Round toward zero.
            RoundingMode.ROUND_UP: Round away from zero.
            RoundingMode.ROUND_HALF_UP: Round half away from zero.
            RoundingMode.ROUND_HALF_DOWN: Round half toward zero.
            RoundingMode.ROUND_HALF_EVEN: Round half to even (banker's).
            RoundingMode.ROUND_CEILING: Round toward +∞.
            RoundingMode.ROUND_FLOOR: Round toward -∞.
        remove_extra_digit_due_to_rounding: If True, remove a trailing digit if
            the rounding mode result in an extra leading digit.
        fill_zeros_to_precision: If True, fill trailing zeros to the precision.

    Raises:
        Error: If an arithmetic error occurs during computation.
    """

    var ndigits_coefficient = number.coefficient.number_of_digits()
    var ndigits_to_remove = ndigits_coefficient - precision

    if ndigits_to_remove == 0:
        return

    if ndigits_to_remove < 0:
        if fill_zeros_to_precision:
            number = number.extend_precision(precision_diff=-ndigits_to_remove)
            return
        else:
            return

    number.coefficient.remove_trailing_digits_with_rounding_inplace(
        ndigits_to_remove=ndigits_to_remove,
        rounding_mode=rounding_mode,
        remove_extra_digit_due_to_rounding=False,
        sign=number.sign,
        ndigits_before_removal=ndigits_coefficient,
    )
    number.scale -= ndigits_to_remove

    if remove_extra_digit_due_to_rounding and (
        number.coefficient.number_of_digits() > precision
    ):
        number.coefficient.remove_trailing_digits_with_rounding_inplace(
            ndigits_to_remove=1,
            rounding_mode=RoundingMode.down(),
            remove_extra_digit_due_to_rounding=False,
            ndigits_before_removal=precision + 1,
        )
        number.scale -= 1


def quantize(
    value: BigDecimal,
    exp: BigDecimal,
    rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
) raises -> BigDecimal:
    """Rounds the value according to the scale (exponent) of the second operand.

    Unlike `round()`, the scale is determined by the scale of the second
    operand, not a number of digits. `quantize()` returns a value with the
    same scale as `exp`, adjusting `value` through rounding if necessary.

    Args:
        value: The BigDecimal value to quantize.
        exp: A BigDecimal whose scale (exponent) will be used for the result.
            The actual value of `exp` is ignored; only its scale matters.
        rounding_mode: The rounding mode to use.
            Defaults to ROUND_HALF_EVEN (banker's rounding).

    Returns:
        A new BigDecimal with the same value as the first operand (except for
        rounding) and the same scale (exponent) as the second operand.

    Notes:
        Scale (exponent) represents the power of 10 to divide the coefficient by.
        The value = coefficient * 10^(-scale)

        Examples of scale:
        - BigDecimal("0.01") → coefficient=1, scale=2 (1 * 10^-2 = 0.01)
        - BigDecimal("1.23") → coefficient=123, scale=2 (123 * 10^-2 = 1.23)
        - BigDecimal("100") → coefficient=100, scale=0 (100 * 10^0 = 100)
        - BigDecimal("1E+2") → coefficient=1, scale=-2 (1 * 10^2 = 100)

        Note: "100" and "1E+2" have the same value but different scales!

    Examples:

    ```mojo
    from decimo import BigDecimal, ROUND_HALF_EVEN

    var x = BigDecimal("1.2345")

    # Quantize to different scales
    _ = x.quantize(BigDecimal("0.001"))  # -> "1.234"  (3 decimal places)
    _ = x.quantize(BigDecimal("0.01"))   # -> "1.23"   (2 decimal places)
    _ = x.quantize(BigDecimal("0.1"))    # -> "1.2"    (1 decimal place)
    _ = x.quantize(BigDecimal("1"))      # -> "1"      (scale=0, integer)
    _ = x.quantize(BigDecimal("1E+1"))   # -> "0"      (scale=-1, tens place)

    # Financial calculations: align currency precision
    var price1 = BigDecimal("19.999")
    var price2 = BigDecimal("20.1")
    var cent = BigDecimal("0.01")  # 2 decimal places template
    var total = price1.quantize(cent) + price2.quantize(cent)
    # -> "40.10" (both prices rounded to cents)

    # Scientific: align significant figures
    var measurement = BigDecimal("123.456789")
    _ = measurement.quantize(BigDecimal("0.001"))  # -> "123.457" (scale=3)
    _ = measurement.quantize(BigDecimal("1E-6"))   # -> "123.456789" (scale=6)

    # Compare with round()
    var y = BigDecimal("123.456")
    _ = y.quantize(BigDecimal("0.01"))  # -> "123.46" (scale=2)
    _ = round(y, 2)                      # -> "123.46" (ndigits=2)
    _ = y.quantize(BigDecimal("1E+2"))  # -> "1E+2" (scale=-2, rounds to hundreds)
    _ = y.quantize(BigDecimal("100"))   # -> "123" (scale=0, rounds to integer)
    _ = round(y, -2)                     # -> "1E+2" (ndigits=-2)
    ```
    End of examples.

    Raises:
        Error: If an arithmetic error occurs during computation.
    """

    # Determine the target scale from the exp parameter
    var target_scale = exp.scale

    # Determine the current scale of the value
    var current_scale = value.scale

    # If scales are already the same, no quantization needed - return a copy
    if target_scale == current_scale:
        return value.copy()

    # Calculate the difference in scales
    var scale_diff = current_scale - target_scale

    if scale_diff > 0:
        # Need to remove digits (increase scale means more precision)
        # Example: value has scale=5, target has scale=2, remove 3 digits
        return round(value, ndigits=target_scale, rounding_mode=rounding_mode)
    else:
        # scale_diff < 0
        # Need to add trailing zeros (decrease scale means less precision)
        # Example: value has scale=2, target has scale=5, add 3 zeros
        return value.extend_precision(precision_diff=-scale_diff)
