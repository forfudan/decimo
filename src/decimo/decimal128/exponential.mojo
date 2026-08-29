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

"""Implements exponential functions for the Decimal128 type."""

import std.math
from std import testing
from std import time

from decimo.errors import ValueError, OverflowError, ZeroDivisionError
from decimo.decimal128.decimal128 import Decimal128
import decimo.decimal128.constants as decimal128_constants
import decimo.decimal128.special as decimal128_special
import decimo.decimal128.utility as decimal128_utility
from decimo.decimal128.wide import (
    Wide,
    Extended,
    WideValue,
    ln2_at,
    ln10_at,
    e_power_of_two_at,
    e_tenth_at,
    e_hundredth_at,
    wide_ln2,
    wide_ln10,
    fixed_from_wide,
    wide_from_fixed,
    fixed_multiply,
    fixed_divide_by_int,
    wide_e_power_of_two,
    wide_e_tenth,
    wide_e_hundredth,
    FIXED_ONE,
)

# ===----------------------------------------------------------------------=== #
# Power and root functions
# ===----------------------------------------------------------------------=== #


# ===----------------------------------------------------------------------=== #
# Deciding the rounding rather than assuming it
#
# A series carries more digits than the answer keeps, and the answer is
# rounded from them once. That is right whenever the extra digits say which
# side of the boundary the true value falls on -- and they do, except when
# the value sits almost exactly on one. Then the extra digits are the
# computation's own error and not the answer's digits at all.
#
# So each kernel states what it is trusted within, in units of the last digit
# it carries, and the conversion refuses to answer when that interval
# straddles a boundary. The caller then runs the same computation at
# `Extended`: 75 digits, forty-six of them below what `Decimal128` keeps,
# where the same interval is a billion times narrower relative to the answer.
#
# The counts below are what the operations can lose, with room to spare. They
# are not measurements of how wrong the kernels are; they are the width of
# the interval the rounding has to place, and the cost of naming them
# generously is how often the second attempt runs, which for these is once in
# a few million calls.
# ===----------------------------------------------------------------------=== #

comptime HALF = Decimal128(5, 0, 0, 1 << 16)
"""One half, the bottom of the range the logarithm series takes directly."""


comptime TWO = Decimal128(2, 0, 0, 0)
"""Two, the top of that range."""


comptime LN_SLACK = 2000
"""Units in the last place `ln` is trusted within, at 38 digits.

Forty series terms, each truncated at the fixed point's own last digit --
which is one digit coarser than the mantissa's -- with the halvings and the
two constants after them. Four hundred units covers it; this is five times
that.
"""


comptime EXP_SLACK = 500
"""Units in the last place `exp` is trusted within, at 38 digits.

A dozen series terms and up to ten table multiplications, each losing under
a unit, at a fixed point whose last digit matches the mantissa's.
"""


comptime SLACK_WIDENING = 20
"""How much larger the counts are at `Extended`.

The wider series runs twice as many terms and runs them in `WideValue`
arithmetic rather than fixed point, so each term can lose a unit of its own.
Even twenty times the narrow count is nothing beside the forty-six digits
that width has below the answer.
"""


def _slack_at[WIDTH: Int](units: Int) -> UInt256:
    """Returns a count of units in the last place, for the width in use.

    Parameters:
        WIDTH: The width the kernel is running at.

    Args:
        units: What the count is at 38 digits.

    Returns:
        The count to use.
    """
    comptime if WIDTH == 38:
        return UInt256(units)
    else:
        return UInt256(units) * UInt256(SLACK_WIDENING)


def _slack_after_cancellation[
    WIDTH: Int
](units: UInt256, largest_exponent: Int, result: WideValue[WIDTH]) -> UInt256:
    """Restates a count of units at the size of a sum that cancelled.

    Args:
        units: The count, in units of the last digit of the terms.
        largest_exponent: The exponent of the largest term that went in.
        result: The sum.

    Parameters:
        WIDTH: The width in use.

    Returns:
        The count, in units of the last digit of the sum. A sum that lost
        `k` digits to cancellation is trusted within `10^k` times as many of
        its own units as the terms were.
    """
    if result.is_zero():
        return units
    var spread = largest_exponent - result.exponent
    if spread <= 0:
        return units
    if spread > 70:
        # Nothing of the terms survived; no rounding at this width can be
        # justified, so ask for the wider one.
        return UInt256.MAX
    return units * decimal128_utility.power_of_10[DType.uint256](spread)


def _quotient_slack(numerator: UInt256, denominator: UInt256) -> UInt256:
    """Returns what a quotient of two trusted values is trusted within.

    Args:
        numerator: The count for the value being divided.
        denominator: The count for the divisor.

    Returns:
        The count for the quotient. Relative error adds, and the quotient's
        last digit can be ten times finer than either input's, so the counts
        are added, multiplied by ten, and given a unit for the division
        itself.
    """
    return (numerator + denominator) * UInt256(10) + UInt256(2)


def power(base: Decimal128, exponent: Decimal128) raises -> Decimal128:
    """Raises a Decimal128 base to an arbitrary Decimal128 exponent power.

    This function handles both integer and non-integer exponents using the
    identity x^y = e^(y * ln(x)).

    Args:
        base: The base Decimal128 value (must be positive).
        exponent: The exponent Decimal128 value (can be any value).

    Returns:
        A new Decimal128 containing the result of base^exponent.

    Raises:
        ValueError: If the base is negative with a non-integer exponent.
        ZeroDivisionError: If a reciprocal power is undefined, such as
            when evaluating `0^-0.5`.
        OverflowError: If the result overflows.
    """

    # CASE: If the exponent is integer
    if exponent.is_integer():
        try:
            return power(base, Int(exponent))
        except e:
            raise e^

    # CASE: For negative bases, only integer exponents are supported
    if base.is_negative():
        raise ValueError(
            message=(
                "Negative base with non-integer exponent results in a"
                " complex number."
            ),
            function="power()",
        )

    # CASE: If the exponent is simple fractions
    # 0.5
    if exponent == decimal128_constants.M0D5():
        try:
            return sqrt(base)
        except e:
            raise ValueError(
                message="See the above exception.",
                function="power()",
                previous_error=e^,
            )
    # -0.5
    if exponent == Decimal128(5, 0, 0, 0x80010000):
        try:
            return Decimal128.ONE() / sqrt(base)
        except e:
            raise ZeroDivisionError(
                message="See the above exception.",
                function="power()",
                previous_error=e^,
            )

    # GENERAL CASE
    # Use the identity x^y = e^(y * ln(x))
    try:
        var ln_base = ln(base)
        var product = exponent * ln_base
        return exp(product)
    except e:
        raise e^


def power(base: Decimal128, exponent: Int) raises -> Decimal128:
    """Raises a Decimal128 base to an integer power.

    Args:
        base: The base value.
        exponent: The integer power to raise base to.

    Returns:
        A new Decimal128 containing the result.

    Raises:
        ValueError: If the base is zero and the exponent is negative
            (`0^n` is undefined for `n < 0`).
        OverflowError: If an intermediate `result * current_base` step
            (binary exponentiation) or the final reciprocal
            `Decimal128.ONE() / result` (for negative exponents) does
            not fit Decimal128's 96-bit coefficient.
    """

    # Special cases
    if exponent == 0:
        # x^0 = 1 (including 0^0 = 1 by convention)
        return Decimal128.ONE()

    if exponent == 1:
        # x^1 = x
        return base

    if base.is_zero():
        # 0^n = 0 for n > 0
        if exponent > 0:
            return Decimal128.ZERO()
        else:
            # 0^n is undefined for n < 0
            raise ValueError(
                message="Zero cannot be raised to a negative power.",
                function="power()",
            )

    if base.coefficient() == 1 and base.scale() == 0:
        # 1^n = 1 for any n
        return Decimal128.ONE()

    # Handle negative exponents: x^(-n) = 1/(x^n)
    var negative_exponent = exponent < 0
    var abs_exp = exponent
    if negative_exponent:
        abs_exp = -exponent

    # Binary exponentiation for efficiency
    var result = Decimal128.ONE()
    var current_base = base

    while abs_exp > 0:
        if abs_exp & 1:  # exp_value is odd
            result = result * current_base

        abs_exp >>= 1  # exp_value = exp_value / 2

        if abs_exp > 0:
            current_base = current_base * current_base

    # For negative exponents, take the reciprocal
    if negative_exponent:
        # For 1/x, use division
        result = Decimal128.ONE() / result

    return result


def root(x: Decimal128, n: Int) raises -> Decimal128:
    """Calculates the n-th root of a Decimal128 value using Newton-Raphson method.

    Args:
        x: The Decimal128 value to compute the n-th root of.
        n: The root to compute (must be positive).

    Returns:
        A new Decimal128 containing the n-th root of x.

    Raises:
        ValueError: If `n <= 0`, if `n` is even and `x` is negative, or
            if the `n > 50` fallback path `exp(ln(x) / n)` raises (any
            underlying `exp` / `ln` failure is wrapped as `ValueError`
            with the original error attached as `previous_error`).
        OverflowError: If an intermediate Newton-Raphson step overflows
            Decimal128 capacity. In particular `power(guess, n-1)` and
            the per-iteration `n_minus_1_decimal * guess + x / pow_n_minus_1`
            combine can overflow for pathological inputs whose initial
            guess sits far from the true root.
    """
    # var t0 = time.perf_counter_ns()

    # Special cases for n
    if n <= 0:
        raise ValueError(
            message="Cannot compute non-positive root.",
            function="root()",
        )
    if n == 1:
        return x
    if n == 2:
        return sqrt(x)

    # Special cases for x
    if x.is_zero():
        return Decimal128.ZERO()
    if x.is_one():
        return Decimal128.ONE()
    if x.is_negative():
        if n % 2 == 0:
            raise ValueError(
                message="Cannot compute even root of a negative number.",
                function="root()",
            )
        # For odd roots of negative numbers, compute |x|^(1/n) and negate
        return -root(-x, n)

    # Special optimization for very large n
    if n > 50:
        # For large n, the Newton-Raphson method may converge slowly
        # Use logarithm approach directly with higher precision
        try:
            # Direct calculation: x^n = e^(ln(x)/n)
            return exp(ln(x) / Decimal128(n))
        except e:
            raise ValueError(
                message="Root computation failed.",
                function="root()",
                previous_error=e^,
            )

    # Initial guess
    # use floating point approach to quickly find a good guess
    var x_coef: UInt128 = x.coefficient()
    var x_scale = x.scale()
    var guess: Decimal128

    # For numbers with zero scale (true integers)
    if x_scale == 0:
        if n <= 8:  # 3<=n<=8
            var float_root = (
                pow(Float64(x_coef), 1 / Float64(n)) * Float64(10) ** 8
            )
            guess = Decimal128.from_uint128(
                UInt128(round(float_root)), scale=8, sign=False
            )
        elif n <= 16:
            var float_root = (
                pow(Float64(x_coef), 1 / Float64(n)) * Float64(10) ** 16
            )
            guess = Decimal128.from_uint128(
                UInt128(round(float_root)), scale=16, sign=False
            )
        else:
            var float_root = (
                pow(Float64(x_coef), 1 / Float64(n)) * Float64(10) ** 26
            )
            guess = Decimal128.from_uint128(
                UInt128(round(float_root)), scale=26, sign=False
            )

    # Otherwise, use the following formulae:
    # let divmod(scale, n) = (x, y)
    # so scale = x * n + y = (x + 1) * n + (y - n)
    #   a^(1/n) / (10^scale)^(1/n)
    # = a^(1/n) / (10^(scale/n))
    # = a^(1/n) / (10^((x + 1) * n + y - n) / n))
    # = a^(1/n) / (10^(x+1 + (y-n)/n))
    # = a^(1/n) / 10^(x+1) / 10^((y-n)/n)
    # = a^(1/n) / 10^((y/n-1) / 10^(x+1)
    else:
        var dividend = x_scale // n
        var remainder = x_scale % n
        var float_root = Float64(x_coef) ** (Float64(1) / Float64(n)) / Float64(
            10
        ) ** (Float64(remainder) / Float64(n) - 1)
        guess = Decimal128.from_uint128(
            UInt128(float_root), scale=UInt32(dividend + 1), sign=False
        )

    # var t_initial_guess = time.perf_counter_ns()

    # Newton-Raphson method for n-th root
    # Formula: x_{k+1} = ((n-1)*x_k + a/x_k^(n-1))/n
    var prev_guess = Decimal128.ZERO()
    var n_decimal = Decimal128(n)
    var n_minus_1 = n - 1
    var n_minus_1_decimal = Decimal128(n_minus_1)
    var iteration_count = 0

    # Newton-Raphson iteration
    while guess != prev_guess and iteration_count < 100:
        prev_guess = guess
        var pow_n_minus_1 = power(guess, n_minus_1)
        var sum_result = n_minus_1_decimal * guess + x / pow_n_minus_1
        guess = sum_result / n_decimal
        iteration_count += 1

    # var t_newton_raphson = time.perf_counter_ns()

    # If exact root found, remove trailing zeros after the decimal point
    # For example, root(27, 3) = 9, not 3.0000000000000
    # Exact root means that the n-th power of coefficient of guess after
    # removing trailing zeros is equal to the coefficient of xs
    var guess_coef = guess.coefficient()

    # No need to do this if the last digit of the coefficient of guess is not zero
    if guess_coef % 10 == 0:
        var num_digits_x_ceof = decimal128_utility.number_of_digits(x_coef)
        var num_digits_x_root_coef = (num_digits_x_ceof // n) + 1
        var num_digits_guess_coef = decimal128_utility.number_of_digits(
            guess_coef
        )
        var num_digits_to_decrease = (
            num_digits_guess_coef - num_digits_x_root_coef
        )

        # testing.assert_true(
        #     num_digits_to_decrease >= 0,
        #     "root of x has fewer digits than expected",
        # )
        for _ in range(num_digits_to_decrease):
            if guess_coef % 10 == 0:
                guess_coef //= 10
            else:
                break
        else:
            var guess_coef_powered = guess_coef**n
            if guess_coef_powered == x_coef:
                return Decimal128.from_uint128(
                    guess_coef,
                    scale=UInt32(guess.scale() - num_digits_to_decrease),
                    sign=False,
                )
            # `n` can be up to 50 here (the `n > 50` early-return path
            # delegates to `exp(ln(x) / n)` instead). UInt128 can only
            # represent 10^n for `n <= 38` (2^128 ~= 3.4e38), so we skip
            # this trailing-zero recovery branch for `n in 39..50` --
            # `x_coef * 10^n` would overflow UInt128 anyway, and the
            # Newton-Raphson result above is already returned correctly
            # below.
            if n <= 38 and (
                guess_coef_powered
                == x_coef * decimal128_utility.power_of_10[DType.uint128](n)
            ):
                return Decimal128.from_uint128(
                    guess_coef // 10,
                    scale=UInt32(guess.scale() - num_digits_to_decrease - 1),
                    sign=False,
                )

    # print("DEBUG: iteration_count", iteration_count)
    # var t_remove_zeros = time.perf_counter_ns()
    # print("TIME: initial guess", t_initial_guess - t0)
    # print("TIME: Newton-Raphson", t_newton_raphson - t_initial_guess)
    # print("TIME: remove zeros", t_remove_zeros - t_newton_raphson)

    return guess


def cbrt(x: Decimal128) raises -> Decimal128:
    """Computes the cube root of a Decimal128 value.

    Convenience wrapper for `root(x, 3)`. Unlike `sqrt()`, `cbrt()` is
    well-defined for negative values: `cbrt(Decimal128("-8"))` returns
    `-2`, since `root()` already supports odd roots of negatives.

    Args:
        x: The Decimal128 value to compute the cube root of.

    Returns:
        A new Decimal128 containing the cube root of x.

    Raises:
        OverflowError: If a Newton-Raphson intermediate inside
            `root()` overflows Decimal128 capacity. None of `root()`'s
            `ValueError` paths apply when `n` is hardcoded to `3`
            (`n <= 0` is false, `n` is odd so even-root-of-negative
            does not trigger, and the `n > 50` `exp(ln(x)/n)` fallback
            is not reached), so `OverflowError` is the only error that
            can actually surface here. `cbrt` is still declared
            `raises` so that any future regression in `root()` would
            propagate rather than be silently masked.
    """
    return root(x, 3)


def sqrt(x: Decimal128) raises -> Decimal128:
    """Computes the square root of a Decimal128 value.

    Args:
        x: The Decimal128 value to compute the square root of.

    Returns:
        The square root of x, correctly rounded.

    Raises:
        ValueError: If `x` is negative.

    Notes:
        By integer square root rather than by Newton in `Decimal128`, which
        rounded to 28 digits at every iteration and was wrong in 18 of 80
        random cases.

        The coefficient is scaled so that its integer square root has the
        digits the answer needs, and `isqrt` decides the answer exactly: the
        true root lies between `r` and `r + 1` whenever the scaled value is
        not a perfect square, so the last digit of `r` says what the
        discarded tail would -- once `r` is nudged off `0` and `5`, where a
        half-way mode would otherwise read a tie that is not there. The same
        argument as `BigDecimal.sqrt`.
    """
    if x.is_negative():
        raise ValueError(
            message="Cannot compute square root of a negative number.",
            function="sqrt()",
        )
    if x.is_zero():
        return Decimal128.ZERO()

    var coefficient = x.coefficient()
    var scale = Int(x.scale())
    var digits = decimal128_utility.number_of_digits(coefficient)

    # Scale up so that the root lands on 30 digits -- one more than the answer
    # keeps, since `isqrt` truncates and that last digit is what says which
    # way to round. The shift is kept even with the scale so that the halved
    # exponent is whole.
    var shift = 59 - digits
    if (shift + scale) % 2 != 0:
        shift += 1
    var target_scale = (shift + scale) // 2

    var scaled = UInt256(coefficient) * decimal128_utility.power_of_10[
        DType.uint256
    ](shift)
    var root = decimal128_utility.isqrt_u256(scaled)
    var exact = root * root == scaled
    if not exact and root % UInt256(5) == UInt256(0):
        # Neither `0` nor `5` in the last place, so no mode reads a tie that
        # the true root does not sit on.
        root += UInt256(1)

    # Down to what `Decimal128` holds, in a single rounding: the answer keeps
    # at most 29 digits and a scale of at most 28, and rounding for one and
    # then the other can hand the second a tie the true root does not sit on.
    var root_digits = decimal128_utility.number_of_digits(root)
    var drop = 0
    if root_digits > 29:
        drop = root_digits - 29
    if target_scale - drop > Decimal128.MAX_SCALE:
        drop = target_scale - Decimal128.MAX_SCALE
    if drop >= root_digits:
        return Decimal128.ZERO()
    if drop > 0:
        var kept = decimal128_utility.round_to_keep_first_n_digits(
            root, False, root_digits - drop
        )
        # 29 digits reach `9.9E+28` where the type stops at `7.9E+28`, so one
        # more may have to go -- from the original root, keeping this a
        # single rounding.
        if kept > Decimal128.MAX_AS_UINT256:
            drop += 1
            kept = decimal128_utility.round_to_keep_first_n_digits(
                root, False, root_digits - drop
            )
        if kept * decimal128_utility.power_of_10[DType.uint256](drop) != root:
            exact = False
        root = kept
        target_scale -= drop

    # Bring the pair into what `Decimal128` holds: a scale of at most 28 and
    # a coefficient of at most 96 bits.
    # A carry can push the root into another digit; that value is exact, so
    # shortening it again loses nothing.
    while root > Decimal128.MAX_AS_UINT256:
        if target_scale == 0:
            raise OverflowError(
                message="Square root does not fit in Decimal128.",
                function="sqrt()",
            )
        root //= UInt256(10)
        target_scale -= 1

    # An exact root keeps its own length: `sqrt(4)` is two, not
    # 2.0000000000000000000000000000. An inexact one keeps its zeros, which
    # are digits of the answer: `sqrt(99)` ends `...82100` and goes on.
    while exact and target_scale > 0 and root % UInt256(10) == UInt256(0):
        root //= UInt256(10)
        target_scale -= 1

    return Decimal128.from_uint128(UInt128(root), UInt32(target_scale), False)


def exp(x: Decimal128) raises -> Decimal128:
    """Calculates e^x for a Decimal128 value.

    Args:
        x: The exponent.

    Returns:
        E raised to x, correctly rounded.

    Raises:
        OverflowError: If the result is larger than `Decimal128` holds, which
            is anything above about 66.54.

    Notes:
        `|x|` is split into a whole part, its first two decimal digits, and
        what is left below 0.01:

            exp(x) = e^n * e^(d1/10) * e^(d2/100) * exp(residual)

        The three factors are read from a table and the residual takes about
        a dozen series terms. The answer is rounded once, at the end, and
        only if the digits below it say which way it goes; when they do not,
        the whole thing runs again at `Extended`.
    """
    if x.is_zero():
        return Decimal128.ONE()
    if x > Decimal128.from_int(value=6654, scale=UInt32(2)):
        raise OverflowError(
            message=(
                "x is too large (must be <= 66.54). Consider using"
                " BigDecimal type."
            ),
            function="exp()",
        )

    var narrow = _exp_at[38](x)
    var decided = narrow[0].to_decimal_decided(narrow[1])
    if decided:
        return decided.value()

    var wide = _exp_at[75](x)
    var settled = wide[0].to_decimal_decided(wide[1])
    if settled:
        return settled.value()
    return wide[0].to_decimal()


def _exp_at[
    WIDTH: Int
](x: Decimal128) raises -> Tuple[WideValue[WIDTH], UInt256]:
    """Returns `exp(x)` at the given width, with how far it may be off.

    Parameters:
        WIDTH: The width to compute at.

    Args:
        x: The exponent.

    Returns:
        The value, and the units in the last place of its mantissa that the
        computation is trusted within.

    Raises:
        Error: Propagated from the arithmetic.
    """
    var magnitude = _exp_of_magnitude_at[WIDTH](
        WideValue[WIDTH].from_decimal(abs(x))
    )
    var slack = _slack_at[WIDTH](EXP_SLACK)
    if not x.is_negative():
        return (magnitude^, slack)
    # A reciprocal keeps the relative error and adds its own unit; the
    # mantissa it lands on can be ten times finer, so the count of units it
    # is trusted within grows by that much.
    var reciprocal = WideValue[WIDTH].from_int(1) / magnitude
    return (reciprocal^, slack * UInt256(10) + UInt256(2))


def _exp_of_magnitude_at[
    WIDTH: Int
](x: WideValue[WIDTH]) raises -> WideValue[WIDTH]:
    """Returns `exp(x)` for a non-negative `x`, at the given width.

    Parameters:
        WIDTH: The width to compute at.

    Args:
        x: The exponent, which must be zero or positive and at most 66.54.

    Returns:
        Its exponential.

    Raises:
        Error: Propagated from the arithmetic.
    """
    var whole = x.to_int_truncated()
    var fraction = x - WideValue[WIDTH].from_int(whole)

    # The first two decimal digits of the fraction.
    var first = fraction.scaled_by_power_of_ten(1).to_int_truncated()
    var after_first = fraction - WideValue[WIDTH](UInt256(first), -1, False)
    var second = after_first.scaled_by_power_of_ten(2).to_int_truncated()
    var residual = after_first - WideValue[WIDTH](UInt256(second), -2, False)

    var result = _exp_series_at[WIDTH](residual)
    if second != 0:
        result = result * e_hundredth_at[WIDTH](second)
    if first != 0:
        result = result * e_tenth_at[WIDTH](first)

    var bit = 0
    while whole != 0:
        if whole & 1:
            result = result * e_power_of_two_at[WIDTH](bit)
        whole >>= 1
        bit += 1
    return result^


def _exp_series_at[WIDTH: Int](r: WideValue[WIDTH]) raises -> WideValue[WIDTH]:
    """Returns `exp(r)` for a small `r`, at the given width.

    Parameters:
        WIDTH: The width to compute at.

    Args:
        r: The exponent, whose magnitude must be below 0.01.

    Returns:
        Its exponential.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:
        The plain Taylor series. With `|r| < 0.01` the terms fall by more
        than two decimal places each time, so a dozen of them cross 38
        digits and about thirty cross 75.

        At 38 digits the sum is taken in fixed point, where an addition is an
        addition and a multiplication is one multiply-high; in `WideValue`
        ops it cost thirty times as much for the same answer. The wider pass
        has no fixed-point form to run in -- a 75-digit product does not fit
        the register the trick relies on -- and pays the ordinary way, which
        is what a path taken once in a million calls should do.
    """
    if r.is_zero():
        return WideValue[WIDTH].from_int(1)

    comptime if WIDTH == 38:
        var r_fixed = fixed_from_wide(r.to_width[38]())
        var total = FIXED_ONE
        var term = FIXED_ONE
        for index in range(1, 200):
            term = fixed_divide_by_int(fixed_multiply(term, r_fixed), index)
            if term == Int256(0):
                break
            total += term
        return wide_from_fixed(total).to_width[WIDTH]()
    else:
        var total = WideValue[WIDTH].from_int(1)
        var term = WideValue[WIDTH].from_int(1)
        for index in range(1, 200):
            term = (term * r).divide_by_int(index)
            if term.is_zero():
                break
            var next = total + term
            if next.compare_absolute(total) == 0:
                break
            total = next^
        return total^


def exp_series(x: Decimal128) raises -> Decimal128:
    """Calculates e^x using Taylor series expansion.
    Do not use this function for values larger than 1, but `exp()` instead.

    Args:
        x: The exponent.

    Returns:
        A Decimal128 approximation of e^x.

    Raises:
        OverflowError: Only if the caller misuses this function with
            `|x| >= 1`. For the intended `|x| < 1` regime the partial
            sums are bounded by `e ~= 2.71828`, so the per-iteration
            `result + term` cannot overflow Decimal128 capacity.

    Notes:

    Sum terms of Taylor series: e^x = 1 + x + x²/2! + x³/3! + ...
    Because ln(2^96-1) ~= 66.54212933375474970405428366,
    the x value should be no greater than 66 to avoid overflow.
    """

    var max_terms = 500

    # For x=0, e^0 = 1
    if x.is_zero():
        return Decimal128.ONE()

    # For x with very small magnitude, just use 1+x approximation
    if abs(x) == Decimal128(1, 0, 0, 28 << 16):
        return Decimal128.ONE() + x

    # Initialize result and term
    var result = Decimal128.ONE()
    var x_power = Decimal128.ONE()  # tracks x^i across iterations
    var term: Decimal128

    # Calculate terms iteratively using precomputed factorial reciprocals.
    # term[i] = x^i / i! = x^i * factorial_reciprocal(i)
    # Replaces a per-iteration `term * x / Decimal128(i)` (one full
    # Decimal128 divide per term) with two multiplies — a ~5x speedup
    # for the typical 25-iteration convergence on x in [0, 0.25).

    for i in range(1, max_terms + 1):
        x_power = x_power * x
        term = x_power * decimal128_special.factorial_reciprocal(i)
        # Check for convergence
        if term.is_zero():
            break

        result = result + term

    return result


# ===----------------------------------------------------------------------=== #
# Logarithmic functions
# ===----------------------------------------------------------------------=== #


def ln(x: Decimal128) raises -> Decimal128:
    """Calculates the natural logarithm (ln) of a Decimal128 value.

    Args:
        x: The Decimal128 value to compute the natural logarithm of.

    Returns:
        The natural logarithm of x, correctly rounded.

    Raises:
        ValueError: If `x` is non-positive.

    Notes:
        The value is written `m * 2^p * 10^q` with `m` in `[0.5, 2)`, and

            ln(x) = ln(m) + p * ln(2) + q * ln(10)

        with `ln(m) = 2 * atanh((m - 1) / (m + 1))`, whose series converges
        on `|z| <= 1/3` here.

        The answer is rounded once, at the end, and only if the digits below
        it say which way it goes; when they do not, the whole thing runs
        again at `Extended`.
    """
    if x.is_negative() or x.is_zero():
        raise ValueError(
            message="Cannot compute logarithm of a non-positive number.",
            function="ln()",
        )
    if x.is_one():
        return Decimal128.ZERO()

    var narrow = _ln_at[38](x)
    var decided = narrow[0].to_decimal_decided(narrow[1])
    if decided:
        return decided.value()

    var wide = _ln_at[75](x)
    var settled = wide[0].to_decimal_decided(wide[1])
    if settled:
        return settled.value()
    return wide[0].to_decimal()


def _ln_at[
    WIDTH: Int
](x: Decimal128) raises -> Tuple[WideValue[WIDTH], UInt256]:
    """Returns `ln(x)` at the given width, with how far it may be off.

    Parameters:
        WIDTH: The width to compute at.

    Args:
        x: The value, which must be positive.

    Returns:
        The value, and the units in the last place of its mantissa that the
        computation is trusted within.

    Raises:
        ValueError: If `x` is not positive.
        Error: Propagated from the arithmetic.

    Notes:
        The three parts of the sum are each around one, while their total can
        be far smaller: `ln(0.9999)` is `-1E-4` from three terms of size two.
        What the series and the constants are trusted within is a count of
        units at the size of those terms, so it is restated at the size of
        the answer -- which is where the rounding reads it -- by the number
        of digits the sum cancelled away.
    """
    if x.is_negative() or x.is_zero():
        raise ValueError(
            message="Cannot compute logarithm of a non-positive number.",
            function="_ln_at()",
        )
    if x.is_one():
        return (WideValue[WIDTH](), UInt256(0))

    var m: WideValue[WIDTH]
    var p = 0
    var q = 0

    if x >= HALF and x < TWO:
        # Already where the series wants it. Taking the reduction anyway
        # would add `p * ln(2) + q * ln(10)` to a series that cancels them
        # back out: `ln(0.99999999999999)` is `-1E-14` from three terms of
        # size two, which throws away fourteen of the digits carried. Here
        # there are no terms to cancel.
        m = WideValue[WIDTH].from_decimal(x)
    else:
        # Write x as `m * 10^q` with `m` in [1, 10), by moving the point.
        var coefficient = x.coefficient()
        var digits = decimal128_utility.number_of_digits(coefficient)
        q = digits - 1 - Int(x.scale())
        m = WideValue[WIDTH](UInt256(coefficient), -(digits - 1), False)

        # And on into [1, 2), by halving. At most three halvings from
        # [1, 10), and each one is exact: the mantissa is raised a digit and
        # halved, which is a multiplication by five.
        var two = WideValue[WIDTH].from_int(2)
        while m.compare_absolute(two) >= 0:
            m = m.divide_by_int(2)
            p += 1

    var result = _ln_series_at[WIDTH](m)
    # The largest term that went in, to measure the sum against. A term that
    # is exactly zero -- `ln(10)` has one, since its `m` is exactly one --
    # carries no error and no digits, and counting its exponent would claim
    # a cancellation that never happened.
    var largest = Int.MIN
    if not result.is_zero():
        largest = result.exponent
    if p != 0:
        var term = ln2_at[WIDTH]() * WideValue[WIDTH].from_int(p)
        largest = max(largest, term.exponent)
        result = result + term
    if q != 0:
        var term = ln10_at[WIDTH]() * WideValue[WIDTH].from_int(q)
        largest = max(largest, term.exponent)
        result = result + term
    if largest == Int.MIN:
        largest = result.exponent

    var slack = _slack_after_cancellation(
        _slack_at[WIDTH](LN_SLACK), largest, result
    )
    return (result^, slack)


def _ln_series_at[WIDTH: Int](m: WideValue[WIDTH]) raises -> WideValue[WIDTH]:
    """Returns `ln(m)` for `m` in `[0.5, 2)`, at the given width.

    Parameters:
        WIDTH: The width to compute at.

    Args:
        m: The value, which must lie in `[0.5, 2)`.

    Returns:
        Its natural logarithm.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:
        `ln(m) = 2 * atanh(z)` with `z = (m - 1) / (m + 1)`, so `|z| <= 1/3`
        and each pair of terms is nine times smaller than the last: forty
        terms cross 38 digits, eighty cross 75. `m - 1` is exact, so a value
        close to one loses nothing here.

        Forty terms are worth summing in fixed point, which is what the
        first width does. Fixed point holds a fixed number of decimal
        places rather than of digits, though, and for a tiny `z` those places
        run out: at `z = 5E-15` only 23 of them are digits of `z`, and the
        answer would be 23 digits long where the caller needs 29. Below a
        thousandth the series is two or three terms anyway, and those are
        taken in the floating form, which keeps its digits wherever the value
        sits.
    """
    var one = WideValue[WIDTH].from_int(1)
    var z = (m - one) / (m + one)
    if z.is_zero():
        return WideValue[WIDTH]()

    comptime if WIDTH == 38:
        if z.exponent >= -41:
            var z_fixed = fixed_from_wide(z.to_width[38]())
            var z_squared = fixed_multiply(z_fixed, z_fixed)
            var term = z_fixed
            var total = z_fixed
            for index in range(1, 200):
                term = fixed_multiply(term, z_squared)
                if term == Int256(0):
                    break
                var contribution = fixed_divide_by_int(term, 2 * index + 1)
                if contribution == Int256(0):
                    break
                total += contribution
            return wide_from_fixed(total * Int256(2)).to_width[WIDTH]()
        return _atanh_series_at[WIDTH](z) * WideValue[WIDTH].from_int(2)
    else:
        return _atanh_series_at[WIDTH](z) * WideValue[WIDTH].from_int(2)


def _atanh_series_at[
    WIDTH: Int
](z: WideValue[WIDTH]) raises -> WideValue[WIDTH]:
    """Returns `atanh(z)` for `|z| <= 1/3`, in the floating form.

    Parameters:
        WIDTH: The width to compute at.

    Args:
        z: The argument, whose magnitude must be at most a third.

    Returns:
        Its inverse hyperbolic tangent.

    Raises:
        Error: Propagated from the arithmetic.
    """
    var z_squared = z * z
    var term = z.copy()
    var total = z.copy()
    for index in range(1, 400):
        term = term * z_squared
        if term.is_zero():
            break
        var contribution = total + term.divide_by_int(2 * index + 1)
        if contribution.compare_absolute(total) == 0:
            break
        total = contribution^
    return total^


def ln_series(z: Decimal128) raises -> Decimal128:
    """Calculates ln(1+z) using Taylor series expansion at 1.
    For best accuracy, |z| should be small (< 0.5).

    Args:
        z: The value to compute ln(1+z) for.

    Returns:
        A Decimal128 approximation of ln(1+z).

    Raises:
        OverflowError: Only if the caller misuses this function with
            `|z|` outside the convergent regime. For the intended
            `|z| < 0.5` use the partial sums are bounded by `ln(1.5)`
            in magnitude, so the per-iteration combine cannot
            overflow Decimal128 capacity.

    Notes:
        Uses the series: ln(1+z) = z - z²/2 + z³/3 - z⁴/4 + ...
        This series converges fastest when |z| is small.
    """

    # print("DEBUG: ln_series(z) called with z =", z)

    var max_terms = 500

    # For z=0, ln(1+z) = ln(1) = 0
    if z.is_zero():
        return Decimal128.ZERO()

    # For z with very small magnitude, just use z approximation
    if abs(z) == Decimal128(1, 0, 0, 28 << 16):
        return z

    # Initialize result and term
    var result = Decimal128.ZERO()
    var term = z
    var neg: Bool = False

    # Calculate terms iteratively
    # term[i] = (-1)^(i+1) * z^i / i

    for i in range(1, max_terms + 1):
        if neg:
            result = result - term
        else:
            result = result + term

        neg = not neg  # Alternate sign

        if i <= 20:
            term = term * z * decimal128_constants.N_DIVIDE_NEXT(i)
        else:
            term = term * z * Decimal128(i) / Decimal128(i + 1)

        # Check for convergence
        if term.is_zero():
            # print("DEBUG: i = ", i)
            break

    # print("DEBUG: result =", result)

    return result


def log(x: Decimal128, base: Decimal128) raises -> Decimal128:
    """Calculates the logarithm of a Decimal128 with respect to an arbitrary base.

    Args:
        x: The Decimal128 value to compute the logarithm of.
        base: The base of the logarithm (must be positive and not equal to 1).

    Returns:
        A Decimal128 approximation of log_base(x).

    Raises:
        ValueError: If `x` is non-positive, `base` is non-positive, or
            `base == 1`.
        OverflowError: If `base` is positive but extremely close to 1
            (e.g. `1 + 1e-28`), in which case `ln(base)` is on the
            order of `1e-28` and the final `ln(x) / ln(base)` divide
            can overflow Decimal128 capacity for non-trivial `x`.

    Notes:

    This implementation uses the identity log_base(x) = ln(x) / ln(base).
    """
    # Special cases: x <= 0
    if x.is_negative() or x.is_zero():
        raise ValueError(
            message="Cannot compute logarithm of a non-positive number.",
            function="log()",
        )

    # Special cases: base <= 0
    if base.is_negative() or base.is_zero():
        raise ValueError(
            message="Cannot use non-positive base for logarithm.",
            function="log()",
        )

    # Special case: base = 1
    if base.is_one():
        raise ValueError(
            message="Cannot use base 1 for logarithm.",
            function="log()",
        )

    # Special case: x = 1
    # log_base(1) = 0 for any valid base
    if x.is_one():
        return Decimal128.ZERO()

    # Special case: x = base
    # log_base(base) = 1 for any valid base
    if x == base:
        return Decimal128.ONE()

    # Special case: base = 10
    if base == Decimal128(10, 0, 0, 0):
        return log10(x)

    # log_base(x) = ln(x) / ln(base), with both logarithms and the division
    # taken in `Wide`: rounding each to 28 digits first made `log_2(8)` come
    # out as 2.9999999999999999999999999999.
    var numerator = _ln_at[38](x)
    var denominator = _ln_at[38](base)
    var quotient = numerator[0] / denominator[0]

    # A whole answer is a fact about the two numbers, not something the
    # quotient can settle: at any width it is three-and-a-hair or
    # three-less-a-hair. So the quotient names the candidate and an exact
    # power decides it, as `log10` already does for powers of ten.
    var candidate = quotient.to_int_nearest()
    if candidate != 0:
        try:
            if power(base, candidate) == x:
                return Decimal128.from_int(candidate)
        except:
            pass

    var decided = quotient.to_decimal_decided(
        _quotient_slack(numerator[1], denominator[1])
    )
    if decided:
        return decided.value()

    var wide_numerator = _ln_at[75](x)
    var wide_denominator = _ln_at[75](base)
    var wide_quotient = wide_numerator[0] / wide_denominator[0]
    var settled = wide_quotient.to_decimal_decided(
        _quotient_slack(wide_numerator[1], wide_denominator[1])
    )
    if settled:
        return settled.value()
    return wide_quotient.to_decimal()


def log10(x: Decimal128) raises -> Decimal128:
    """Calculates the base-10 logarithm (log10) of a Decimal128 value.

    Args:
        x: The Decimal128 value to compute the base-10 logarithm of.

    Returns:
        A Decimal128 approximation of log10(x).

    Raises:
        ValueError: If `x` is non-positive.

    Notes:
        This implementation uses the identity log10(x) = ln(x) / ln(10).
        For any positive Decimal128 input the result magnitude is
        bounded by `|log10(MAX)| < 29`, so no `OverflowError` path
        exists.
    """
    # Special cases: x <= 0
    if x.is_negative() or x.is_zero():
        raise ValueError(
            message="Cannot compute logarithm of a non-positive number.",
            function="log10()",
        )

    var x_scale = x.scale()
    var x_coef = x.coefficient()

    # Sepcial case: x = 10^(-n)
    if x_coef == 1:
        # Special case: x = 1
        if x_scale == 0:
            return Decimal128.ZERO()
        else:
            return Decimal128(UInt32(x_scale), 0, 0, 0x8000_0000)

    var ten_to_power_of_scale = decimal128_utility.power_of_10_unsafe[
        DType.uint128
    ](x_scale)

    # Special case: x = 1.00...0
    if x_coef == ten_to_power_of_scale:
        return Decimal128.ZERO()

    # Special case: x = 10^n (exact integer power of 10)
    # x is a power of 10 iff its integer part equals 10^(ndigits-1).
    # Use `number_of_digits()` instead of a per-digit divide-by-10 loop.
    if x_coef % ten_to_power_of_scale == 0:
        var integral_part = x_coef // ten_to_power_of_scale
        var n_digits = decimal128_utility.number_of_digits(integral_part)
        var pow10_check = decimal128_utility.power_of_10_unsafe[DType.uint128](
            n_digits - 1
        )
        if integral_part == pow10_check:
            return Decimal128(UInt32(n_digits - 1), 0, 0, 0)

    # log10(x) = ln(x) / ln(10), with the division taken at the working
    # width as well: dividing two rounded 28-digit values is one more
    # rounding, and it showed in 18 of 80 random cases before this.
    var narrow = _ln_at[38](x)
    var quotient = narrow[0] / ln10_at[38]()
    var decided = quotient.to_decimal_decided(_quotient_slack(narrow[1], 1))
    if decided:
        return decided.value()

    var wide = _ln_at[75](x)
    var wide_quotient = wide[0] / ln10_at[75]()
    var settled = wide_quotient.to_decimal_decided(_quotient_slack(wide[1], 1))
    if settled:
        return settled.value()
    return wide_quotient.to_decimal()
