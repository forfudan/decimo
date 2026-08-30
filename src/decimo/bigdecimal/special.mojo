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
#
# Implements special functions for the BigDecimal type
#
# ===----------------------------------------------------------------------=== #

"""Implements functions for special operations on BigDecimal objects."""

from decimo.bigdecimal.bigdecimal import BigDecimal
from decimo.errors import ValueError

# Extra significant digits carried during a rounded factorial, on top of the
# requested precision and the digit count of `n`. Covers the rounding error
# that accumulates over the `n` intermediate products.
comptime FACTORIAL_GUARD_DIGITS = 9  # guard digits, not a word width
"""Extra guard digits carried during a rounded `factorial`."""

# Largest argument accepted by `factorial`. Even 10^6 already needs ~10^6
# multiplications, so anything beyond it is impractical with the simple
# iterative product. The cap also keeps the value within Mojo's `Int` range,
# so an out-of-range argument raises a clear error instead of an `Int`
# overflow. (A faster algorithm, e.g. binary splitting, could lift this.)
comptime FACTORIAL_MAX_INPUT = 1_000_000
"""The largest argument accepted by `factorial` (10^6)."""


def factorial(x: BigDecimal, precision: Int = 0) raises -> BigDecimal:
    """Calculates the factorial of a non-negative integer value.

    Args:
        x: The non-negative integer value to take the factorial of.
        precision: Significant digits for the result. `0` (the default)
            computes the exact factorial with no rounding. A positive value
            rounds the intermediate products to a bounded working width,
            which lowers the cost for large `x`, and returns `precision`
            correct significant digits.

    Returns:
        `x!`, the product of all positive integers up to `x` (`0! == 1`).
        Exact when `precision == 0`.

    Raises:
        ValueError: If `x` is not an integer, is negative, or is larger than
            `FACTORIAL_MAX_INPUT` (10^6).

    Notes:

    The value must currently fit in a Mojo `Int`. Arbitrarily large
    arguments will be supported later.
    """
    if not x.is_integer():
        raise ValueError(
            message="Factorial is only defined for integer values.",
            function="factorial()",
        )
    if x < BigDecimal(0):
        raise ValueError(
            message="Factorial is not defined for negative numbers.",
            function="factorial()",
        )
    if x > BigDecimal(FACTORIAL_MAX_INPUT):
        raise ValueError(
            message=(
                "Factorial argument is too large to compute (must be <= 10^6)."
            ),
            function="factorial()",
        )

    # `truncate` gives a scale-0 BigDecimal, so integer values written with a
    # fractional part (e.g. "5.00") convert cleanly to `Int`.
    var n = Int(x.truncate())
    if precision <= 0:
        # Exact: balanced binary splitting (same idea as BigInt) is much
        # faster than a left-to-right running product for large `n`.
        if n < 2:
            return BigDecimal(1)
        return product_range(2, n)

    # Rounded: keep every product at `precision + guard` significant digits,
    # where the guard also grows with the number of digits in `n`. Round the
    # final result back to `precision` (HALF_EVEN, via multiply-by-one).
    var working_precision = (
        precision + String(n).byte_length() + FACTORIAL_GUARD_DIGITS
    )
    var result = BigDecimal(1)
    for i in range(2, n + 1):
        result = result.multiply(BigDecimal(i), working_precision)
    return result.multiply(BigDecimal(1), precision)


def product_range(low: Int, high: Int) raises -> BigDecimal:
    """Returns the exact product of the consecutive integers in `[low, high]`.

    The range is inclusive; an empty range (`low > high`) returns 1. Uses
    balanced binary splitting with exact multiplication (`precision=0`), so
    each multiplication stays between operands of similar size.

    Args:
        low: The first integer in the range.
        high: The last integer in the range.

    Returns:
        `low * (low + 1) * ... * high` (1 when the range is empty).

    Raises:
        Error: Propagated from an intermediate `BigDecimal` multiplication.
    """
    if low > high:
        return BigDecimal(1)
    if low == high:
        return BigDecimal(low)
    if high == low + 1:
        return BigDecimal(low).multiply(BigDecimal(high))
    var mid = low + (high - low) // 2
    return product_range(low, mid).multiply(product_range(mid + 1, high))


def permutation(x: BigDecimal, k: Int, precision: Int = 0) raises -> BigDecimal:
    """Calculates the number of `k`-permutations of `n = x` items.

    `P(n, k) = n! / (n - k)!`. The result is exact when `precision == 0`; a
    positive `precision` rounds the intermediate products and returns
    `precision` significant digits.

    Args:
        x: The number of items `n` (a non-negative integer value).
        k: The number of ordered positions to fill (non-negative).
        precision: Significant digits for the result (`0` = exact).

    Returns:
        `P(n, k)`. Returns 0 when `k > n` (no such arrangement exists);
        `P(n, 0) == 1`.

    Raises:
        ValueError: If `x` is not an integer, `x` or `k` is negative, or `k`
            is larger than `FACTORIAL_MAX_INPUT` (10^6).
    """
    if not x.is_integer():
        raise ValueError(
            message="Permutation is only defined for integer values of n.",
            function="permutation()",
        )
    if x < BigDecimal(0):
        raise ValueError(
            message="Permutation is not defined for a negative n.",
            function="permutation()",
        )
    if k < 0:
        raise ValueError(
            message="Permutation is not defined for a negative k.",
            function="permutation()",
        )
    if k > FACTORIAL_MAX_INPUT:
        raise ValueError(
            message="Permutation k is too large to compute (must be <= 10^6).",
            function="permutation()",
        )
    if x > BigDecimal(Int.MAX):
        raise ValueError(
            message="Permutation n is too large to fit in an Int.",
            function="permutation()",
        )
    var n = Int(x.truncate())
    if k > n:
        return BigDecimal(0)
    if precision <= 0:
        return product_range(n - k + 1, n)

    var working_precision = (
        precision + String(n).byte_length() + FACTORIAL_GUARD_DIGITS
    )
    var result = BigDecimal(1)
    for i in range(n - k + 1, n + 1):
        result = result.multiply(BigDecimal(i), working_precision)
    return result.multiply(BigDecimal(1), precision)
