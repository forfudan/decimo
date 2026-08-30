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

"""Trigonometric functions for BigDecimal.

Provides high-precision implementations of trigonometric and inverse
trigonometric functions (sin, cos, tan, asin, acos, atan, atan2, etc.)
operating on the arbitrary-precision BigDecimal type.
"""

from std import time

from decimo.bigdecimal.bigdecimal import BigDecimal
import decimo.bigdecimal.constants as bigdecimal_constants
from decimo.bigdecimal.exponential import _round_by_deciding
import decimo.bigdecimal.exponential as bigdecimal_exponential
from decimo.biguint.biguint import BigUInt
from decimo.errors import ValueError
from decimo.rounding_mode import RoundingMode


# ===----------------------------------------------------------------------=== #
# Trigonometric functions
# ===----------------------------------------------------------------------=== #


comptime RESERVE_DIGITS = 99
"""Digits carried beyond the argument's own, when reducing by pi.

Conservative on purpose: an argument that lands very close to a multiple of
`pi/2` cancels further than its magnitude alone predicts, and the series that
follows the reduction rounds a few more times.
"""


comptime SAFETY_DIGITS = 20
"""Digits the reduction must still have in hand after the cancellation.

Covers the series that follows and the roundings around it. `RESERVE_DIGITS`
is what a fresh attempt is given; this is what an attempt already made has to
have kept to be worth finishing.
"""


def budget_for(x: BigDecimal, reduced: BigDecimal, precision: Int) -> Int:
    """Returns the narrowest width at which this reduction was worth doing.

    Args:
        x: The argument that was reduced.
        reduced: What the reduction produced, whose smallness is the
            cancellation.
        precision: The number of significant digits wanted in the result.

    Returns:
        The width below which the reduction cannot have kept `precision`
        digits. A caller that used less has to compute again, wider.

    Notes:

    The digits between the argument and its reduced form are the ones the
    subtraction ate. An argument far from zero spends its magnitude; an
    argument near a multiple of `pi/2` spends its closeness; this counts
    whichever happened, by looking at the result rather than predicting it.

    What it does not count is the ordinary shrinkage of an identity --
    `pi/2 - 1.5` is `0.07`, two digits smaller, and that is not a problem
    worth recomputing for. Only the width actually needed is returned, and
    the caller compares it with the width it used, which starts a hundred
    digits clear of it.
    """
    if reduced.coefficient.is_zero():
        return reduction_digits(x, precision)
    var cancellation = x.adjusted() - reduced.adjusted()
    return precision + SAFETY_DIGITS + (cancellation if cancellation > 0 else 0)


def reduction_digits(x: BigDecimal, precision: Int) -> Int:
    """Returns the working precision a reduction by pi needs for this argument.

    Args:
        x: The argument about to be reduced.
        precision: The number of significant digits wanted in the result.

    Returns:
        The number of digits pi and the reduction must carry.

    Notes:

    `x mod 2pi` subtracts a multiple of `2pi` from `x`, and everything above
    the remainder cancels. An argument of `10^k` therefore spends `k` digits
    of pi before the remainder even starts. A budget that does not count `k`
    is a budget that runs out: at `precision + 99`, which these functions used
    to carry, `sin` is right up to `10^99`, has lost half its digits by
    `10^105`, and by `10^150` returns a number with nothing correct in it at
    all -- silently, since nothing in the computation notices.

    So the budget counts the argument.
    """
    var magnitude = x.adjusted()
    return precision + RESERVE_DIGITS + (magnitude if magnitude > 0 else 0)


comptime TRIG_SLACK = 4
"""Units in the last place a trigonometric kernel may be off at the width it
was asked for.

The reduction is the delicate part, and `reduction_digits()` already sizes
itself to the argument, so what is left here is the Taylor series and the few
roundings around it. Four units is well past that.
"""


def sin_rounded(
    x: BigDecimal, precision: Int, rounding_mode: RoundingMode
) raises -> BigDecimal:
    """Returns `sin(x)` rounded to `precision` digits, decided not assumed.

    Args:
        x: The angle in radians.
        precision: The number of significant digits wanted.
        rounding_mode: How to round the result.

    Returns:
        The correctly rounded value.

    Raises:
        Error: Propagated from `sin()`.
    """
    if x.is_zero():
        # `sin(0)` is exactly zero, and the loop could not settle on it.
        return sin(x, precision)
    return _round_by_deciding[sin, TRIG_SLACK](x, precision, rounding_mode)


def cos_rounded(
    x: BigDecimal, precision: Int, rounding_mode: RoundingMode
) raises -> BigDecimal:
    """Returns `cos(x)` rounded to `precision` digits, decided not assumed.

    Args:
        x: The angle in radians.
        precision: The number of significant digits wanted.
        rounding_mode: How to round the result.

    Returns:
        The correctly rounded value.

    Raises:
        Error: Propagated from `cos()`.
    """
    if x.is_zero():
        # `cos(0)` is exactly one.
        return cos(x, precision)
    return _round_by_deciding[cos, TRIG_SLACK](x, precision, rounding_mode)


def tan_rounded(
    x: BigDecimal, precision: Int, rounding_mode: RoundingMode
) raises -> BigDecimal:
    """Returns `tan(x)` rounded to `precision` digits, decided not assumed.

    Args:
        x: The angle in radians.
        precision: The number of significant digits wanted.
        rounding_mode: How to round the result.

    Returns:
        The correctly rounded value.

    Raises:
        Error: Propagated from `tan()`.
    """
    if x.is_zero():
        # `tan(0)` is exactly zero.
        return tan(x, precision)
    return _round_by_deciding[tan, TRIG_SLACK](x, precision, rounding_mode)


def sin(x: BigDecimal, precision: Int) raises -> BigDecimal:
    """Calculates sine (sin) of the number.

    Args:
        x: The input number in radians.
        precision: The desired precision of the result.

    Returns:
        The sine of x with the specified precision.

    Raises:
        Error: Propagated from underlying arithmetic operations, or if the
            reduction does not settle within four attempts.

    Notes:

    The reduction by pi is where the digits go, and how many it takes cannot
    be known in advance: an argument far from zero spends its magnitude, and
    an argument near a multiple of `pi/2` spends its closeness. So the first
    attempt budgets for the magnitude, which is free to work out, and
    `_sin_at()` reports what the reduction turned out to need. Almost every
    argument settles on that first attempt; the ones that do not are computed
    again at the width their own cancellation asked for.
    """
    var budget = reduction_digits(x, precision)
    for _ in range(4):
        var attempt = _sin_at(x, precision, budget)
        if attempt[1] <= budget:
            return attempt[0].copy()
        budget = attempt[1]
    raise Error(
        "the reduction of this argument did not settle; it lies closer to a"
        " multiple of pi/2 than four widenings could measure"
    )


def _sin_at(
    x: BigDecimal, precision: Int, working_precision: Int
) raises -> Tuple[BigDecimal, Int]:
    """Calculates sine at a given working precision, and says what it needed.

    Args:
        x: The input number in radians.
        precision: The desired precision of the result.
        working_precision: The width to reduce and sum at.

    Returns:
        The sine, and the width the reduction turned out to need. When the
        second exceeds `working_precision` the first is meaningless: the
        caller must try again with the wider one.

    Raises:
        Error: Propagated from underlying arithmetic operations.
    """
    if x.is_zero():
        return (BigDecimal(BigUInt.zero()), 0)

    var bdec_2 = BigDecimal.from_raw_components(
        BigUInt.Word(2), scale=0, sign=False
    )
    var bdec_4 = BigDecimal.from_raw_components(
        BigUInt.Word(4), scale=0, sign=False
    )
    var bdec_6 = BigDecimal.from_raw_components(
        BigUInt.Word(6), scale=0, sign=False
    )
    var bdec_pi = bigdecimal_constants.pi(precision=working_precision)
    var bdec_2pi = bdec_2.multiply(bdec_pi)
    var bdec_pi_div_2 = bdec_pi.true_divide(bdec_2, precision=working_precision)
    var bdec_1d6 = BigDecimal.from_raw_components(
        BigUInt.Word(16), scale=1, sign=False
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
    # This is because 2π is an unstable point for comparison.
    # To avoid infinite recursion in the final step,
    # we reduce it to [6-2π, 2π-6].
    if x_reduced.compare_absolute(bdec_6) >= 0:
        if x_reduced.sign:
            # x in [-2π, -6], reduce to [0, 2π-6]
            x_reduced.add_inplace(bdec_2pi)
        else:
            # x in [6, 2π], reduce to [0, 2π-6]
            x_reduced.subtract_inplace(bdec_2pi)

    # Step 3: Reduce to [0, 2π) using symmetry
    # At this stage, the value should be in the range [0, 6].
    var is_negative: Bool
    if x_reduced.sign:
        is_negative = True
        x_reduced = -x_reduced
    else:
        is_negative = False

    # Step 4: Reduce to [0, π/4], choosing the identity before applying it so
    # that the cancellation can be weighed once, below, whichever branch did
    # the subtracting.
    #
    # 0: |x| ≤ π/4, the series takes it as it stands
    # 1: π/4 < |x| ≤ 1.6, sin(x) = cos(π/2 - x); 1.6 rather than π/2, which
    #    is an unstable point for the comparison
    # 2: 1.6 < |x| ≤ π, sin(x) = sin(π - x)
    # 3: π < |x| < 2π, sin(x) = -sin(x - π)
    var identity: Int
    if x_reduced.compare_absolute(bdec_pi_div_4) <= 0:
        identity = 0
    elif x_reduced.compare_absolute(bdec_1d6) <= 0:
        identity = 1
        x_reduced = bdec_pi_div_2.subtract(x_reduced)
    elif x_reduced.compare_absolute(bdec_pi) <= 0:
        identity = 2
        x_reduced = bdec_pi.subtract(x_reduced)
    else:
        identity = 3
        x_reduced = x_reduced.subtract(bdec_pi)

    # What the reduction cost, now that it has happened. Wider is needed only
    # when the argument was near a multiple of pi/2, which almost none are.
    var needed = budget_for(x, x_reduced, precision)
    if needed > working_precision:
        return (
            BigDecimal(BigUInt.zero()),
            needed + RESERVE_DIGITS - SAFETY_DIGITS,
        )

    var result: BigDecimal
    if identity == 0:
        result = sin_taylor_series(
            x_reduced, minimum_precision=working_precision
        )
    elif identity == 1:
        result = cos_taylor_series(
            x_reduced, minimum_precision=working_precision
        )
    elif identity == 2:
        result = sin(x_reduced, precision=precision)
    else:
        result = -sin(x_reduced, precision=precision)

    if is_negative:
        result = -result

    result.round_to_precision_inplace(
        precision,
        RoundingMode.half_even(),
        remove_extra_digit_due_to_rounding=True,
        fill_zeros_to_precision=False,
    )

    return (result^, needed)


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

    Raises:
        Error: Propagated from underlying arithmetic operations.

    Notes:

    Using Taylor series.
    sin(x) = x - x³/3! + x⁵/5! - x⁷/7! + ...
    """

    comptime BUFFER_DIGITS = 9  # guard digits, not a word width
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
        # Use O(n) single-word division instead of full BigDecimal divide
        # n*(n-1) fits in one word for any practical Taylor series iteration count
        term = term.true_divide_inexact_by_word(
            BigUInt.Word(n * (n - 1)), working_precision
        )
        if sign == 1:
            result.add_inplace(term)
        else:
            result.subtract_inplace(term)
        sign *= -1

        # Ensure that the result will not explode in size
        result.round_to_precision_inplace(
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

    Raises:
        Error: Propagated from underlying arithmetic operations.

    Notes:
    This function adopts range reduction for optimal convergence.
    """

    if x.is_zero():
        return BigDecimal(BigUInt.one())

    # cos(x) = sin(π/2 - x). That subtraction is this function's own
    # reduction, and an argument near π/2 cancels in it, so what it cost is
    # weighed afterwards and the width raised if it was not enough. `sin`
    # then weighs its own.
    var budget = reduction_digits(x, precision)
    for _ in range(4):
        var pi = bigdecimal_constants.pi(precision=budget)
        var pi_div_2 = pi.true_divide(2, precision=budget)
        var shifted = pi_div_2.subtract(x)
        var needed = budget_for(x, shifted, precision)
        if needed <= budget:
            return sin(shifted, precision=precision)
        budget = needed + RESERVE_DIGITS - SAFETY_DIGITS
    raise Error(
        "the reduction of this argument did not settle; it lies closer to a"
        " multiple of pi/2 than four widenings could measure"
    )


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

    Raises:
        Error: Propagated from underlying arithmetic operations.

    Notes:

    Using Taylor series.
    cos(x) = 1 - x²/2! + x⁴/4! - x⁶/6! + ...
    """

    comptime BUFFER_DIGITS = 9
    var working_precision = minimum_precision + BUFFER_DIGITS

    if x.is_zero():
        return BigDecimal.from_raw_components(
            BigUInt.Word(1), scale=minimum_precision, sign=x.sign
        )

    var bdec_1 = BigDecimal.from_raw_components(
        BigUInt.Word(1), scale=0, sign=False
    )
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
        # Use O(n) single-word division instead of full BigDecimal divide
        term = term.true_divide_inexact_by_word(
            BigUInt.Word(n * (n - 1)), working_precision
        )

        if sign == 1:
            result.add_inplace(term)
        else:
            result.subtract_inplace(term)

        sign *= -1

        # Prevent size explosion
        result.round_to_precision_inplace(
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

    Raises:
        Error: Propagated from underlying arithmetic operations (e.g.,
            division by zero at singularities x = π/2 + nπ).

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

    Raises:
        ValueError: If x is zero (cot(0) is treated as undefined in
            `tan_cot()`).
        ZeroDivisionError: At other singularities x = nπ (n != 0) where
            sin(x) is zero, propagated from the underlying division.

    Notes:

    This function calculates cot(x) = cos(x) / sin(x).
    """
    return tan_cot(x, precision, is_tan=False)


def tan_cot(x: BigDecimal, precision: Int, is_tan: Bool) raises -> BigDecimal:
    """Calculates tangent or cotangent, widening if the reduction asks.

    Args:
        x: The input number in radians.
        precision: The desired precision of the result.
        is_tan: If True, calculates tangent; if False, calculates cotangent.

    Returns:
        The tangent or cotangent of x.

    Raises:
        Error: Propagated from the arithmetic, or if the reduction does not
            settle within four attempts.
    """
    var budget = reduction_digits(x, precision)
    for _ in range(4):
        var attempt = _tan_cot_at(x, precision, budget, is_tan)
        if attempt[1] <= budget:
            return attempt[0].copy()
        budget = attempt[1]
    raise Error(
        "the reduction of this argument did not settle; it lies closer to a"
        " multiple of pi/2 than four widenings could measure"
    )


def _tan_cot_at(
    x: BigDecimal, precision: Int, working_precision: Int, is_tan: Bool
) raises -> Tuple[BigDecimal, Int]:
    """Calculates tangent (tan) or cotangent (cot) of the number.

    Args:
        x: The input number in radians.
        precision: The desired precision of the result.
        working_precision: The width to reduce and divide at.
        is_tan: If True, calculates tangent; if False, calculates cotangent.

    Returns:
        The cotangent of x with the specified precision.

    Raises:
        ValueError: If computing cot(nπ) which is undefined.

    Notes:

    This function calculates tan(x) = cos(x) / sin(x) or
    cot(x) = sin(x) / cos(x) depending on the is_tan flag.
    """

    # `tan` cancels twice: once reducing by pi, and again near a pole, where
    # `sin / cos` divides by something small. So pi carries the reserve twice.
    # The reduction below subtracts multiples of pi from the argument, and
    # what that costs is weighed once it has happened: an argument near a
    # multiple of pi/2 -- which for `tan` is a zero on one side and a pole on
    # the other -- cancels there by as much as it is close.
    var working_precision_pi = working_precision + RESERVE_DIGITS

    if x.is_zero():
        if is_tan:
            return (BigDecimal(BigUInt.zero()), 0)
        else:
            # cot(0) is undefined, so it raises. tan(0) is defined and
            # returns 0 in the branch above.
            raise ValueError(
                message="cot(nπ) is undefined", function="tan_cot()"
            )

    var pi = bigdecimal_constants.pi(precision=working_precision_pi)
    var bdec_2 = BigDecimal.from_raw_components(
        BigUInt.Word(2), scale=0, sign=False
    )
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

    var needed = budget_for(x, x_reduced, precision)
    if needed > working_precision:
        # Not enough: the subtraction ate more than the width allowed.
        return (
            BigDecimal(BigUInt.zero()),
            needed + RESERVE_DIGITS - SAFETY_DIGITS,
        )

    # Calculate
    # tan(x) = sin(x) / cos(x)
    # cot(x) = cos(x) / sin(x)
    var sin_x: BigDecimal = sin(x_reduced, precision=working_precision)
    var cos_x: BigDecimal = cos(x_reduced, precision=working_precision)
    var result: BigDecimal
    if is_tan:
        result = sin_x.true_divide(cos_x, precision=working_precision)
    else:
        result = cos_x.true_divide(sin_x, precision=working_precision)

    result.round_to_precision_inplace(
        precision,
        RoundingMode.half_even(),
        remove_extra_digit_due_to_rounding=True,
        fill_zeros_to_precision=False,
    )

    return (result^, needed)


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

    Raises:
        Error: Propagated from underlying arithmetic operations (e.g.,
            division by zero when cos(x) = 0 at x = π/2 + nπ).

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


comptime ARCTAN_SLACK = 4
"""Units in the last place `arctan()` may be off at the width it was asked
for.

It reaches the series through at most one halving and one reciprocal, each
rounding once, and the series itself is summed with its own buffer.
"""


def cot_rounded(
    x: BigDecimal, precision: Int, rounding_mode: RoundingMode
) raises -> BigDecimal:
    """Returns `cot(x)` rounded to `precision` digits, decided not assumed.

    Args:
        x: The angle in radians.
        precision: The number of significant digits wanted.
        rounding_mode: How to round the result.

    Returns:
        The correctly rounded value.

    Raises:
        Error: Propagated from `cot()`.
    """
    return _round_by_deciding[cot, TRIG_SLACK](x, precision, rounding_mode)


def csc_rounded(
    x: BigDecimal, precision: Int, rounding_mode: RoundingMode
) raises -> BigDecimal:
    """Returns `csc(x)` rounded to `precision` digits, decided not assumed.

    Args:
        x: The angle in radians.
        precision: The number of significant digits wanted.
        rounding_mode: How to round the result.

    Returns:
        The correctly rounded value.

    Raises:
        Error: Propagated from `csc()`.
    """
    return _round_by_deciding[csc, TRIG_SLACK](x, precision, rounding_mode)


def sec_rounded(
    x: BigDecimal, precision: Int, rounding_mode: RoundingMode
) raises -> BigDecimal:
    """Returns `sec(x)` rounded to `precision` digits, decided not assumed.

    Args:
        x: The angle in radians.
        precision: The number of significant digits wanted.
        rounding_mode: How to round the result.

    Returns:
        The correctly rounded value.

    Raises:
        Error: Propagated from `sec()`.
    """
    if x.is_zero():
        # `sec(0)` is exactly one, which the loop could not settle on.
        return sec(x, precision)
    return _round_by_deciding[sec, TRIG_SLACK](x, precision, rounding_mode)


def arctan_rounded(
    x: BigDecimal, precision: Int, rounding_mode: RoundingMode
) raises -> BigDecimal:
    """Returns `arctan(x)` rounded to `precision` digits, decided not assumed.

    Args:
        x: The value to take the arctangent of.
        precision: The number of significant digits wanted.
        rounding_mode: How to round the result.

    Returns:
        The correctly rounded value.

    Raises:
        Error: Propagated from `arctan()`.

    Notes:

    `arctan()` on its own adds nine guard digits and rounds once, which is
    wrong when the discarded tail sits on a boundary. It does, for instance,
    at `x = 0.719140535117048373117282825889546395318364929183100430962012`,
    where the true value continues `...67850000000000000000000000000021929`
    and nine digits of guard see only the zeros: the kernel rounds the
    apparent tie to even and answers one unit low.
    """
    if x.is_zero():
        # `arctan(0)` is exactly zero.
        return arctan(x, precision)
    return _round_by_deciding[arctan, ARCTAN_SLACK](x, precision, rounding_mode)


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

    Raises:
        Error: Propagated from underlying arithmetic operations.
    """

    comptime BUFFER_DIGITS = 9  # guard digits, not a word width
    var working_precision = precision + BUFFER_DIGITS

    var bdec_1 = BigDecimal.from_raw_components(
        BigUInt.Word(1), scale=0, sign=False
    )
    var bdec_2 = BigDecimal.from_raw_components(
        BigUInt.Word(2), scale=0, sign=False
    )
    var bdec_0d5 = BigDecimal.from_raw_components(
        BigUInt.Word(5), scale=1, sign=False
    )

    var result: BigDecimal

    if x.compare_absolute(bdec_0d5) <= 0:
        # |x| <= 0.5, use Taylor series:
        result = arctan_taylor_series(x, minimum_precision=precision)

    elif x.compare_absolute(bdec_2) <= 0:
        # |x| <= 2, use the identity:
        # arctan(x) = 2 * arctan(x / (1 + sqrt(1 + x²)))
        # This is to ensure convergence of the Taylor series.
        # Use sqrt_via_reciprocal_iteration for speed — exact perfect square detection is
        # unnecessary since this is an intermediate computation.
        var sqrt_term = bigdecimal_exponential.sqrt_via_reciprocal_iteration(
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

    result.round_to_precision_inplace(
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

    Raises:
        Error: Propagated from underlying arithmetic operations.

    Notes:

    Using Taylor series.
    arctan(x) = x - x³/3 + x⁵/5 - x⁷/7 + ...
    The input x must be in the range (-0.5, 0.5) for convergence.
    """

    comptime BUFFER_DIGITS = 9  # guard digits, not a word width
    var working_precision = minimum_precision + BUFFER_DIGITS

    if x.is_zero():
        return BigDecimal.from_raw_components(
            BigUInt.Word(0), scale=minimum_precision, sign=x.sign
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
        # Use O(n) single-word division instead of full BigDecimal divide
        term_divided = term.true_divide_inexact_by_word(
            BigUInt.Word(n), working_precision
        )  # x^n / n
        if sign == 1:
            result.add_inplace(term_divided)
        else:
            result.subtract_inplace(term_divided)
        sign *= -1
        # Ensure that the result will not explode in size
        result.round_to_precision_inplace(
            working_precision,
            rounding_mode=RoundingMode.down(),
            remove_extra_digit_due_to_rounding=False,
            fill_zeros_to_precision=False,
        )

    return result^
