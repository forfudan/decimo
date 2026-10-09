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

It also provides the quadratic residue symbols -- Jacobi, Legendre and
Kronecker -- along with square roots modulo a prime and the Chinese remainder
theorem. Those four sit here rather than in `primality` because they are
ordinary modular arithmetic that happens to be what a primality test is built
from, not the other way round: `primality` imports the Jacobi symbol for its
Lucas test, so the symbol cannot live there without the dependency pointing
backwards.

Two conventions are worth stating once, because the three symbols differ only
in where they are defined and not in what they compute. `legendre` and
`jacobi` do not verify that the modulus is prime, and say so in their own
documentation; `kronecker` is total over the integers and needs no
precondition at all. Where an answer may genuinely not exist -- a non-residue
has no square root, an over-determined congruence system has no solution --
the function returns nothing rather than raising, since neither case is a
caller error.
"""

from std.bit import count_trailing_zeros

from decimo.bigint.arithmetics import (
    absolute,
    floor_divide,
    floor_divmod,
    floor_modulo,
    left_shift,
    multiply,
    negative,
    right_shift_inplace,
    subtract,
    subtract_inplace,
)
from decimo.bigint.bigint import BigInt, Magnitude
from decimo.bigint.comparison import compare_magnitudes
from decimo.errors import ValueError


# ===----------------------------------------------------------------------=== #
# Internal helpers
# ===----------------------------------------------------------------------=== #


def _count_trailing_zeros(words: Magnitude) -> Int:
    """Counts the number of trailing zero bits in a magnitude word list.

    Words are stored little-endian, so trailing zero bits correspond to
    the least-significant bits of the first non-zero word, plus 64 for
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

    # `std.bit.count_trailing_zeros` lowers to `rbit`+`clz` on arm64,
    # replacing the bit-at-a-time shift loop.
    return i * 64 + Int(count_trailing_zeros(words[i]))


# ===----------------------------------------------------------------------=== #
# GCD — Euclid-balanced Binary GCD (Stein's Algorithm)
# ===----------------------------------------------------------------------=== #

comptime _GCD_EUCLID_GAP_BITS = 64
"""Bit-length gap at which `gcd()` prefers a Euclidean step over a binary one.

Two words. Below this the remainder costs more than the subtractions it saves;
above it the remainder wins by orders of magnitude.
"""


def gcd(a: BigInt, b: BigInt) raises -> BigInt:
    """Computes the greatest common divisor of two integers.

    Uses the binary GCD (Stein's) algorithm, which is efficient for the
    base-2^64 representation since it relies only on subtraction and
    right-shifts rather than expensive division. Operands of very different
    sizes are balanced with Euclidean steps first (see below).

    Follows Python semantics:
    - gcd(0, 0) = 0
    - gcd(a, 0) = |a|, gcd(0, b) = |b|
    - The result is always non-negative.

    Args:
        a: First integer.
        b: Second integer.

    Returns:
        The greatest common divisor, always >= 0.

    Raises:
        Error: Propagated from underlying BigInt arithmetic.
    """
    # Work with absolute values — GCD is always non-negative
    var u = absolute(a)
    var v = absolute(b)

    # Base cases
    if u.is_zero():
        return v^
    if v.is_zero():
        return u^

    # Order the operands by magnitude, so that `gcd(a, b)` and `gcd(b, a)`
    # take the same path from here on. `bit_length()` returns a signed `Int`,
    # so without this the gap below is simply negative for the reversed
    # argument order and the balancing loop never runs.
    if compare_magnitudes(u, v) < 0:
        var larger = v^
        v = u^
        u = larger^

    # Balance the operands before entering the binary loop.
    #
    # Stein's algorithm makes progress of roughly one bit per iteration, and
    # every iteration costs a subtraction over the *larger* operand. That is
    # fine when the two are comparable, and terrible when they are not:
    # gcd(18 000-bit, 20-bit) spends 18 000 full-width subtractions to reach
    # what a single remainder gets to at once. Euclidean steps, on the other
    # hand, are only worth their division cost while they shrink the operand
    # by a large factor - which is exactly the unbalanced case.
    #
    # So take Euclidean steps while the gap is wide and hand over to Stein as
    # soon as it is not. Measured on this machine, gcd of a 17 940-bit value
    # with a 20-bit one: 4.85 ms before, 0.003 ms after. Balanced operands
    # skip the loop entirely and are unaffected (5 980 bits: 0.805 vs 0.818
    # ms, i.e. noise).
    #
    # `u` is the larger operand on entry, and each step keeps it that way:
    # the new pair is `(v, u mod v)` and a remainder is smaller than what it
    # was taken modulo.
    while u.bit_length() - v.bit_length() >= _GCD_EUCLID_GAP_BITS:
        var remainder = floor_modulo(u, v)
        u = v^
        v = remainder^
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


# ===----------------------------------------------------------------------=== #
# Quadratic Residue Symbols
# ===----------------------------------------------------------------------=== #


def jacobi(a: BigInt, n: BigInt) raises -> Int:
    """Computes the Jacobi symbol of `a` over `n`.

    Args:
        a: The numerator, of either sign.
        n: The denominator, which must be odd and positive.

    Returns:
        `0` when `a` and `n` share a factor, and otherwise `1` or `-1`.

    Raises:
        ValueError: If `n` is not odd and positive.
        Error: Propagated from the arithmetic.

    Notes:

    The symbol is the product of the Legendre symbols over the prime factors
    of `n`, counted with multiplicity, but it is computed here without
    factoring: pulling the factors of two out of the numerator and then
    applying quadratic reciprocity reduces the pair the way a Euclidean GCD
    does, in the same number of steps.

    A `1` does not mean `a` is a square modulo a composite `n`. It means the
    product of the Legendre symbols is `1`, which an even number of
    non-residues also achieves. Only for a prime `n` -- the `legendre` case --
    does `1` mean a square.

    A negative numerator needs no separate treatment, because the symbol only
    depends on `a` modulo `n` and the reduction here is a floor modulo, which
    lands on a non-negative residue.

    The parity and low-bit reads below go through `words[0]` rather than
    `bitwise.test_bit`, and the count of twos through the local
    `_count_trailing_zeros`, because `bitwise` imports from this module and
    importing it back would close a cycle. Both operands are non-negative
    throughout the loop, so the low word of the magnitude is the value modulo
    `2^64` and masking it is the value modulo 8 or 4.
    """
    if not n.is_positive() or (n.words[0] & 1) == 0:
        raise ValueError(
            message=(
                "The denominator of a Jacobi symbol must be odd and positive."
            ),
            function="jacobi()",
        )

    var numerator = floor_modulo(a, n)
    var denominator = n.copy()
    var result = 1

    while not numerator.is_zero():
        # Pull out the factors of two. Two is a quadratic residue modulo an
        # odd number exactly when that number is one or seven modulo eight,
        # so each factor flips the sign for the other two cases.
        var twos = _count_trailing_zeros(numerator.words)
        if twos > 0:
            numerator = numerator >> twos
            if twos & 1 != 0:
                var residue = Int(denominator.words[0] & 7)
                if residue == 3 or residue == 5:
                    result = -result

        # Reciprocity. Both arguments are odd here, and the sign flips only
        # when both are three modulo four.
        if (numerator.words[0] & 3) == 3 and (denominator.words[0] & 3) == 3:
            result = -result
        var previous = numerator.copy()
        numerator = floor_modulo(denominator, previous)
        denominator = previous^

    return result if denominator.is_one() else 0


def legendre(a: BigInt, p: BigInt) raises -> Int:
    """Computes the Legendre symbol of `a` over an odd prime `p`.

    Args:
        a: The numerator, of either sign.
        p: The denominator, which must be an odd prime. Primality is a
            precondition and is not checked; see the notes.

    Returns:
        `0` when `p` divides `a`, `1` when `a` is a non-zero square modulo
        `p`, and `-1` when it is not a square.

    Raises:
        ValueError: If `p` is not odd and greater than two. That much is
            cheap to check and rules out the mistakes a caller is most likely
            to make, including passing `2`, for which the symbol is undefined.
        Error: Propagated from the arithmetic.

    Notes:

    For a prime modulus the Jacobi symbol is the Legendre symbol, so this
    shares that implementation rather than repeating it. The function exists
    for the name and for the stronger reading its result carries: over a
    prime, and only over a prime, `1` means `a` really is a square.

    Primality is not verified. Deciding it costs a Baillie-PSW test, which is
    several modular exponentiations and so orders of magnitude more than the
    symbol itself -- the symbol runs in Euclidean time, with no exponentiation
    at all. Charging every caller for a test that a caller working in a fixed
    prime field already knows the answer to would make the cheap operation the
    expensive one. A caller who does not know should call `is_prime` once,
    outside the loop.

    Passing a composite `p` is therefore not an error here; it returns the
    Jacobi symbol, whose `1` carries the weaker meaning described in `jacobi`.
    """
    if p <= BigInt(2) or (p.words[0] & 1) == 0:
        raise ValueError(
            message=(
                "The denominator of a Legendre symbol must be an odd prime,"
                " so it must at least be odd and greater than two."
            ),
            function="legendre()",
        )
    return jacobi(a, p)


def kronecker(a: BigInt, n: BigInt) raises -> Int:
    """Computes the Kronecker symbol of `a` over any integer `n`.

    Args:
        a: The numerator, of either sign.
        n: The denominator, of either sign, and possibly even or zero.

    Returns:
        `0`, `1` or `-1`.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    This extends `jacobi` to every integer denominator, so it never raises on
    its arguments: there is no `n` it is undefined for.

    The extension is forced by asking that the symbol stay multiplicative in
    `n`. Writing `n` as `u * 2^k * m` with `u` either `1` or `-1` and `m` odd
    and positive, the symbol is the product of the symbol over each part:

    - `(a/u)` is `-1` exactly when both `u` and `a` are negative. This is the
      convention that makes the symbol a real character, and it is the one
      Pari/GP's `kronecker` uses.
    - `(a/2)` is `0` for even `a`, `1` when `a` is one or seven modulo eight,
      and `-1` when it is three or five. That is the reciprocity rule
      `jacobi` already applies to a factor of two, read in the other
      direction.
    - `(a/m)` is the Jacobi symbol.

    The zero denominator falls out of the empty product: `(a/0)` is `1` when
    `a` is `1` or `-1` and `0` otherwise.
    """
    if n.is_zero():
        return 1 if absolute(a).is_one() else 0

    var result = 1
    var denominator = absolute(n)
    if n.is_negative() and a.is_negative():
        result = -result

    var twos = _count_trailing_zeros(denominator.words)
    if twos > 0:
        denominator = denominator >> twos
        var residue = Int(floor_modulo(a, BigInt(8)))
        var symbol_of_two = 0
        if residue == 1 or residue == 7:
            symbol_of_two = 1
        elif residue == 3 or residue == 5:
            symbol_of_two = -1
        # An even `a` makes the whole product zero; otherwise only the parity
        # of the exponent matters, since the symbol is `1` or `-1`.
        if symbol_of_two == 0:
            return 0
        if symbol_of_two == -1 and (twos & 1) != 0:
            result = -result

    return result * jacobi(a, denominator)


# ===----------------------------------------------------------------------=== #
# Modular Square Root
# ===----------------------------------------------------------------------=== #


def sqrt_mod(a: BigInt, modulus: BigInt) raises -> Optional[BigInt]:
    """Computes a square root of `a` modulo a prime.

    Args:
        a: The value to take the root of, of either sign.
        modulus: The modulus, which must be a prime. Primality is a
            precondition and is not checked, for the reason given in
            `legendre`.

    Returns:
        The smaller of the two roots when `a` is a square modulo `modulus`,
        and nothing when it is not. Zero has the single root zero.

    Raises:
        ValueError: If `modulus` is less than two.
        Error: Propagated from the arithmetic.

    Notes:

    A non-residue is not an error. Half of the non-zero residues modulo an odd
    prime are squares and half are not, so "no root" is an ordinary answer
    about an ordinary input, and a caller sweeping a range would otherwise
    have to put its normal path inside an exception handler. That is why this
    returns nothing instead of raising, unlike `mod_inverse`, where a missing
    inverse means the caller chose a modulus that does not match the value.

    The two roots are `x` and `modulus - x`. The smaller is returned so that
    the answer is a function of the arguments alone. Tonelli-Shanks below
    starts from the first quadratic non-residue it finds by counting upwards,
    and which of the two roots the ladder lands on depends on that search, so
    without this the result would be reproducible but arbitrary.

    Three cases are separated out because they need no search. Modulo two,
    squaring is the identity. When the modulus is three modulo four, the
    exponent `(modulus + 1) / 4` is an integer and a single modular
    exponentiation gives the root, since then
    `(a^((p+1)/4))^2 = a^((p+1)/2) = a * a^((p-1)/2) = a` for a residue `a`.
    Only a modulus of one modulo four needs the full algorithm.
    """
    if modulus < BigInt(2):
        raise ValueError(
            message="The modulus of a modular square root must be prime.",
            function="sqrt_mod()",
        )

    var one = BigInt.one()
    var two = BigInt(2)
    if modulus == two:
        # Squaring is the identity modulo two, so `a` is its own root.
        return floor_modulo(a, two)

    var residue = floor_modulo(a, modulus)
    if residue.is_zero():
        return BigInt(0)
    if jacobi(residue, modulus) != 1:
        return None

    var four = BigInt(4)
    if floor_modulo(modulus, four) == BigInt(3):
        var direct = mod_pow(residue, (modulus + one) // four, modulus)
        return _nearer_root(direct^, modulus)

    # Tonelli-Shanks. Write `modulus - 1 = odd_part * 2^shift`, with
    # `shift >= 2` because the modulus is one modulo four.
    var even_part = modulus - one
    var shift = _count_trailing_zeros(even_part.words)
    var odd_part = even_part >> shift

    # Any non-residue will do, and the smallest is found by counting up.
    # Half the residues are non-residues, so this stops almost at once.
    var non_residue = two.copy()
    while jacobi(non_residue, modulus) != -1:
        non_residue = non_residue + one

    var ladder = mod_pow(non_residue, odd_part, modulus)
    var root = mod_pow(residue, (odd_part + one) >> 1, modulus)
    var remainder = mod_pow(residue, odd_part, modulus)
    var order = shift

    # `remainder` has order dividing `2^order`. Each pass finds its exact
    # order `2^i`, kills the top factor of two with a matching power of the
    # non-residue, and so strictly lowers `order`. It reaches one in at most
    # `shift` passes.
    while not remainder.is_one():
        var i = 0
        var square = remainder.copy()
        while not square.is_one():
            square = floor_modulo(multiply(square, square), modulus)
            i += 1

        var factor = ladder.copy()
        for _ in range(order - i - 1):
            factor = floor_modulo(multiply(factor, factor), modulus)

        root = floor_modulo(multiply(root, factor), modulus)
        ladder = floor_modulo(multiply(factor, factor), modulus)
        remainder = floor_modulo(multiply(remainder, ladder), modulus)
        order = i

    return _nearer_root(root^, modulus)


def _nearer_root(root: BigInt, modulus: BigInt) raises -> BigInt:
    """Picks the smaller of the two square roots `root` and `modulus - root`.

    Args:
        root: One root, in `[0, modulus)`.
        modulus: The modulus.

    Returns:
        Whichever of the pair is smaller.

    Raises:
        Error: Propagated from the arithmetic.
    """
    var other = subtract(modulus, root)
    return root.copy() if compare_magnitudes(root, other) <= 0 else other^


# ===----------------------------------------------------------------------=== #
# Chinese Remainder Theorem
# ===----------------------------------------------------------------------=== #


def crt(
    residues: List[BigInt], moduli: List[BigInt]
) raises -> Optional[Tuple[BigInt, BigInt]]:
    """Solves a system of simultaneous congruences.

    Args:
        residues: The right-hand sides, of either sign.
        moduli: The moduli, each of which must be positive. They need not be
            pairwise coprime.

    Returns:
        A pair `(x, m)` where `m` is the least common multiple of the moduli
        and `x` is the unique solution in `[0, m)`, so that `x` is congruent
        to `residues[i]` modulo `moduli[i]` for every `i`. Nothing when the
        system has no solution.

    Raises:
        ValueError: If the two lists differ in length, or if any modulus is
            not positive.
        Error: Propagated from the arithmetic.

    Notes:

    Coprime moduli are not required. The congruences are merged one at a
    time: given a solution `x` modulo `m`, the next congruence asks for a `k`
    with `x + m * k` congruent to `r` modulo `n`, which is the linear
    congruence `m * k = r - x` modulo `n`. With `g` the GCD of `m` and `n`
    that has a solution exactly when `g` divides `r - x`, and then `k` is
    determined modulo `n / g`, which makes the merged modulus
    `m * (n / g)` -- the least common multiple, as claimed above. Coprime
    moduli are only the case where `g` is always one and nothing can fail.

    An inconsistent system returns nothing rather than raising. `x = 1 mod 2`
    together with `x = 2 mod 4` is not a malformed request; it is a
    well-formed question whose answer is that no such `x` exists, and a caller
    intersecting congruences it did not choose needs that answer as a value.
    A modulus of zero, by contrast, is malformed and raises: it describes no
    congruence.

    The empty system returns `(0, 1)`. Every integer is congruent modulo one,
    so the empty intersection is all of them, represented by the one residue
    class modulo one. That also makes the function foldable: starting from
    `(0, 1)` and merging is what the loop below does.
    """
    if len(residues) != len(moduli):
        raise ValueError(
            message=(
                "A congruence system needs one modulus for every residue, but"
                " got "
                + String(len(residues))
                + " residues and "
                + String(len(moduli))
                + " moduli."
            ),
            function="crt()",
        )

    var solution = BigInt(0)
    var modulus = BigInt.one()

    for index in range(len(moduli)):
        var next_modulus = moduli[index].copy()
        if not next_modulus.is_positive():
            raise ValueError(
                message=(
                    "Every modulus of a congruence system must be positive,"
                    " but the one at index "
                    + String(index)
                    + " is not."
                ),
                function="crt()",
            )

        var difference = subtract(residues[index], solution)
        var common = gcd(modulus, next_modulus)
        var split = floor_divmod(difference, common)
        if not split[1].is_zero():
            # `common` does not divide `r - x`, so the two congruences
            # disagree on a residue class they share.
            return None

        # `k = ((r - x) / g) * (m / g)^-1 mod (n / g)`. The inverse exists
        # because dividing out the GCD leaves the two parts coprime.
        var reduced = floor_divide(next_modulus, common)
        var step = floor_modulo(
            multiply(
                split[0], mod_inverse(floor_divide(modulus, common), reduced)
            ),
            reduced,
        )

        solution = solution + multiply(modulus, step)
        modulus = multiply(modulus, reduced)
        solution = floor_modulo(solution, modulus)

    return Optional(Tuple(solution^, modulus^))
