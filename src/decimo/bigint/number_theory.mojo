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

"""Number theory operations for BigInt.

Provides greatest common divisor (GCD), extended GCD, least common multiple
(LCM), modular exponentiation, and modular multiplicative inverse.
"""

from decimo.bigint.bigint import BigInt
from decimo.bigint.comparison import compare_magnitudes
from decimo.bigint.arithmetics import (
    absolute,
    negative,
    multiply,
    subtract,
    floor_divide,
    floor_modulo,
    floor_divmod,
    left_shift,
    subtract_inplace,
    right_shift_inplace,
)
from decimo.errors import ValueError


# ===----------------------------------------------------------------------=== #
# Internal helpers
# ===----------------------------------------------------------------------=== #


def _count_trailing_zeros(words: List[UInt32]) -> Int:
    """Counts the number of trailing zero bits in a magnitude word list.

    Words are stored little-endian, so trailing zero bits correspond to
    the least-significant bits of the first non-zero word, plus 32 for
    every entirely-zero word that precedes it.

    Returns 0 for the zero value (trailing zeros undefined for zero).
    """
    var n = len(words)

    # Find the first non-zero word
    var i = 0
    while i < n and words[i] == 0:
        i += 1

    if i == n:
        return 0  # Value is zero

    # Count trailing zeros in the first non-zero word
    var word = words[i]
    var bits = 0
    while (word & 1) == 0:
        word >>= 1
        bits += 1

    return i * 32 + bits


# ===----------------------------------------------------------------------=== #
# GCD — Binary GCD (Stein's Algorithm)
# ===----------------------------------------------------------------------=== #


def gcd(a: BigInt, b: BigInt) -> BigInt:
    """Computes the greatest common divisor of two integers.

    Uses the binary GCD (Stein's) algorithm, which is efficient for the
    base-2^32 representation since it relies only on subtraction and
    right-shifts rather than expensive division.

    Follows Python semantics:
    - gcd(0, 0) = 0
    - gcd(a, 0) = |a|, gcd(0, b) = |b|
    - The result is always non-negative.

    Args:
        a: First integer.
        b: Second integer.

    Returns:
        The greatest common divisor, always >= 0.
    """
    # Work with absolute values — GCD is always non-negative
    var u = absolute(a)
    var v = absolute(b)

    # Base cases
    if u.is_zero():
        return v^
    if v.is_zero():
        return u^

    # Factor out common powers of 2
    var u_tz = _count_trailing_zeros(u.words)
    var v_tz = _count_trailing_zeros(v.words)
    var common_shift = min(u_tz, v_tz)

    # Make both odd
    right_shift_inplace(u, u_tz)
    right_shift_inplace(v, v_tz)

    # Main loop — both u and v are odd at the start of each iteration.
    # In each step we subtract the smaller from the larger (giving an
    # even result since odd − odd = even) and then strip the trailing
    # zeros to restore the odd invariant.  The process terminates when
    # u == v.
    while True:
        var cmp = compare_magnitudes(u, v)
        if cmp == 0:
            break  # u == v, GCD found
        if cmp > 0:
            # u > v: replace u with (u − v), then make odd
            subtract_inplace(u, v)
            right_shift_inplace(u, _count_trailing_zeros(u.words))
        else:
            # v > u: replace v with (v − u), then make odd
            subtract_inplace(v, u)
            right_shift_inplace(v, _count_trailing_zeros(v.words))

    # Restore the common factor of 2
    return left_shift(u, common_shift)


# ===----------------------------------------------------------------------=== #
# Extended GCD — Iterative Euclidean Algorithm
# ===----------------------------------------------------------------------=== #


def extended_gcd(a: BigInt, b: BigInt) raises -> Tuple[BigInt, BigInt, BigInt]:
    """Computes the extended greatest common divisor.

    Returns (g, x, y) such that a * x + b * y = g, where g = gcd(a, b) >= 0.

    Uses the iterative extended Euclidean algorithm.

    Args:
        a: First integer.
        b: Second integer.

    Returns:
        A 3-tuple (g, x, y) where g is the non-negative GCD and x, y are
        Bézout coefficients satisfying a * x + b * y = g.

    Raises:
        Error: Propagated from underlying BigInt arithmetic.
    """
    var a_neg = a.is_negative()
    var b_neg = b.is_negative()
    var old_r = absolute(a)
    var r = absolute(b)
    var old_s = BigInt(1)
    var s = BigInt(0)
    var old_t = BigInt(0)
    var t = BigInt(1)

    while not r.is_zero():
        var qr = floor_divmod(old_r, r)
        var q = qr[0].copy()
        var remainder = qr[1].copy()

        # Compute new Bézout coefficients before reassigning
        var new_s = subtract(old_s, multiply(q, s))
        var new_t = subtract(old_t, multiply(q, t))

        old_r = r.copy()
        r = remainder^

        old_s = s.copy()
        s = new_s^

        old_t = t.copy()
        t = new_t^

    # Adjust signs for the original (possibly negative) inputs.
    # We computed |a| * old_s + |b| * old_t = gcd on absolute values.
    # If a < 0 then a = −|a|, so a * (−old_s) = |a| * old_s  ⟹  x = −old_s.
    # Similarly for b.
    if a_neg:
        old_s = negative(old_s)
    if b_neg:
        old_t = negative(old_t)

    return (old_r^, old_s^, old_t^)


# ===----------------------------------------------------------------------=== #
# LCM — Least Common Multiple
# ===----------------------------------------------------------------------=== #


def lcm(a: BigInt, b: BigInt) raises -> BigInt:
    """Computes the least common multiple of two integers.

    Follows Python semantics:
    - lcm(0, n) = lcm(n, 0) = 0
    - The result is always non-negative.

    Args:
        a: First integer.
        b: Second integer.

    Returns:
        The least common multiple, always >= 0.

    Raises:
        Error: Propagated from underlying BigInt arithmetic.
    """
    if a.is_zero() or b.is_zero():
        return BigInt(0)

    var g = gcd(a, b)
    # |a| / gcd(a,b) * |b| — divide first to keep intermediates small
    return multiply(floor_divide(absolute(a), g), absolute(b))


# ===----------------------------------------------------------------------=== #
# Modular Exponentiation
# ===----------------------------------------------------------------------=== #


def mod_pow(base: BigInt, exponent: BigInt, modulus: BigInt) raises -> BigInt:
    """Computes (base ** exponent) mod modulus efficiently.

    Uses right-to-left binary exponentiation with modular reduction at
    each step, so intermediate values never exceed modulus².

    Args:
        base: The base (may be negative; reduced mod modulus first).
        exponent: The exponent (must be non-negative).
        modulus: The modulus (must be positive).

    Returns:
        A BigInt in the range [0, modulus).

    Raises:
        ValueError: If the exponent is negative.
        ValueError: If the modulus is not positive.
    """
    if exponent.is_negative():
        raise ValueError(
            function="mod_pow()",
            message="Exponent must be non-negative",
        )

    if not modulus.is_positive():
        raise ValueError(
            function="mod_pow()",
            message="Modulus must be positive",
        )

    # x mod 1 = 0 for all x
    if modulus.is_one():
        return BigInt(0)

    # base^0 = 1
    if exponent.is_zero():
        return floor_modulo(BigInt(1), modulus)

    # Reduce base modulo modulus (handles negative base via floor modulo)
    var result = BigInt(1)
    var b = floor_modulo(base, modulus)
    var exp = exponent.copy()  # mutable copy to iterate over

    # Right-to-left binary exponentiation
    while not exp.is_zero():
        # If the lowest bit is set, multiply result by current base
        if (exp.words[0] & 1) != 0:
            result = floor_modulo(multiply(result, b), modulus)

        # Shift exponent right by 1
        right_shift_inplace(exp, 1)

        # Square the base (skip if exponent is exhausted)
        if not exp.is_zero():
            b = floor_modulo(multiply(b, b), modulus)

    return result^


def mod_pow(base: BigInt, exponent: Int, modulus: BigInt) raises -> BigInt:
    """Convenience overload accepting an Int exponent.

    Args:
        base: The base (may be negative; reduced mod modulus first).
        exponent: The exponent as an Int (must be non-negative).
        modulus: The modulus (must be positive).

    Returns:
        A BigInt in the range [0, modulus).

    Raises:
        ValueError: If the exponent is negative.
        ValueError: If the modulus is not positive.
    """
    return mod_pow(base, BigInt(exponent), modulus)


# ===----------------------------------------------------------------------=== #
# Modular Inverse
# ===----------------------------------------------------------------------=== #


def mod_inverse(a: BigInt, modulus: BigInt) raises -> BigInt:
    """Computes the modular multiplicative inverse of a modulo modulus.

    Returns x in [0, modulus) such that (a * x) ≡ 1 (mod modulus).

    The inverse exists if and only if gcd(a, modulus) == 1.

    Args:
        a: The value to invert.
        modulus: The modulus (must be positive).

    Returns:
        The modular inverse, in [0, modulus).

    Raises:
        ValueError: If the modulus is not positive.
        ValueError: If the modular inverse does not exist (gcd != 1).
    """
    if not modulus.is_positive():
        raise ValueError(
            function="mod_inverse()",
            message="Modulus must be positive",
        )

    var result = extended_gcd(a, modulus)
    var g = result[0].copy()
    var x = result[1].copy()

    if not g.is_one():
        raise ValueError(
            function="mod_inverse()",
            message="Modular inverse does not exist (gcd != 1)",
        )

    # Ensure result is in [0, modulus)
    return floor_modulo(x, modulus)
