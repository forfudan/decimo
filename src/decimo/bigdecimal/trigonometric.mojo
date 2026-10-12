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

import decimo.bigdecimal.arithmetics as bigdecimal_arithmetics
from decimo.bigdecimal.bigdecimal import BigDecimal
import decimo.bigdecimal.constants as bigdecimal_constants
from decimo.bigdecimal.exponential import (
    _ZIV_LIMIT,
    _ZIV_START,
    _round_by_deciding,
    _settled_answer,
)
import decimo.bigdecimal.exponential as bigdecimal_exponential
from decimo.bigfloat.bigfloat import BigFloat
import decimo.bigfloat.trigonometric as bigfloat_trigonometric
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


comptime MAX_REDUCTION_DIGITS: Int = Int.MAX // 4
"""The widest reduction by pi this layer will attempt.

Reducing `x` modulo `2pi` spends one digit of pi for every digit of `x`
above the point, so an argument of `10^k` asks for `k` digits of the constant
before the answer's own digits begin. That is honest work for a `k` of
thousands or millions, and it is not work at all for a `k` of quintillions:
nothing would finish it.

The bound is the one `bigfloat.rounding` draws for a precision, and for the
same reason -- so that an argument nothing could answer is refused in one
line rather than discovered as a hang. An argument below it is attempted
however long that takes, which is what the binary layer and MPFR do too.
"""


def checked_reduction_digits(
    x: BigDecimal, precision: Int, function: String
) raises -> Int:
    """The reduction's budget, refusing one that could never be computed.

    Args:
        x: The argument about to be reduced.
        precision: The number of significant digits wanted in the result.
        function: The name to put in the error.

    Returns:
        What `reduction_digits()` returns.

    Raises:
        ValueError: If the budget is past `MAX_REDUCTION_DIGITS`, or has
            wrapped past what an `Int` holds on the way there.
    """
    var budget = reduction_digits(x, precision)
    if budget > MAX_REDUCTION_DIGITS or budget < 0:
        raise ValueError(
            message=(
                "This argument is so far from nought that reducing it would"
                " need more digits of pi than any precision holds."
            ),
            function=function,
        )
    return budget


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
    return _round_by_deciding[_sine_in_binary, TRIG_SLACK](
        x, precision, rounding_mode
    )


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
    return _round_by_deciding[_cosine_in_binary, TRIG_SLACK](
        x, precision, rounding_mode
    )


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
    return _round_by_deciding[_tangent_in_binary, TRIG_SLACK](
        x, precision, rounding_mode
    )


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
    var budget = checked_reduction_digits(x, precision, "sin()")
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
    var budget = checked_reduction_digits(x, precision, "cos()")
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
    var budget = checked_reduction_digits(x, precision, "tan_cot()")
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


# ===----------------------------------------------------------------------=== #
# The circular functions, worked out in binary
# ===----------------------------------------------------------------------=== #
#
# The reduction is what costs, not the series. `sin()` below reduces the
# argument by `pi/2` in base 10^18 and sums the Taylor series there, and both
# halves are quadratic in the digits. The binary layer reduces and sums in
# base 2^64, where a multiplication of the same size costs about a third as
# much, and sums the series in blocks besides.
#
# So the three of them hand the work over, as the inverse functions above do.
# What is new here is the width: the sine and the cosine of an argument near
# a multiple of `pi/2` begin with a run of zeros, and every one of those is a
# digit the reduction had to find and lose. An argument far from zero spends
# its magnitude the same way. Both are the same quantity -- what the answer
# is worth against what the argument is worth -- and a first attempt reports
# it, so the second is wide enough. The decimal series stays for short
# requests, for arguments the binary exponent range cannot hold, for an
# answer that comes out exactly zero, and as the second implementation the
# tests compare against.


# There is no floor on the digits here, unlike the inverse functions below.
# The binary route wins at every precision there is, down to a single digit,
# because what it replaces is a reduction and not just a series. Measured in
# nanoseconds per call, `sin(1.2)` at 1, 28 and 64 digits: 12,413 against
# 4,596, 16,380 against 6,463, and 20,595 against 7,305. The tangent is the
# extreme case, 67,436 against 4,140 at a single digit -- sixteen times --
# because the decimal tangent sums two series and divides them.

comptime _AMPLIFICATION_ROOM = 64
"""Bits of amplification the guard absorbs without a second attempt.

`_bits_for_digits()` carries ninety-six bits beyond the digits asked for.
Thirty-two of them answer for the two conversions and the roundings between
them, which leaves sixty-four for an amplification the first attempt did not
predict -- and almost every argument amplifies by a handful of bits, not by
sixty. Without this the loop would compute `sin(1.2)` twice to find that it
needed one more bit than it had already set aside.
"""

comptime _BINARY_FORWARD_LIMIT = 2_000_000_000_000_000_000
"""The decimal exponent past which the binary layer has no room.

The same line the inverse functions draw.
"""


def _magnitude_bits(x: BigDecimal) raises -> Int:
    """Bits of the argument's own magnitude, which the reduction spends.

    Args:
        x: The argument.

    Returns:
        What `|x|` is worth in bits when it is above one, and nought below.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    A seed for the loop below rather than a bound. Getting it right saves an
    attempt for a large argument; getting it wrong costs one.
    """
    var places = Int(x.adjusted())
    if places <= 0:
        return 0
    return (places * 10 + 2) // 3


def _width_the_answer_asked_for(
    argument: BigFloat, answer: BigFloat, runs_off: Bool
) raises -> Int:
    """Bits the function makes of the width the argument was held at.

    Args:
        argument: The argument, as the binary layer was given it.
        answer: What the binary layer returned, which is not zero.
        runs_off: True for the tangent, whose answer can be large as well as
            small.

    Returns:
        The bits to add, never negative.

    Raises:
        Error: Propagated from the exponents.

    Notes:

    An argument held to `b` bits is held to an absolute error of about
    `|x| 2^-b`. The sine and the cosine both have a derivative of at most
    one, so that is the absolute error of the answer too, and against an
    answer of size `|a|` it is a relative error of `|x| / |a| * 2^-b`. The
    bits to add are therefore what `|x| / |a|` is worth -- the argument's
    magnitude and the answer's leading zeros, which is why one quantity
    covers an argument far from zero and an argument near a multiple of
    `pi/2` both.

    The tangent is the one that also runs off: its derivative is `1 + t^2`,
    so a large answer amplifies as much as a small one, and the bits to add
    are what `|x| |t|` is worth instead.
    """
    var answer_bits = Int(answer.logb())
    var grow = -answer_bits
    if runs_off and answer_bits > 0:
        grow = answer_bits
    var needed = Int(argument.logb()) + grow
    if needed < 0:
        return 0
    return needed


def _below_the_reduction(x: BigDecimal) raises -> Bool:
    """True when the decimal series answers without reducing the argument.

    Args:
        x: The argument.

    Returns:
        True when `|x|` is at most about `pi/4`.

    Raises:
        Error: Propagated from the comparison.

    Notes:

    The reduction is the whole reason to go to binary, so an argument that
    does not need one is better left where it is: measured at 10,000 digits,
    `sin(0.7)` is 17 milliseconds in decimal against 55 in binary, while
    `sin(0.8)` -- just the other side of `pi/4` -- is 248 against 112. The
    cliff is that sharp because below `pi/4` the decimal side sums the series
    at the argument it was given.

    Only the sine has this. Its series at a small argument is as cheap as
    arithmetic gets -- the answer is nearly the argument -- while the decimal
    cosine and tangent cost three or four times as much there and lose to
    binary all the same: at 2,000 digits and an argument of `0.5`, 3.3
    milliseconds against 1.0 for the cosine and 4.5 against 2.0 for the
    tangent. So they go to binary at every argument and only the sine asks
    this question.

    The bound is three digits of `pi/4` rather than the constant itself, so
    that the test costs a word comparison and no constant at all. It sits
    just under, which hands the sliver between `0.785` and `pi/4` to the
    binary route; that route is correct there, only a shade slower than the
    decimal one would have been.
    """
    var places = Int(x.adjusted())
    if places >= 0:
        return False
    if places < -1:
        return True
    return abs(x) < BigDecimal(
        BigUInt.from_word_unsafe(BigUInt.Word(785)), 3, False
    )


def _circular_in_binary[
    binary: def(BigFloat, Int, RoundingMode) thin raises -> BigFloat,
    runs_off: Bool,
](x: BigDecimal, precision: Int) raises -> Optional[BigDecimal]:
    """`binary(x)` to `precision` digits, or nothing if it will not settle.

    Parameters:
        binary: The binary layer's own version of the function.
        runs_off: True for the tangent; see
            `_width_the_answer_asked_for()`.

    Args:
        x: The argument, which is not zero.
        precision: The significant digits wanted.

    Returns:
        The value, within `TRIG_SLACK` units of the last place, or nothing
        when the answer came out exactly zero or four attempts did not find
        a width that held. The caller then asks the decimal series.

    Raises:
        Error: Propagated from the conversions or the binary function.

    Notes:

    Each attempt reports the width it turned out to need and the next uses
    it, which is the shape `sin()` already has in decimal. Almost every
    argument settles on the first or the second.
    """
    var target = _bits_for_digits(precision, 0)
    var extra = _magnitude_bits(x)
    for _ in range(4):
        var bits = target + extra
        var argument = BigFloat.from_bigdecimal(x, bits)
        var answer = binary(argument, bits, RoundingMode.ROUND_HALF_EVEN)
        if answer.is_zero():
            return None
        var needed = _width_the_answer_asked_for(argument, answer, runs_off)
        if needed <= extra + _AMPLIFICATION_ROOM:
            return answer.to_bigdecimal_rounded(
                precision, RoundingMode.ROUND_HALF_EVEN
            )
        extra = needed
    return None


def _sine_in_binary(x: BigDecimal, precision: Int) raises -> BigDecimal:
    """`sin(x)` to `precision` digits, worked out in the binary layer.

    Args:
        x: The angle in radians.
        precision: The significant digits wanted.

    Returns:
        The sine, within `TRIG_SLACK` units of the last place, which is what
        the decimal series promises too.

    Raises:
        Error: Propagated from the conversions or the binary sine.
    """
    if (
        x.coefficient.is_zero()
        or x.adjusted() > _BINARY_FORWARD_LIMIT
        or x.adjusted() < -_BINARY_FORWARD_LIMIT
        or _below_the_reduction(x)
    ):
        return sin(x, precision)
    var answer = _circular_in_binary[bigfloat_trigonometric.sin, False](
        x, precision
    )
    if answer:
        return answer.take()
    return sin(x, precision)


def _cosine_in_binary(x: BigDecimal, precision: Int) raises -> BigDecimal:
    """`cos(x)` to `precision` digits, worked out in the binary layer.

    Args:
        x: The angle in radians.
        precision: The significant digits wanted.

    Returns:
        The cosine, within `TRIG_SLACK` units of the last place.

    Raises:
        Error: Propagated from the conversions or the binary cosine.
    """
    if (
        x.coefficient.is_zero()
        or x.adjusted() > _BINARY_FORWARD_LIMIT
        or x.adjusted() < -_BINARY_FORWARD_LIMIT
    ):
        return cos(x, precision)
    var answer = _circular_in_binary[bigfloat_trigonometric.cos, False](
        x, precision
    )
    if answer:
        return answer.take()
    return cos(x, precision)


def _tangent_in_binary(x: BigDecimal, precision: Int) raises -> BigDecimal:
    """`tan(x)` to `precision` digits, worked out in the binary layer.

    Args:
        x: The angle in radians.
        precision: The significant digits wanted.

    Returns:
        The tangent, within `TRIG_SLACK` units of the last place.

    Raises:
        Error: Propagated from the conversions or the binary tangent.
    """
    if (
        x.coefficient.is_zero()
        or x.adjusted() > _BINARY_FORWARD_LIMIT
        or x.adjusted() < -_BINARY_FORWARD_LIMIT
    ):
        return tan(x, precision)
    var answer = _circular_in_binary[bigfloat_trigonometric.tan, True](
        x, precision
    )
    if answer:
        return answer.take()
    return tan(x, precision)


# ===----------------------------------------------------------------------=== #
# The inverse functions, worked out in binary
# ===----------------------------------------------------------------------=== #
#
# The arctangent's series gains `2 log2(1/|x|)` bits a term, which for an
# argument near one is almost nothing, and the decimal side sums it without
# reducing the argument first. That is quadratic in the digits, and it shows:
# 2.25 seconds at nine hundred digits, where the binary layer -- which halves
# the argument first and sums the rest in blocks -- takes 174 microseconds.
# The arcsine and the arccosine go through the arctangent and inherit it.
#
# So the three of them hand the work over, the way `ln` and `exp` do in
# `bigdecimal.exponential`: convert the argument, evaluate in binary a little
# wider than the digits asked for, convert back, and let the deciding loop
# settle the last digit. The decimal series stays for short requests, for
# arguments the binary exponent range cannot hold, and as the second
# implementation the tests compare against.


comptime _BINARY_INVERSE_FLOOR = 24
"""The digits from which the binary route beats the decimal series.

Low, because the series it replaces is quadratic and loses early. Measured,
in microseconds at 28, 60, 150, 300 and 900 digits: the arctangent 43 against
8, 285 against 11, 4776 against 24, 44974 against 47, and 2252021 against
174.
"""

comptime _BINARY_INVERSE_LIMIT = 2_000_000_000_000_000_000
"""The decimal exponent past which the binary layer has no room.

The same line `bigdecimal.exponential` draws: a `BigFloat` holds a power of
two up to `2^63`, which is `10^2.78e18`.
"""


def _bits_for_digits(digits: Int, amplification: Int) -> Int:
    """How many bits hold `digits` decimal digits, with room to spare.

    Args:
        digits: The decimal digits, never negative.
        amplification: Bits the function multiplies the argument's own error
            by, which the caller works out from the argument.

    Returns:
        The bits: ten thirds of the digits -- over the three and a third a
        digit takes -- plus the guard and the amplification.
    """
    return (digits * 10 + 2) // 3 + 96 + amplification


def _arctangent_in_binary(x: BigDecimal, precision: Int) raises -> BigDecimal:
    """`arctan(x)` to `precision` digits, worked out in the binary layer.

    Args:
        x: The argument.
        precision: The significant digits wanted.

    Returns:
        The arctangent, within `ARCTAN_SLACK` units of the last place, which
        is what the decimal series promises too.

    Raises:
        Error: Propagated from the conversions or the binary arctangent.

    Notes:

    No room to make for the argument's own error. The derivative is
    `1/(1 + x^2)`, which is never above one, and for a small argument the
    answer is about the argument, so a relative error going in is a relative
    error of the same size coming out -- the arctangent is as well behaved as
    a function gets.
    """
    if (
        precision < _BINARY_INVERSE_FLOOR
        or x.coefficient.is_zero()
        or x.adjusted() > _BINARY_INVERSE_LIMIT
        or x.adjusted() < -_BINARY_INVERSE_LIMIT
    ):
        return arctan(x, precision)
    var bits = _bits_for_digits(precision, 0)
    var answer = bigfloat_trigonometric.arctan(
        BigFloat.from_bigdecimal(x, bits),
        bits,
        RoundingMode.ROUND_HALF_EVEN,
    )
    return answer.to_bigdecimal_rounded(precision, RoundingMode.ROUND_HALF_EVEN)


def _inverse_amplification(x: BigDecimal) raises -> Int:
    """Bits the arcsine and the arccosine make of the argument's own error.

    Args:
        x: The argument, whose magnitude is at most one.

    Returns:
        The bits, which is what `1 - |x|` is worth and nought away from the
        ends.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    Both derivatives are `1/sqrt(1 - x^2)`, which runs off at the ends, and
    the arccosine's answer runs down to nought there at the same time. An
    argument `d` below one therefore turns a relative error of `2^-bits` into
    one of `2^-bits / d`, so the bits are raised by what `d` is worth. Asking
    for them up front is what lets the first attempt settle.
    """
    var distance = bigdecimal_arithmetics.subtract(
        BigDecimal(BigUInt.one(), 0, False), abs(x)
    )
    if distance.sign or distance.coefficient.is_zero():
        return 0
    var places = -Int(distance.adjusted())
    if places <= 0:
        return 0
    return (places * 10 + 2) // 3


def _arcsine_in_binary(x: BigDecimal, precision: Int) raises -> BigDecimal:
    """`arcsin(x)` to `precision` digits, worked out in the binary layer.

    Args:
        x: The argument, whose magnitude must be at most one.
        precision: The significant digits wanted.

    Returns:
        The arcsine, within `INVERSE_TRIG_SLACK` units of the last place.

    Raises:
        ValueError: If the argument is outside `[-1, 1]`.
        Error: Propagated from the conversions or the binary arcsine.
    """
    if precision < _BINARY_INVERSE_FLOOR or x.coefficient.is_zero():
        return arcsin(x, precision)
    var bits = _bits_for_digits(precision, _inverse_amplification(x))
    var answer = bigfloat_trigonometric.arcsin(
        BigFloat.from_bigdecimal(x, bits),
        bits,
        RoundingMode.ROUND_HALF_EVEN,
    )
    return answer.to_bigdecimal_rounded(precision, RoundingMode.ROUND_HALF_EVEN)


def _arccosine_in_binary(x: BigDecimal, precision: Int) raises -> BigDecimal:
    """`arccos(x)` to `precision` digits, worked out in the binary layer.

    Args:
        x: The argument, whose magnitude must be at most one.
        precision: The significant digits wanted.

    Returns:
        The arccosine, within `INVERSE_TRIG_SLACK` units of the last place.

    Raises:
        ValueError: If the argument is outside `[-1, 1]`.
        Error: Propagated from the conversions or the binary arccosine.
    """
    if precision < _BINARY_INVERSE_FLOOR:
        return arccos(x, precision)
    var bits = _bits_for_digits(precision, _inverse_amplification(x))
    var answer = bigfloat_trigonometric.arccos(
        BigFloat.from_bigdecimal(x, bits),
        bits,
        RoundingMode.ROUND_HALF_EVEN,
    )
    return answer.to_bigdecimal_rounded(precision, RoundingMode.ROUND_HALF_EVEN)


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
    return _round_by_deciding[_arctangent_in_binary, ARCTAN_SLACK](
        x, precision, rounding_mode
    )


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

        # Past a point the reciprocal is below the last place and the series
        # has nothing to add -- and must not be asked, because its terms are
        # the reciprocal cubed and fifthed, whose scales are three and five
        # times an exponent that already reaches `10^18`. Lining those up
        # against the sum is what exhausts memory: `arctan(10^(3*10^18))`
        # used to abort here rather than answer.
        #
        # Every rounding mode's answer is then the same mode's answer for
        # `pi/2`. The true value is `pi/2` less `1/x`, which puts it strictly
        # between the representable value below `pi/2` and `pi/2` itself, and
        # `pi/2` is irrational, so it is strictly between the same pair.
        if Int(x.adjusted()) > working_precision + 2:
            result = -half_pi if x.sign else half_pi^
        else:
            var reciprocal_x = bdec_1.true_divide(
                x, precision=working_precision
            )
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


comptime INVERSE_TRIG_SLACK = 4
"""Units in the last place `arcsin()`, `arccos()` and `arctan2()` may be off at
the width they were asked for.

Each reaches `arctan()` through a division and at most one square root, every
step rounded once at twelve guard digits, so the error that survives the final
rounding is the rounding itself. Four is what `arctan()` states, and none of
these is further off than the `arctan()` inside it.
"""


def arcsin(x: BigDecimal, precision: Int) raises -> BigDecimal:
    """Calculates the arcsine (inverse sine) of the number.

    Args:
        x: The value to take the arcsine of, in `[-1, 1]`.
        precision: The number of significant digits for the result.

    Returns:
        The arcsine of x in radians, in the range `[-π/2, π/2]`.

    Raises:
        ValueError: If `|x| > 1`, where the result would not be real.
        Error: Propagated from underlying arithmetic operations.

    Notes:

    `arcsin(x) = arctan(x / sqrt(1 - x^2))`, with `|x| = 1` taken separately
    because the quotient there is unbounded.

    The usual objection to this identity is that `1 - x^2` cancels as `|x|`
    approaches one. It does not cost anything here: both the square and the
    subtraction are exact, so the small difference that comes out is the exact
    difference, and only the square root that follows rounds at all.
    """
    comptime BUFFER_DIGITS = 12  # guard digits, not a word width
    var working_precision = precision + BUFFER_DIGITS

    var bdec_1 = BigDecimal.from_raw_components(
        BigUInt.Word(1), scale=0, sign=False
    )
    var bdec_2 = BigDecimal.from_raw_components(
        BigUInt.Word(2), scale=0, sign=False
    )

    var against_one = x.compare_absolute(bdec_1)
    if against_one > 0:
        raise ValueError(
            message="arcsin() is defined on [-1, 1].",
            function="arcsin()",
        )

    if x.is_zero():
        # `arcsin(0)` is exactly zero.
        return BigDecimal.zero()

    var result: BigDecimal
    if against_one == 0:
        # `arcsin(1) = π/2`, the one argument the identity cannot take.
        result = bigdecimal_constants.pi(
            precision=working_precision
        ).true_divide(bdec_2, precision=working_precision)
        if x.sign:
            result = -result
    else:
        var one_minus_square = bdec_1.subtract(x.multiply(x))
        var cosine = bigdecimal_exponential.sqrt_via_reciprocal_iteration(
            one_minus_square, working_precision
        )
        result = arctan(
            x.true_divide(cosine, precision=working_precision),
            working_precision,
        )

    result.round_to_precision_inplace(
        precision,
        RoundingMode.half_even(),
        remove_extra_digit_due_to_rounding=True,
        fill_zeros_to_precision=False,
    )
    return result^


def arccos(x: BigDecimal, precision: Int) raises -> BigDecimal:
    """Calculates the arccosine (inverse cosine) of the number.

    Args:
        x: The value to take the arccosine of, in `[-1, 1]`.
        precision: The number of significant digits for the result.

    Returns:
        The arccosine of x in radians, in the range `[0, π]`.

    Raises:
        ValueError: If `|x| > 1`, where the result would not be real.
        Error: Propagated from underlying arithmetic operations.

    Notes:

    `arccos(x) = 2 * arctan(sqrt((1 - x) / (1 + x)))`, rather than the shorter
    `π/2 - arcsin(x)`. Near `x = 1` the answer is small, and the shorter form
    reaches it as the difference of two values that nearly cancel, which costs
    as many digits as the answer is small. This form computes it directly: the
    quotient is near zero there, and so is the arctangent of its square root.

    Both ends are taken separately: at `x = 1` the quotient is zero and at
    `x = -1` its divisor is.
    """
    comptime BUFFER_DIGITS = 12  # guard digits, not a word width
    var working_precision = precision + BUFFER_DIGITS

    var bdec_1 = BigDecimal.from_raw_components(
        BigUInt.Word(1), scale=0, sign=False
    )
    var bdec_2 = BigDecimal.from_raw_components(
        BigUInt.Word(2), scale=0, sign=False
    )

    var against_one = x.compare_absolute(bdec_1)
    if against_one > 0:
        raise ValueError(
            message="arccos() is defined on [-1, 1].",
            function="arccos()",
        )

    var result: BigDecimal
    if against_one == 0:
        # `arccos(1)` is exactly zero and `arccos(-1)` is π.
        if x.sign:
            result = bigdecimal_constants.pi(precision=working_precision)
        else:
            return BigDecimal.zero()
    else:
        var ratio = bdec_1.subtract(x).true_divide(
            bdec_1.add(x), precision=working_precision
        )
        var tangent = bigdecimal_exponential.sqrt_via_reciprocal_iteration(
            ratio, working_precision
        )
        result = bdec_2.multiply(arctan(tangent, working_precision))

    result.round_to_precision_inplace(
        precision,
        RoundingMode.half_even(),
        remove_extra_digit_due_to_rounding=True,
        fill_zeros_to_precision=False,
    )
    return result^


def arctan2(y: BigDecimal, x: BigDecimal, precision: Int) raises -> BigDecimal:
    """Calculates the angle of the point `(x, y)` from the positive x-axis.

    Args:
        y: The ordinate of the point.
        x: The abscissa of the point.
        precision: The number of significant digits for the result.

    Returns:
        The angle in radians, in the range `(-π, π]`. It is the quadrant the
        two signs put the point in, which `arctan(y / x)` on its own cannot
        tell: that quotient loses the signs.

    Raises:
        Error: Propagated from underlying arithmetic operations.

    Notes:

    `arctan2(0, 0)` is zero. The pair carries no angle at all, and zero is
    what `math.atan2` answers; decimo has no signed zero to distinguish the
    four answers CPython gives there.
    """
    comptime BUFFER_DIGITS = 12  # guard digits, not a word width
    var working_precision = precision + BUFFER_DIGITS

    var bdec_2 = BigDecimal.from_raw_components(
        BigUInt.Word(2), scale=0, sign=False
    )

    var result: BigDecimal
    if x.is_zero():
        if y.is_zero():
            return BigDecimal.zero()
        # On the y-axis the angle is a right angle either way.
        result = bigdecimal_constants.pi(
            precision=working_precision
        ).true_divide(bdec_2, precision=working_precision)
        if y.sign:
            result = -result
    else:
        result = arctan(
            y.true_divide(x, precision=working_precision), working_precision
        )
        if x.sign:
            # Left of the y-axis the quotient's arctangent lands a half turn
            # away, on the side the ordinate's sign chooses.
            var half_turn = bigdecimal_constants.pi(precision=working_precision)
            if y.sign:
                result = result.subtract(half_turn)
            else:
                result = result.add(half_turn)

    result.round_to_precision_inplace(
        precision,
        RoundingMode.half_even(),
        remove_extra_digit_due_to_rounding=True,
        fill_zeros_to_precision=False,
    )
    return result^


def arcsin_rounded(
    x: BigDecimal, precision: Int, rounding_mode: RoundingMode
) raises -> BigDecimal:
    """Returns `arcsin(x)` rounded to `precision` digits, decided not assumed.

    Args:
        x: The value to take the arcsine of.
        precision: The number of significant digits wanted.
        rounding_mode: How to round the result.

    Returns:
        The correctly rounded value.

    Raises:
        Error: Propagated from `arcsin()`.
    """
    if x.is_zero():
        # `arcsin(0)` is exactly zero.
        return arcsin(x, precision)
    return _round_by_deciding[_arcsine_in_binary, INVERSE_TRIG_SLACK](
        x, precision, rounding_mode
    )


def arccos_rounded(
    x: BigDecimal, precision: Int, rounding_mode: RoundingMode
) raises -> BigDecimal:
    """Returns `arccos(x)` rounded to `precision` digits, decided not assumed.

    Args:
        x: The value to take the arccosine of.
        precision: The number of significant digits wanted.
        rounding_mode: How to round the result.

    Returns:
        The correctly rounded value.

    Raises:
        Error: Propagated from `arccos()`.
    """
    return _round_by_deciding[_arccosine_in_binary, INVERSE_TRIG_SLACK](
        x, precision, rounding_mode
    )


def arctan2_rounded(
    y: BigDecimal,
    x: BigDecimal,
    precision: Int,
    rounding_mode: RoundingMode,
) raises -> BigDecimal:
    """Returns `arctan2(y, x)` rounded to `precision` digits, decided.

    Args:
        y: The ordinate of the point.
        x: The abscissa of the point.
        precision: The number of significant digits wanted.
        rounding_mode: How to round the result.

    Returns:
        The correctly rounded value.

    Raises:
        Error: Propagated from `arctan2()`, and if the width doubles
            `_ZIV_LIMIT` times without settling.
    """
    var width = precision + _ZIV_START
    for _ in range(_ZIV_LIMIT):
        var settled = _settled_answer(
            arctan2(y, x, width),
            width,
            INVERSE_TRIG_SLACK,
            precision,
            rounding_mode,
        )
        if settled:
            return settled.take()
        width += width - precision
    raise Error(
        "the rounding of this angle could not be decided; the kernel is"
        " further from the true value than its stated bound allows"
    )
