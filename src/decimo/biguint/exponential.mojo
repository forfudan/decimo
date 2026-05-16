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
from std.memory import memset_zero

from decimo.biguint.biguint import BigUInt
import decimo.biguint.arithmetics as biguint_arithmetics

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
            return BigUInt.from_uint32_unsafe(math.sqrt(x.words[0]))

    elif len(x.words) == 2:
        var res = UInt32(
            math.sqrt(
                (
                    x.words.unsafe_ptr().load[width=2]().cast[DType.uint64]()
                    * SIMD[DType.uint64, 2](1, 1_000_000_000)
                ).reduce_add()
            )
        )
        return BigUInt.from_uint32_unsafe(res)

    # Use Newton's method for larger numbers
    else:  # len(x.words) > 2
        if x.is_zero():
            debug_assert[assert_mode="none"](
                len(x.words) == 1,
                "biguint.exponential.sqrt(): 0 hould be a single word",
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

        # # Ensure we return the floor of the square root
        # # Check if guess^2 > x, if so, decrement guess
        # var guess_squared = guess * guess
        # if guess_squared > x:
        #     # guess must be larger than 1
        #     decimo.biguint.arithmetics.subtract_by_uint32_inplace(guess, 1)

        return guess^


def isqrt(x: BigUInt) -> BigUInt:
    """Calculates the integer square root of a BigUInt.

    Args:
        x: The BigUInt to calculate the integer square root of.

    Returns:
        The integer square root of x as a BigUInt.
    """
    # Use the sqrt function for the actual calculation
    return sqrt(x)


def sqrt_initial_guess(x: BigUInt) -> BigUInt:
    """Calculates a intial guess for the square root of a BigUInt.

    Notes:

    The words of the BigUInt should be more than 2.

    The initial guess is always smaller or equal to the actual square root.

    Args:
        x: The `BigUInt` value to estimate the square root of.

    Returns:
        An initial guess that is less than or equal to the actual square root.
    """

    # Yuhao ZHU:
    # If a number consists of mutliple limbs, we can remove the last 2n limbs,
    # take the sqrt of the remaining limbs, and then append 2n zeros.
    # The less libms are removed, the more accurate the initial guess is.
    # So I will try to make the remaining limbs as large as possible so as to
    # make use of the built-in sqrt function.
    # For exmaple, a number with 8 limbs, <a7a6a5a4a3a2a1a0>:
    # (1) Remove the last 6 limbs
    # (2) Convert <a7a6> to UInt64, take the sqrt, transfer to UInt32
    # (3) Append 3 zero limbs to the result

    debug_assert[assert_mode="none"](
        len(x.words) > 2,
        "BigUInt with 2 words or fewer should be handled separately",
    )

    var n_words = (len(x.words) - 1) // 2  # Number of words to append later
    var msw_sqrt: UInt32
    var nsw: UInt32  # Next significant word
    if len(x.words) & 1 == 0:  # If even, we use the most significant 2 words
        nsw = x.words[len(x.words) - 3]
        msw_sqrt = UInt32(
            math.sqrt(
                (
                    x.words.unsafe_ptr()
                    .load[width=2](len(x.words) - 2)
                    .cast[DType.uint64]()
                    * SIMD[DType.uint64, 2](1, 1_000_000_000)
                ).reduce_add()
            )
        )
    else:  # If odd, we use the most significant word
        nsw = x.words[len(x.words) - 2]
        msw_sqrt = math.sqrt(x.words[len(x.words) - 1])

    # Some additional adjustments based on the next significant word
    nsw //= 2 * msw_sqrt  # The next word contributes to the guess
    if nsw > 999_999_999:  # Cap at max word value
        nsw = 999_999_999

    result = BigUInt(unsafe_uninit_length=n_words + 1)
    memset_zero(ptr=result.words._data, count=n_words + 1)
    # Boundary checks are not needed here because len(x.words) > 2
    result.words.unsafe_set(n_words, msw_sqrt)
    result.words.unsafe_set(
        n_words - 1, UInt32(nsw)
    )  # Set the next significant word contribution

    return result^
