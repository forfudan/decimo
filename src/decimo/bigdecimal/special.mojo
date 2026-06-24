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
comptime FACTORIAL_GUARD_DIGITS = 9  # word size

# Largest argument accepted by `factorial`. 10^9 already needs ~10^9
# multiplications and produces a result with billions of digits, so anything
# beyond it is computationally infeasible. The cap also keeps the value within
# Mojo's `Int` range, so an out-of-range argument raises a clear error
# instead of an `Int` overflow.
comptime FACTORIAL_MAX_INPUT = 1_000_000_000


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
        ValueError: If `x` is negative or larger than `FACTORIAL_MAX_INPUT`
            (10^9).

    Notes:

    The value must currently fit in a Mojo `Int`. Arbitrarily large
    arguments will be supported later.
    """
    if x < BigDecimal(0):
        raise ValueError(
            message="Factorial is not defined for negative numbers.",
            function="factorial()",
        )
    if x > BigDecimal(FACTORIAL_MAX_INPUT):
        raise ValueError(
            message=(
                "Factorial argument is too large to compute (must be <= 10^9)."
            ),
            function="factorial()",
        )

    var n = Int(x)
    if precision <= 0:
        # Exact: full-width products, no rounding.
        var result = BigDecimal(1)
        for i in range(2, n + 1):
            result = result.multiply(BigDecimal(i))
        return result^

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
