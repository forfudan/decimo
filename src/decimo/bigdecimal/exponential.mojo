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

"""Implements exponential functions for the BigDecimal type."""

from std import math

from decimo.biguint.biguint import BigUInt
import decimo.biguint.arithmetics as biguint_arithmetics
import decimo.biguint.exponential as biguint_exponential
import decimo.decimal128.utility as decimal128_utility
from decimo.bigdecimal.bigdecimal import BigDecimal
import decimo.bigdecimal.arithmetics as bigdecimal_arithmetics
from decimo.errors import ValueError, OverflowError, ZeroDivisionError
from decimo.rounding_mode import RoundingMode

# ===----------------------------------------------------------------------=== #
# List of functions in this module:
# - MathCache (struct): Cache for ln(2) and ln(1.25) constants
# - power(base: BigDecimal, exponent: BigDecimal, precision: Int) -> BigDecimal
# - integer_power(base: BigDecimal, exponent: BigDecimal, precision: Int) -> BigDecimal
# - root(x: BigDecimal, n: BigDecimal, precision: Int) -> BigDecimal
# - integer_root(x: BigDecimal, n: BigDecimal, precision: Int) -> BigDecimal
# - is_integer_reciprocal_and_return(n: BigDecimal) -> Tuple[Bool, BigDecimal]
# - is_odd_reciprocal(n: BigDecimal) -> Bool
# - fast_isqrt(c: BigUInt, working_digits: Int) -> BigUInt
# - sqrt(x: BigDecimal, precision: Int) -> BigDecimal  [public API]
# - sqrt_exact(x: BigDecimal, precision: Int) -> BigDecimal  [CPython-style]
# - sqrt_reciprocal(x: BigDecimal, precision: Int) -> BigDecimal  [fast, for internal use]
# - sqrt_decimal_approach(x: BigDecimal, precision: Int) -> BigDecimal  [legacy]
# - sqrt_newton(x: BigDecimal, precision: Int) -> BigDecimal  [legacy]
# - exp(x: BigDecimal, precision: Int) -> BigDecimal
# - exp_taylor_series(x: BigDecimal, minimum_precision: Int) -> BigDecimal
# - ln(x: BigDecimal, precision: Int) -> BigDecimal
# - ln(x: BigDecimal, precision: Int, mut cache: MathCache) -> BigDecimal
# - log(x: BigDecimal, precision: Int) -> BigDecimal
# - log10(x: BigDecimal, precision: Int) -> BigDecimal
# - ln_series_expansion(x: BigDecimal, precision: Int) -> BigDecimal
# - compute_ln2(precision: Int) -> BigDecimal
# - compute_ln1d25(precision: Int) -> BigDecimal
# ===----------------------------------------------------------------------=== #


# ===----------------------------------------------------------------------=== #
# Cache for mathematical constants
# ===----------------------------------------------------------------------=== #


struct MathCache:
    """Cache for expensive mathematical constants used in ln() and related
    functions.

    Since Mojo does not support module-level mutable variables, this struct
    provides a way to cache computed values of ln(2) and ln(1.25) across
    multiple function calls, avoiding redundant computation.

    The cache automatically handles precision upgrades: if a cached value was
    computed at precision P1 and a new call requests precision P2 > P1, the
    cache will recompute and store the higher-precision value.

    Usage:

    ```mojo
    from decimo import Decimal
    from decimo.bigdecimal.exponential import MathCache, ln

    var x1 = Decimal("2.0")
    var x2 = Decimal("3.0")
    var cache = MathCache()
    var result1 = ln(x1, 100, cache)
    var result2 = ln(x2, 100, cache)  # Reuses cached ln(2) and ln(1.25)
    ```

    This is especially beneficial for:
    - Functions like `log()` that call `ln()` twice internally
    - User code that calls `ln()` on multiple values at the same precision
    """

    var _ln2: BigDecimal
    """Cached value of ln(2)."""
    var _ln1d25: BigDecimal
    """Cached value of ln(1.25)."""
    var _ln10: BigDecimal
    """Cached value of ln(10)."""
    var _ln2_precision: Int
    """Precision (in significant digits) at which _ln2 was computed."""
    var _ln1d25_precision: Int
    """Precision (in significant digits) at which _ln1d25 was computed."""
    var _ln10_precision: Int
    """Precision (in significant digits) at which _ln10 was computed."""

    def __init__(out self):
        """Initializes an empty MathCache with no cached values."""
        self._ln2 = BigDecimal(BigUInt.zero(), 0, False)
        self._ln1d25 = BigDecimal(BigUInt.zero(), 0, False)
        self._ln10 = BigDecimal(BigUInt.zero(), 0, False)
        self._ln2_precision = 0
        self._ln1d25_precision = 0
        self._ln10_precision = 0

    def get_ln2(mut self, precision: Int) raises -> BigDecimal:
        """Returns ln(2) computed to at least the specified precision.

        If the cached value has sufficient precision, it is returned (rounded
        down to the requested precision). Otherwise, ln(2) is recomputed and
        cached at the new precision.

        Args:
            precision: The minimum number of significant digits required.

        Returns:
            The value of ln(2) with at least the specified precision.

        Raises:
            Error: Propagated from underlying arithmetic and conversion operations.
        """
        if self._ln2_precision >= precision:
            var result = self._ln2.copy()
            result.round_to_precision_inplace(
                precision=precision,
                rounding_mode=RoundingMode.down(),
                remove_extra_digit_due_to_rounding=False,
                fill_zeros_to_precision=False,
            )
            return result^
        self._ln2 = compute_ln2(precision)
        self._ln2_precision = precision
        return self._ln2.copy()

    def get_ln1d25(mut self, precision: Int) raises -> BigDecimal:
        """Returns ln(1.25) computed to at least the specified precision.

        If the cached value has sufficient precision, it is returned (rounded
        down to the requested precision). Otherwise, ln(1.25) is recomputed
        and cached at the new precision.

        Args:
            precision: The minimum number of significant digits required.

        Returns:
            The value of ln(1.25) with at least the specified precision.

        Raises:
            Error: Propagated from underlying arithmetic and conversion operations.
        """
        if self._ln1d25_precision >= precision:
            var result = self._ln1d25.copy()
            result.round_to_precision_inplace(
                precision=precision,
                rounding_mode=RoundingMode.down(),
                remove_extra_digit_due_to_rounding=False,
                fill_zeros_to_precision=False,
            )
            return result^
        self._ln1d25 = compute_ln1d25(precision)
        self._ln1d25_precision = precision
        return self._ln1d25.copy()

    def get_ln10(mut self, precision: Int) raises -> BigDecimal:
        """Returns ln(10) computed to at least the specified precision.

        If the cached value has sufficient precision, it is returned (rounded
        down to the requested precision). Otherwise, ln(10) is recomputed and
        cached at the new precision.

        Uses the identity: ln(10) = 3*ln(2) + ln(1.25), leveraging the cached
        values of ln(2) and ln(1.25) to avoid redundant computation.

        Args:
            precision: The minimum number of significant digits required.

        Returns:
            The value of ln(10) with at least the specified precision.

        Raises:
            Error: Propagated from underlying arithmetic and conversion operations.
        """
        if self._ln10_precision >= precision:
            var result = self._ln10.copy()
            result.round_to_precision_inplace(
                precision=precision,
                rounding_mode=RoundingMode.down(),
                remove_extra_digit_due_to_rounding=False,
                fill_zeros_to_precision=False,
            )
            return result^
        # ln(10) = ln(2 * 5) = ln(2) + ln(5)
        #        = ln(2) + ln(4 * 1.25) = ln(2) + 2*ln(2) + ln(1.25)
        #        = 3*ln(2) + ln(1.25)
        var extra = precision + 9
        var ln2 = self.get_ln2(extra)
        var ln1d25 = self.get_ln1d25(extra)
        self._ln10 = ln2.multiply(BigDecimal(3)).add(ln1d25)
        self._ln10.round_to_precision_inplace(
            precision=precision,
            rounding_mode=RoundingMode.down(),
            remove_extra_digit_due_to_rounding=False,
            fill_zeros_to_precision=False,
        )
        self._ln10_precision = precision
        return self._ln10.copy()


# ===----------------------------------------------------------------------=== #
# Power and root functions
# power(base, exponent, precision)
# integer_power(base, exponent, precision)
# ===----------------------------------------------------------------------=== #


def power(
    base: BigDecimal, exponent: BigDecimal, precision: Int = 28
) raises -> BigDecimal:
    """Raises a BigDecimal base to an arbitrary BigDecimal exponent power.

    Args:
        base: The base value to be raised to a power.
        exponent: The exponent to raise the base to.
        precision: Desired precision in significant digits.

    Returns:
        The result of base^exponent.

    Raises:
        ValueError: If base is negative and exponent is not an integer.
        ValueError: If base is zero and exponent is zero.
        ZeroDivisionError: If base is zero and exponent is negative.

    Notes:

    This function handles both integer and non-integer exponents using the
    identity x^y = e^(y * ln(x)) for the general case, with optimizations
    for integer exponents.
    """
    comptime BUFFER_DIGITS = 9
    var working_precision = precision + BUFFER_DIGITS

    # Special cases
    if base.coefficient.is_zero():
        if exponent.coefficient.is_zero():
            raise ValueError(
                message="0^0 is undefined.",
                function="power()",
            )
        elif exponent.sign:
            raise ZeroDivisionError(
                message="Division by zero (negative exponent with zero base).",
                function="power()",
            )
        else:
            return BigDecimal(BigUInt.zero(), 0, False)

    if exponent.coefficient.is_zero():
        return BigDecimal(BigUInt.one(), 0, False)  # x^0 = 1

    if base == BigDecimal(BigUInt.one(), 0, False):
        return BigDecimal(BigUInt.one(), 0, False)  # 1^y = 1

    if exponent == BigDecimal(BigUInt.one(), 0, False):
        # return base  # x^1 = x
        var result = base.copy()
        result.round_to_precision_inplace(
            precision,
            rounding_mode=RoundingMode.half_even(),
            remove_extra_digit_due_to_rounding=True,
            fill_zeros_to_precision=False,
        )
        return result^

    # Check for negative base with non-integer exponent
    if base.sign and not exponent.is_integer():
        raise ValueError(
            message=(
                "Negative base with non-integer exponent would produce"
                " a complex result."
            ),
            function="power()",
        )

    # Optimization for integer exponents
    if exponent.is_integer() and exponent.coefficient.number_of_digits() <= 9:
        return integer_power(base, exponent, precision)

    # General case using x^y = e^(y*ln(x))
    # Need to be careful with negative base
    var abs_base = abs(base)
    var ln_result = ln(abs_base, working_precision)
    var product = ln_result.multiply(exponent)
    var exp_result = exp(product, working_precision)

    # Handle sign for negative base with odd integer exponents
    if base.sign and exponent.is_integer() and exponent.is_odd():
        exp_result.sign = True

    exp_result.round_to_precision_inplace(
        precision,
        rounding_mode=RoundingMode.half_even(),
        remove_extra_digit_due_to_rounding=True,
        fill_zeros_to_precision=False,
    )
    return exp_result^


def integer_power(
    base: BigDecimal, exponent: BigDecimal, precision: Int
) raises -> BigDecimal:
    """Raises a base to integer exponents using binary exponentiation.

    Args:
        base: The base value.
        exponent: The integer exponent.
        precision: Desired precision.

    Returns:
        The result of base^exponent.

    Raises:
        ZeroDivisionError: If the base is zero and the exponent is negative.
        Error: Propagated from arithmetic operations.
    """
    var working_precision = precision + 9  # Add buffer digits
    var abs_exp = abs(exponent)
    var exp_value: BigUInt
    if abs_exp.scale > 0:
        exp_value = abs_exp.coefficient.floor_divide_by_power_of_ten(
            abs_exp.scale
        )
    elif abs_exp.scale == 0:
        exp_value = abs_exp.coefficient.copy()
    else:
        exp_value = abs_exp.coefficient.multiply_by_power_of_ten(-abs_exp.scale)

    var result = BigDecimal(BigUInt.one(), 0, False)
    var current_power = base.copy()

    # Handle negative exponent: result will be 1/positive_power
    var is_negative_exponent = exponent.sign

    # Binary exponentiation algorithm: x^n = (x^2)^(n/2) if n is even
    while exp_value > BigUInt.zero():
        if exp_value.words[0] % 2 == 1:
            # If current bit is set, multiply result by current power
            # Use inplace multiply
            bigdecimal_arithmetics.multiply_inplace(result, current_power)
            # Round to avoid coefficient explosion
            result.round_to_precision_inplace(
                working_precision,
                rounding_mode=RoundingMode.down(),
                remove_extra_digit_due_to_rounding=False,
                fill_zeros_to_precision=False,
            )

        # Use inplace multiply for squaring is not beneficial
        # because we need to copy first — just use regular multiply
        current_power = current_power.multiply(current_power)
        # Round to avoid coefficient explosion
        current_power.round_to_precision_inplace(
            working_precision,
            rounding_mode=RoundingMode.down(),
            remove_extra_digit_due_to_rounding=False,
            fill_zeros_to_precision=False,
        )

        biguint_arithmetics.floor_divide_by_2_inplace(exp_value)

    # For negative exponents, compute reciprocal
    if is_negative_exponent:
        result = BigDecimal(BigUInt.one(), 0, False).true_divide(
            result, working_precision
        )

    result.round_to_precision_inplace(
        precision,
        rounding_mode=RoundingMode.half_even(),
        remove_extra_digit_due_to_rounding=False,
        fill_zeros_to_precision=False,
    )
    return result^


def _strip_trailing_fractional_zeros(mut number: BigDecimal):
    """Strip trailing zeros that are after the decimal point only.

    Unlike normalize(), this preserves integer trailing zeros. For example,
    `100.0000` becomes `100` (not `1E+2`), and `2.000` becomes `2`.

    Only strips when the number of trailing fractional zeros is large enough
    to indicate an exact result (>= 9 zeros). This avoids stripping
    coincidental trailing zeros from approximate results (e.g., a result like
    1.395612425086089528628125320 has one trailing zero that is significant).

    This is used by root() to match Python's behavior for exact results
    (e.g., cbrt(8) = "2" instead of "2.000000000000000000000000000"),
    without affecting the internal integer_root() hot path.
    """
    if number.scale <= 0 or number.coefficient.is_zero():
        return

    var n_trailing = number.number_of_trailing_zeros()
    if n_trailing == 0:
        return

    # Only strip zeros up to scale (fractional part), never into the integer part.
    var n_strip = min(n_trailing, number.scale)

    # Use a threshold to distinguish exact results (many trailing zeros) from
    # coincidental trailing zeros in approximate results. At precision N with
    # BUFFER_DIGITS=9 guard digits, an exact result has >= N trailing fractional
    # zeros, while a non-exact result has at most 1-2 by chance (prob ~10^-9
    # for 9+ consecutive zeros).
    if n_strip < 9:
        return

    number.coefficient = number.coefficient.floor_divide_by_power_of_ten(
        n_strip
    )
    number.scale -= n_strip


def root(x: BigDecimal, n: BigDecimal, precision: Int) raises -> BigDecimal:
    """Calculate the nth root of a BigDecimal number.

    Args:
        x: The number to calculate the root of.
        n: The root value.
        precision: The precision (number of significant digits) of the result.

    Returns:
        The nth root of x with the specified precision.

    Raises:
        ValueError: If x is negative and n is not an odd integer.
        ValueError: If n is zero.

    Notes:
        Uses the identity x^(1/n) = exp(ln(|x|)/n) for calculation.
        For integer roots, calls the specialized integer_root function.
        Trailing fractional zeros are stripped from exact results (e.g.,
        root(8, 3) returns "2" instead of "2.000...0") to match Python's
        behavior. Internal functions like integer_root() skip this step
        for performance.
    """
    comptime BUFFER_DIGITS = 9
    var working_precision = precision + BUFFER_DIGITS

    # Check for n = 0
    if n.coefficient.is_zero():
        raise ValueError(
            message="Cannot compute zeroth root.",
            function="root()",
        )

    # Special case for integer roots - use more efficient implementation
    if not n.sign:
        if n.is_integer():
            var result = integer_root(x, n, precision)
            _strip_trailing_fractional_zeros(result)
            return result^
        var _tuple = is_integer_reciprocal_and_return(n)
        var is_integer_reciprocal: Bool = _tuple[0]
        ref integer_reciprocal: BigDecimal = _tuple[1]
        if is_integer_reciprocal:
            # If m = 1/n is an integer, use integer_root
            var result = integer_power(x, integer_reciprocal, precision)
            _strip_trailing_fractional_zeros(result)
            return result^

        # Rational root decomposition
        # If n = a/b (reduced fraction), then x^(1/n) = x^(b/a)
        #   = integer_power(integer_root(x, a), b).
        # This avoids the expensive exp(ln(x)/n) path for fractional n.
        # Only for non-negative x: fractional roots of negative numbers
        # are disallowed (consistent with Python Decimal behavior).
        if not x.sign:
            var _rtuple = _rational_root_decomposition(n)
            var is_rational: Bool = _rtuple[0]
            var root_order: Int = _rtuple[1]
            var power_order: Int = _rtuple[2]
            if is_rational:
                # x^(b/a) = integer_power(integer_root(x, a), b)
                var a_bd = BigDecimal(root_order)
                var b_bd = BigDecimal(power_order)
                # Use extra precision for the intermediate integer_root
                var root_result = integer_root(x, a_bd, working_precision)
                var result = integer_power(root_result, b_bd, precision)
                _strip_trailing_fractional_zeros(result)
                return result^

    # Handle negative n as 1/(x^(1/|n|))
    if n.sign:
        var positive_root = root(x, -n, working_precision)
        var result = BigDecimal(BigUInt.one(), 0, False).true_divide(
            positive_root, precision
        )
        return result^

    # Handle special cases for x
    if x.coefficient.is_zero():
        return BigDecimal(BigUInt.zero(), 0, False)

    if x.is_one():
        return BigDecimal(BigUInt.one(), 0, False)

    # Check if x is negative - only odd integer roots of negative numbers are defined
    if x.sign:
        var n_is_integer = n.is_integer()
        var n_is_odd_reciprocal = is_odd_reciprocal(n)
        if not n_is_integer and not n_is_odd_reciprocal:
            raise ValueError(
                message=(
                    "Cannot compute non-odd-integer root of a negative number."
                ),
                function="root()",
            )
        elif n_is_integer:
            var result = integer_root(x, n, precision)
            _strip_trailing_fractional_zeros(result)
            return result^

    # Compute root using the identity: x^(1/n) = exp(ln(|x|)/n)
    var abs_x = abs(x)
    var ln_x = ln(abs_x, working_precision)
    var ln_divided = ln_x.true_divide(n, working_precision)
    var result = exp(ln_divided, working_precision)

    # Handle sign for negative inputs (only possible with odd integer roots)
    if x.sign:
        result.sign = True

    result.round_to_precision_inplace(
        precision=precision,
        rounding_mode=RoundingMode.half_even(),
        remove_extra_digit_due_to_rounding=True,
        fill_zeros_to_precision=True,
    )

    _strip_trailing_fractional_zeros(result)
    return result^


def integer_root(
    x: BigDecimal, n: BigDecimal, precision: Int
) raises -> BigDecimal:
    """Calculate the nth integer root of a BigDecimal number using Newton's
    method.

    Uses the iteration: r_{k+1} = ((n-1)*r_k + x/r_k^(n-1)) / n
    which converges quadratically to x^(1/n).

    Args:
        x: The number to calculate the root of.
        n: The root value (must be a positive integer).
        precision: The precision (number of significant digits) of the result.

    Returns:
        The nth root of x with the specified precision.

    Raises:
        ValueError: If x is negative and n is even.
        ValueError: If n is not a positive integer.
        ValueError: If n is zero.
    """
    comptime BUFFER_DIGITS = 9
    var working_precision = precision + BUFFER_DIGITS

    # Handle special case: n must be a positive integer
    if n.sign:
        raise ValueError(
            message="Root value must be positive.",
            function="integer_root()",
        )

    if not n.is_integer():
        raise ValueError(
            message="Root value must be an integer.",
            function="integer_root()",
        )

    if n.coefficient.is_zero():
        raise ValueError(
            message="Cannot compute zeroth root.",
            function="integer_root()",
        )

    # Special case: n = 1 (1st root is just the number itself)
    if n.is_one():
        var result = x.copy()
        result.round_to_precision_inplace(
            precision,
            rounding_mode=RoundingMode.half_even(),
            remove_extra_digit_due_to_rounding=True,
            fill_zeros_to_precision=False,
        )
        return result^

    # Special case: n = 2 (use dedicated sqrt function for better performance)
    if n == BigDecimal(BigUInt(raw_words=[2]), 0, False):
        return sqrt(x, precision)

    # Handle special cases for x
    if x.coefficient.is_zero():
        return BigDecimal(BigUInt.zero(), 0, False)

    # For x = 1, the result is always 1
    if x.is_one():
        return BigDecimal(BigUInt.one(), 0, False)

    var result_sign = False
    # Check if x is negative
    if x.sign:
        # Convert n to integer to check odd/even
        var n_uint: BigUInt
        if n.scale > 0:
            n_uint = n.coefficient.floor_divide_by_power_of_ten(n.scale)
        else:  # n.scale <= 0
            n_uint = n.coefficient.copy()

        if n_uint.words[0] % 2 == 1:  # Odd root
            result_sign = True
        else:  # n_uint.words[0] % 2 == 0:  # Even root
            raise ValueError(
                message="Cannot compute even root of a negative number.",
                function="integer_root()",
            )

    # Extract n as Int for Newton's method
    var n_int: Int
    if n.scale > 0:
        n_int = Int(
            n.coefficient.floor_divide_by_power_of_ten(n.scale).words[0]
        )
    elif n.scale == 0:
        n_int = Int(n.coefficient.words[0])
    else:
        # n has negative scale (e.g., n = 300 stored as 3 * 10^2)
        # For very large n, fall back to exp(ln(x)/n)
        return _integer_root_via_exp_ln(x, n, precision, result_sign)

    # For very large n values, the Newton approach with integer_power(r, n-1)
    # is expensive. Fall back to exp(ln(x)/n) for n > 1000.
    if n_int > 1000:
        return _integer_root_via_exp_ln(x, n, precision, result_sign)

    var abs_x = abs(x)

    # --- Newton's method for x^(1/n) ---
    # Iteration: r_{k+1} = ((n-1)*r + x/r^(n-1)) / n
    # This converges quadratically to x^(1/n).

    # Initial guess using Float64 approximation
    # Use exponent to get log10(x), then compute 10^(log10(x)/n)
    var x_exp = abs_x.adjusted()  # floor(log10(x))

    # Extract leading digits for a more precise Float64 approximation
    var top_word = Float64(
        abs_x.coefficient.words[len(abs_x.coefficient.words) - 1]
    )
    var digits_in_top = 0
    var temp_val = abs_x.coefficient.words[len(abs_x.coefficient.words) - 1]
    while temp_val > 0:
        temp_val //= 10
        digits_in_top += 1
    if digits_in_top == 0:
        digits_in_top = 1

    # Normalize: get a value in [1, 10) * 10^x_exp
    var mantissa = top_word / Float64(10.0) ** Float64(digits_in_top - 1)
    if len(abs_x.coefficient.words) > 1:
        mantissa += Float64(
            abs_x.coefficient.words[len(abs_x.coefficient.words) - 2]
        ) / (Float64(10.0) ** Float64(digits_in_top - 1) * 1e9)

    var x_f64 = mantissa * Float64(10.0) ** Float64(x_exp)
    var guess_f64 = x_f64 ** (1.0 / Float64(n_int))
    # Clamp to avoid degenerate values
    if guess_f64 <= 0.0 or guess_f64 != guess_f64:  # NaN check
        guess_f64 = 1.0

    var r = BigDecimal(String(guess_f64))

    # BigDecimal constants
    var n_bd = BigDecimal.from_integral_scalar(n_int)
    var n_minus_1_bd = BigDecimal.from_integral_scalar(n_int - 1)
    var n_minus_1_int = n_int - 1

    # Newton's method with precision doubling
    # Start at low precision and double each iteration (quadratic convergence)
    # Number of iterations: ceil(log2(working_precision / 15)) + 2
    var iter_precision = 18  # Start with 18-digit precision
    var max_iterations = 0
    var p = iter_precision
    while p < working_precision:
        p *= 2
        max_iterations += 1
    max_iterations += 3  # Safety margin

    var converged_early = False  # Track early convergence
    for i in range(max_iterations):
        # Increase precision toward the target
        if iter_precision < working_precision:
            if converged_early:
                # If value converged at low precision (exact result like
                # cbrt(0.001)=0.1), jump to working_precision to finish
                # quickly rather than wasting iterations at intermediate
                # precision levels.
                iter_precision = working_precision
            else:
                iter_precision = min(iter_precision * 2, working_precision)

        # Trim r to iter_precision digits to prevent coefficient bloat.
        # Without this, exact results like 0.1 = coeff(10^71)/scale(72) cause
        # integer_power to produce huge coefficients that trigger BigUInt
        # division edge cases.
        if r.coefficient.number_of_digits() > iter_precision + BUFFER_DIGITS:
            r.round_to_precision_inplace(
                precision=iter_precision + BUFFER_DIGITS,
                rounding_mode=RoundingMode.half_even(),
                remove_extra_digit_due_to_rounding=True,
                fill_zeros_to_precision=False,
            )

        # r_new = ((n-1)*r + x / r^(n-1)) / n
        var r_pow_nm1 = integer_power(r, n_minus_1_bd, iter_precision)
        var x_div_r_pow = abs_x.true_divide_inexact(r_pow_nm1, iter_precision)

        var numerator: BigDecimal
        if n_minus_1_int == 1:
            numerator = r.add(x_div_r_pow)
        elif n_minus_1_int == 2:
            numerator = r.add(r).add(x_div_r_pow)
        else:
            numerator = r.multiply(n_minus_1_bd).add(x_div_r_pow)

        var r_new: BigDecimal
        if n_int <= Int(UInt32.MAX):
            r_new = numerator.true_divide_inexact_by_uint32(
                UInt32(n_int), iter_precision
            )
        else:
            r_new = numerator.true_divide_inexact(n_bd, iter_precision)

        # Check convergence
        if i >= 1:
            if iter_precision >= working_precision:
                # Final precision reached: compare at target precision
                var r_rounded = r.copy()
                r_rounded.round_to_precision_inplace(
                    precision=precision,
                    rounding_mode=RoundingMode.half_even(),
                    remove_extra_digit_due_to_rounding=True,
                    fill_zeros_to_precision=False,
                )
                var r_new_rounded = r_new.copy()
                r_new_rounded.round_to_precision_inplace(
                    precision=precision,
                    rounding_mode=RoundingMode.half_even(),
                    remove_extra_digit_due_to_rounding=True,
                    fill_zeros_to_precision=False,
                )
                if r_rounded == r_new_rounded:
                    r = r_new^
                    break
            else:
                # Before final precision: detect early convergence (exact results
                # like cbrt(0.001)=0.1 converge in few iterations at any precision).
                var r_rounded = r.copy()
                r_rounded.round_to_precision_inplace(
                    precision=iter_precision,
                    rounding_mode=RoundingMode.half_even(),
                    remove_extra_digit_due_to_rounding=True,
                    fill_zeros_to_precision=False,
                )
                var r_new_rounded = r_new.copy()
                r_new_rounded.round_to_precision_inplace(
                    precision=iter_precision,
                    rounding_mode=RoundingMode.half_even(),
                    remove_extra_digit_due_to_rounding=True,
                    fill_zeros_to_precision=False,
                )
                if r_rounded == r_new_rounded:
                    converged_early = True

        r = r_new^

    r.sign = result_sign
    r.round_to_precision_inplace(
        precision=precision,
        rounding_mode=RoundingMode.half_even(),
        remove_extra_digit_due_to_rounding=True,
        fill_zeros_to_precision=False,
    )

    return r^


def _integer_root_via_exp_ln(
    x: BigDecimal, n: BigDecimal, precision: Int, result_sign: Bool
) raises -> BigDecimal:
    """Fallback: compute integer root via exp(ln(|x|)/n).

    Used when n is too large for Newton's method to be efficient
    (each iteration requires computing r^(n-1) via binary exponentiation).

    Args:
        x: The input value.
        n: The root index.
        precision: Desired precision.
        result_sign: The sign of the result.

    Returns:
        x^(1/n) with the specified precision.
    """
    comptime BUFFER_DIGITS = 9
    var working_precision = precision + BUFFER_DIGITS
    var abs_x = abs(x)
    var ln_x = ln(abs_x, working_precision)
    var ln_divided = ln_x.true_divide(n, working_precision)
    var result = exp(ln_divided, working_precision)
    result.sign = result_sign

    result.round_to_precision_inplace(
        precision=precision,
        rounding_mode=RoundingMode.half_even(),
        remove_extra_digit_due_to_rounding=True,
        fill_zeros_to_precision=False,
    )

    return result^


def is_integer_reciprocal_and_return(
    n: BigDecimal,
) raises -> Tuple[Bool, BigDecimal]:
    """Check if 1/n (n != 1) represents an odd integer and return the result.

    Args:
        n: The value to check.

    Returns:
        True if 1/n is an odd integer, False otherwise.
        The integer reciprocal of n.

    Raises:
        ZeroDivisionError: If n is zero.
    """
    var m = BigDecimal(BigUInt.one(), 0, False).true_divide(
        n, precision=n.coefficient.number_of_digits() + 9
    )

    return Tuple(m.is_integer(), m^)


def is_odd_reciprocal(n: BigDecimal) raises -> Bool:
    """Check if 1/n (n != 1) represents an odd integer.

    Args:
        n: The value to check.

    Returns:
        True if 1/n is an odd integer, False otherwise.

    Raises:
        ZeroDivisionError: If n is zero.

    Notes:

    Numbers with infinite decimal places cannot be represented as BigDecimal.
    If integer m ends with 3, n=1/m cannot be exactly represented as input.
    Same applies to 1 (execpt exact 1), 7, 9.
    """
    # If n is of form 1/m where m is an odd integer, then 1/n = m is odd
    # This is true when n = 1/m for odd integer m

    var m = BigDecimal(BigUInt.one(), 0, False).true_divide(
        n, precision=n.coefficient.number_of_digits() + 9
    )

    if m.is_integer():
        # Check if m is odd
        if m.coefficient.ith_digit(-m.scale) % 2 == 1:
            return True
        else:
            return False
    else:
        return False


def _gcd(var a: Int, var b: Int) -> Int:
    """Compute the greatest common divisor of two integers.

    Handles negative inputs by taking absolute values first.
    """
    a = abs(a)
    b = abs(b)
    while b != 0:
        var temp = b
        b = a % b
        a = temp
    return a


def _rational_root_decomposition(
    n: BigDecimal,
) raises -> Tuple[Bool, Int, Int]:
    """Try to decompose a positive fractional n into a/b in lowest terms.

    If n = a/b (reduced), then root(x, n) = x^(1/n) = x^(b/a), which can be
    computed as integer_power(integer_root(x, a), b). This avoids the
    expensive exp(ln(x)/n) path.

    Args:
        n: A positive, non-integer BigDecimal value.

    Returns:
        A tuple (success, a, b) where:
        - success: True if decomposition succeeded and is practical.
        - a: The numerator (root order for integer_root).
        - b: The denominator (power for integer_power).
        x^(1/n) = x^(b/a) = integer_power(integer_root(x, a), b).

    Notes:
        Returns (False, 0, 0) if:
        - n.scale <= 0 (integer or no fractional part),
        - n.coefficient or 10^scale overflows Int,
        - a or b is 1 (already handled by earlier checks),
        - a > 1000 (integer_root would be too slow or fall back to exp/ln),
        - b > 1000 (integer_power with O(log b) big-number multiplications
          would be too expensive).

        Overflow safety: scale <= 18 ensures 10^scale fits in Int64
        (max 10^18 < 2^63-1). After GCD reduction, both a and b are
        bounded by their pre-reduction values which fit in Int, and the
        subsequent a <= 1000 / b <= 1000 guards ensure the values stay
        in a practical range for integer_root and integer_power.
    """
    # n must have a fractional part (scale > 0)
    if n.scale <= 0:
        return Tuple(False, 0, 0)

    # Avoid overflow: 10^scale must fit in Int (scale <= 18 for 64-bit)
    if n.scale > 18:
        return Tuple(False, 0, 0)

    # Coefficient must be small enough to fit in Int.
    # BigUInt uses base-10^9 words. With at most 2 words (18 digits), fits Int.
    if len(n.coefficient.words) > 2:
        return Tuple(False, 0, 0)

    var numerator: Int = Int(n.coefficient.words[0])
    if len(n.coefficient.words) == 2:
        numerator += Int(n.coefficient.words[1]) * 1_000_000_000

    var denominator = Int(10) ** n.scale

    # Reduce to lowest terms
    var g = _gcd(numerator, denominator)
    var a = numerator // g  # root order
    var b = denominator // g  # power order

    # a=1 or b=1 cases are already handled by prior checks
    # (integer reciprocal or integer root respectively)
    if a <= 1 or b <= 1:
        return Tuple(False, 0, 0)

    # Large root or power orders would be slow; fall through to exp/ln.
    # a > 1000: integer_root with Newton iteration is too slow.
    # b > 1000: integer_power needs O(log b) big-number multiplications.
    if a > 1000 or b > 1000:
        return Tuple(False, 0, 0)

    return Tuple(True, a, b)


# ===----------------------------------------------------------------------=== #
# Square root functions
#
# Yuhao ZHU:
# In Decimo v0.3.0, `sqrt` is implemented by using the BigDecimal objects to
# store the intermediate results. While this is more direct, it is not very
# efficient because it requires a lot of calculations to ensure that the scales
# and the precisions in the intermediate results are correct. It is also error-
# prone when scales are negative or there are two many significant digits.
#
# In Decimo v0.5.0, `sqrt` is re-implemented by using the BigUInt.sqrt()
# function. It first calculates the square root of the coefficient of x, and
# then adjust the scale based on the input scale, which is more efficient and
# error-free.
#
# In Decimo v0.6.0, `sqrt` is re-implemented as `sqrt_exact`, using the
# CPython _pydecimal.py algorithm for bit-perfect results matching Python's
# Decimal.sqrt() output. For large numbers (>20 words), `fast_isqrt` uses
# reciprocal sqrt with precision doubling for a fast initial approximation,
# then exact integer Newton iterations to converge to isqrt(c).
#
# Function hierarchy:
# - sqrt()                : Public API, delegates to sqrt_exact().
# - sqrt_exact()          : CPython-style exact integer algorithm. Produces
#                           results identical to Python's Decimal.sqrt().
# - sqrt_reciprocal()     : Fast reciprocal sqrt iteration. For use as an
#                           intermediate function by other functions (e.g.,
#                           arctan, ln) where exact perfect square detection
#                           is unnecessary.
# - fast_isqrt()          : Hybrid isqrt: reciprocal sqrt approximation +
#                           exact integer Newton refinement. Used by
#                           sqrt_exact() for large numbers.
# - sqrt_decimal_approach() : Legacy implementation (v0.3.0).
# - sqrt_newton()           : Legacy implementation (v0.5.0).
# ===----------------------------------------------------------------------=== #


# TODO:
# When global config for pad_zeros_to_precision is implemented,
# Pass the config to sqrt() and use it to control whether to
# call `sqrt_exact()` (pad zeros) or `sqrt_reciprocal()` (no padding)
def sqrt(x: BigDecimal, precision: Int) raises -> BigDecimal:
    """Calculate the square root of a BigDecimal number.

    This is the public API for square root. It delegates to `sqrt_exact()`,
    which uses the CPython _pydecimal.py algorithm for bit-perfect results
    that match Python's `Decimal.sqrt()` output exactly.

    Use this function when the result is returned directly to users.
    For intermediate computations inside other functions (e.g., arctan, ln),
    prefer `sqrt_reciprocal()` for better performance.

    Args:
        x: The number to calculate the square root of.
        precision: The desired precision (number of significant digits) of the
            result.

    Returns:
        The square root of x with the specified precision.

    Raises:
        ValueError: If x is negative.
    """
    return sqrt_exact(x, precision)


def fast_isqrt(c: BigUInt, working_digits: Int) raises -> BigUInt:
    """Compute isqrt(c) using reciprocal sqrt with precision doubling for speed,
    then verify/correct with exact integer Newton iterations.

    This is a hybrid approach:
    1. Use reciprocal sqrt Newton (division-free, precision doubling) to get
       a close approximation of sqrt(c) — typically within ±1 of isqrt(c).
    2. Refine with 1-3 exact integer Newton iterations to converge to isqrt(c).

    Args:
        c: The BigUInt to compute isqrt of (must be > 0).
        working_digits: Number of significant digits for the reciprocal sqrt
            approximation. Should be at least number_of_digits(c)/2 + 10.

    Returns:
        The integer square root floor(sqrt(c)).

    Raises:
        Error: Propagated from arithmetic operations.
    """
    # Convert c to BigDecimal for the reciprocal sqrt approximation
    var c_bd = BigDecimal(c.copy(), 0, False)

    # --- Normalization ---
    var c_exp = c_bd.adjusted()
    var norm_shift: Int
    if c_exp >= 0:
        norm_shift = (c_exp // 2) * 2
    else:
        norm_shift = -((-c_exp + 1) // 2) * 2
    var c_norm = c_bd.copy()
    c_norm.scale += norm_shift

    # --- Float64 initial guess for 1/sqrt(c_norm) ---
    var top_word = Float64(
        c_norm.coefficient.words[len(c_norm.coefficient.words) - 1]
    )
    var digits_in_top: Int = 0
    var temp_val = c_norm.coefficient.words[len(c_norm.coefficient.words) - 1]
    while temp_val > 0:
        temp_val //= 10
        digits_in_top += 1
    if digits_in_top == 0:
        digits_in_top = 1

    var mantissa = top_word / Float64(10.0) ** Float64(digits_in_top - 1)
    if len(c_norm.coefficient.words) > 1:
        mantissa += Float64(
            c_norm.coefficient.words[len(c_norm.coefficient.words) - 2]
        ) / (Float64(10.0) ** Float64(digits_in_top + 8))

    var c_norm_exp = c_norm.adjusted()
    var c_norm_f64 = mantissa * Float64(10.0) ** Float64(c_norm_exp)
    var r_f64 = c_norm_f64 ** (-0.5)
    if r_f64 != r_f64 or r_f64 <= 0.0:
        r_f64 = 1.0

    var r = BigDecimal(String(r_f64))

    # --- Precision doubling schedule ---
    var prec_schedule = List[Int]()
    var p = working_digits
    while p > 20:
        prec_schedule.append(p)
        p = (p + 1) // 2

    # Constant 3
    var three = BigDecimal(BigUInt(raw_words=[3]), 0, False)

    # --- Reciprocal sqrt Newton iterations ---
    for i in range(len(prec_schedule) - 1, -1, -1):
        var ip = prec_schedule[i] + 10

        var r_sq = r.multiply(r)
        r_sq.round_to_precision_inplace(
            precision=ip,
            rounding_mode=RoundingMode.half_up(),
            remove_extra_digit_due_to_rounding=True,
            fill_zeros_to_precision=False,
        )

        bigdecimal_arithmetics.multiply_inplace(r_sq, c_norm)
        r_sq.round_to_precision_inplace(
            precision=ip,
            rounding_mode=RoundingMode.half_up(),
            remove_extra_digit_due_to_rounding=True,
            fill_zeros_to_precision=False,
        )

        var correction = three.subtract(r_sq)

        bigdecimal_arithmetics.multiply_inplace(r, correction)
        r.round_to_precision_inplace(
            precision=ip,
            rounding_mode=RoundingMode.half_up(),
            remove_extra_digit_due_to_rounding=True,
            fill_zeros_to_precision=False,
        )

        r = r.true_divide_inexact_by_uint32(UInt32(2), ip)

    # --- Compute sqrt(c) = c_norm * r * 10^(norm_shift/2) ---
    var result_bd = c_norm.multiply(r)
    result_bd.scale -= norm_shift // 2

    # Round to enough digits to get an accurate integer
    result_bd.round_to_precision_inplace(
        precision=working_digits,
        rounding_mode=RoundingMode.half_up(),
        remove_extra_digit_due_to_rounding=True,
        fill_zeros_to_precision=False,
    )

    # --- Convert to BigUInt integer approximation ---
    # result_bd is approximately sqrt(c), which should be an integer
    # (since c was rescaled to make isqrt(c) have specific number of digits).
    # Extract the integer part.
    var n: BigUInt
    if result_bd.scale <= 0:
        # Integer or with trailing zeros
        n = result_bd.coefficient.copy()
        if result_bd.scale < 0:
            n = biguint_arithmetics.multiply_by_power_of_ten(
                n, -result_bd.scale
            )
    else:
        # Has decimal places — truncate to integer
        n = biguint_arithmetics.floor_divide_by_power_of_ten(
            result_bd.coefficient, result_bd.scale
        )

    # --- Exact integer Newton refinement ---
    # The reciprocal sqrt approximation may be above or below isqrt(c).
    # Use standard integer Newton convergence (same as BigUInt.sqrt):
    # iterate n = (n + c/n) / 2 until convergence (n stops changing or
    # oscillates by 1).
    for _ in range(20):  # Generous limit; typically converges in 1-3 steps
        var prev_n = n.copy()
        # Newton step: n = (n + c/n) / 2
        var q = c.floor_divide(n)
        n += q
        biguint_arithmetics.floor_divide_by_2_inplace(n)
        if n == prev_n:
            break
        if prev_n == n + BigUInt.one():
            # prev was one more than new — converged
            break
        if n == prev_n + BigUInt.one():
            # new is one more than prev — prev was the answer (floor)
            n = prev_n^
            break

    return n^


def sqrt_exact(x: BigDecimal, precision: Int) raises -> BigDecimal:
    """Calculate the square root of a BigDecimal number using CPython's
    exact integer algorithm.

    Uses the same algorithm as CPython's _pydecimal.py to produce identical
    results. The algorithm works on exact integer arithmetic:

    1. Express x as c * 10^e where c is an integer
    2. Rescale c so that isqrt(c) has exactly (precision+1) digits
    3. Compute n = isqrt(c) using BigUInt integer Newton's method
    4. Check if n*n == c (exact perfect square detection)
    5. For exact results: undo rescaling to get natural representation
    6. For inexact results: perturb n if n%5==0 to avoid rounding ties
    7. Round to precision digits using ROUND_HALF_EVEN

    This function produces results identical to Python's `Decimal.sqrt()`.
    For better performance in intermediate computations where exact perfect
    square detection is not needed, use `sqrt_reciprocal()` instead.

    Args:
        x: The number to calculate the square root of.
        precision: The desired precision (number of significant digits) of the
            result.

    Returns:
        The square root of x with the specified precision.

    Raises:
        ValueError: If x is negative.
    """

    # Handle special cases
    if x.sign:
        raise ValueError(
            message="Cannot compute square root of a negative number.",
            function="sqrt_exact()",
        )

    if x.coefficient.is_zero():
        # sqrt(0) — preserve exponent like CPython: e = x_exp // 2
        # x_exp = -x.scale, so result exponent = (-x.scale) // 2
        # result scale = -((-x.scale) // 2)
        var x_exp = -x.scale
        var result_exp = x_exp >> 1  # floor division toward -inf for >>
        return BigDecimal(BigUInt.zero(), -result_exp, False)

    # --- CPython _pydecimal.py sqrt algorithm ---
    # prec = precision + 1 (one guard digit for rounding)
    var prec = precision + 1

    # x = coefficient * 10^(-scale), so the "decimal exponent" is:
    # x_exp = -scale  (CPython's op.exp)
    var x_exp = -x.scale  # The decimal exponent
    var c = x.coefficient.copy()  # The integer coefficient

    # e = ideal exponent for result = x_exp // 2  (floored)
    var e = x_exp >> 1  # arithmetic right-shift = floor division by 2

    # If x_exp is odd, multiply c by 10 so c becomes "even-exponent" form
    # This ensures sqrt(c) * 10^e = sqrt(x)
    var num_digits = c.number_of_digits()
    var l: Int  # number of base-100 "digits" of c

    if x_exp & 1:
        # Odd exponent: c = c * 10
        c = biguint_arithmetics.multiply_by_power_of_ten(c, 1)
        l = (num_digits >> 1) + 1
    else:
        # Even exponent
        l = (num_digits + 1) >> 1

    # Rescale c so that isqrt(c) has exactly `prec` digits.
    # After rescaling: 10^(2*(prec-1)) <= c < 10^(2*prec)
    # so isqrt(c) has exactly `prec` digits.
    var shift = prec - l
    var exact = True

    if shift >= 0:
        # Pad c with 2*shift zeros: c = c * 100^shift
        c = biguint_arithmetics.multiply_by_power_of_ten(c, 2 * shift)
    else:
        # Truncate c: c, remainder = divmod(c, 100^(-shift))
        var divisor = biguint_arithmetics.multiply_by_power_of_ten(
            BigUInt.one(), -2 * shift
        )
        var qr = c.__divmod__(divisor)
        c = qr[0].copy()
        exact = qr[1].is_zero()
    e -= shift

    # --- Integer square root: n = isqrt(c) ---
    # For large c, use reciprocal sqrt with precision doubling to get a fast
    # initial approximation, then verify/correct with exact integer arithmetic.
    # For small c (≤ 180 digits), BigUInt.sqrt() is fast enough directly.
    var n: BigUInt
    if len(c.words) <= 20:
        n = biguint_exponential.sqrt(c)
    else:
        n = fast_isqrt(c, prec + 10)

    # Check for exact perfect square
    exact = exact and (n * n == c)

    if exact:
        # Undo the rescaling to get the natural number of significant digits.
        # This naturally strips artificial trailing zeros.
        if shift >= 0:
            n = biguint_arithmetics.floor_divide_by_power_of_ten(n, shift)
        else:
            n = biguint_arithmetics.multiply_by_power_of_ten(n, -shift)
        e += shift
    else:
        # For inexact results, if n ends in 0 or 5, perturb by +1.
        # This avoids exact midpoint ties when rounding to `precision` digits.
        # Check: n % 5 == 0
        # Since our BigUInt base is 10^9, n % 5 == (last_word % 5)
        if n.words[0] % 5 == 0:
            biguint_arithmetics.add_by_uint32_inplace(n, 1)

    # Construct result: coefficient=n, scale=-e (since exponent=e means *10^e)
    var result = BigDecimal(n^, -e, False)

    # Round to the requested precision using ROUND_HALF_EVEN (like CPython).
    # Applied unconditionally: for exact results that already fit within
    # `precision` digits this is a no-op, but when the natural digit count
    # exceeds `precision` (e.g. sqrt(10000) at precision=1) it correctly
    # truncates — matching CPython's `_fix(context)` behavior.
    result.round_to_precision_inplace(
        precision=precision,
        rounding_mode=RoundingMode.half_even(),
        remove_extra_digit_due_to_rounding=True,
        fill_zeros_to_precision=False,
    )

    return result^


def sqrt_reciprocal(x: BigDecimal, precision: Int) raises -> BigDecimal:
    """Calculate the square root of a BigDecimal number using reciprocal square
    root iteration.

    Uses reciprocal square root Newton iteration with precision doubling:
        r_{k+1} = r_k * (3 - x * r_k^2) / 2   (computes 1/sqrt(x))
    Then sqrt(x) = x * r.

    This avoids division entirely — each Newton iteration uses only
    multiplication, subtraction, and trivial divide-by-2. Combined with
    precision doubling (starting at Float64 precision and doubling each
    iteration), total work is approximately 3x the cost of one
    full-precision iteration.

    Args:
        x: The number to calculate the square root of.
        precision: The desired precision (number of significant digits) of the
            result.

    Returns:
        The square root of x with the specified precision.

    Raises:
        ValueError: If x is negative.
    """

    # Handle special cases
    if x.sign:
        raise ValueError(
            message="Cannot compute square root of a negative number.",
            function="sqrt_reciprocal()",
        )

    if x.coefficient.is_zero():
        return BigDecimal(BigUInt.zero(), (x.scale + 1) // 2, False)

    # For x = 1, return 1
    if x.is_one():
        return BigDecimal(BigUInt.one(), 0, False)

    comptime BUFFER_DIGITS = 25
    var working_precision = precision + BUFFER_DIGITS

    # --- Normalization ---
    # Shift x by an even power of 10 to bring it into [0.1, 100) for a
    # stable Float64 initial guess. Then sqrt(x) = sqrt(x_norm) * 10^(shift/2).
    var x_norm = x.copy()
    var x_exp = x_norm.adjusted()  # floor(log10(x))

    # Make shift even and bring x_norm near 1
    var shift: Int
    if x_exp >= 0:
        shift = (x_exp // 2) * 2  # round down to even
    else:
        shift = -((-x_exp + 1) // 2) * 2  # round up magnitude to even
    x_norm.scale += shift  # x_norm = x * 10^(-shift)

    # --- Float64 initial guess for 1/sqrt(x_norm) ---
    var top_word = Float64(
        x_norm.coefficient.words[len(x_norm.coefficient.words) - 1]
    )
    var digits_in_top: Int = 0
    var temp_val = x_norm.coefficient.words[len(x_norm.coefficient.words) - 1]
    while temp_val > 0:
        temp_val //= 10
        digits_in_top += 1
    if digits_in_top == 0:
        digits_in_top = 1

    var mantissa = top_word / Float64(10.0) ** Float64(digits_in_top - 1)
    if len(x_norm.coefficient.words) > 1:
        mantissa += Float64(
            x_norm.coefficient.words[len(x_norm.coefficient.words) - 2]
        ) / (Float64(10.0) ** Float64(digits_in_top + 8))

    var x_norm_exp = x_norm.adjusted()
    var x_norm_f64 = mantissa * Float64(10.0) ** Float64(x_norm_exp)
    var r_f64 = x_norm_f64 ** (-0.5)  # 1/sqrt(x_norm)
    if r_f64 != r_f64 or r_f64 <= 0.0:  # NaN or degenerate
        r_f64 = 1.0

    var r = BigDecimal(String(r_f64))

    # --- Precision doubling schedule ---
    # Build list from working_precision down to ~20, iterate in reverse.
    # Float64 gives ~15 correct digits; each Newton iteration doubles that.
    var prec_schedule = List[Int]()
    var p = working_precision
    while p > 20:
        prec_schedule.append(p)
        p = (p + 1) // 2

    # Constant 3
    var three = BigDecimal(BigUInt(raw_words=[3]), 0, False)

    # --- Newton iterations: r_{k+1} = r_k * (3 - x_norm * r_k^2) / 2 ---
    for i in range(len(prec_schedule) - 1, -1, -1):
        var ip = prec_schedule[i] + 10  # iteration precision with guard

        # r^2 (self-squaring, cannot use multiply_inplace)
        var r_sq = r.multiply(r)
        r_sq.round_to_precision_inplace(
            precision=ip,
            rounding_mode=RoundingMode.half_up(),
            remove_extra_digit_due_to_rounding=True,
            fill_zeros_to_precision=False,
        )

        # x_norm * r^2 (inplace to avoid allocation: r_sq becomes x_norm * r^2)
        bigdecimal_arithmetics.multiply_inplace(r_sq, x_norm)
        r_sq.round_to_precision_inplace(
            precision=ip,
            rounding_mode=RoundingMode.half_up(),
            remove_extra_digit_due_to_rounding=True,
            fill_zeros_to_precision=False,
        )

        # 3 - x_norm * r^2 (should be close to 2 when converged)
        var correction = three.subtract(r_sq)

        # r * (3 - x_norm * r^2) (inplace)
        bigdecimal_arithmetics.multiply_inplace(r, correction)
        r.round_to_precision_inplace(
            precision=ip,
            rounding_mode=RoundingMode.half_up(),
            remove_extra_digit_due_to_rounding=True,
            fill_zeros_to_precision=False,
        )

        # / 2
        r = r.true_divide_inexact_by_uint32(UInt32(2), ip)

    # --- Final: sqrt(x_norm) = x_norm * r ---
    var result = x_norm.multiply(r)

    # --- Un-normalize: sqrt(x) = sqrt(x_norm) * 10^(shift/2) ---
    result.scale -= shift // 2

    # --- Round to desired precision ---
    result.round_to_precision_inplace(
        precision=precision,
        rounding_mode=RoundingMode.half_up(),
        remove_extra_digit_due_to_rounding=True,
        fill_zeros_to_precision=False,
    )

    # --- Strip trailing zeros for exact results (e.g., sqrt(4) = 2, not 2.000...) ---
    # Only strip if the stripped result is a verified perfect square.
    var n_trailing = result.coefficient.number_of_trailing_zeros()
    if n_trailing > 0:
        var stripped_coef = biguint_arithmetics.floor_divide_by_power_of_ten(
            result.coefficient, n_trailing
        )
        var stripped_scale = result.scale - n_trailing
        var candidate = BigDecimal(stripped_coef^, stripped_scale, False)
        # Verify: candidate * candidate == x?
        var check = candidate.multiply(candidate)
        if check == x:
            # If the scale went negative but the input had non-negative scale,
            # normalize back to scale=0 to preserve integer representation.
            # E.g., sqrt(100) should return "10" (scale=0), not "1E+1" (scale=-1).
            # But sqrt(1e10) should return "1E+5" (scale=-5) since input has scale=-10.
            if candidate.scale < 0 and x.scale >= 0:
                candidate.coefficient = (
                    biguint_arithmetics.multiply_by_power_of_ten(
                        candidate.coefficient, -candidate.scale
                    )
                )
                candidate.scale = 0
            return candidate^

    return result^


def sqrt_newton(x: BigDecimal, precision: Int) raises -> BigDecimal:
    """Calculates the square root of a BigDecimal number using Newton's method.

    Args:
        x: The number to calculate the square root of.
        precision: The desired precision (number of significant digits) of the
            result.

    Returns:
        The square root of x with the specified precision.

    Raises:
        ValueError: If x is negative.

    Notes:

    This function uses BigUInt.sqrt() to calculate the square root of the
    coefficient of x, and then adjusts the scale based on the input scale.
    """

    # Yuhao ZHU:
    # I am using the following tricks to ensure that the scales are correct
    # during scale up and scale down operations.
    # A BigDecimal has a coefficient (c) and a scale (s) -> c*10^(-s).
    # Let the final targeted scale to be t. So the result should have
    # (c*10^(-s))^(1/2) = (c*10^(2t-s)*10^(-2t+s)*10^(-s))^(1/2)
    #                   = (c*10^(2t-s))^(1/2) * 10^(-t)
    #                   = c_0 * 10^(-t)
    # where c_0 is the new coefficient after taking the square root and
    # t is the new scale.
    # So we first need to extend the coefficient by 10^(2t-s) to ensure
    # the square root has enough precision. Let's denote the precision as p.
    # Thus, the number of digits of c*10^(2t-s) should be at least 2p.
    # That is t > p + (s - d(c)) // 2

    # Handle special cases
    if x.sign:
        raise ValueError(
            message="Cannot compute square root of a negative number.",
            function="sqrt_newton()",
        )

    if x.coefficient.is_zero():
        return BigDecimal(BigUInt.zero(), (x.scale + 1) // 2, False)

    # STEP 1: Extend the coefficient by 10^(2p-s)
    var working_precision = precision + 9  # p
    var n_digits_coef = x.coefficient.number_of_digits()  # d(c)
    var new_scale = working_precision + (x.scale - n_digits_coef) // 2 + 1  # t
    var n_digits_to_extend = new_scale * 2 - x.scale  # 2t - s
    var half_n_digits_to_extend = n_digits_to_extend // 2
    var extended_coefficient: BigUInt
    if n_digits_to_extend > 0:
        extended_coefficient = biguint_arithmetics.multiply_by_power_of_ten(
            x.coefficient, n_digits_to_extend
        )
    elif n_digits_to_extend == 0:
        extended_coefficient = x.coefficient.copy()
    else:  # n_digits_to_extend < 0
        extended_coefficient = biguint_arithmetics.floor_divide_by_power_of_ten(
            x.coefficient, -n_digits_to_extend
        )

    # STEP 2: Calculate the square root of the extended coefficient
    var sqrt_coefficient = biguint_exponential.sqrt(extended_coefficient)

    # If the last p digits of the coefficient are zeros, this means that
    # we have a perfect square, so we can scale down the coefficient
    # and the scale.
    if (
        sqrt_coefficient.number_of_trailing_zeros() >= half_n_digits_to_extend
    ) and (half_n_digits_to_extend > 0):
        sqrt_coefficient = biguint_arithmetics.floor_divide_by_power_of_ten(
            sqrt_coefficient, half_n_digits_to_extend
        )
        new_scale -= half_n_digits_to_extend

    var result = BigDecimal(
        sqrt_coefficient^,
        new_scale,
        False,
    )
    result.round_to_precision_inplace(
        precision=precision,
        rounding_mode=RoundingMode.half_up(),
        remove_extra_digit_due_to_rounding=True,
        fill_zeros_to_precision=False,
    )
    return result^


def sqrt_decimal_approach(x: BigDecimal, precision: Int) raises -> BigDecimal:
    """Calculate the square root of a BigDecimal number.

    Args:
        x: The number to calculate the square root of.
        precision: The desired precision (number of significant digits) of the
            result.

    Returns:
        The square root of x with the specified precision.

    Raises:
        ValueError: If x is negative.

    Notes:

    This function uses Newton's method to iteratively approximate the square
    root. The intermediate calculations are done with BigDecimal objects.
    An other approach is to use the BigUInt.sqrt() function to calculate the
    square root of the coefficient of x, and then adjust the scale based on the
    input scale.
    """
    comptime BUFFER_DIGITS = 9

    # Handle special cases
    if x.sign:
        raise ValueError(
            message="Cannot compute square root of a negative number.",
            function="sqrt_decimal_approach()",
        )

    if x.coefficient.is_zero():
        return BigDecimal(BigUInt.zero(), (x.scale + 1) // 2, False)

    # Initial guess
    # A decimal has coefficient and scale
    # Example 1:
    # 123456789012345678901234567890.12345 (sqrt ~= 351364182882014.4253111222382)
    # coef = 12345678_901234567_890123456_789012345, scale = 5
    # first three words = 12345678_901234567_890123456
    # number of integral digits = 30
    # Because it is even, no need to scale up by 10
    # not scale up by 10 => 12345678901234567890123456
    # sqrt(12345678901234567890123456) = 3513641828820
    # number of integral digits of the sqrt = (30 + 1) // 2 = 15
    # coef = 3513641828820, 13 digits, so scale = 13 - 15
    #
    # Example 2:
    # 12345678901.234567890123456789012345 (sqrt ~= 111111.1106111111099361111058)
    # coef = 12345678_901234567_890123456_789012345, scale = 24
    # first three words = 12345678_901234567_890123456
    # remaining number of words = 11
    # Because it is odd, need to scale up by 10
    # scale up by 10 => 123456789012345678901234560
    # sqrt(123456789012345678901234560) = 11111111061111
    # number of integral digits of the sqrt = (11 + 1) // 2 = 6
    # coef = 11111111061111, 14 digits, so scale = 14 - 6 => (111111.11061111)

    var guess: BigDecimal
    var ndigits_coef = x.coefficient.number_of_digits()
    var ndigits_int_part = x.coefficient.number_of_digits() - x.scale
    var ndigits_int_part_sqrt = (ndigits_int_part + 1) // 2
    var odd_ndigits_frac_part = x.scale % 2 == 1

    var value: UInt128
    if ndigits_coef <= 9:
        value = UInt128(x.coefficient.words[0]) * UInt128(
            1_000_000_000_000_000_000
        )
    elif ndigits_coef <= 18:
        value = (
            UInt128(x.coefficient.words[len(x.coefficient.words) - 1])
            * UInt128(1_000_000_000_000_000_000)
        ) + (
            UInt128(x.coefficient.words[len(x.coefficient.words) - 2])
            * UInt128(1_000_000_000)
        )
    else:  # ndigits_coef > 18
        value = (
            (
                UInt128(x.coefficient.words[len(x.coefficient.words) - 1])
                * UInt128(1_000_000_000_000_000_000)
            )
            + UInt128(x.coefficient.words[len(x.coefficient.words) - 2])
            * UInt128(1_000_000_000)
            + UInt128(x.coefficient.words[len(x.coefficient.words) - 3])
        )
    if odd_ndigits_frac_part:
        value = value * UInt128(10)
    var sqrt_value = decimal128_utility.sqrt(value)
    var sqrt_value_biguint = BigUInt.from_integral_scalar(sqrt_value)
    guess = BigDecimal(
        sqrt_value_biguint,
        sqrt_value_biguint.number_of_digits() - ndigits_int_part_sqrt,
        False,
    )

    # For Newton's method, we need extra precision during calculations
    # to ensure the final result has the desired precision
    var working_precision = precision + BUFFER_DIGITS

    # Newton's method iterations
    # x_{n+1} = (x_n + N/x_n) / 2
    var prev_guess = BigDecimal(BigUInt.zero(), 0, False)
    var iteration_count = 0

    while guess != prev_guess and iteration_count < 100:
        prev_guess = guess.copy()
        var quotient = x.true_divide_inexact(guess, working_precision)
        var sum_val = guess.add(quotient)
        # Use O(n) uint32 division instead of full BigDecimal divide-by-2
        guess = sum_val.true_divide_inexact_by_uint32(2, working_precision)
        iteration_count += 1

    # Round to the desired precision (in-place, no intermediate copy)
    var guess_ndigits = guess.coefficient.number_of_digits()
    var ndigits_to_remove = guess_ndigits - precision
    if ndigits_to_remove > 0:
        guess.coefficient.remove_trailing_digits_with_rounding_inplace(
            ndigits_to_remove,
            rounding_mode=RoundingMode.half_up(),
            remove_extra_digit_due_to_rounding=True,
            ndigits_before_removal=guess_ndigits,
        )
        guess.scale -= ndigits_to_remove

    # Remove trailing zeros for exact results
    if guess.coefficient.ith_digit(0) == 0:
        var guess_coefficient_without_trailing_zeros = (
            guess.coefficient.remove_trailing_digits_with_rounding(
                guess.coefficient.number_of_trailing_zeros(),
                rounding_mode=RoundingMode.down(),
                remove_extra_digit_due_to_rounding=False,
            )
        )
        var x_coefficient_without_trailing_zeros = (
            x.coefficient.remove_trailing_digits_with_rounding(
                x.coefficient.number_of_trailing_zeros(),
                rounding_mode=RoundingMode.down(),
                remove_extra_digit_due_to_rounding=False,
            )
        )
        if (
            guess_coefficient_without_trailing_zeros
            * guess_coefficient_without_trailing_zeros
        ) == x_coefficient_without_trailing_zeros:
            var expected_ndigits_of_result = (
                x.coefficient.number_of_digits() + 1
            ) // 2
            guess.round_to_precision_inplace(
                precision=expected_ndigits_of_result,
                rounding_mode=RoundingMode.down(),
                remove_extra_digit_due_to_rounding=False,
                fill_zeros_to_precision=False,
            )
            guess.scale = (x.scale + 1) // 2

    return guess^


def cbrt(x: BigDecimal, precision: Int) raises -> BigDecimal:
    """Calculate the cube root of a BigDecimal number.

    Args:
        x: The number to calculate the cube root of.
        precision: The desired precision (number of significant digits) of the result.

    Returns:
        The cube root of x with the specified precision.

    Raises:
        Error: Propagated from integer_root.
    """

    var result = integer_root(
        x,
        BigDecimal(coefficient=BigUInt(raw_words=[3]), scale=0, sign=False),
        precision,
    )
    return result^


# ===----------------------------------------------------------------------=== #
# Exponential functions
# ===----------------------------------------------------------------------=== #


def exp(x: BigDecimal, precision: Int) raises -> BigDecimal:
    """Calculate the natural exponential of x (e^x) to the specified precision.

    Args:
        x: The exponent value.
        precision: Desired precision in significant digits.

    Returns:
        The natural exponential of x (e^x) to the specified precision.

    Raises:
        OverflowError: If the result is too large to represent.

    Notes:
        Uses aggressive range reduction for optimal performance:
        1. Divide x by 2^M where M ≈ √(3.322·precision) to make x tiny
        2. Evaluate Taylor series (converges in ~M terms since x/2^M is small)
        3. Square the result M times to recover exp(x)

        This minimizes total multiplications: ~2·√(3.322·p) instead of ~2.5·p.
    """
    # Handle special cases
    if x.coefficient.is_zero():
        # e^0 = 1 always, regardless of how zero is represented.
        # BigDecimal("0.00") has scale=2 — we must NOT propagate that.
        return BigDecimal(BigUInt.one(), 0, False)

    # For very large positive values, result will overflow BigDecimal capacity
    # TODO: Use BigInt10 as scale can avoid overflow in this case
    if not x.sign and x.adjusted() >= 20:  # x > 10^20
        raise OverflowError(
            message="Result too large to represent", function="exp()"
        )

    # For very large negative values, result will be effectively zero
    if x.sign and x.adjusted() >= 20:  # x < -10^20
        return BigDecimal(BigUInt.zero(), precision, False)

    # Handle negative x using identity: exp(-x) = 1/exp(x)
    if x.sign:
        var pos_result = exp(-x, precision + 2)
        return BigDecimal(BigUInt.one(), 0, False).true_divide(
            pos_result, precision
        )

    # --- Aggressive range reduction ---
    # We want to divide x by 2^M to make it tiny, so that the Taylor series
    # converges in very few terms. Then we square the result M times.
    #
    # Total cost = (Taylor terms) + (M squarings).
    # Taylor terms ≈ p·ln(10) / (M·ln(2) + ln(1/|x|)).
    # Optimal M minimizes total cost:
    #   M = max(0, ⌈(√(1.596·p) + log₁₀(|x|)·2.303) / 0.693⌉)
    #
    # For |x| ≈ 1: M ≈ √(3.322·p), giving ~2·√(3.322·p) total multiplications
    # vs the old approach of ~2.5·p multiplications.
    var x_exp = x.adjusted()  # floor(log10(x))
    var p_float = Float64(precision)

    # Compute optimal number of halvings
    var optimal_total = math.sqrt(1.596 * p_float)
    var ln_inv_x = Float64(-x_exp) * 2.303  # ≈ ln(1/|x|), positive when x < 1
    var m = max(0, Int(math.ceil((optimal_total - ln_inv_x) / 0.693)))

    # Correctness guard: exp_taylor_series() converges best for |x| <= 1.
    # Our heuristic m may be too small at low precisions, leaving |x/2^m| > 1.
    # Enforce minimum m so that 2^m >= 10^(x_exp+1) > |x|, i.e. |x/2^m| < 1.
    if x_exp >= 0:
        var min_m = Int(math.ceil(Float64(x_exp + 1) * 3.3219280948874))
        if m < min_m:
            m = min_m

    # Extra guard digits to compensate for error amplification during squaring.
    # After M squarings, relative error is amplified by ~2^M, requiring
    # M·log₁₀(2) ≈ 0.301·M extra significant digits.
    var squaring_guard = Int(Float64(m) * 0.35) + 3
    var working_precision = precision + squaring_guard + 9

    if m > 0:
        # Divide x by 2^M exactly: x / 2^M = (coeff · 5^M) · 10^(-(scale+M))
        # This is exact — no rounding needed.
        var reduced_coeff = x.coefficient.copy()
        for _ in range(m):
            biguint_arithmetics.multiply_by_uint32_inplace(reduced_coeff, 5)
        var reduced_x = BigDecimal(reduced_coeff^, x.scale + m, False)

        # Compute exp(x/2^M) via Taylor series (converges in ~√(3.3·p) terms)
        var result = exp_taylor_series(reduced_x, working_precision)

        # Square result M times: exp(x) = exp(x/2^M)^(2^M)
        for _ in range(m):
            result = result.multiply(result)
            result.round_to_precision_inplace(
                precision=working_precision,
                rounding_mode=RoundingMode.half_up(),
                remove_extra_digit_due_to_rounding=False,
                fill_zeros_to_precision=False,
            )

        result.round_to_precision_inplace(
            precision=precision,
            rounding_mode=RoundingMode.half_even(),
            remove_extra_digit_due_to_rounding=False,
            fill_zeros_to_precision=False,
        )

        return result^

    # For very small x where M=0 (|x| is already tiny), use Taylor directly
    var working_precision_basic = precision + 9
    var result = exp_taylor_series(x, working_precision_basic)

    result.round_to_precision_inplace(
        precision=precision,
        rounding_mode=RoundingMode.half_even(),
        remove_extra_digit_due_to_rounding=True,
        fill_zeros_to_precision=False,
    )

    return result^


def exp_taylor_series(
    x: BigDecimal, minimum_precision: Int
) raises -> BigDecimal:
    """Calculate exp(x) using Taylor series for |x| <= 1.

    Args:
        x: The exponent value.
        minimum_precision: Minimum precision in significant digits.

    Returns:
        The natural exponential of x (e^x) to the specified precision with some
        extra digits to ensure accuracy.

    Raises:
        Error: Propagated from arithmetic operations.
    """
    # Theoretical number of terms needed based on precision
    # For |x| ≤ 1, error after n terms is approximately |x|^(n+1)/(n+1)!
    # We need |x|^(n+1)/(n+1)! < 10^(-precision)
    # For x=1, we need approximately n ≈ precision * ln(10) ≈ precision * 2.3
    #
    # ZHU: About complexity:
    # In each loop, there are 2 mul (2 x 100ns) and 1 div (2000ns)
    # There are intotal 2.3 * precision iterations

    # print("DEBUG: exp_taylor_series")
    # print("DEBUG: x =", x)

    var max_number_of_terms = Int(Float64(minimum_precision) * 2.5) + 1
    var result = BigDecimal(BigUInt.one(), 0, False)
    var term = BigDecimal(BigUInt.one(), 0, False)
    var n: UInt32 = 1

    # Calculate Taylor series: 1 + x + x²/2! + x³/3! + ...
    for _ in range(1, max_number_of_terms):
        # Calculate next term: x^i/i! = x^{i-1} * x/i
        # We can use the previous term to calculate the next one
        # Use O(n) single-word division instead of full BigDecimal div
        var add_on = x.true_divide_inexact_by_uint32(n, minimum_precision)
        # Use inplace multiply to avoid BigDecimal allocation
        bigdecimal_arithmetics.multiply_inplace(term, add_on)
        term.round_to_precision_inplace(
            precision=minimum_precision,
            rounding_mode=RoundingMode.half_up(),
            remove_extra_digit_due_to_rounding=False,
            fill_zeros_to_precision=False,
        )
        n += 1

        # Add term to result
        result.add_inplace(term)

        # print("DEUBG: round {}, term {}, result {}".format(n, term, result))

        # Check if we've reached desired precision
        if term.adjusted() < -minimum_precision:
            break

    result.round_to_precision_inplace(
        precision=minimum_precision,
        rounding_mode=RoundingMode.half_up(),
        remove_extra_digit_due_to_rounding=False,
        fill_zeros_to_precision=False,
    )
    # print("DEBUG: final result", result)

    return result^


# ===----------------------------------------------------------------------=== #
# Logarithmic functions
# ===----------------------------------------------------------------------=== #


def ln(x: BigDecimal, precision: Int) raises -> BigDecimal:
    """Calculate the natural logarithm of x to the specified precision.

    This is the non-cached version. For repeated calls, use the overload that
    accepts a `MathCache` parameter to avoid recomputing ln(2) and ln(1.25).

    Args:
        x: The input value.
        precision: Desired precision in significant digits.

    Returns:
        The natural logarithm of x to the specified precision.

    Raises:
        ValueError: If x is negative or zero.
    """
    var cache = MathCache()
    return ln(x, precision, cache)


def ln(
    x: BigDecimal, precision: Int, mut cache: MathCache
) raises -> BigDecimal:
    """Calculate the natural logarithm of x to the specified precision.

    This overload accepts a `MathCache` to reuse cached values of ln(2) and
    ln(1.25) across multiple calls, significantly improving performance.

    Args:
        x: The input value.
        precision: Desired precision in significant digits.
        cache: A mutable MathCache instance for caching ln(2) and ln(1.25).

    Returns:
        The natural logarithm of x to the specified precision.

    Raises:
        ValueError: If x is negative or zero.
    """
    comptime BUFFER_DIGITS = 9  # word-length, easy to append and trim
    var working_precision = precision + BUFFER_DIGITS

    # Handle special cases
    if x.sign:
        raise ValueError(
            message="Cannot compute logarithm of negative number",
            function="ln()",
        )
    if x.coefficient.is_zero():
        raise ValueError(
            message="Cannot compute logarithm of zero", function="ln()"
        )
    if x == BigDecimal(BigUInt.one(), 0, False):
        return BigDecimal(BigUInt.zero(), 0, False)  # ln(1) = 0

    # Range reduction to improve convergence
    # ln(x) = ln(m * 10^p10 * 2^a * 5^b)
    #       = ln(m) + p10*ln(10) + a*ln(2) + b*ln(5)
    #       = ln(m) + p10*ln(10) + (a+2b)*ln(2) + b*ln(1.25)
    #   where 0.5 <= m < 1.5
    # By keeping power_of_10 separate (cached), we avoid decomposing it into
    # ln(2) and ln(1.25), which was the source of the catastrophic slowdown
    # for ln(10), ln(100), ln(0.001) etc.
    var m = x.copy()
    var adj_power_of_2: Int = 0
    var adj_power_of_5: Int = 0
    # First, scale down to [0.1, 1)
    var power_of_10 = m.adjusted() + 1
    m.scale += power_of_10
    # Second, scale to [0.5, 1.5)
    if m < BigDecimal(BigUInt(raw_words=[135]), 3, False):
        # [0.1, 0.135) * 10 -> [1, 1.35)
        power_of_10 -= 1
        m.scale -= 1
    elif m < BigDecimal(BigUInt(raw_words=[275]), 3, False):
        # [0.135, 0.275) * 5 -> [0.675, 1.375)]
        adj_power_of_5 = -1
        m = m.multiply(BigDecimal(BigUInt(raw_words=[5]), 0, False))
    elif m < BigDecimal(BigUInt(raw_words=[65]), 2, False):
        # [0.275, 0.65) * 2 -> [0.55, 1.3)]
        adj_power_of_2 = -1
        m = m.multiply(BigDecimal(BigUInt(raw_words=[2]), 0, False))
    else:  # [0.65, 1) -> no change
        pass

    # Use series expansion for ln(m) = ln(1+z) = z - z²/2 + z³/3 - ...
    var result = ln_series_expansion(
        m.subtract(BigDecimal(BigUInt.one(), 0, False)), working_precision
    )

    # Apply range reduction adjustments
    # ln(x) = ln(m) + power_of_10*ln(10) + (adj_2 + 2*adj_5)*ln(2)
    #                                     + adj_5*ln(1.25)
    # Decompose power_of_10 into ln(2)/ln(1.25) to avoid computing ln(10)
    # unnecessarily: ln(10) = 3*ln(2) + ln(1.25)
    # This avoids regression for inputs like ln(2) which would otherwise
    # trigger a full ln(10) computation (requiring both ln(2) AND ln(1.25)).
    # The cached get_ln10() is still used by log10()/log() where it's needed.
    var combined_ln2_factor = (
        adj_power_of_2 + adj_power_of_5 * 2 + 3 * power_of_10
    )
    var combined_ln1d25_factor = adj_power_of_5 + power_of_10
    if combined_ln2_factor != 0:
        var ln2 = cache.get_ln2(working_precision)
        result.add_inplace(
            ln2.multiply(BigDecimal.from_integral_scalar(combined_ln2_factor))
        )
    if combined_ln1d25_factor != 0:
        var ln1d25 = cache.get_ln1d25(working_precision)
        result.add_inplace(
            ln1d25.multiply(
                BigDecimal.from_integral_scalar(combined_ln1d25_factor)
            )
        )

    # Round to final precision
    result.round_to_precision_inplace(
        precision=precision,
        rounding_mode=RoundingMode.half_even(),
        remove_extra_digit_due_to_rounding=True,
        fill_zeros_to_precision=False,
    )

    return result^


def log(x: BigDecimal, base: BigDecimal, precision: Int) raises -> BigDecimal:
    """Calculates the logarithm of x with respect to an arbitrary base.

    Args:
        x: The value to compute the logarithm.
        base: The base of the logarithm.
        precision: Desired precision in decimal digits.

    Returns:
        The logarithm of x with respect to base.

    Raises:
        ValueError: If x is negative or zero.
        ValueError: If base is negative, zero, or one.
    """
    comptime BUFFER_DIGITS = 9  # word-length, easy to append and trim
    var working_precision = precision + BUFFER_DIGITS

    # Special cases
    if x.sign:
        raise ValueError(
            message="Cannot compute logarithm of a negative number",
            function="log()",
        )
    if x.coefficient.is_zero():
        raise ValueError(
            message="Cannot compute logarithm of zero", function="log()"
        )

    # Base validation
    if base.sign:
        raise ValueError(message="Cannot use a negative base", function="log()")
    if base.coefficient.is_zero():
        raise ValueError(message="Cannot use zero as a base", function="log()")
    if (
        base.coefficient.number_of_digits() == base.scale + 1
        and base.coefficient.words[len(base.coefficient.words) - 1] == 1
    ):
        raise ValueError(
            message="Cannot use base 1 for logarithm", function="log()"
        )

    # Special cases
    if (
        x.coefficient.number_of_digits() == x.scale + 1
        and x.coefficient.words[len(x.coefficient.words) - 1] == 1
    ):
        return BigDecimal(BigUInt.zero(), 0, False)  # log_base(1) = 0

    if x == base:
        return BigDecimal(BigUInt.one(), 0, False)  # log_base(base) = 1

    # Optimization for base 10
    if (
        base.scale == 0
        and base.coefficient.number_of_digits() == 2
        and base.coefficient.words[len(base.coefficient.words) - 1] == 10
    ):
        return log10(x, precision)

    # Use the identity: log_base(x) = ln(x) / ln(base)
    # Use a shared cache so that both ln() calls reuse cached ln(2)/ln(1.25)
    var cache = MathCache()
    var ln_x = ln(x, working_precision, cache)
    var ln_base = ln(base, working_precision, cache)

    var result = ln_x.true_divide(ln_base, precision)
    return result^


def log10(x: BigDecimal, precision: Int) raises -> BigDecimal:
    """Calculates the base-10 logarithm of a BigDecimal value.

    Args:
        x: The value to compute log10.
        precision: Desired precision in decimal digits.

    Returns:
        The base-10 logarithm of x.

    Raises:
        ValueError: If x is negative or zero.
    """
    comptime BUFFER_DIGITS = 9  # word-length, easy to append and trim
    var working_precision = precision + BUFFER_DIGITS

    # Special cases
    if x.sign:
        raise ValueError(
            message="Cannot compute logarithm of a negative number",
            function="log10()",
        )
    if x.coefficient.is_zero():
        raise ValueError(
            message="Cannot compute logarithm of zero", function="log10()"
        )

    # Fast path: Powers of 10 are handled directly
    if x.coefficient.is_power_of_10():
        # If x = 10^n, return n
        var power = x.coefficient.number_of_trailing_zeros() - x.scale
        return BigDecimal.from_integral_scalar(power)

    # Special case for x = 1
    if (
        x.coefficient.number_of_digits() == x.scale + 1
        and x.coefficient.words[len(x.coefficient.words) - 1] == 1
    ):
        return BigDecimal(BigUInt.zero(), 0, False)  # log10(1) = 0

    # Use the identity: log10(x) = ln(x) / ln(10)
    # Use a shared cache so that ln(10) is retrieved from cache
    var cache = MathCache()
    var ln_result = ln(x, working_precision, cache)
    var ln10 = cache.get_ln10(working_precision)
    var result = ln_result.true_divide(ln10, precision)

    return result^


def ln_series_expansion(
    z: BigDecimal, working_precision: Int
) raises -> BigDecimal:
    """Calculate ln(1+z) using a hybrid Taylor / atanh series.

    For small |z| (few significant digits), uses the direct Taylor series:
        ln(1+z) = z - z²/2 + z³/3 - z⁴/4 + ...
    because multiplying by a small z is nearly free (few-digit coefficient).

    For larger |z|, uses the atanh (inverse hyperbolic tangent) identity:
        ln(1+z) = 2 * atanh(u),  where u = z / (2 + z)
        = 2 * (u + u³/3 + u⁵/5 + u⁷/7 + ...)
    which converges at rate u² ≤ 1/9 instead of |z| ≤ 1/2, giving ~3×
    fewer iterations at the cost of one upfront division.

    Args:
        z: The input value, should be |z| < 1 for convergence.
        working_precision: Desired working precision in significant digits.

    Returns:
        The ln(1+z) computed to the specified working precision.

    Raises:
        Error: Propagated from arithmetic operations.

    Notes:
        The last few digits of result are not accurate as there is no buffer
        for precision. You need to use a larger precision to get the last few
        digits accurate.
    """

    if z.is_zero():
        return BigDecimal(BigUInt.zero(), 0, False)

    # Decide strategy based on z's coefficient digit count.
    # When z has few significant digits (e.g. z = -0.01 for ln(0.99)),
    # the multiply-by-z is O(n × d) with d << n, making Taylor cheaper.
    # When z has many digits (after range reduction), the multiply cost
    # is similar for both, but atanh needs ~3× fewer terms.
    # The coefficient grows by ~z_digits each iteration in the Taylor
    # recurrence; we truncate it periodically to keep it bounded.
    var z_digits = z.coefficient.number_of_digits()

    # Threshold: use Taylor when z has ≤ 1/10 of the working precision
    # in digits.  Rationale (from benchmarks): when d = z_digits is small
    # relative to n = working_precision, each Taylor multiply costs O(n×d)
    # which is essentially O(n).  The atanh path trades 3× fewer iterations
    # for a heavier per-iteration cost (full n×n multiply by u²), so it
    # only wins when d ≈ n.  The 1/10 ratio was chosen empirically:
    # at p=100 the crossover is around d=10; at p=1000 around d=100.
    comptime _TAYLOR_ATANH_DIGIT_RATIO = 10
    if z_digits <= working_precision // _TAYLOR_ATANH_DIGIT_RATIO:
        # ---- Taylor path (optimal for small/simple z) ----
        var max_terms = Int(Float64(working_precision) * 2.5) + 1
        var result = BigDecimal(BigUInt.zero(), working_precision, False)
        var term = z.copy()
        var k: UInt32 = 1

        # ln(1+z) = z - z²/2 + z³/3 - z⁴/4 + ...
        result.add_inplace(term)  # first term is z

        for _ in range(2, max_terms):
            bigdecimal_arithmetics.multiply_inplace(term, z)
            # Truncate to prevent unbounded coefficient growth.
            # The coefficient grows by z_digits each iteration; without
            # this, after k iterations it has ~k×z_digits digits, making
            # each subsequent multiply O(k×d×n) — quadratic in k.
            if (
                term.coefficient.number_of_digits()
                > working_precision + z_digits
            ):
                term.round_to_precision_inplace(
                    working_precision,
                    RoundingMode.down(),
                    remove_extra_digit_due_to_rounding=False,
                    fill_zeros_to_precision=False,
                )
            k += 1

            var is_even = k % 2 == 0
            var next_term = term.true_divide_inexact_by_uint32(
                k, working_precision
            )

            if is_even:
                result.subtract_inplace(next_term)
            else:
                result.add_inplace(next_term)

            if next_term.adjusted() < -working_precision:
                break

        result.round_to_precision_inplace(
            precision=working_precision,
            rounding_mode=RoundingMode.down(),
            remove_extra_digit_due_to_rounding=False,
            fill_zeros_to_precision=False,
        )
        return result^

    # ---- atanh path (optimal for larger z with many digits) ----
    # Compute u = z / (2 + z)
    var two = BigDecimal(BigUInt(raw_words=[2]), 0, False)
    var two_plus_z = z.add(two)
    var u = z.true_divide(two_plus_z, working_precision)

    # Compute u² (cached for the recurrence)
    var u_squared = u.multiply(u)
    u_squared.round_to_precision_inplace(
        working_precision,
        RoundingMode.down(),
        remove_extra_digit_due_to_rounding=False,
        fill_zeros_to_precision=False,
    )

    # Series: 2*atanh(u) = 2u + 2u³/3 + 2u⁵/5 + ...
    # First term: t₀ = 2u
    # Recurrence: t_k = t_{k-1} * u² * (2k-1) / (2k+1)
    bigdecimal_arithmetics.multiply_inplace(u, two)
    var term = u^  # term = 2u (first term, k=0)
    var result = term.copy()

    # Convergence: u² ≤ 1/9, so ~1.05*p terms suffice (vs 3.3*p Taylor)
    var max_terms = Int(Float64(working_precision) * 1.2) + 10

    for k in range(1, max_terms):
        var old_denom = UInt32(2 * k - 1)
        var new_denom = UInt32(2 * k + 1)

        # Step 1: Undo previous denominator: multiply by (2k-1).
        # Note: when k=1, old_denom=1, so this is a no-op by design;
        # the first term (k=0) has denominator 1, which needs no undoing.
        biguint_arithmetics.multiply_by_uint32_inplace(
            term.coefficient, old_denom
        )
        # Step 2: Multiply by u²
        bigdecimal_arithmetics.multiply_inplace(term, u_squared)
        # Step 3: Divide by (2k+1) — also truncates to working_precision
        term = term.true_divide_inexact_by_uint32(new_denom, working_precision)

        result.add_inplace(term)

        if term.adjusted() < -working_precision:
            break

    result.round_to_precision_inplace(
        precision=working_precision,
        rounding_mode=RoundingMode.down(),
        remove_extra_digit_due_to_rounding=False,
        fill_zeros_to_precision=False,
    )
    return result^


def compute_ln2(working_precision: Int) raises -> BigDecimal:
    """Compute ln(2) to the specified working precision.

    Args:
        working_precision: Desired precision in significant digits.

    Returns:
        The ln(2) computed to the specified precision.

    Raises:
        Error: Propagated from underlying arithmetic operations.

    Notes:

    The last few digits of result are not accurate as there is no buffer for
    precision. You need to use a larger precision to get the last few digits
    accurate. The precision is only used to determine the number of terms in
    the series expansion, not for the final result.
    """
    # Directly using Taylor series expansion for ln(2) is not efficient
    # Instead, we can use the identity:
    # ln((1+x)/(1-x)) = 2*arcth(x) = 2*(x + x³/3 + x⁵/5 + ...)
    # For x = 1/3:
    # ln(2) = 2*(1/3 + (1/3)³/3 + (1/3)⁵/5 + ...)

    if working_precision <= 90:
        # Use precomputed value for ln(2) for lower precision
        var result = BigDecimal(
            BigUInt(
                raw_words=[
                    UInt32(605863326),
                    UInt32(969694715),
                    UInt32(493393621),
                    UInt32(120680009),
                    UInt32(360255254),
                    UInt32(75500134),
                    UInt32(458176568),
                    UInt32(417232121),
                    UInt32(559945309),
                    UInt32(693147180),
                ]
            ),
            90,
            False,
        )
        result.round_to_precision_inplace(
            precision=working_precision,
            rounding_mode=RoundingMode.down(),
            remove_extra_digit_due_to_rounding=False,
            fill_zeros_to_precision=False,
        )
        return result^

    var max_terms = Int(Float64(working_precision) * 2.5) + 1

    var number_of_words = working_precision // 9 + 1
    var words = List[UInt32](capacity=number_of_words)
    for _ in range(number_of_words):
        words.append(UInt32(333_333_333))
    var x = BigDecimal(
        BigUInt(raw_words=words^), number_of_words * 9, False
    )  # x = 1/3

    var result = BigDecimal(BigUInt.zero(), 0, False)
    var term = x.multiply(
        BigDecimal(BigUInt(raw_words=[2]), 0, False)
    )  # First term: 2*(1/3)
    var k: UInt32 = 1

    # Add terms: 2*(x + x³/3 + x⁵/5 + ...)
    # Series: term_k = 2 * x^(2k-1) * 1 * 3 * 5 * ... * (2k-3) / (1 * 3 * 5 * ... * (2k-1))
    # Recurrence: term_{k+1} = term_k * x² * k / (k+2)
    #
    # `x` is a finite-precision decimal approximation to 1/3. Because 1/3 is a
    # unit fraction, the x² factor is the rational 1/9, which we apply as a
    # single UInt32 divide by 9 (rounded once to the target precision) instead
    # of an O(M(n)) BigDecimal multiply by a pre-truncated 0.111…. We fold the
    # 1/9 and the 1/(k+2) factors into one divide by 9*(k+2), and apply the *k
    # factor at the coefficient level — so each iteration is O(n), and the
    # divide also avoids compounding the truncation error of an approximate x².
    for _ in range(1, max_terms):
        result.add_inplace(term)
        var new_k = k + 2
        # Multiply by k using coefficient-level UInt32 multiply (avoids BigDecimal alloc)
        biguint_arithmetics.multiply_by_uint32_inplace(term.coefficient, k)
        # term *= 1/9 * 1/(k+2): one O(n) single-word divide by 9*(k+2)
        term = term.true_divide_inexact_by_uint32(9 * new_k, working_precision)
        k = new_k
        if term.adjusted() < -working_precision:
            break

    result.round_to_precision_inplace(
        precision=working_precision,
        rounding_mode=RoundingMode.down(),
        remove_extra_digit_due_to_rounding=False,
        fill_zeros_to_precision=False,
    )
    return result^


def compute_ln1d25(precision: Int) raises -> BigDecimal:
    """Compute ln(1.25) to the specified precision.

    Args:
        precision: Desired precision in significant digits.

    Returns:
        The ln(1.25) computed to the specified precision.

    Raises:
        Error: Propagated from underlying arithmetic operations.

    Notes:

    The last few digits of result are not accurate as there is no buffer for
    precision. You need to use a larger precision to get the last few digits
    accurate.
    """
    # ln(1.25) = 2*atanh(1/9), since (1 + 1/9)/(1 - 1/9) = (10/9)/(8/9) = 1.25.
    # So ln(1.25) = 2*(1/9 + (1/9)³/3 + (1/9)⁵/5 + ...).
    # As in compute_ln2, `x` is a finite-precision decimal approximation to 1/9.
    # Because 1/9 is a unit fraction, the x² factor is the rational 1/81, which
    # we apply as a single UInt32 divide by 81 (rounded once to the target
    # precision) instead of an O(M(n)) BigDecimal multiply. We fold the 1/81 and
    # the 1/(2k+1) factors into one divide by 81*(k+2) and apply the *k factor
    # at the coefficient level, so each iteration is O(n).
    var working_precision = precision
    var max_terms = Int(Float64(working_precision) * 1.2) + 10

    var number_of_words = working_precision // 9 + 1
    var words = List[UInt32](capacity=number_of_words)
    for _ in range(number_of_words):
        words.append(UInt32(111_111_111))
    var x = BigDecimal(
        BigUInt(raw_words=words^), number_of_words * 9, False
    )  # x = 1/9

    var result = BigDecimal(BigUInt.zero(), 0, False)
    var term = x.multiply(
        BigDecimal(BigUInt(raw_words=[2]), 0, False)
    )  # First term: 2*(1/9)
    var k: UInt32 = 1

    # Recurrence: term_{k+1} = term_k * x² * k / (k+2), with x² = 1/81.
    for _ in range(1, max_terms):
        result.add_inplace(term)
        var new_k = k + 2
        # Multiply by k using coefficient-level UInt32 multiply (avoids BigDecimal alloc)
        biguint_arithmetics.multiply_by_uint32_inplace(term.coefficient, k)
        # term *= 1/81 * 1/(k+2): one O(n) single-word divide by 81*(k+2)
        term = term.true_divide_inexact_by_uint32(81 * new_k, working_precision)
        k = new_k
        if term.adjusted() < -working_precision:
            break

    result.round_to_precision_inplace(
        precision=working_precision,
        rounding_mode=RoundingMode.down(),
        remove_extra_digit_due_to_rounding=False,
        fill_zeros_to_precision=False,
    )
    return result^
