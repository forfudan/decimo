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

from decimo.bigint.arithmetics import multiply_by_word_inplace
from decimo.bigint.bigint import BigInt
from decimo.errors import ValueError

# Largest argument accepted by `factorial`. Even 10^6 already needs ~10^6
# multiplications, so anything beyond it is impractical with the simple
# iterative product. The cap also keeps the value within Mojo's `Int` range,
# so an out-of-range argument raises a clear error instead of an `Int`
# overflow. (A faster algorithm, e.g. binary splitting, could lift this.)
comptime FACTORIAL_MAX_INPUT = 1_000_000
"""The largest argument accepted by `factorial` (10^6)."""

# At this many factors or fewer, `product_range` stops splitting and
# accumulates them with in-place single-word multiplies instead. That avoids
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
        high: The last integer in the range.

    Returns:
        `low * (low + 1) * ... * high` (1 when the range is empty).

    Raises:
        ValueError: If the range is non-empty and `low < 0`, or if it has
            more than `FACTORIAL_MAX_INPUT` factors.

    Notes:
        The upper bound used to be `high <= 2^32 - 1`, because the leaf
        multiplies cast each factor to a single word. A word now holds every
        non-negative `Int`, so that bound says nothing -- but it was also
        doing a second job, keeping absurd ranges from running forever, and
        that job still needs doing. The cap is on the number of factors now,
        which is what it was really about: the same `FACTORIAL_MAX_INPUT`
        that `factorial()` and `permutation()` already answer to, and which
        every internal caller is inside by construction.
    """
    if low > high:
        return BigInt.one()
    if low < 0:
        raise ValueError(
            message="product_range bounds must satisfy 0 <= low <= high.",
            function="product_range()",
        )
    if high - low + 1 > FACTORIAL_MAX_INPUT:
        raise ValueError(
            message="product_range covers too many factors (must be <= 10^6).",
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
            or if `n` does not fit an `Int`, which is what `product_range()`
            takes its bounds as.
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
    if x > BigInt(Int.MAX):
        raise ValueError(
            message=(
                "Permutation n is too large to compute (must be <= 2^63 - 1)."
            ),
            function="permutation()",
        )
    var n = Int(x)
    if k > n:
        return BigInt.zero()
    return product_range(n - k + 1, n)


def binomial(x: BigInt, k: Int) raises -> BigInt:
    """Calculates the number of `k`-combinations of `n = x` items.

    `C(n, k) = n! / (k! * (n - k)!)`, the count that `permutation()` gives
    divided by the `k!` orderings of each selection.

    Args:
        x: The number of items `n` (non-negative).
        k: The number of items to choose (non-negative).

    Returns:
        `C(n, k)`. Returns 0 when `k > n`, as `math.comb` does; `C(n, 0)` and
        `C(n, n)` are 1.

    Raises:
        ValueError: If `x` or `k` is negative, if the smaller of `k` and
            `n - k` is larger than `FACTORIAL_MAX_INPUT` (10^6, the cap on
            the number of factors), or if `n` does not fit an `Int`.

    Notes:

    `k` is folded to `min(k, n - k)` first, which is the same answer by
    symmetry and the cheaper one to reach: `C(1000, 999)` then costs one
    factor rather than nine hundred and ninety-nine.

    The quotient of the two products is exact, so the division truncates
    nothing. It is a single division of two numbers built by binary
    splitting, rather than the three factorials the formula reads as.
    """
    if x < BigInt.zero():
        raise ValueError(
            message="Binomial coefficient is not defined for a negative n.",
            function="binomial()",
        )
    if k < 0:
        raise ValueError(
            message="Binomial coefficient is not defined for a negative k.",
            function="binomial()",
        )
    if x > BigInt(Int.MAX):
        raise ValueError(
            message=(
                "Binomial coefficient n is too large to compute (must be <="
                " 2^63 - 1)."
            ),
            function="binomial()",
        )

    var n = Int(x)
    if k > n:
        return BigInt.zero()

    var chosen = min(k, n - k)
    if chosen == 0:
        return BigInt.one()
    if chosen > FACTORIAL_MAX_INPUT:
        raise ValueError(
            message=(
                "Binomial coefficient k is too large to compute (min(k, n - k)"
                " must be <= 10^6)."
            ),
            function="binomial()",
        )

    var numerator = product_range(n - chosen + 1, n)
    var denominator = product_range(1, chosen)
    return numerator.truncate_divide(denominator)


# Largest argument accepted by `fibonacci` and `lucas`. Fast doubling needs
# only about `log2(n)` multiplications, so time is not what the cap is for:
# `F(10^7)` is some two million digits, and the limit is there to turn an
# argument that would exhaust memory into an error. It is larger than
# `FACTORIAL_MAX_INPUT` because the work here grows with the logarithm of the
# argument rather than with the argument.
comptime FIBONACCI_MAX_INPUT = 10_000_000
"""The largest magnitude accepted by `fibonacci` and `lucas` (10^7)."""


def _fibonacci_pair(n: Int) raises -> Tuple[BigInt, BigInt]:
    """Returns `(F(n), F(n+1))` for a non-negative `n`, by fast doubling.

    Args:
        n: The index, which must not be negative.

    Returns:
        The pair of consecutive Fibonacci numbers starting at `n`.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    The doubling identities are

        F(2k)   = F(k) * (2*F(k+1) - F(k))
        F(2k+1) = F(k)^2 + F(k+1)^2

    so one pass down the bits of `n` from the top reaches `F(n)` in about
    `log2(n)` steps, each of them two or three multiplications of numbers the
    size of the answer. The alternative, adding `n` times, is `n` additions of
    the same size.
    """
    var a = BigInt.zero()  # F(0)
    var b = BigInt.one()  # F(1)
    var top = 0
    while (n >> top) != 0:
        top += 1
    for position in range(top - 1, -1, -1):
        var even = a * ((b << 1) - a)  # F(2k)
        var odd = a * a + b * b  # F(2k+1)
        if (n >> position) & 1:
            a = odd^
            b = even + a
        else:
            a = even^
            b = odd^
    return (a^, b^)


def fibonacci(n: BigInt) raises -> BigInt:
    """Returns the `n`-th Fibonacci number.

    Args:
        n: The index, which may be negative.

    Returns:
        `F(n)`, where `F(0)` is zero, `F(1)` is one and each one after is the
        sum of the two before.

    Raises:
        ValueError: If the magnitude of `n` is above `FIBONACCI_MAX_INPUT`
            (10^7).
        Error: Propagated from the arithmetic.

    Notes:

    A negative index is answered rather than refused. The recurrence runs
    backwards as readily as forwards -- `F(n-1) = F(n+1) - F(n)` -- and gives
    `F(-n) = (-1)^(n+1) * F(n)`, so the sequence alternates in sign to the
    left of zero: `F(-1)` is 1, `F(-2)` is -1, `F(-3)` is 2. These are the
    values the identities hold for, so they are the values returned.
    """
    if n > BigInt(FIBONACCI_MAX_INPUT) or n < BigInt(-FIBONACCI_MAX_INPUT):
        raise ValueError(
            message=(
                "Fibonacci index is too large to compute (magnitude must be"
                " <= 10^7)."
            ),
            function="fibonacci()",
        )
    var index = Int(n)
    if index >= 0:
        var pair = _fibonacci_pair(index)
        return pair[0].copy()
    var pair = _fibonacci_pair(-index)
    var value = pair[0].copy()
    # F(-n) = (-1)^(n+1) F(n): negative for an even n.
    if (-index) % 2 == 0:
        return -value
    return value^


def lucas(n: BigInt) raises -> BigInt:
    """Returns the `n`-th Lucas number.

    Args:
        n: The index, which may be negative.

    Returns:
        `L(n)`, where `L(0)` is two, `L(1)` is one and each one after is the
        sum of the two before.

    Raises:
        ValueError: If the magnitude of `n` is above `FIBONACCI_MAX_INPUT`
            (10^7).
        Error: Propagated from the arithmetic.

    Notes:

    `L(n) = 2*F(n+1) - F(n)`, and the fast doubling already returns that pair,
    so a Lucas number costs a subtraction more than a Fibonacci one and needs
    no second algorithm.

    A negative index follows the same extension: `L(-n) = (-1)^n * L(n)`, so
    `L(-1)` is -1 and `L(-2)` is 3.
    """
    if n > BigInt(FIBONACCI_MAX_INPUT) or n < BigInt(-FIBONACCI_MAX_INPUT):
        raise ValueError(
            message=(
                "Lucas index is too large to compute (magnitude must be <="
                " 10^7)."
            ),
            function="lucas()",
        )
    var signed = Int(n)
    var index = signed if signed >= 0 else -signed
    var pair = _fibonacci_pair(index)
    var value = (pair[1] << 1) - pair[0]
    if signed < 0 and index % 2 == 1:
        return -value
    return value^


def _odd_product(low: Int, high: Int) raises -> BigInt:
    """Returns the product of every other integer in `[low, high]`.

    Args:
        low: The first factor, which must be odd and non-negative.
        high: The last factor, odd and at least `low - 2`.

    Returns:
        `low * (low + 2) * ... * high`, and 1 for an empty range.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    The same shape as `product_range()`: balanced splitting so that every
    multiplication is between operands of similar size, with the small leaves
    accumulated by single-word multiplies instead of recursing further.
    """
    if low > high:
        return BigInt.one()
    var count = (high - low) // 2 + 1
    if count <= PRODUCT_RANGE_LEAF_CUTOFF:
        var result = BigInt(low)
        var factor = low + 2
        while factor <= high:
            multiply_by_word_inplace(result, UInt64(factor))
            factor += 2
        return result^
    var middle = low + 2 * (count // 2 - 1)
    return _odd_product(low, middle) * _odd_product(middle + 2, high)


def double_factorial(n: BigInt) raises -> BigInt:
    """Returns `n!!`, the product of `n` and every other integer below it.

    Args:
        n: The argument, which must be at least -1.

    Returns:
        `n * (n-2) * (n-4) * ...` down to 1 or 2, and 1 for `n` of -1 or 0.

    Raises:
        ValueError: If `n` is below -1 or above `FACTORIAL_MAX_INPUT` (10^6).
        Error: Propagated from the arithmetic.

    Notes:

    `(-1)!!` is 1, the empty product, which is the value that makes the
    recurrence `n!! = n * (n-2)!!` hold at `n = 1`. Below that the extension
    leaves the integers -- `(-3)!!` is -1 but `(-5)!!` is a third -- so an
    argument under -1 is refused rather than answered in a type that cannot
    hold the answer.

    An even argument is not multiplied out one factor at a time: `(2m)!!` is
    `2^m * m!`, so it is a factorial and a shift. Only the odd arguments need
    their own product, and that one splits the same way `product_range()`
    does.
    """
    if n < BigInt(-1):
        raise ValueError(
            message=(
                "Double factorial is not an integer below -1; the argument"
                " must be at least -1."
            ),
            function="double_factorial()",
        )
    if n > BigInt(FACTORIAL_MAX_INPUT):
        raise ValueError(
            message=(
                "Double factorial argument is too large to compute (must be"
                " <= 10^6)."
            ),
            function="double_factorial()",
        )
    var argument = Int(n)
    if argument <= 0:
        return BigInt.one()
    if argument % 2 == 0:
        var half = argument // 2
        return product_range(1, half) << half
    return _odd_product(1, argument)
