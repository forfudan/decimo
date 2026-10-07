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

"""Implements exponential functions for the BigUInt type."""

from std import math
from std.memory import unsafe_memset_zero

import decimo.biguint.arithmetics as biguint_arithmetics
from decimo.biguint.biguint import BigUInt
from decimo.errors import ValueError
from decimo.utility import isqrt_uint128, isqrt_uint64

# ===----------------------------------------------------------------------=== #
# Square Root
# sqrt()
# sqrt_initial_guess()
# ===----------------------------------------------------------------------=== #


def sqrt(x: BigUInt) -> BigUInt:
    """Calculates the square root of a BigUInt using Newton's method.

    Args:
        x: The BigUInt to calculate the square root of.

    Returns:
        The square root of x as a BigUInt.

    Notes:

    The square root is the largest integer y such that y * y <= x.
    This implementation uses Newton's method with quadratic convergence.
    """

    # Use built-in methods for small numbers (up to 2 words)
    if len(x.words) == 1:
        if x.words[0] == 0:
            return BigUInt.zero()
        elif x.words[0] == 1:
            return BigUInt.one()
        else:
            return BigUInt.from_word_unsafe(
                BigUInt.Word(isqrt_uint64(x.words[0]))
            )

    elif len(x.words) == 2:
        # Two words are `BASE^2`, so the value needs 128 bits and its root
        # needs 64. The base-10^9 version packed the pair into a `UInt64` with
        # a SIMD dot product; that only worked while two words fit one.
        var value = UInt128(x.words[1]) * UInt128(BigUInt.BASE) + UInt128(
            x.words[0]
        )
        return BigUInt.from_word_unsafe(BigUInt.Word(isqrt_uint128(value)))

    # Use Newton's method for larger numbers
    else:  # len(x.words) > 2
        if x.is_zero():
            debug_assert[assert_mode="none"](
                len(x.words) == 1,
                "biguint.exponential.sqrt(): 0 should be a single word",
            )
            return BigUInt.zero()

        # Start with a initial guess
        # The initial guess is smaller or equal to the actual square root
        var guess = sqrt_initial_guess(x)
        if guess.is_zero():
            return BigUInt.one()

        # Newton's iteration: x_{k+1} = (x_k + n/x_k) / 2
        # Continue until convergence
        var prev_guess: BigUInt
        var quotient: BigUInt

        var iterations = 0
        while True:
            iterations += 1
            prev_guess = guess.copy()

            # Calculate (x_k + n/x_k) // 2
            try:
                # Division by zero should not occur if guess is positive
                quotient = x.floor_divide(guess)
            except:
                # This should not happen
                quotient = BigUInt.one()

            guess += quotient
            biguint_arithmetics.floor_divide_by_2_inplace(guess)

            if guess == prev_guess:
                break
            if prev_guess == guess + BigUInt.one():
                break
            if guess == prev_guess + BigUInt.one():
                return prev_guess^

        return guess^


def isqrt(x: BigUInt) -> BigUInt:
    """Calculates the integer square root of a BigUInt.

    Args:
        x: The BigUInt to calculate the integer square root of.

    Returns:
        The integer square root of x as a BigUInt.
    """
    return sqrt(x)


def sqrt_initial_guess(x: BigUInt) -> BigUInt:
    """Calculates an initial guess for the square root of a BigUInt.

    Notes:

    The words of the BigUInt should be more than 2.

    The initial guess is always smaller or equal to the actual square root.

    Args:
        x: The `BigUInt` value to estimate the square root of.

    Returns:
        An initial guess that is less than or equal to the actual square root.
    """

    # Yuhao ZHU:
    # If a number consists of multiple limbs, we can remove the last 2n limbs,
    # take the sqrt of the remaining limbs, and then append 2n zeros.
    # The fewer limbs are removed, the more accurate the initial guess is.
    # So I will try to make the remaining limbs as large as possible so as to
    # make use of the built-in sqrt function.
    # For example, a number with 8 limbs, <a7a6a5a4a3a2a1a0>:
    # (1) Remove the last 6 limbs
    # (2) Convert <a7a6> to UInt64, take the sqrt, transfer to UInt32
    # (3) Append 3 zero limbs to the result

    debug_assert[assert_mode="none"](
        len(x.words) > 2,
        "BigUInt with 2 words or fewer should be handled separately",
    )

    var n_words = (len(x.words) - 1) // 2  # Number of words to append later
    var msw_sqrt: BigUInt.Word
    var nsw: BigUInt.Word  # Next significant word
    if len(x.words) & 1 == 0:  # If even, we use the most significant 2 words
        nsw = x.words[len(x.words) - 3]
        # Same as the two-word case above: the pair is `BASE^2` wide now, so
        # it is a `UInt128` rather than a SIMD dot product into a `UInt64`.
        var top_pair = UInt128(x.words[len(x.words) - 1]) * UInt128(
            BigUInt.BASE
        ) + UInt128(x.words[len(x.words) - 2])
        msw_sqrt = BigUInt.Word(isqrt_uint128(top_pair))
    else:  # If odd, we use the most significant word
        nsw = x.words[len(x.words) - 2]
        msw_sqrt = BigUInt.Word(isqrt_uint64(x.words[len(x.words) - 1]))

    # Some additional adjustments based on the next significant word
    nsw //= 2 * msw_sqrt  # The next word contributes to the guess
    if nsw > BigUInt.BASE_MAX:  # Cap at max word value
        nsw = BigUInt.BASE_MAX

    var result = BigUInt(unsafe_uninit_length=n_words + 1)
    unsafe_memset_zero(ptr=result.words.unsafe_ptr(), count=n_words + 1)
    # Boundary checks are not needed here because len(x.words) > 2
    result.words.unsafe_set(n_words, msw_sqrt)
    result.words.unsafe_set(
        n_words - 1, BigUInt.Word(nsw)
    )  # Set the next significant word contribution

    return result^


def root(x: BigUInt, n: Int) raises -> BigUInt:
    """Returns the integer `n`-th root of `x`, truncated toward zero.

    Args:
        x: The value to take the root of.
        n: The degree of the root, which must be positive.

    Returns:
        The largest `s` with `s^n <= x`, which is what GMP's `mpz_root`
        answers and what an integral type should: the root of 10 is 3.

    Raises:
        ValueError: If `n` is not positive.
        Error: Propagated from the arithmetic.

    Notes:

    Newton's iteration on integers, `s <- ((n - 1) * s + x / s^(n-1)) / n`,
    started from an upper bound so that the sequence decreases to the answer
    and stops when it would rise. A value of `d` decimal digits has a root of
    at most `ceil(d / n)` digits, which makes `10^ceil(d/n)` the bound to
    start from and costs nothing to form in a base-10^18 representation.

    The two adjustments at the end are a safety net rather than part of the
    method: the iteration lands on the answer, and they cost one comparison
    each to say so.
    """
    if n <= 0:
        raise ValueError(
            message="The degree of a root must be positive.",
            function="root()",
        )
    if n == 1:
        return x.copy()
    if x.is_zero() or x.is_one():
        return x.copy()

    var digits = x.number_of_digits()

    # A degree past the value's size can only answer one: `x < 10^digits` and
    # `10^digits <= 2^(4 * digits)`, so `2^n > x` once `n >= 4 * digits` and
    # even two is too large a root. The test also keeps `n` away from the
    # arithmetic below, where `power()` refuses an exponent of a billion or
    # more and `digits + n` would overflow for an `n` near `Int.MAX`.
    if n >= 4 * digits:
        return BigUInt.one()

    var guess_digits = (digits + n - 1) // n
    var s = BigUInt.power_of_10(guess_digits)

    while True:
        var previous = s.power(n - 1)
        var candidate = biguint_arithmetics.floor_divide(
            (s * BigUInt(UInt64(n - 1)))
            + biguint_arithmetics.floor_divide(x, previous),
            BigUInt(UInt64(n)),
        )
        if candidate.compare(s) >= 0:
            break
        s = candidate^

    # The iteration is exact on integers, so these settle nothing in practice.
    # They are here because an off-by-one root is silent, and one comparison
    # is cheaper than trusting that.
    while s.power(n).compare(x) > 0:
        s = s - BigUInt.one()
    while (s + BigUInt.one()).power(n).compare(x) <= 0:
        s = s + BigUInt.one()
    return s^
