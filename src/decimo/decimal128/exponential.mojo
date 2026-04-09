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

"""Implements exponential functions for the Decimal128 type."""

import std.math
from std import testing
from std import time

from decimo.errors import ValueError, OverflowError, ZeroDivisionError
import decimo.decimal128.constants
import decimo.decimal128.special
import decimo.decimal128.utility

# ===----------------------------------------------------------------------=== #
# Power and root functions
# ===----------------------------------------------------------------------=== #


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
    if exponent == decimo.decimal128.constants.M0D5():
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
        ValueError: If the base is zero and exponent is negative.
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
        ValueError: If n is non-positive or the input is invalid.
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
        var num_digits_x_ceof = decimo.decimal128.utility.number_of_digits(
            x_coef
        )
        var num_digits_x_root_coef = (num_digits_x_ceof // n) + 1
        var num_digits_guess_coef = decimo.decimal128.utility.number_of_digits(
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
            if (
                guess_coef_powered
                == x_coef
                * decimo.decimal128.utility.power_of_10[DType.uint128](n)
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


def sqrt(x: Decimal128) raises -> Decimal128:
    """Computes the square root of a Decimal128 value using Newton-Raphson method.

    Args:
        x: The Decimal128 value to compute the square root of.

    Returns:
        A new Decimal128 containing the square root of x.

    Raises:
        ValueError: If x is negative.
    """
    # Special cases
    if x.is_negative():
        raise ValueError(
            message="Cannot compute square root of a negative number.",
            function="sqrt()",
        )

    if x.is_zero():
        return Decimal128.ZERO()

    # Initial guess
    # use floating point approach to quickly find a good guess
    var x_coef: UInt128 = x.coefficient()
    var x_scale = x.scale()
    var guess: Decimal128

    # For numbers with zero scale (true integers)
    if x_scale == 0:
        var float_sqrt = std.math.sqrt(Float64(x_coef))
        guess = Decimal128.from_uint128(UInt128(round(float_sqrt)))

    # For numbers with even scale
    elif x_scale % 2 == 0:
        var float_sqrt = std.math.sqrt(Float64(x_coef))
        guess = Decimal128.from_uint128(
            UInt128(float_sqrt), scale=UInt32(x_scale >> 1), sign=False
        )
        # print("DEBUG: scale is even")

    # For numbers with odd scale
    else:
        var float_sqrt = std.math.sqrt(Float64(x_coef)) * Float64(3.15625)
        guess = Decimal128.from_uint128(
            UInt128(float_sqrt), scale=UInt32((x_scale + 1) >> 1), sign=False
        )
        # print("DEBUG: scale is odd")

    # print("DEBUG: initial guess", guess)
    # testing.assert_false(guess.is_zero(), "Initial guess should not be zero")

    # Newton-Raphson iterations
    # x_n+1 = (x_n + S/x_n) / 2
    var prev_guess = Decimal128.ZERO()
    var iteration_count = 0

    # Iterate until guess converges or max iterations reached
    # max iterations is set to 100 to avoid infinite loop
    # log2(1e18) ~= 60, so 100 iterations should be enough
    while guess != prev_guess and iteration_count < 100:
        prev_guess = guess
        var division_result = x / guess
        var sum_result = guess + division_result
        guess = sum_result / Decimal128(2, 0, 0, 0, False)
        iteration_count += 1

        # print("------------------------------------------------------")
        # print("DEBUG: iteration_count", iteration_count)
        # print("DEBUG: prev guess", prev_guess)
        # print("DEBUG: new guess ", guess)

    # print("DEBUG: iteration_count", iteration_count)

    # If exact square root found, remove trailing zeros after the decimal point
    # For example, sqrt(81) = 9, not 9.000000
    # For example, sqrt(100.0000) = 10.00 not 10.000000
    # Exact square means that the squared coefficient of guess after removing
    # trailing zeros is equal to the coefficient of x

    var guess_coef = guess.coefficient()

    # No need to do this if the last digit of the coefficient of guess is not zero
    if guess_coef % 10 == 0:
        var num_digits_x_ceof = decimo.decimal128.utility.number_of_digits(
            x_coef
        )
        var num_digits_x_sqrt_coef = (num_digits_x_ceof >> 1) + 1
        var num_digits_guess_coef = decimo.decimal128.utility.number_of_digits(
            guess_coef
        )
        var num_digits_to_decrease = (
            num_digits_guess_coef - num_digits_x_sqrt_coef
        )

        # testing.assert_true(
        #     num_digits_to_decrease >= 0,
        #     "sqrt of x has fewer digits than expected",
        # )
        for _ in range(num_digits_to_decrease):
            if guess_coef % 10 == 0:
                guess_coef //= 10
            else:
                break
        else:
            # print("DEBUG: guess", guess)
            # print("DEBUG: guess_coef after removing trailing zeros", guess_coef)
            var guess_coef_squared = guess_coef * guess_coef
            if (guess_coef_squared == x_coef) or (
                guess_coef_squared == x_coef * 10
            ):
                return Decimal128.from_uint128(
                    guess_coef,
                    scale=UInt32(guess.scale() - num_digits_to_decrease),
                    sign=False,
                )

    return guess


# ===----------------------------------------------------------------------=== #
# Exponential functions
# ===----------------------------------------------------------------------=== #


def exp(x: Decimal128) raises -> Decimal128:
    """Calculates e^x for any Decimal128 value using optimized range reduction.
    x should be no greater than 66 to avoid overflow.

    Args:
        x: The exponent.

    Returns:
        A Decimal128 approximation of e^x.

    Raises:
        OverflowError: If x is too large (> 66.54).

    Notes:
        Because ln(2^96-1) ~= 66.54212933375474970405428366,
        the x value should be no greater than 66 to avoid overflow.
    """

    if x > Decimal128.from_int(value=6654, scale=UInt32(2)):
        raise OverflowError(
            message=(
                "x is too large (must be <= 66.54). Consider using"
                " BigDecimal type."
            ),
            function="exp()",
        )

    # Handle special cases
    if x.is_zero():
        return Decimal128.ONE()

    if x.is_negative():
        return Decimal128.ONE() / exp(-x)

    # For x < 1, use Taylor series expansion
    # For x > 1, use optimized range reduction with smaller chunks
    # Yuhao's notes:
    # e^50 is more accurate than (e^2)^25 if e^2 needs to be approximated
    #   because estimating e^x would introduce errors
    # e^50 is less accurate than (e^2)^25 if e^2 is precomputed
    #   because too many multiplications would introduce errors
    # So we need to find a way to reduce both the number of multiplications
    #   and the error introduced by approximating e^x
    # This helps improve accuracy as well as speed.
    # My solution is to factorize x into a combination of integers and
    #   a fractional part smaller than 1.
    # Then use precomputed e^integer values to calculate e^x
    # For example, e^59.12 = (e^50)^1 * (e^5)^1 * (e^2)^2 * e^0.12
    # This way, we just need to do 4 multiplications instead of 59.
    # The fractional part is then calculated using the series expansion.
    # Because the fractional part is <1, the series converges quickly.

    var exp_chunk: Decimal128
    var remainder: Decimal128
    var num_chunks: Int = 1
    var x_int = Int(x)

    if x.is_one():
        return decimo.decimal128.constants.E()

    elif x_int < 1:
        var M0D5 = decimo.decimal128.constants.M0D5()
        var M0D25 = decimo.decimal128.constants.M0D25()

        if x < M0D25:  # 0 < x < 0.25
            return exp_series(x)

        elif x < M0D5:  # 0.25 <= x < 0.5
            exp_chunk = decimo.decimal128.constants.E0D25()
            remainder = x - M0D25

        else:  # 0.5 <= x < 1
            exp_chunk = decimo.decimal128.constants.E0D5()
            remainder = x - M0D5

    elif x_int == 1:  # 1 <= x < 2, chunk = 1
        exp_chunk = decimo.decimal128.constants.E()
        remainder = x - x_int

    elif x_int == 2:  # 2 <= x < 3, chunk = 2
        exp_chunk = decimo.decimal128.constants.E2()
        remainder = x - x_int

    elif x_int == 3:  # 3 <= x < 4, chunk = 3
        exp_chunk = decimo.decimal128.constants.E3()
        remainder = x - x_int

    elif x_int == 4:  # 4 <= x < 5, chunk = 4
        exp_chunk = decimo.decimal128.constants.E4()
        remainder = x - x_int

    elif x_int == 5:  # 5 <= x < 6, chunk = 5
        exp_chunk = decimo.decimal128.constants.E5()
        remainder = x - x_int

    elif x_int == 6:  # 6 <= x < 7, chunk = 6
        exp_chunk = decimo.decimal128.constants.E6()
        remainder = x - x_int

    elif x_int == 7:  # 7 <= x < 8, chunk = 7
        exp_chunk = decimo.decimal128.constants.E7()
        remainder = x - x_int

    elif x_int == 8:  # 8 <= x < 9, chunk = 8
        exp_chunk = decimo.decimal128.constants.E8()
        remainder = x - x_int

    elif x_int == 9:  # 9 <= x < 10, chunk = 9
        exp_chunk = decimo.decimal128.constants.E9()
        remainder = x - x_int

    elif x_int == 10:  # 10 <= x < 11, chunk = 10
        exp_chunk = decimo.decimal128.constants.E10()
        remainder = x - x_int

    elif x_int == 11:  # 11 <= x < 12, chunk = 11
        exp_chunk = decimo.decimal128.constants.E11()
        remainder = x - x_int

    elif x_int == 12:  # 12 <= x < 13, chunk = 12
        exp_chunk = decimo.decimal128.constants.E12()
        remainder = x - x_int

    elif x_int == 13:  # 13 <= x < 14, chunk = 13
        exp_chunk = decimo.decimal128.constants.E13()
        remainder = x - x_int

    elif x_int == 14:  # 14 <= x < 15, chunk = 14
        exp_chunk = decimo.decimal128.constants.E14()
        remainder = x - x_int

    elif x_int == 15:  # 15 <= x < 16, chunk = 15
        exp_chunk = decimo.decimal128.constants.E15()
        remainder = x - x_int

    elif x_int < 32:  # 16 <= x < 32, chunk = 16
        num_chunks = x_int >> 4
        exp_chunk = decimo.decimal128.constants.E16()
        remainder = x - (num_chunks << 4)

    else:  # chunk = 32
        num_chunks = x_int >> 5
        exp_chunk = decimo.decimal128.constants.E32()
        remainder = x - (num_chunks << 5)

    # Calculate e^(chunk * num_chunks) = (e^chunk)^num_chunks
    var exp_main = power(exp_chunk, num_chunks)

    # Calculate e^remainder by calling exp() again
    # If it is <1, then use Taylor's series
    var exp_remainder = exp(remainder)

    # Combine: e^x = e^(main+remainder) = e^main * e^remainder
    return exp_main * exp_remainder


def exp_series(x: Decimal128) raises -> Decimal128:
    """Calculates e^x using Taylor series expansion.
    Do not use this function for values larger than 1, but `exp()` instead.

    Args:
        x: The exponent.

    Returns:
        A Decimal128 approximation of e^x.

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
    var term = Decimal128.ONE()
    var term_add_on: Decimal128

    # Calculate terms iteratively
    # term[x] = x^i / i!
    # term[x-1] = x^{i-1} / (i-1)!
    # => term[x] / term[x-1] = x / i

    for i in range(1, max_terms + 1):
        term_add_on = x / Decimal128(i)

        term = term * term_add_on
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
        A Decimal128 approximation of ln(x).

    Raises:
        ValueError: If x is non-positive.

    Notes:
        This implementation uses range reduction to improve accuracy and performance.
    """

    # print("DEBUG: ln(x) called with x =", x)

    # Handle special cases
    if x.is_negative() or x.is_zero():
        raise ValueError(
            message="Cannot compute logarithm of a non-positive number.",
            function="ln()",
        )

    if x.is_one():
        return Decimal128.ZERO()

    # Special cases for common values
    if x == decimo.decimal128.constants.E():
        return Decimal128.ONE()

    # For values close to 1, use series expansion directly
    if Decimal128(95, 0, 0, 2 << 16) <= x <= Decimal128(105, 0, 0, 2 << 16):
        return ln_series(x - Decimal128.ONE())

    # For all other values, use range reduction
    # ln(x) = ln(m * 2^p * 10^q) = ln(m) + p*ln(2) + q*ln(10), where 1 <= m < 2

    var m: Decimal128 = x
    var p: Int = 0
    var q: Int = 0

    # Step 1: handle powers of 10 for large values
    if x >= decimo.decimal128.constants.M10():
        # Repeatedly divide by 10 until m < 10
        while m >= decimo.decimal128.constants.M10():
            m = m / decimo.decimal128.constants.M10()
            q += 1
    elif x < Decimal128(1, 0, 0, 1 << 16):
        # Repeatedly multiply by 10 until m >= 0.1
        while m < Decimal128(1, 0, 0, 1 << 16):
            m = m * decimo.decimal128.constants.M10()
            q -= 1

    # Now 0.1 <= m < 10
    # Step 2: normalize to [0.5, 2) using powers of 2
    if m >= decimo.decimal128.constants.M2():
        # Repeatedly divide by 2 until m < 2
        while m >= decimo.decimal128.constants.M2():
            m = m / decimo.decimal128.constants.M2()
            p += 1
    elif m < Decimal128(5, 0, 0, 1 << 16):
        # Repeatedly multiply by 2 until m >= 0.5
        while m < Decimal128(5, 0, 0, 1 << 16):
            m = m * decimo.decimal128.constants.M2()
            p -= 1

    # Now 0.5 <= m < 2
    var ln_m: Decimal128

    # Use precomputed values and series expansion for accuracy and performance
    if m < Decimal128.ONE():
        # For 0.5 <= m < 1
        if m >= Decimal128(9, 0, 0, 1 << 16):
            ln_m = (
                ln_series(
                    (m - Decimal128(9, 0, 0, 1 << 16))
                    * decimo.decimal128.constants.INV0D9()
                )
                + decimo.decimal128.constants.LN0D9()
            )
        elif m >= Decimal128(8, 0, 0, 1 << 16):
            ln_m = (
                ln_series(
                    (m - Decimal128(8, 0, 0, 1 << 16))
                    * decimo.decimal128.constants.INV0D8()
                )
                + decimo.decimal128.constants.LN0D8()
            )
        elif m >= Decimal128(7, 0, 0, 1 << 16):
            ln_m = (
                ln_series(
                    (m - Decimal128(7, 0, 0, 1 << 16))
                    * decimo.decimal128.constants.INV0D7()
                )
                + decimo.decimal128.constants.LN0D7()
            )
        elif m >= Decimal128(6, 0, 0, 1 << 16):
            ln_m = (
                ln_series(
                    (m - Decimal128(6, 0, 0, 1 << 16))
                    * decimo.decimal128.constants.INV0D6()
                )
                + decimo.decimal128.constants.LN0D6()
            )
        else:  # 0.5 <= m < 0.6
            ln_m = (
                ln_series(
                    (m - Decimal128(5, 0, 0, 1 << 16))
                    * decimo.decimal128.constants.INV0D5()
                )
                + decimo.decimal128.constants.LN0D5()
            )

    else:
        # For 1 < m < 2
        if m < Decimal128(11, 0, 0, 1 << 16):  # 1 < m < 1.1
            ln_m = ln_series(m - Decimal128.ONE())
        elif m < Decimal128(12, 0, 0, 1 << 16):  # 1.1 <= m < 1.2
            ln_m = (
                ln_series(
                    (m - Decimal128(11, 0, 0, 1 << 16))
                    * decimo.decimal128.constants.INV1D1()
                )
                + decimo.decimal128.constants.LN1D1()
            )
        elif m < Decimal128(13, 0, 0, 1 << 16):  # 1.2 <= m < 1.3
            ln_m = (
                ln_series(
                    (m - Decimal128(12, 0, 0, 1 << 16))
                    * decimo.decimal128.constants.INV1D2()
                )
                + decimo.decimal128.constants.LN1D2()
            )
        elif m < Decimal128(14, 0, 0, 1 << 16):  # 1.3 <= m < 1.4
            ln_m = (
                ln_series(
                    (m - Decimal128(13, 0, 0, 1 << 16))
                    * decimo.decimal128.constants.INV1D3()
                )
                + decimo.decimal128.constants.LN1D3()
            )
        elif m < Decimal128(15, 0, 0, 1 << 16):  # 1.4 <= m < 1.5
            ln_m = (
                ln_series(
                    (m - Decimal128(14, 0, 0, 1 << 16))
                    * decimo.decimal128.constants.INV1D4()
                )
                + decimo.decimal128.constants.LN1D4()
            )
        elif m < Decimal128(16, 0, 0, 1 << 16):  # 1.5 <= m < 1.6
            ln_m = (
                ln_series(
                    (m - Decimal128(15, 0, 0, 1 << 16))
                    * decimo.decimal128.constants.INV1D5()
                )
                + decimo.decimal128.constants.LN1D5()
            )
        elif m < Decimal128(17, 0, 0, 1 << 16):  # 1.6 <= m < 1.7
            ln_m = (
                ln_series(
                    (m - Decimal128(16, 0, 0, 1 << 16))
                    * decimo.decimal128.constants.INV1D6()
                )
                + decimo.decimal128.constants.LN1D6()
            )
        elif m < Decimal128(18, 0, 0, 1 << 16):  # 1.7 <= m < 1.8
            ln_m = (
                ln_series(
                    (m - Decimal128(17, 0, 0, 1 << 16))
                    * decimo.decimal128.constants.INV1D7()
                )
                + decimo.decimal128.constants.LN1D7()
            )
        elif m < Decimal128(19, 0, 0, 1 << 16):  # 1.8 <= m < 1.9
            ln_m = (
                ln_series(
                    (m - Decimal128(18, 0, 0, 1 << 16))
                    * decimo.decimal128.constants.INV1D8()
                )
                + decimo.decimal128.constants.LN1D8()
            )
        else:  # 1.9 <= m < 2
            ln_m = (
                ln_series(
                    (m - Decimal128(19, 0, 0, 1 << 16))
                    * decimo.decimal128.constants.INV1D9()
                )
                + decimo.decimal128.constants.LN1D9()
            )

    # Combine result: ln(x) = ln(m) + p*ln(2) + q*ln(10)
    var result = ln_m

    # Add power of 2 contribution
    if p != 0:
        result = result + Decimal128(p) * decimo.decimal128.constants.LN2()

    # Add power of 10 contribution
    if q != 0:
        result = result + Decimal128(q) * decimo.decimal128.constants.LN10()

    return result


def ln_series(z: Decimal128) raises -> Decimal128:
    """Calculates ln(1+z) using Taylor series expansion at 1.
    For best accuracy, |z| should be small (< 0.5).

    Args:
        z: The value to compute ln(1+z) for.

    Returns:
        A Decimal128 approximation of ln(1+z).

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
            term = term * z * decimo.decimal128.constants.N_DIVIDE_NEXT(i)
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
        ValueError: If x is non-positive, base is non-positive, or base is 1.

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

    # Use the identity: log_base(x) = ln(x) / ln(base)
    var ln_x = ln(x)
    var ln_base = ln(base)

    return ln_x / ln_base


def log10(x: Decimal128) raises -> Decimal128:
    """Calculates the base-10 logarithm (log10) of a Decimal128 value.

    Args:
        x: The Decimal128 value to compute the base-10 logarithm of.

    Returns:
        A Decimal128 approximation of log10(x).

    Raises:
        ValueError: If x is non-positive.

    Notes:
        This implementation uses the identity log10(x) = ln(x) / ln(10).
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

    var ten_to_power_of_scale = decimo.decimal128.utility.power_of_10[
        DType.uint128
    ](x_scale)

    # Special case: x = 1.00...0
    if x_coef == ten_to_power_of_scale:
        return Decimal128.ZERO()

    # Special case: x = 10^n
    # First get the integral part of x
    if x_coef % ten_to_power_of_scale == 0:
        var integeral_part = x_coef // ten_to_power_of_scale
        var exponent = 0
        while integeral_part % 10 == 0:
            integeral_part //= 10
            exponent += 1
        if integeral_part == 1:
            return Decimal128(UInt32(exponent), 0, 0, 0)
        else:
            pass

    # Use the identity: log10(x) = ln(x) / ln(10)
    return ln(x) / decimo.decimal128.constants.LN10()
