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
# Implements special functions for the BigInt type
#
# ===----------------------------------------------------------------------=== #

"""Implements functions for special operations on BigInt objects."""

from decimo.bigint.bigint import BigInt
from decimo.errors import ValueError

# Largest argument accepted by `factorial`. Even 10^6 already needs ~10^6
# multiplications, so anything beyond it is impractical with the simple
# iterative product. The cap also keeps the value within Mojo's `Int` range,
# so an out-of-range argument raises a clear error instead of an `Int`
# overflow. (A faster algorithm, e.g. binary splitting, could lift this.)
comptime FACTORIAL_MAX_INPUT = 1_000_000


def factorial(x: BigInt) raises -> BigInt:
    """Calculates the factorial of a non-negative integer value.

    Args:
        x: The non-negative integer value to take the factorial of.

    Returns:
        `x!`, the product of all positive integers up to `x` (`0! == 1`).

    Raises:
        ValueError: If `x` is negative or larger than `FACTORIAL_MAX_INPUT`
            (10^6).

    Notes:

    The value must currently fit in a Mojo `Int`. Arbitrarily large
    arguments will be supported later.
    """
    if x < BigInt.zero():
        raise ValueError(
            message="Factorial is not defined for negative numbers.",
            function="factorial()",
        )
    if x > BigInt(FACTORIAL_MAX_INPUT):
        raise ValueError(
            message=(
                "Factorial argument is too large to compute (must be <= 10^6)."
            ),
            function="factorial()",
        )

    var n = Int(x)
    if n < 2:
        return BigInt.one()
    # Balanced binary splitting multiplies similar-sized operands instead of
    # the naive tiny * huge running product, which is far faster for large
    # `n` (measured ~1.4x at n=1000 up to ~10x at n=100000).
    return product_range(2, n)


def product_range(low: Int, high: Int) -> BigInt:
    """Returns the product of the consecutive integers in `[low, high]`.

    The range is inclusive; an empty range (`low > high`) returns 1. Uses
    balanced binary splitting so each multiplication stays between operands
    of similar size, which is much faster than a left-to-right running
    product for large ranges.

    Args:
        low: The first integer in the range.
        high: The last integer in the range.

    Returns:
        `low * (low + 1) * ... * high` (1 when the range is empty).
    """
    if low > high:
        return BigInt.one()
    if low == high:
        return BigInt(low)
    if high == low + 1:
        return BigInt(low) * BigInt(high)
    var mid = (low + high) // 2
    return product_range(low, mid) * product_range(mid + 1, high)


def permutation(x: BigInt, k: Int) raises -> BigInt:
    """Calculates the number of `k`-permutations of `n = x` items.

    `P(n, k) = n! / (n - k)! = (n - k + 1) * (n - k + 2) * ... * n`.

    Args:
        x: The number of items `n` (non-negative).
        k: The number of ordered positions to fill (non-negative).

    Returns:
        `P(n, k)`. Returns 0 when `k > n` (no such arrangement exists);
        `P(n, 0) == 1`.

    Raises:
        ValueError: If `x` or `k` is negative, or if `k` is larger than
            `FACTORIAL_MAX_INPUT` (10^6, the cap on the number of factors).
    """
    if x < BigInt.zero():
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
    var n = Int(x)
    if k > n:
        return BigInt.zero()
    return product_range(n - k + 1, n)
