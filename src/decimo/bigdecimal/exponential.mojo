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
from std.ffi import _Global

from decimo.biguint.biguint import BigUInt
import decimo.biguint.arithmetics as biguint_arithmetics
import decimo.biguint.exponential as biguint_exponential
import decimo.decimal128.utility as decimal128_utility
from decimo.bigdecimal.bigdecimal import BigDecimal
import decimo.bigdecimal.arithmetics as bigdecimal_arithmetics
from decimo.errors import ValueError, OverflowError, ZeroDivisionError
from decimo.rounding_mode import RoundingMode

comptime _F64_SEED_DIGITS = 12
"""Correct decimal digits the `Float64` seed of a Newton iteration is worth.

`Float64` carries just under 16 decimal digits, and taking `x ** -0.5` costs a
couple more. Twelve is the conservative floor: the reciprocal-sqrt schedules
below halve down to this value so that the doubling actually reaches the top of
the schedule.
"""


def _reciprocal_sqrt_seed_f64(c: Float64) raises -> Float64:
    """Returns a `Float64` seed for `1 / sqrt(c)` worth `_F64_SEED_DIGITS`.

    Args:
        c: The value whose reciprocal square root is wanted, normalized by
            the caller into `[1, 100)`.

    Returns:
        A seed whose residual `1 - c r^2` is below `1e-12`, which is the
        accuracy the doubling schedules credit it with.

    Raises:
        Error: If no such seed can be built, which means the caller handed
            in something that is not a normalized positive number.

    Notes:

    `1 / sqrt(c)` rather than `c ** -0.5`: the power operator goes through
    `exp`/`log` and is accurate to only about ten digits for some inputs,
    which the doubling schedule would then carry all the way to the top.

    The seed is checked, not assumed. The condition that matters is not a
    band on `r` -- a seed of `0.5` lies in `(0.1, 1]` and still diverges for
    every `c` above 12 -- but the residual, which bounds both the distance
    from the root and the convergence basin `c r^2 < 3` of the iteration
    `r <- r (3 - c r^2) / 2`.

    When the direct value fails the check, the seed is rebuilt by running
    that same iteration in `Float64` from `0.1`, which is inside the basin
    for every `c` below 300. Growth is about 1.5 per step until the residual
    is small and quadratic after that, so the loop is over long before its
    cap. Rebuilding rather than clamping is what keeps the schedules honest:
    a clamped `0.1` is not worth twelve digits, nor even one, and the top of
    the schedule would come back short.
    """
    var r = Float64(1.0) / math.sqrt(c)
    if r > 0.0 and abs(1.0 - c * r * r) < 1e-12:
        return r

    r = 0.1
    for _ in range(60):
        var residual = 1.0 - c * r * r
        if abs(residual) < 1e-14:
            break
        r = r * (1.0 + 0.5 * residual)
    if r > 0.0 and abs(1.0 - c * r * r) < 1e-12:
        return r
    raise Error(
        "cannot build a reciprocal square root seed for ",
        c,
        "; the value was expected to be normalized into [1, 100)",
    )


# ===----------------------------------------------------------------------=== #
# List of functions in this module:
# - MathCache (struct): Cache for ln(2) and ln(1.25) constants
# - power(base: BigDecimal, exponent: BigDecimal, precision: Int) -> BigDecimal
# - integer_power(base: BigDecimal, exponent: BigDecimal, precision: Int) -> BigDecimal
# - root(x: BigDecimal, n: BigDecimal, precision: Int) -> BigDecimal
# - integer_root(x: BigDecimal, n: BigDecimal, precision: Int) -> BigDecimal
# - is_integer_reciprocal_and_return(n: BigDecimal) -> Tuple[Bool, BigDecimal]
# - is_odd_reciprocal(n: BigDecimal) -> Bool
# - isqrt_via_reciprocal_seed(c: BigUInt, working_digits: Int) -> BigUInt
# - sqrt(x: BigDecimal, precision: Int) -> BigDecimal  [public API]
# - sqrt_exact(x: BigDecimal, precision: Int) -> BigDecimal  [CPython-style]
# - sqrt_via_reciprocal_iteration(x: BigDecimal, precision: Int) -> BigDecimal
#       [returns sqrt(x); fast, for internal use]
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

    The two-argument `ln()`, `log()` and `log10()` share one process-wide
    instance, held in `std.ffi._Global` (see `_SHARED_MATH_CACHE`). Pass
    your own cache to the three-argument `ln()` to keep separate state.

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

    comptime GUARD_DIGITS = 9
    """Digits computed beyond what is asked for, and then dropped.

    `compute_ln2()` and `compute_ln1d25()` both say in their own docstrings
    that their last few digits are not accurate, because neither carries a
    buffer. These getters promise a value good to the precision asked for, so
    the buffer belongs here. `get_ln10()` has always added it; the other two
    passed the requested precision straight through and returned a value whose
    last digit was short by one: `get_ln1d25(5)` gave 0.22313 where ln(1.25)
    truncates to 0.22314, and above the 90-digit table in `compute_ln2()` the
    same happened to `get_ln2()` at about half the precisions tried.
    """

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
        self._ln2 = compute_ln2(precision + Self.GUARD_DIGITS)
        # Only `precision` digits are guaranteed, whatever was computed.
        self._ln2_precision = precision
        var computed = self._ln2.copy()
        computed.round_to_precision_inplace(
            precision=precision,
            rounding_mode=RoundingMode.down(),
            remove_extra_digit_due_to_rounding=False,
            fill_zeros_to_precision=False,
        )
        return computed^

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
        self._ln1d25 = compute_ln1d25(precision + Self.GUARD_DIGITS)
        # Only `precision` digits are guaranteed, whatever was computed.
        self._ln1d25_precision = precision
        var computed = self._ln1d25.copy()
        computed.round_to_precision_inplace(
            precision=precision,
            rounding_mode=RoundingMode.down(),
            remove_extra_digit_due_to_rounding=False,
            fill_zeros_to_precision=False,
        )
        return computed^

    def get_ln10(mut self, precision: Int) raises -> BigDecimal:
        """Returns ln(10) computed to at least the specified precision.

        If the cached value has sufficient precision, it is returned (rounded
        down to the requested precision). Otherwise, ln(10) is recomputed and
        cached at the new precision.

        Uses the identity ln(10) = 3*ln(2) + ln(1.25), with the cached
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
        var extra = precision + Self.GUARD_DIGITS
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


def _make_math_cache() -> MathCache:
    return MathCache()


comptime _SHARED_MATH_CACHE = _Global["decimo_math_cache", _make_math_cache]
"""One `MathCache` for the whole process.

Mojo 1.0 rejects module-level `var`; `std.ffi._Global` is the supported way
to hold process-wide state, if a private one. Each constant is stored at the
highest precision asked for so far and only ever grows.

Not thread-safe. `_Global` locks creation only, and a cache upgrade rewrites
a list-backed `BigDecimal` in place, so `ln`, `log` and `log10` must not run
on two threads at once. The Python binding is safe: CPython holds the GIL
across a call. A native program that wants those functions in parallel has
to serialize them itself until the Mojo standard library offers a lock.

Below about 1000 digits the constants come from the literal tables and the
cache saves nothing; above that it halves the cost of every `ln()` after the
first at a given precision.
"""


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
        remove_extra_digit_due_to_rounding=True,
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
        else:  # Even root
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

    # The seed wants the leading digits, and `Float64` holds about sixteen of
    # them. Taking the top two words as one 128-bit integer covers a word of
    # nine digits and one of eighteen alike, the same shape the square-root
    # seeds use. This used to add the second word divided by `1e9`, an offset
    # that only ever described a nine-digit word.
    ref abs_x_words = abs_x.coefficient.words
    var abs_x_n = len(abs_x_words)
    var top = UInt128(abs_x_words[abs_x_n - 1])
    if abs_x_n > 1:
        top = top * UInt128(BigUInt.BASE) + UInt128(abs_x_words[abs_x_n - 2])

    var digits_in_top: Int = 0
    var temp_val = top
    while temp_val > 0:
        temp_val //= 10
        digits_in_top += 1
    if digits_in_top == 0:
        digits_in_top = 1

    # `top` scaled into `[1, 10)`.
    var mantissa = Float64(top) / Float64(10.0) ** Float64(digits_in_top - 1)

    # `x = mantissa * 10^x_exp`, so `x^(1/n) = mantissa^(1/n) * 10^(x_exp/n)`.
    # The exponent is split into whole decades and a fraction so that every
    # `Float64` here stays inside `[1, 10)`. Forming `x` itself first, which
    # is what this did, overflows to infinity above 308 digits: the seed was
    # then infinite, Newton cannot walk back from that in the handful of steps
    # it runs, and the cube root of `10^330` came out as `3.1E+123` where the
    # answer is `1E+110`. Anything with more than about 310 digits was wrong.
    var exponent_decades = x_exp // n_int
    var exponent_fraction = Float64(x_exp - exponent_decades * n_int) / Float64(
        n_int
    )
    var guess_f64 = mantissa ** (1.0 / Float64(n_int)) * Float64(10.0) ** (
        exponent_fraction
    )
    # Clamp to avoid degenerate values
    if guess_f64 <= 0.0 or guess_f64 != guess_f64:  # NaN check
        guess_f64 = 1.0

    var r = BigDecimal(String(guess_f64))
    # The whole decades, applied to the exponent rather than through `Float64`.
    r.scale -= exponent_decades

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
        if n_int <= Int(BigUInt.Word.MAX):
            r_new = numerator.true_divide_inexact_by_word(
                BigUInt.Word(n_int), iter_precision
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
    Same applies to 1 (except exact 1), 7, 9.
    """
    # If n is of form 1/m where m is an odd integer, then 1/n = m is odd.

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

    # The coefficient must fit an `Int`. Ask, rather than counting words and
    # reassembling them: the count was 2 and the multiplier `10^9`, both of
    # which describe a nine-digit word. At eighteen digits two words are
    # `10^36` and do not fit an `Int` at all, and the reassembly was scaling
    # the high word by `10^9` on top of that.
    var numerator: Int
    try:
        numerator = n.coefficient.to_int()
    except:
        return Tuple(False, 0, 0)

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
# Decimal.sqrt() output. For large numbers (>20 words),
# `isqrt_via_reciprocal_seed` uses reciprocal sqrt with precision doubling for
# a fast initial approximation, then exact integer Newton iterations to
# converge to isqrt(c).
#
# Function hierarchy:
# - sqrt()
#       Public API, delegates to sqrt_exact().
# - sqrt_exact()
#       CPython-style exact integer algorithm. Produces results identical to
#       Python's Decimal.sqrt().
# - sqrt_via_reciprocal_iteration()
#       Returns sqrt(x), reached through the division-free Newton iteration
#       for 1/sqrt(x). For use as an intermediate by other functions (e.g.
#       arctan, ln) where exact perfect-square detection is unnecessary.
#       It returns the root itself, not the reciprocal - the reciprocal is
#       `bigint.exponential.reciprocal_sqrt_fixed_point()`.
# - isqrt_via_reciprocal_seed()
#       Hybrid isqrt: reciprocal sqrt approximation + exact integer Newton
#       refinement. Used by sqrt_exact() for large numbers.
# - sqrt_newton()
#       Legacy implementation (v0.5.0).
# ===----------------------------------------------------------------------=== #


# TODO:
# When global config for pad_zeros_to_precision is implemented,
# Pass the config to sqrt() and use it to control whether to
# call `sqrt_exact()` (pad zeros) or `sqrt_via_reciprocal_iteration()` (no padding)
def sqrt(
    x: BigDecimal,
    precision: Int,
    rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
) raises -> BigDecimal:
    """Calculate the square root of a BigDecimal number.

    This is the public API for square root. It delegates to `sqrt_exact()`,
    which uses the CPython _pydecimal.py algorithm for bit-perfect results
    that match Python's `Decimal.sqrt()` output exactly.

    Use this function when the result is returned directly to users.
    For intermediate computations inside other functions (e.g., arctan, ln),
    prefer `sqrt_via_reciprocal_iteration()` for better performance.

    Args:
        x: The number to calculate the square root of.
        precision: The desired precision (number of significant digits) of the
            result.
        rounding_mode: How to round the result. Every mode is exact here, not
            approximated with guard digits: see the note where `sqrt_exact()`
            rounds.

    Returns:
        The square root of x with the specified precision.

    Raises:
        ValueError: If x is negative.
    """
    return sqrt_exact(x, precision, rounding_mode)


def isqrt_via_reciprocal_seed(
    c: BigUInt, working_digits: Int
) raises -> BigUInt:
    """Returns `isqrt(c)`, seeded by a reciprocal square root approximation.

    The seed is what makes this faster than a plain integer Newton: reaching
    `sqrt(c)` through `1 / sqrt(c)` needs no division, so the approximation is
    cheap, and the exact refinement that follows it then costs one or two
    divisions instead of a full convergence.

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
    #
    # The seed wants the leading digits and `Float64` holds about sixteen of
    # them, which is two words at nine digits each and one and a bit at
    # eighteen. Taking the top two words as one 128-bit integer covers both
    # without knowing which: the only thing it has to be told is `BASE`.
    #
    # The version this replaces added the second word at a hand-written
    # `10^(digits_in_top + 8)`, where the 8 was `DIGITS_PER_WORD - 1` spelled
    # out. A wider word left that offset nine decades short, the seed was
    # worth eight digits where the schedule below credits it with
    # `_F64_SEED_DIGITS`, and every result came back with about two thirds of
    # the digits it promised -- silently, because nothing checks the seed.
    ref c_norm_words = c_norm.coefficient.words
    var c_norm_n = len(c_norm_words)
    var top = UInt128(c_norm_words[c_norm_n - 1])
    if c_norm_n > 1:
        top = top * UInt128(BigUInt.BASE) + UInt128(c_norm_words[c_norm_n - 2])

    var digits_in_top: Int = 0
    var temp_val = top
    while temp_val > 0:
        temp_val //= 10
        digits_in_top += 1
    if digits_in_top == 0:
        digits_in_top = 1

    # `top` scaled into `[1, 10)`, then placed by the value's own exponent.
    # Doing it in two steps keeps `10.0 ** e` away from the range where it
    # underflows: `e` here is at most a couple, where the value's full
    # exponent can be thousands.
    var mantissa = Float64(top) / Float64(10.0) ** Float64(digits_in_top - 1)
    var c_norm_exp = c_norm.adjusted()
    var c_norm_f64 = mantissa * Float64(10.0) ** Float64(c_norm_exp)
    # What the seed's accuracy buys here is speed, not digits. The exact
    # integer Newton refinement at the end of this function corrects whatever
    # the float part leaves behind, so the answer is right regardless:
    # truncating this seed to
    # a single digit still returns `sqrt(2)` correct to 400 digits. It returns
    # it more slowly, because the refinement then pays for full-size divisions
    # the schedule was supposed to have avoided. Measured on `sqrt(2)`:
    #
    # | digits | full seed | seed truncated to one digit |
    # | ------ | --------- | --------------------------- |
    # |    400 |   16.2 us |                     15.5 us |
    # |  1 000 |   26.6 us |                     47.3 us |
    # |  2 000 |   54.2 us |                    109.7 us |
    #
    # What the seed does have to guarantee is landing inside the convergence
    # basin, which `_reciprocal_sqrt_seed_f64()` checks; a seed outside it
    # diverges, and `test_sqrt_via_reciprocal_iteration_matches_sqrt_exact`
    # catches that.
    var r_f64 = _reciprocal_sqrt_seed_f64(c_norm_f64)

    var r = BigDecimal(String(r_f64))

    # --- Precision doubling schedule ---
    # Halve down to what the seed is worth. A Newton step doubles the correct
    # digits, so `n` steps reach `_F64_SEED_DIGITS * 2^n`; stopping the halving
    # higher than the seed leaves the top of the schedule short of its nominal
    # precision and forces the integer refinement below to pay for extra
    # full-size divisions. That is a cost, not a correctness question -- see
    # the note on the seed above.
    var prec_schedule = List[Int]()
    var p = working_digits
    while p > _F64_SEED_DIGITS:
        prec_schedule.append(p)
        p = (p + 1) // 2

    # Constant 1
    var one = BigDecimal(BigUInt(raw_words=[1]), 0, False)

    # --- Newton iterations: r_{k+1} = r_k + r_k * (1 - c_norm * r_k^2) / 2 ---
    #
    # Rearranged around the residual for exactly the reason spelled out in
    # `sqrt_via_reciprocal_iteration()`: `e = 1 - c_norm * r^2` is around `10^(-ip/2)`, and a
    # `BigDecimal` holds those leading zeros in the scale rather than the
    # coefficient, so the correction multiply is half-width by half-width where
    # `r * (3 - c_norm * r^2)` was half-width by full-width.
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

        # e = 1 - c_norm * r^2, the Newton residual. Signed, and tiny.
        var residual = one.subtract(r_sq)

        # r * e / 2
        bigdecimal_arithmetics.multiply_inplace(residual, r)
        residual.round_to_precision_inplace(
            precision=ip,
            rounding_mode=RoundingMode.half_up(),
            remove_extra_digit_due_to_rounding=True,
            fill_zeros_to_precision=False,
        )
        residual = residual.true_divide_inexact_by_word(BigUInt.Word(2), ip)

        # r + r * e / 2
        r = r.add(residual)
        r.round_to_precision_inplace(
            precision=ip,
            rounding_mode=RoundingMode.half_up(),
            remove_extra_digit_due_to_rounding=True,
            fill_zeros_to_precision=False,
        )

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


def sqrt_exact(
    x: BigDecimal,
    precision: Int,
    rounding_mode: RoundingMode = RoundingMode.ROUND_HALF_EVEN,
) raises -> BigDecimal:
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
    square detection is not needed, use `sqrt_via_reciprocal_iteration()` instead.

    Args:
        x: The number to calculate the square root of.
        precision: The desired precision (number of significant digits) of the
            result.
        rounding_mode: How to round the result. Exact under every mode, see
            the note where the rounding happens.

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
    # so that sqrt(c) * 10^e = sqrt(x)
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
    # For small c (up to 20 words), BigUInt.sqrt() is fast enough directly.
    var n: BigUInt
    if len(c.words) <= 20:
        n = biguint_exponential.sqrt(c)
    else:
        n = isqrt_via_reciprocal_seed(c, prec + 10)

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
        # The BigUInt base is a power of ten, so n % 5 == (last_word % 5)
        if n.words[0] % 5 == 0:
            biguint_arithmetics.add_by_word_inplace(n, 1)

    # Construct result: coefficient=n, scale=-e (since exponent=e means *10^e)
    var result = BigDecimal(n^, -e, False)

    # Round to the requested precision. Applied unconditionally: for exact
    # results that already fit within `precision` digits this is a no-op, but
    # when the natural digit count exceeds `precision` (e.g. sqrt(10000) at
    # precision=1) it correctly truncates -- matching CPython's
    # `_fix(context)` behavior.
    #
    # Every mode is exact here, which is what the perturbation above buys.
    # `n` is `isqrt` of the scaled coefficient, so when the result is inexact
    # the true root lies strictly between `n` and `n + 1`; and `n` never ends
    # in `0` or `5`, since those were nudged. So the last digit of `n` says
    # everything the discarded tail would: a directional mode reads it as a
    # non-zero remainder and steps away from zero, a half mode is never
    # handed a false tie, and neither can be wrong by a digit. That is why
    # `sqrt` needs no guard digits under ROUND_FLOOR where `exp` and `ln`
    # still do.
    result.round_to_precision_inplace(
        precision=precision,
        rounding_mode=rounding_mode,
        remove_extra_digit_due_to_rounding=True,
        fill_zeros_to_precision=False,
    )

    return result^


def sqrt_via_reciprocal_iteration(
    x: BigDecimal, precision: Int
) raises -> BigDecimal:
    """Returns `sqrt(x)`, computed through a reciprocal square root iteration.

    The return value is the square root itself, not its reciprocal; the
    reciprocal only appears inside, because the Newton iteration for
    `1 / sqrt(x)` needs no division where the one for `sqrt(x)` does. For the
    reciprocal as a return value, see
    `bigint.exponential.reciprocal_sqrt_fixed_point()`.

    Uses reciprocal square root Newton iteration with precision doubling:
        r_{k+1} = r_k + r_k * (1 - x * r_k^2) / 2   (computes 1/sqrt(x))
    Then sqrt(x) = x * r.

    That is the textbook `r * (3 - x * r^2) / 2` rearranged around the
    residual, which makes the correction multiply half-width by half-width
    instead of half-width by full-width. See the note on the loop itself.

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
            function="sqrt_via_reciprocal_iteration()",
        )

    if x.coefficient.is_zero():
        return BigDecimal(BigUInt.zero(), (x.scale + 1) // 2, False)

    # For x = 1, return 1
    if x.is_one():
        return BigDecimal(BigUInt.one(), 0, False)

    comptime BUFFER_DIGITS = 25
    var working_precision = precision + BUFFER_DIGITS

    # --- Normalization ---
    # Shift x by an even power of 10 to bring it into [1, 100) for a
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
    #
    # The seed wants the leading digits and `Float64` holds about sixteen of
    # them, which is two words at nine digits each and one and a bit at
    # eighteen. Taking the top two words as one 128-bit integer covers both
    # without knowing which: the only thing it has to be told is `BASE`.
    #
    # The version this replaces added the second word at a hand-written
    # `10^(digits_in_top + 8)`, where the 8 was `DIGITS_PER_WORD - 1` spelled
    # out. A wider word left that offset nine decades short, the seed was
    # worth eight digits where the schedule below credits it with
    # `_F64_SEED_DIGITS`, and every result came back with about two thirds of
    # the digits it promised -- silently, because nothing checks the seed.
    ref x_norm_words = x_norm.coefficient.words
    var x_norm_n = len(x_norm_words)
    var top = UInt128(x_norm_words[x_norm_n - 1])
    if x_norm_n > 1:
        top = top * UInt128(BigUInt.BASE) + UInt128(x_norm_words[x_norm_n - 2])

    var digits_in_top: Int = 0
    var temp_val = top
    while temp_val > 0:
        temp_val //= 10
        digits_in_top += 1
    if digits_in_top == 0:
        digits_in_top = 1

    # `top` scaled into `[1, 10)`, then placed by the value's own exponent.
    # Doing it in two steps keeps `10.0 ** e` away from the range where it
    # underflows: `e` here is at most a couple, where the value's full
    # exponent can be thousands.
    var mantissa = Float64(top) / Float64(10.0) ** Float64(digits_in_top - 1)
    var x_norm_exp = x_norm.adjusted()
    var x_norm_f64 = mantissa * Float64(10.0) ** Float64(x_norm_exp)
    var r_f64 = _reciprocal_sqrt_seed_f64(x_norm_f64)

    var r = BigDecimal(String(r_f64))

    # --- Precision doubling schedule ---
    # Build the list from `working_precision` down to what the seed is worth,
    # then iterate in reverse. Halving `n` times from `working_precision` lands
    # at or below `_F64_SEED_DIGITS`, so `working_precision <=
    # _F64_SEED_DIGITS * 2^n` and the `n` doublings below reach the top. A
    # higher stopping point
    # silently returns fewer correct digits than asked for: with the halving
    # stopped at 20 the seed was credited with 20 digits it does not have, and
    # `sqrt_via_reciprocal_iteration(10005, 5009)` came back correct to only
    # 4244 digits.
    var prec_schedule = List[Int]()
    var p = working_precision
    while p > _F64_SEED_DIGITS:
        prec_schedule.append(p)
        p = (p + 1) // 2

    # Constant 1
    var one = BigDecimal(BigUInt(raw_words=[1]), 0, False)

    # --- Newton iterations: r_{k+1} = r_k + r_k * (1 - x_norm * r_k^2) / 2 ---
    #
    # This is the textbook `r * (3 - x * r^2) / 2` rearranged around the
    # residual `e = 1 - x * r^2`. The two forms are algebraically identical -
    # `(3 - x r^2) / 2 = 1 + e / 2` - but they cost different amounts. `r`
    # entering an iteration is accurate to half the target, so `e` is around
    # `10^(-ip/2)` and a `BigDecimal` keeps those leading zeros in the scale
    # rather than in the coefficient. The correction multiply is therefore
    # half-width by half-width, where `r * (3 - x r^2)` was half-width by
    # full-width. That is one full half-precision multiplication saved per
    # iteration, about 3 ms of `pi(100000)`.
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

        # e = 1 - x_norm * r^2, the Newton residual. Signed, and tiny.
        var residual = one.subtract(r_sq)

        # r * e / 2
        bigdecimal_arithmetics.multiply_inplace(residual, r)
        residual.round_to_precision_inplace(
            precision=ip,
            rounding_mode=RoundingMode.half_up(),
            remove_extra_digit_due_to_rounding=True,
            fill_zeros_to_precision=False,
        )
        residual = residual.true_divide_inexact_by_word(BigUInt.Word(2), ip)

        # r + r * e / 2
        r = r.add(residual)
        r.round_to_precision_inplace(
            precision=ip,
            rounding_mode=RoundingMode.half_up(),
            remove_extra_digit_due_to_rounding=True,
            fill_zeros_to_precision=False,
        )

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


# Legacy implementation
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
    # the square root has enough precision. Denote the precision as p.
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


# ===----------------------------------------------------------------------=== #
# Rounding that is decided rather than assumed
#
# A kernel computes a value to whatever width it is asked for, and says how
# far from the truth that may be. A caller who wants `p` digits does not round
# what came back and hope: it asks for more digits than it needs, takes the
# interval the kernel's own bound allows, and checks that the whole of that
# interval rounds to one answer. If it does, the answer is right -- under any
# mode, the default included. If it does not, the width doubles and the kernel
# is asked again.
#
# What this replaces is a fixed number of guard digits and a single rounding:
# the same computation without the check, right whenever the interval happens
# to miss a boundary and silently wrong when it does not. That was as true of
# HALF_EVEN as of the directional modes -- a tie is just another boundary.
#
# The loop ends because a transcendental value never sits exactly on a decimal
# boundary. The arguments where the value is rational -- `exp(0)`, `ln(1)`,
# `log10(10^k)`, an integer exponent -- are answered before the loop is
# entered, and nothing else can be exactly on one.
#
# `sqrt` is not here. A root is algebraic, and `sqrt_exact()` decides it by
# construction: `isqrt` of the scaled coefficient, nudged off `0` and `5`, is
# already the correctly rounded answer under every mode.
# ===----------------------------------------------------------------------=== #

comptime EXP_SLACK = 4
"""Units in the last place `exp()` may be off at the width it was asked for.

It carries `0.35 * m + 9` digits of its own through the squarings and rounds
once at the end, so one unit is the honest figure. Four is the margin this
decides with.
"""

comptime LN_SLACK = 4
"""Units in the last place `ln()` may be off at the width it was asked for.

Its constants come from tables good to the last digit, or from series whose
error `test_bigdecimal_ln_constants_bound.mojo` pins, and `MathCache` adds
nine digits on top.
"""

comptime LOG10_SLACK = 4
"""Units in the last place `log10()` may be off.

It is `ln(x) / ln(10)`: the two logarithms and the division between them.
"""

comptime POWER_SLACK = 8
"""Units in the last place `power()` may be off.

It is `exp(exponent * ln(base))`, so the bounds of both compound and the
multiply between them rounds once more.
"""

comptime _ZIV_START = 3
"""Digits asked for beyond the caller's precision on the first attempt.

The check fails, and the width grows, only when a rounding boundary lies
within `slack` units of the last place of that width: about eight calls in a
thousand at three digits, one in twelve thousand at five, one in a hundred
million at ten.

Wider is not better. Asking for ten cost 37% on `exp` at 28 digits, five cost
20%, three costs 12%, while a retry -- which is one more call at six digits
over, not a doubling of the work -- costs about the same again on eight calls
in a thousand. Three is where the two curves meet.
"""

comptime _ZIV_LIMIT = 8
"""How many times the width may double before giving up.

Eight doublings is 2560 digits beyond the caller's precision, and the loop
always ends long before that. It is here so that a bug ends in an error
rather than in a hang.
"""


def _settled_answer(
    wide: BigDecimal,
    width: Int,
    slack: Int,
    precision: Int,
    rounding_mode: RoundingMode,
) raises -> Optional[BigDecimal]:
    """Returns the answer, if every value the kernel's bound allows rounds to it.

    Args:
        wide: What the kernel returned.
        width: The number of significant digits it was asked for.
        slack: Units in the last place of `width` the kernel may be off by.
        precision: The number of significant digits wanted.
        rounding_mode: How to round.

    Returns:
        The rounded value when the whole interval `wide +/- slack` rounds to
        it, and nothing when the interval straddles a boundary and the answer
        is therefore not yet decided.

    Raises:
        Error: If the arithmetic on the interval fails.
    """
    if wide.coefficient.is_zero():
        return wide.copy()

    # One unit in the last place of what the kernel returned is where its own
    # error lives.
    var last_place = wide.adjusted() - width + 1
    var reach = BigDecimal(
        BigUInt.from_word_unsafe(BigUInt.Word(slack)), -last_place, False
    )
    var low = wide.subtract(reach, precision=0)
    var high = wide.add(reach, precision=0)
    low.round_to_precision_inplace(
        precision=precision,
        rounding_mode=rounding_mode,
        remove_extra_digit_due_to_rounding=True,
        fill_zeros_to_precision=False,
    )
    high.round_to_precision_inplace(
        precision=precision,
        rounding_mode=rounding_mode,
        remove_extra_digit_due_to_rounding=True,
        fill_zeros_to_precision=False,
    )
    if low == high and low.scale == high.scale:
        return low^
    return None


def _round_by_deciding[
    kernel: def(BigDecimal, Int) thin raises -> BigDecimal, slack: Int
](
    x: BigDecimal, precision: Int, rounding_mode: RoundingMode
) raises -> BigDecimal:
    """Returns `kernel(x)` rounded to `precision` digits, decided not assumed.

    Parameters:
        kernel: The function to evaluate.
        slack: Units in the last place the kernel may be off by at the width
            it is asked for. Each function states its own; see `EXP_SLACK`.

    Args:
        x: The argument to pass to the kernel.
        precision: The number of significant digits wanted.
        rounding_mode: How to round the result.

    Returns:
        The correctly rounded value.

    Raises:
        Error: If the kernel raises, or if the width doubles `_ZIV_LIMIT`
            times without settling, which would mean the kernel is further
            off than `slack` allows.
    """
    var width = precision + _ZIV_START
    for _ in range(_ZIV_LIMIT):
        var settled = _settled_answer(
            kernel(x, width), width, slack, precision, rounding_mode
        )
        if settled:
            return settled.take()
        width += width - precision
    raise Error(
        "the rounding of this value could not be decided; the kernel is"
        " further from the true value than its stated bound allows"
    )


def exp_rounded(
    x: BigDecimal, precision: Int, rounding_mode: RoundingMode
) raises -> BigDecimal:
    """Returns `exp(x)` rounded to `precision` digits, decided not assumed.

    Args:
        x: The exponent.
        precision: The number of significant digits wanted.
        rounding_mode: How to round the result.

    Returns:
        The correctly rounded value.

    Raises:
        Error: Propagated from `exp()`.
    """
    if x.coefficient.is_zero():
        # `exp(0)` is exactly one, the only argument where it is rational.
        return exp(x, precision)
    return _round_by_deciding[exp, EXP_SLACK](x, precision, rounding_mode)


def ln_rounded(
    x: BigDecimal, precision: Int, rounding_mode: RoundingMode
) raises -> BigDecimal:
    """Returns `ln(x)` rounded to `precision` digits, decided not assumed.

    Args:
        x: The value to take the logarithm of.
        precision: The number of significant digits wanted.
        rounding_mode: How to round the result.

    Returns:
        The correctly rounded value.

    Raises:
        Error: Propagated from `ln()`.
    """
    if x == BigDecimal.one():
        # `ln(1)` is exactly zero, the only argument where it is rational.
        return ln(x, precision)
    return _round_by_deciding[ln, LN_SLACK](x, precision, rounding_mode)


def log10_rounded(
    x: BigDecimal, precision: Int, rounding_mode: RoundingMode
) raises -> BigDecimal:
    """Returns `log10(x)` rounded to `precision` digits, decided not assumed.

    Args:
        x: The value to take the logarithm of.
        precision: The number of significant digits wanted.
        rounding_mode: How to round the result.

    Returns:
        The correctly rounded value.

    Raises:
        Error: Propagated from `log10()`.
    """
    if _is_power_of_ten(x):
        # `log10(10^k)` is exactly `k`, the only argument where it is
        # rational, and `log10()` answers those exactly already.
        return log10(x, precision)
    return _round_by_deciding[log10, LOG10_SLACK](x, precision, rounding_mode)


def power_rounded(
    base: BigDecimal,
    exponent: BigDecimal,
    precision: Int,
    rounding_mode: RoundingMode,
) raises -> BigDecimal:
    """Returns `base ** exponent` rounded, decided not assumed.

    Args:
        base: The base.
        exponent: The exponent.
        precision: The number of significant digits wanted.
        rounding_mode: How to round the result.

    Returns:
        The correctly rounded value.

    Raises:
        Error: Propagated from `power()`, and if the width doubles
            `_ZIV_LIMIT` times without settling.

    Notes:

    An integer exponent is left to `power()` itself: that path is a chain of
    exact multiplications with one rounding at the end, so the mode simply
    applies, and the value can land exactly on a boundary -- `2 ** 10` is
    `1024` -- which is the one case the loop could not settle.
    """
    if exponent.is_integer():
        var result = power(base, exponent, precision)
        result.round_to_precision_inplace(
            precision=precision,
            rounding_mode=rounding_mode,
            remove_extra_digit_due_to_rounding=True,
            fill_zeros_to_precision=False,
        )
        return result^

    var width = precision + _ZIV_START
    for _ in range(_ZIV_LIMIT):
        var settled = _settled_answer(
            power(base, exponent, width),
            width,
            POWER_SLACK,
            precision,
            rounding_mode,
        )
        if settled:
            return settled.take()
        width += width - precision
    raise Error(
        "the rounding of this power could not be decided; the kernel is"
        " further from the true value than its stated bound allows"
    )


def _is_power_of_ten(x: BigDecimal) -> Bool:
    """Returns whether `x` is ten to some whole power.

    Args:
        x: The value to test.

    Returns:
        True for `1`, `100`, `0.001` and the like, where `log10` is a whole
        number and the loop would never settle because the true value sits
        exactly on a boundary.
    """
    if x.sign or x.coefficient.is_zero():
        return False
    var text = x.coefficient.to_string()
    if not (text[byte=0] == "1"):
        return False
    for index in range(1, text.byte_length()):
        if not (text[byte=index] == "0"):
            return False
    return True


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
            biguint_arithmetics.multiply_by_word_inplace(reduced_coeff, 5)
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
            remove_extra_digit_due_to_rounding=True,
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
    # Each loop does one single-word division, one multiplication and one
    # addition, and there are about 2.3 * precision iterations. The division
    # dominates.

    var max_number_of_terms = Int(Float64(minimum_precision) * 2.5) + 1
    var result = BigDecimal(BigUInt.one(), 0, False)
    var term = BigDecimal(BigUInt.one(), 0, False)
    var n: BigUInt.Word = 1

    # Calculate Taylor series: 1 + x + x²/2! + x³/3! + ...
    for _ in range(1, max_number_of_terms):
        # Calculate next term: x^i/i! = x^{i-1} * x/i
        # We can use the previous term to calculate the next one
        # Use O(n) single-word division instead of full BigDecimal div
        var add_on = x.true_divide_inexact_by_word(n, minimum_precision)
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

        # Check if we've reached desired precision
        if term.adjusted() < -minimum_precision:
            break

    result.round_to_precision_inplace(
        precision=minimum_precision,
        rounding_mode=RoundingMode.half_up(),
        remove_extra_digit_due_to_rounding=False,
        fill_zeros_to_precision=False,
    )

    return result^


# ===----------------------------------------------------------------------=== #
# Logarithmic functions
# ===----------------------------------------------------------------------=== #


def ln(x: BigDecimal, precision: Int) raises -> BigDecimal:
    """Calculate the natural logarithm of x to the specified precision.

    Uses the process-wide `MathCache`, so repeated calls at the same or a
    lower precision reuse ln(2) and ln(1.25). Pass your own cache to the
    three-argument overload to keep separate state.

    Args:
        x: The input value.
        precision: Desired precision in significant digits.

    Returns:
        The natural logarithm of x to the specified precision.

    Raises:
        ValueError: If x is negative or zero.
    """
    return ln(x, precision, _SHARED_MATH_CACHE.get_or_create_ptr()[])


def ln(
    x: BigDecimal, precision: Int, mut cache: MathCache
) raises -> BigDecimal:
    """Calculate the natural logarithm of x to the specified precision.

    This overload accepts a `MathCache` to reuse cached values of ln(2) and
    ln(1.25) across multiple calls.

    Args:
        x: The input value.
        precision: Desired precision in significant digits.
        cache: A mutable MathCache instance for caching ln(2) and ln(1.25).

    Returns:
        The natural logarithm of x to the specified precision.

    Raises:
        ValueError: If x is negative or zero.
    """
    comptime BUFFER_DIGITS = 9  # guard digits, dropped by the final rounding
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
    # ln(2) and ln(1.25), which was the source of the large slowdown
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
    comptime BUFFER_DIGITS = 9  # guard digits, dropped by the final rounding
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
    # The process-wide cache serves both ln() calls with the same ln(2) and
    # ln(1.25), and keeps them for the next call.
    var cache = _SHARED_MATH_CACHE.get_or_create_ptr()
    var ln_x = ln(x, working_precision, cache[])
    var ln_base = ln(base, working_precision, cache[])

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
    comptime BUFFER_DIGITS = 9  # guard digits, dropped by the final rounding
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
    # The process-wide cache holds ln(10) as well.
    var cache = _SHARED_MATH_CACHE.get_or_create_ptr()
    var ln_result = ln(x, working_precision, cache[])
    var ln10 = cache[].get_ln10(working_precision)
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

    # The Taylor recurrence grows the coefficient by about `z_digits` each
    # iteration, and the loop truncates it back to keep the multiply bounded.
    var z_digits = z.coefficient.number_of_digits()

    # Which series to sum is decided by how small `z` is, not by how many
    # digits it has. Taylor gains `-adjusted(z)` digits a term and atanh
    # gains twice that, and once `z` is long enough to multiply by, a term
    # costs about the same either way -- so Taylor is worth it only when the
    # series is over in a few terms.
    #
    # The rule was `z_digits <= working_precision / 10`, which reads the
    # coefficient's length and not its magnitude. `ln(2.3456789)` has eight
    # digits but leaves `z = 0.34` after the reduction, so it took the Taylor
    # path at every precision above 71 and paid twice over: 41.3 microseconds
    # at 100 digits against 16.5, and 319 against 172 at 400.
    comptime _TAYLOR_TERM_BUDGET = 20
    var magnitude = -z.adjusted()
    if magnitude < 1:
        magnitude = 1

    if working_precision <= _TAYLOR_TERM_BUDGET * magnitude:
        # ---- Taylor path (optimal for small/simple z) ----
        var max_terms = Int(Float64(working_precision) * 2.5) + 1
        var result = BigDecimal(BigUInt.zero(), working_precision, False)
        var term = z.copy()
        var k: BigUInt.Word = 1

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
            var next_term = term.true_divide_inexact_by_word(
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
        var old_denom = BigUInt.Word(2 * k - 1)
        var new_denom = BigUInt.Word(2 * k + 1)

        # Step 1: Undo previous denominator: multiply by (2k-1).
        # Note: when k=1, old_denom=1, so this is a no-op by design;
        # the first term (k=0) has denominator 1, which needs no undoing.
        biguint_arithmetics.multiply_by_word_inplace(
            term.coefficient, old_denom
        )
        # Step 2: Multiply by u²
        bigdecimal_arithmetics.multiply_inplace(term, u_squared)
        # Step 3: Divide by (2k+1) — also truncates to working_precision
        term = term.true_divide_inexact_by_word(new_denom, working_precision)

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


comptime LN2_1100 = (
    "0.6931471805599453094172321214581765680755001343602552541206800094"
    "933936219696947156058633269964186875420014810205706857336855202357"
    "581305570326707516350759619307275708283714351903070386238916734711"
    "233501153644979552391204751726815749320651555247341395258829504530"
    "070953263666426541042391578149520437404303855008019441706416715186"
    "447128399681717845469570262716310645461502572074024816377733896385"
    "506952606683411372738737229289564935470257626520988596932019650585"
    "547647033067936544325476327449512504060694381471046899465062201677"
    "204245245296126879465461931651746813926725041038025462596568691441"
    "928716082938031727143677826548775664850856740776484514644399404614"
    "226031930967354025744460703080960850474866385231381816767514386674"
    "766478908814371419854942315199735488037516586127535291661000710535"
    "582498794147295092931138971559982056543928717000721808576102523688"
    "921324497138932037843935308877482597017155910708823683627589842589"
    "185353024363421436706118923678919237231467232172053401649256872747"
    "782344535347648114941864238677677440606956265737960086707625719918"
    "4734022651462837904883062033061144630073719489"
)
"""The value of ln(2), truncated to 1100 digits.

Generated with CPython: `getcontext().prec = 1300; str(Decimal(2).ln())[:1102]`.
Parsing this costs about 1 us; computing it costs about 1600 us."""


comptime LN1D25_1100 = (
    "0.2231435513142097557662950903098345033746010855480072136712878724"
    "873917437682683334184072241003422357159633409805741914323529647578"
    "084150855682751141935538036907244958404403752728787789545581781150"
    "234549628718838669114847378481775629020244201723412488967553919153"
    "438690698343869770787621459595440908838105576723945362964762501521"
    "344182544171074818811404016514783722736865734525782498550261927635"
    "580948625020413882061290997048051744176084056110454879785077477467"
    "911464659721914575264885713340479246758173631898216220896846771555"
    "528924494217322451238186280485130405689765045155206420691478214989"
    "062376699830776746378642791629448402475098383623043172740985271861"
    "744411405062942637717668382971894016212339507282834071808175104525"
    "435335935982595169757755852903379045672715624825000851334162177899"
    "247591425081825054307780942867385371790022276541698166049809483243"
    "063508893628851905563804372659376527186057625583279488682418169742"
    "818911815601915895070982736201781493450232500749127082017340244328"
    "145165243935804528945752970176134736677209483383631678421572940025"
    "8912623639078110392535483131827325953610760662"
)
"""The value of ln(1.25), truncated to 1100 digits.

Generated with CPython: `getcontext().prec = 1300;
str(Decimal("1.25").ln())[:1102]`."""


comptime TABLE_DIGITS = 1100
"""Digits held by `LN2_1100` and `LN1D25_1100`."""


def compute_ln2(working_precision: Int) raises -> BigDecimal:
    """Compute ln(2) to the specified working precision.

    Args:
        working_precision: Desired precision in significant digits.

    Returns:
        The ln(2) computed to the specified precision.

    Raises:
        Error: Propagated from underlying arithmetic operations.

    Notes:

    Up to `TABLE_DIGITS` the value is read from `LN2_1100`, exact. Above it
    the series `2 * atanh(1/3)` runs at `working_precision` digits, and the
    result is below `4.5` units in the last place of the true value: each
    term is rounded down (below `1.125` units over the series, since the
    terms fall by 9x and the recurrence divides by an exact integer rather
    than multiplying by a truncated square), the initial `1/3` enters through
    the first term only (one unit), the stopping rule leaves a tail below
    `1.2` units, and the final round-down is one more. So at most the last
    digit is off, at every precision; `MathCache` adds nine guard digits and
    that is enough. Pinned by `test_bigdecimal_ln_constants_bound.mojo`.
    """
    # Directly using Taylor series expansion for ln(2) is not efficient
    # Instead, we can use the identity:
    # ln((1+x)/(1-x)) = 2*arcth(x) = 2*(x + x³/3 + x⁵/5 + ...)
    # For x = 1/3:
    # ln(2) = 2*(1/3 + (1/3)³/3 + (1/3)⁵/5 + ...)

    if working_precision <= TABLE_DIGITS:
        # The table used to hold 90 digits as five words. Up to 1100 the
        # series is never needed: parsing the literal is about a microsecond
        # against milliseconds for the series, and the constants were most of
        # what `ln()` paid for at every call.
        var result = BigDecimal(LN2_1100)
        result.round_to_precision_inplace(
            precision=working_precision,
            rounding_mode=RoundingMode.down(),
            remove_extra_digit_due_to_rounding=False,
            fill_zeros_to_precision=False,
        )
        return result^

    var max_terms = Int(Float64(working_precision) * 2.5) + 1

    var number_of_words = working_precision // BigUInt.DIGITS_PER_WORD + 1
    var words = List[BigUInt.Word](capacity=number_of_words)
    # A word of all threes, whatever the word width: (BASE - 1) / 3.
    comptime WORD_OF_THREES = BigUInt.Word(BigUInt.BASE_MAX // 3)
    for _ in range(number_of_words):
        words.append(WORD_OF_THREES)
    var x = BigDecimal(
        BigUInt(raw_words=words^),
        number_of_words * BigUInt.DIGITS_PER_WORD,
        False,
    )  # x = 1/3

    var result = BigDecimal(BigUInt.zero(), 0, False)
    var term = x.multiply(
        BigDecimal(BigUInt(raw_words=[2]), 0, False)
    )  # First term: 2*(1/3)
    var k: BigUInt.Word = 1

    # Add terms: 2*(x + x³/3 + x⁵/5 + ...)
    # Series: term_k = 2 * x^(2k-1) * 1 * 3 * 5 * ... * (2k-3) / (1 * 3 * 5 * ... * (2k-1))
    # Recurrence: term_{k+1} = term_k * x² * k / (k+2)
    #
    # `x` is a finite-precision decimal approximation to 1/3. Because 1/3 is a
    # unit fraction, the x² factor is the rational 1/9, which we apply as a
    # single single-word divide by 9 (rounded once to the target precision) instead
    # of an O(M(n)) BigDecimal multiply by a pre-truncated 0.111…. We fold the
    # 1/9 and the 1/(k+2) factors into one divide by 9*(k+2), and apply the *k
    # factor at the coefficient level — so each iteration is O(n), and the
    # divide also avoids compounding the truncation error of an approximate x².
    for _ in range(1, max_terms):
        result.add_inplace(term)
        var new_k = k + 2
        # Multiply by k at the coefficient level (avoids a BigDecimal alloc)
        biguint_arithmetics.multiply_by_word_inplace(term.coefficient, k)
        # term *= 1/9 * 1/(k+2): one O(n) single-word divide by 9*(k+2)
        term = term.true_divide_inexact_by_word(9 * new_k, working_precision)
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

    Up to `TABLE_DIGITS` the value is read from `LN1D25_1100`, exact. Above
    it the series `2 * atanh(1/9)` runs, with the same error bound as
    `compute_ln2()`: below `4.5` units in the last place, so at most the last
    digit is off, at every precision.
    """
    # ln(1.25) = 2*atanh(1/9), since (1 + 1/9)/(1 - 1/9) = (10/9)/(8/9) = 1.25.
    # So ln(1.25) = 2*(1/9 + (1/9)³/3 + (1/9)⁵/5 + ...).
    # As in compute_ln2, `x` is a finite-precision decimal approximation to 1/9.
    # Because 1/9 is a unit fraction, the x² factor is the rational 1/81, which
    # we apply as a single single-word divide by 81 (rounded once to the target
    # precision) instead of an O(M(n)) BigDecimal multiply. We fold the 1/81 and
    # the 1/(2k+1) factors into one divide by 81*(k+2) and apply the *k factor
    # at the coefficient level, so each iteration is O(n).
    if precision <= TABLE_DIGITS:
        var result = BigDecimal(LN1D25_1100)
        result.round_to_precision_inplace(
            precision=precision,
            rounding_mode=RoundingMode.down(),
            remove_extra_digit_due_to_rounding=False,
            fill_zeros_to_precision=False,
        )
        return result^

    var working_precision = precision
    var max_terms = Int(Float64(working_precision) * 1.2) + 10

    var number_of_words = working_precision // BigUInt.DIGITS_PER_WORD + 1
    var words = List[BigUInt.Word](capacity=number_of_words)
    # A word of all ones, whatever the word width: (BASE - 1) / 9.
    comptime WORD_OF_ONES = BigUInt.Word(BigUInt.BASE_MAX // 9)
    for _ in range(number_of_words):
        words.append(WORD_OF_ONES)
    var x = BigDecimal(
        BigUInt(raw_words=words^),
        number_of_words * BigUInt.DIGITS_PER_WORD,
        False,
    )  # x = 1/9

    var result = BigDecimal(BigUInt.zero(), 0, False)
    var term = x.multiply(
        BigDecimal(BigUInt(raw_words=[2]), 0, False)
    )  # First term: 2*(1/9)
    var k: BigUInt.Word = 1

    # Recurrence: term_{k+1} = term_k * x² * k / (k+2), with x² = 1/81.
    for _ in range(1, max_terms):
        result.add_inplace(term)
        var new_k = k + 2
        # Multiply by k at the coefficient level (avoids a BigDecimal alloc)
        biguint_arithmetics.multiply_by_word_inplace(term.coefficient, k)
        # term *= 1/81 * 1/(k+2): one O(n) single-word divide by 81*(k+2)
        term = term.true_divide_inexact_by_word(81 * new_k, working_precision)
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
