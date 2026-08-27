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
from decimo.bigint.arithmetics import multiply_by_word_inplace
from decimo.errors import ValueError

# Largest argument accepted by `factorial`. Even 10^6 already needs ~10^6
# multiplications, so anything beyond it is impractical with the simple
# iterative product. The cap also keeps the value within Mojo's `Int` range,
# so an out-of-range argument raises a clear error instead of an `Int`
# overflow. (A faster algorithm, e.g. binary splitting, could lift this.)
comptime FACTORIAL_MAX_INPUT = 1_000_000
"""The largest argument accepted by `factorial` (10^6)."""

# Below this many factors, `product_range` stops splitting and accumulates the
# consecutive factors with in-place single-word multiplies instead. That avoids
# building a fresh BigInt for every factor and the buffer churn of the pairwise
# products near the bottom of the recursion. Measured ~1.1x (large n) to ~4x
# (small n) faster than splitting all the way down.
comptime PRODUCT_RANGE_LEAF_CUTOFF = 32
"""Maximum factors in a `product_range` leaf before it binary-splits."""


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
    # Balanced binary splitting keeps every multiplication between operands of
    # similar size, and the small leaves are accumulated with in-place
    # single-word multiplies. Far faster than a naive left-to-right product.
    return product_range(2, n)


def product_range(low: Int, high: Int) raises -> BigInt:
    """Returns the product of the consecutive integers in `[low, high]`.

    The range is inclusive; an empty range (`low > high`) returns 1. Large
    ranges use balanced binary splitting so each multiplication stays between
    operands of similar size. Once a sub-range has at most
    `PRODUCT_RANGE_LEAF_CUTOFF` factors, the product is accumulated directly
    with in-place single-word multiplies, which is faster than recursing all
    the way down.

    Args:
        low: The first integer in the range (must be `>= 0`).
        high: The last integer in the range (must be `<= 2^32 - 1` so every
            factor fits in a single word).

    Returns:
        `low * (low + 1) * ... * high` (1 when the range is empty).

    Raises:
        ValueError: If the range is non-empty and `low < 0` or
            `high > 2^32 - 1`, since the leaf multiplies cast each factor to a
            single word.
    """
    if low > high:
        return BigInt.one()
    if low < 0 or high > Int(BigInt.WORD_MAX):
        raise ValueError(
            message=(
                "product_range bounds must satisfy 0 <= low <= high <= 2^32 -"
                " 1."
            ),
            function="product_range()",
        )
    # `high - low + 1` is the number of factors; accumulate the leaf directly
    # once that count is within the cutoff. `low` and every factor fit in a
    # single word (checked above), and each multiply adds at most one word, so
    # reserve the result up front to avoid reallocating while it grows.
    if high - low + 1 <= PRODUCT_RANGE_LEAF_CUTOFF:
        var result = BigInt(uninitialized_capacity=high - low + 2)
        result.words.append(UInt64(low))
        for factor in range(low + 1, high + 1):
            multiply_by_word_inplace(result, UInt64(factor))
        return result^
    var mid = low + (high - low) // 2
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
        ValueError: If `x` or `k` is negative, if `k` is larger than
            `FACTORIAL_MAX_INPUT` (10^6, the cap on the number of factors),
            or if `n` does not fit in a single word (`> 2^32 - 1`).
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
    if x > BigInt(BigInt.WORD_MAX):
        raise ValueError(
            message=(
                "Permutation n is too large to compute (must be <= 2^32 - 1)."
            ),
            function="permutation()",
        )
    var n = Int(x)
    if k > n:
        return BigInt.zero()
    return product_range(n - k + 1, n)
