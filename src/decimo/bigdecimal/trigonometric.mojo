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

# ===----------------------------------------------------------------------=== #
# Trigonometric functions for BigDecimal
# ===----------------------------------------------------------------------=== #

from std import time

from decimo.bigdecimal.bigdecimal import BigDecimal
from decimo.errors import ValueError
from decimo.rounding_mode import RoundingMode
import decimo.bigdecimal.constants as bigdecimal_constants
import decimo.bigdecimal.exponential as bigdecimal_exponential


# ===----------------------------------------------------------------------=== #
# Trigonometric functions
# ===----------------------------------------------------------------------=== #


def sin(x: BigDecimal, precision: Int) raises -> BigDecimal:
    """Calculates sine (sin) of the number.

    Args:
        x: The input number in radians.
        precision: The desired precision of the result.

    Returns:
        The sine of x with the specified precision.

    Notes:
    This function adopts range reduction for optimal convergence.
    """

    # Yuhao Zhu's notes:
    # I use a very comservative number of buffer digits because we need to have
    # a very high precision to calculate the pi so that we can conduct range
    # reduction accurately.
    # Otherwise, the result will be inaccurate when x is close to π-related
    # values, e.g., π/2, π, 3π/2, 2π, etc.
    comptime BUFFER_DIGITS = 99
    var working_precision = precision + BUFFER_DIGITS

    var result: BigDecimal

    if x.is_zero():
        return BigDecimal(BigUInt.zero())

    var bdec_2 = BigDecimal.from_raw_components(UInt32(2), scale=0, sign=False)
    var bdec_4 = BigDecimal.from_raw_components(UInt32(4), scale=0, sign=False)
    var bdec_6 = BigDecimal.from_raw_components(UInt32(6), scale=0, sign=False)
    var bdec_pi = bigdecimal_constants.pi(precision=working_precision)
    var bdec_2pi = bdec_2.multiply(bdec_pi)
    var bdec_pi_div_2 = bdec_pi.true_divide(bdec_2, precision=working_precision)
    var bdec_1d6 = BigDecimal.from_raw_components(
        UInt32(16), scale=1, sign=False
    )
    var bdec_pi_div_4 = bdec_pi.true_divide(bdec_4, precision=working_precision)

    # Step 1: Reduce to (-2π, 2π) using modulo and symmetry
    # sin(x) = sin(x mod 2π)
    var x_reduced: BigDecimal
    if x.compare_absolute(bdec_2pi) >= 0:
        # x_reduced = x mod 2π
        x_reduced = x % bdec_2pi
    else:
        x_reduced = x.copy()

    # Step 2: Reduce [-2π, -6] or [6, 2π] to [6-2π, 2π-6]
    # sin(x) = sin(x - 2π)
    # This is because 2π is an instable point for comparison.
    # To avoid infinite recursion in the final step,
    # we reduce it to [6-2π, 2π-6].
    if x_reduced.compare_absolute(bdec_6) >= 0:
        if x_reduced.sign:
            # x in [-2π, -6], reduce to [0, 2π-6]
            x_reduced.add_inplace(bdec_2pi)
        else:
            # x in [6, 2π], reduce to [0, 2π-6]
            x_reduced.subtract_inplace(bdec_2pi)

    # Step 2: Reduce to [0, 2π) using symmetry
    # At this stage, the value should be in the range [0, 6].
    var is_negative: Bool
    if x_reduced.sign:
        is_negative = True
        x_reduced = -x_reduced
    else:
        is_negative = False

    # Step 3: Reduce to [0, π/4] with different cases

    # |x| ≤ π/4: Use Taylor series directly
    if x_reduced.compare_absolute(bdec_pi_div_4) <= 0:
        result = sin_taylor_series(
            x_reduced, minimum_precision=working_precision
        )

    # π/4 < |x| ≤ π/2: Use identity sin(x) = cos(π/2 - x)
    # 0 ≤ (π/2 - x) < π/4
    # Use 1.6 because π/4 is an instable point for the next case.
    # To avoid infinite recursion, we use 1.6 as a threshold.
    # π/4 < |x| ≤ 1.6
    elif x_reduced.compare_absolute(bdec_1d6) <= 0:
        x_reduced = bdec_pi_div_2.subtract(x_reduced)
        result = cos_taylor_series(
            x_reduced, minimum_precision=working_precision
        )

    # π/2 < |x| ≤ π: Use identity sin(x) = sin(π - x)
    # 0 ≤ (π - x) < π/2
    # Because 1.6 is used as a threshold before
    # π/2 < 1.6 < |x| ≤ π
    # 0 ≤ (π - x) < π - 1.6 < π/2
    elif x_reduced.compare_absolute(bdec_pi) <= 0:
        x_reduced = bdec_pi.subtract(x_reduced)
        result = sin(x_reduced, precision=precision)

    # π < |x| < 2π: Use identity sin(x) = -sin(x - π)
    # 0 < (x - π) < π
    # Note tha the acutal range is (π, 6), so it is reduced to (0, 6 - π).
    else:
        x_reduced = x_reduced.subtract(bdec_pi)
        result = -sin(x_reduced, precision=precision)

    if is_negative:
        result = -result

    result.round_to_precision(
        precision,
        RoundingMode.half_even(),
        remove_extra_digit_due_to_rounding=True,
        fill_zeros_to_precision=False,
    )

    return result^


def sin_taylor_series(
    x: BigDecimal, minimum_precision: Int
) raises -> BigDecimal:
    """Calculates sine of a number with Taylor series.

    Args:
        x: The input number in radians.
        minimum_precision: The minimum precision of the result.

    Returns:
        The sine of the input number with the specified precision plus
        some extra digits to ensure accuracy.

    Notes:

    Using Taylor series.
    sin(x) = x - x³/3! + x⁵/5! - x⁷/7! + ...
    """

    comptime BUFFER_DIGITS = 9  # word-length, easy to append and trim
    var working_precision = minimum_precision + BUFFER_DIGITS

    if x.is_zero():
        return BigDecimal(BigUInt.zero())

    var term = x.copy()  # x^n / n!
    var result = x.copy()
    var x_squared = x.multiply(x)
    var n = 1
    var sign = -1

    # Continue until term is smaller than desired precision
    var epsilon = BigDecimal(BigUInt.one(), scale=working_precision, sign=False)

    while term.compare_absolute(epsilon) > 0:
        # x^n = x^(n-2) * x^2 / ((n-1)(n))
        n += 2
        # Use inplace multiply to avoid BigDecimal allocation
        term.multiply_inplace(x_squared)
        # Use O(n) uint32 division instead of full BigDecimal divide
        # n*(n-1) fits in UInt32 for any practical Taylor series iteration count
        term = term.true_divide_inexact_by_uint32(
            UInt32(n * (n - 1)), working_precision
        )
        if sign == 1:
            result.add_inplace(term)
        else:
            result.subtract_inplace(term)
        sign *= -1

        # Ensure that the result will not explode in size
        result.round_to_precision(
            working_precision,
            rounding_mode=RoundingMode.down(),
            remove_extra_digit_due_to_rounding=False,
            fill_zeros_to_precision=False,
        )

    return result^


def cos(x: BigDecimal, precision: Int) raises -> BigDecimal:
    """Calculates cosine (cos) of the number.

    Args:
        x: The input number in radians.
        precision: The desired precision of the result.

    Returns:
        The cosine of x with the specified precision.

    Notes:
    This function adopts range reduction for optimal convergence.
    """

    comptime BUFFER_DIGITS = 99
    var working_precision = precision + BUFFER_DIGITS

    if x.is_zero():
        return BigDecimal(BigUInt.one())

    # cos(x) = sin(π/2 - x)
    var pi = bigdecimal_constants.pi(precision=working_precision)
    var pi_div_2 = pi.true_divide(2, precision=working_precision)
    var result = sin(pi_div_2.subtract(x), precision=precision)
    return result^


def cos_taylor_series(
    x: BigDecimal, minimum_precision: Int
) raises -> BigDecimal:
    """Calculates cosine using Taylor series.

    Args:
        x: The input number in radians.
        minimum_precision: The minimum precision of the result.

    Returns:
        The cosine of the input number with the specified precision plus
        some extra digits to ensure accuracy.

    Notes:

    Using Taylor series.
    cos(x) = 1 - x²/2! + x⁴/4! - x⁶/6! + ...
    """

    comptime BUFFER_DIGITS = 9
    var working_precision = minimum_precision + BUFFER_DIGITS

    if x.is_zero():
        return BigDecimal.from_raw_components(
            UInt32(1), scale=minimum_precision, sign=x.sign
        )

    var bdec_1 = BigDecimal.from_raw_components(UInt32(1), scale=0, sign=False)
    var term = bdec_1.copy()  # Current term: x^n / n!
    var result = bdec_1.copy()  # Start with 1
    var x_squared = x.multiply(x)
    var n = 0  # Current power (0, 2, 4, 6, ...)
    var sign = -1  # Alternating sign

    var epsilon = BigDecimal(BigUInt.one(), scale=working_precision, sign=False)

    while term.compare_absolute(epsilon) > 0:
        n += 2  # Next even power: 2, 4, 6, 8, ...
        # Use inplace multiply to avoid BigDecimal allocation
        term.multiply_inplace(x_squared)
        # Use O(n) uint32 division instead of full BigDecimal divide
        term = term.true_divide_inexact_by_uint32(
            UInt32(n * (n - 1)), working_precision
        )

        if sign == 1:
            result.add_inplace(term)
        else:
            result.subtract_inplace(term)

        sign *= -1

        # # Prevent size explosion
        result.round_to_precision(
            working_precision,
            rounding_mode=RoundingMode.down(),
            remove_extra_digit_due_to_rounding=False,
            fill_zeros_to_precision=False,
        )

    return result^


def tan(x: BigDecimal, precision: Int) raises -> BigDecimal:
    """Calculates tangent (tan) of the number.

    Args:
        x: The input number in radians.
        precision: The desired precision of the result.

    Returns:
        The tangent of x with the specified precision.

    Notes:

    This function calculates tan(x) = sin(x) / cos(x).
    """
    return tan_cot(x, precision, is_tan=True)


def cot(x: BigDecimal, precision: Int) raises -> BigDecimal:
    """Calculates cotangent (cot) of the number.

    Args:
        x: The input number in radians.
        precision: The desired precision of the result.

    Returns:
        The cotangent of x with the specified precision.

    Notes:

    This function calculates cot(x) = cos(x) / sin(x).
    """
    return tan_cot(x, precision, is_tan=False)


def tan_cot(x: BigDecimal, precision: Int, is_tan: Bool) raises -> BigDecimal:
    """Calculates tangent (tan) or cotangent (cot) of the number.

    Args:
        x: The input number in radians.
        precision: The desired precision of the result.
        is_tan: If True, calculates tangent; if False, calculates cotangent.

    Returns:
        The cotangent of x with the specified precision.

    Raises:
        ValueError: If computing cot(nπ) which is undefined.

    Notes:

    This function calculates tan(x) = cos(x) / sin(x) or
    cot(x) = sin(x) / cos(x) depending on the is_tan flag.
    """

    comptime BUFFER_DIGITS = 99
    var working_precision_pi = precision + 2 * BUFFER_DIGITS
    var working_precision = precision + BUFFER_DIGITS

    if x.is_zero():
        if is_tan:
            return BigDecimal(BigUInt.zero())
        else:
            # cot(0) is undefined, but we return 0 for consistency
            # since tan(0) is defined as 0.
            # This is a design choice, not a mathematical one.
            # In practice, cot(0) should raise an error.
            raise ValueError(
                message="cot(nπ) is undefined", function="tan_cot()"
            )

    var pi = bigdecimal_constants.pi(precision=working_precision_pi)
    var bdec_2 = BigDecimal.from_raw_components(UInt32(2), scale=0, sign=False)
    var two_pi = bdec_2.multiply(pi)
    var pi_div_2 = pi.true_divide(bdec_2, precision=working_precision_pi)

    var x_reduced = x.copy()
    # First reduce to (-π, π) range
    if x_reduced.compare_absolute(pi) > 0:
        x_reduced = x_reduced % two_pi
        # Adjust to (-π, π) range
        if x_reduced.compare_absolute(pi) > 0:
            if x_reduced.sign:
                x_reduced.add_inplace(two_pi)
            else:
                x_reduced.subtract_inplace(two_pi)

    # Now reduce to (-π/2, π/2) using tan(x + π) = tan(x)
    if x_reduced.compare_absolute(pi_div_2) > 0:
        if x_reduced.sign:
            x_reduced.add_inplace(pi)
        else:
            x_reduced.subtract_inplace(pi)

    # Calculate
    # tan(x) = sin(x) / cos(x)
    # cot(x) = cos(x) / sin(x)
    var sin_x: BigDecimal = sin(x_reduced, precision=working_precision)
    var cos_x: BigDecimal = cos(x_reduced, precision=working_precision)
    if is_tan:
        result: BigDecimal = sin_x.true_divide(
            cos_x, precision=working_precision
        )
    else:
        result: BigDecimal = cos_x.true_divide(
            sin_x, precision=working_precision
        )

    result.round_to_precision(
        precision,
        RoundingMode.half_even(),
        remove_extra_digit_due_to_rounding=True,
        fill_zeros_to_precision=False,
    )

    return result^


def csc(x: BigDecimal, precision: Int) raises -> BigDecimal:
    """Calculates cosecant (csc) of the number.

    Args:
        x: The input number in radians.
        precision: The desired precision of the result.

    Returns:
        The cosecant of x with the specified precision.

    Raises:
        ValueError: If x is zero (csc(nπ) is undefined).

    Notes:

    This function calculates csc(x) = 1 / sin(x).
    """
    if x.is_zero():
        raise ValueError(message="csc(nπ) is undefined", function="csc()")

    comptime BUFFER_DIGITS = 9
    var working_precision = precision + BUFFER_DIGITS

    var sin_x = sin(x, precision=working_precision)

    return BigDecimal(BigUInt.one()).true_divide(sin_x, precision=precision)


def sec(x: BigDecimal, precision: Int) raises -> BigDecimal:
    """Calculates secant (sec) of the number.

    Args:
        x: The input number in radians.
        precision: The desired precision of the result.

    Returns:
        The secant of x with the specified precision.

    Notes:

    This function calculates sec(x) = 1 / cos(x).
    """
    if x.is_zero():
        return BigDecimal(BigUInt.one())

    comptime BUFFER_DIGITS = 9
    var working_precision = precision + BUFFER_DIGITS

    var cos_x = cos(x, precision=working_precision)

    return BigDecimal(BigUInt.one()).true_divide(cos_x, precision=precision)


# ===----------------------------------------------------------------------=== #
# Inverse trigonometric functions
# ===----------------------------------------------------------------------=== #


def arctan(x: BigDecimal, precision: Int) raises -> BigDecimal:
    """Calculates arctangent (arctan) of the number.

    Notes:

    y = arctan(x),
    where x can be all real numbers,
    and y is in the range (-π/2, π/2).

    Args:
        x: The input number to compute the arctangent of.
        precision: The number of significant digits for the result.

    Returns:
        The arctangent of x in radians, in the range (-π/2, π/2).
    """

    comptime BUFFER_DIGITS = 9  # word-length, easy to append and trim
    var working_precision = precision + BUFFER_DIGITS

    bdec_1 = BigDecimal.from_raw_components(UInt32(1), scale=0, sign=False)
    bdec_2 = BigDecimal.from_raw_components(UInt32(2), scale=0, sign=False)
    bdec_0d5 = BigDecimal.from_raw_components(UInt32(5), scale=1, sign=False)

    var result: BigDecimal

    if x.compare_absolute(bdec_0d5) <= 0:
        # |x| <= 0.5, use Taylor series:
        # print("Using Taylor series for arctan with |x| <= 0.5")
        result = arctan_taylor_series(x, minimum_precision=precision)

    elif x.compare_absolute(bdec_2) <= 0:
        # |x| <= 2, use the identity:
        # arctan(x) = 2 * arctan(x / (1 + sqrt(1 + x²)))
        # This is to ensure convergence of the Taylor series.
        # print("Using identity for arctan with |x| <= 2")
        # print(bdec_1 + x * x)
        # Use sqrt_reciprocal for speed — exact perfect square detection is
        # unnecessary since this is an intermediate computation.
        var sqrt_term = bigdecimal_exponential.sqrt_reciprocal(
            bdec_1.add(x.multiply(x)), working_precision
        )
        var x_divided = x.true_divide(
            bdec_1.add(sqrt_term), precision=working_precision
        )
        result = bdec_2.multiply(
            arctan_taylor_series(x_divided, minimum_precision=precision)
        )

    else:  # x.compare_absolute(bdec_1) > 0
        # |x| > 2, use the identity:
        # For x > 2: arctan(x) = π/2 - arctan(1/x)
        # For x < -2: arctan(x) = -π/2 - arctan(1/x)
        # This is to ensure convergence of the Taylor series.
        # print("Using identity for arctan with |x| > 2")
        var half_pi = bigdecimal_constants.pi(
            precision=working_precision
        ).true_divide(bdec_2, precision=working_precision)
        var reciprocal_x = bdec_1.true_divide(x, precision=working_precision)
        var arctan_reciprocal = arctan_taylor_series(
            reciprocal_x^, minimum_precision=precision
        )

        if x.sign:
            result = (-half_pi).subtract(arctan_reciprocal)
        else:
            result = half_pi.subtract(arctan_reciprocal)

    result.round_to_precision(
        precision,
        RoundingMode.half_even(),
        remove_extra_digit_due_to_rounding=True,
        fill_zeros_to_precision=False,
    )
    return result^


def arctan_taylor_series(
    x: BigDecimal, minimum_precision: Int
) raises -> BigDecimal:
    """Calculates arctangent (arctan) of a number with Taylor series.

    Args:
        x: The input number, must be in the range (-0.5, 0.5) for convergence.
        minimum_precision: The mininum precision of the result.

    Returns:
        The arctangent of the input number with the specified precision plus
        some extra digits to ensure accuracy.

    Notes:

    Using Taylor series.
    arctan(x) = x - x³/3 + x⁵/5 - x⁷/7 + ...
    The input x must be in the range (-0.5, 0.5) for convergence.
    """

    comptime BUFFER_DIGITS = 9  # word-length, easy to append and trim
    var working_precision = minimum_precision + BUFFER_DIGITS

    if x.is_zero():
        return BigDecimal.from_raw_components(
            UInt32(0), scale=minimum_precision, sign=x.sign
        )

    var term = x.copy()  # x^n
    var term_divided = x.copy()  # x^n / n
    var result = x.copy()
    var x_squared = x.multiply(x)
    var n = 1
    var sign = -1

    # Continue until term is smaller than desired precision
    var epsilon = BigDecimal(BigUInt.one(), scale=working_precision, sign=False)

    while term_divided.compare_absolute(epsilon) > 0:
        n += 2
        # Use inplace multiply to avoid BigDecimal allocation
        term.multiply_inplace(x_squared)  # x^n = x^(n-2) * x^2
        # Use O(n) uint32 division instead of full BigDecimal divide
        term_divided = term.true_divide_inexact_by_uint32(
            UInt32(n), working_precision
        )  # x^n / n
        if sign == 1:
            result.add_inplace(term_divided)
        else:
            result.subtract_inplace(term_divided)
        sign *= -1
        # Ensure that the result will not explode in size
        result.round_to_precision(
            working_precision,
            rounding_mode=RoundingMode.down(),
            remove_extra_digit_due_to_rounding=False,
            fill_zeros_to_precision=False,
        )

    return result^
