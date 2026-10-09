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

"""Primality testing for BigInt.

Below `2^64` the answer is certain and above it is not, so this file makes two
different kinds of claim and keeps them apart.

Under `2^64`, Miller-Rabin over a fixed set of seven bases decides the
question. The set -- 2, 325, 9375, 28178, 450775, 9780504 and 1795265022 --
was found by Jim Sinclair in April 2011 and has no strong pseudoprime below
`2^64`. That is a computational result and not a theorem: it rests on Jan
Feitsma's complete enumeration of the base-2 strong pseudoprimes under
`2^64`, against which candidate sets were checked. The test suite rechecks
the set exhaustively over a range small enough to sieve, and against the
composites that are known to fool fewer bases.

Above `2^64` the test is Baillie-PSW: one Miller-Rabin round to base 2
followed by a strong Lucas test with Selfridge's parameters. The two halves
fail on different composites by construction -- a Fermat liar to base 2 is
not generally a Lucas liar -- and no composite is known to pass both, though
a counting argument says infinitely many must exist. A value this test calls
prime is therefore a probable prime, and `is_prime` says so in its own
documentation rather than leaving the caller to find out.

Trial division by the primes below a hundred comes first in either case,
because most composites are divisible by one of them and a division is far
cheaper than a modular exponentiation.
"""

from decimo.bigint.bigint import BigInt
from decimo.bigint.bitwise import test_bit, trailing_zeros
from decimo.bigint.exponential import sqrt_rem
from decimo.bigint.number_theory import jacobi, mod_pow
from decimo.biguint.biguint import BigUInt
from decimo.errors import ValueError

comptime _TRIAL_DIVISION_LIMIT = 100
"""Trial division covers the primes below this bound.

Twenty-five divisions remove every composite with a factor under a hundred,
which is most of them, for a cost well below one modular exponentiation.
"""

comptime _TRIAL_DIVISION_DECIDES_BELOW = 10201
"""Trial division alone settles everything below this, which is `101^2`.

A value with no factor below a hundred and no factor at or above its own
square root has none at all, so once the primes under a hundred have been
divided out, anything below the square of the first prime left -- 101 -- is
prime. That decides every value of four digits or fewer without a single
modular exponentiation.
"""

comptime _LUCAS_DISCRIMINANT_TRIES = 64
"""How many candidates the search for a Lucas discriminant tries.

The search fails only for a perfect square, which is checked for once the
candidates run out rather than before every test, since a square root costs
more than the first few Jacobi symbols.
"""


# ===----------------------------------------------------------------------=== #
# Small factors
# ===----------------------------------------------------------------------=== #


def _small_primes() -> List[Int]:
    """The primes below `_TRIAL_DIVISION_LIMIT`.

    Returns:
        The twenty-five primes under a hundred, in order.
    """
    return [
        2,
        3,
        5,
        7,
        11,
        13,
        17,
        19,
        23,
        29,
        31,
        37,
        41,
        43,
        47,
        53,
        59,
        61,
        67,
        71,
        73,
        79,
        83,
        89,
        97,
    ]


def _trial_division(x: BigInt) raises -> Int:
    """Looks for a factor of `x` among the primes below a hundred.

    Args:
        x: The value to divide, which must be at least two.

    Returns:
        The smallest prime below a hundred that divides `x`, or `0` when none
        does. A prime below a hundred divides itself, so `x` being returned
        means `x` is that prime.

    Raises:
        Error: Propagated from the division.
    """
    for p in _small_primes():
        var prime = BigInt(p)
        if (x % prime).is_zero():
            return p
    return 0


# ===----------------------------------------------------------------------=== #
# Miller-Rabin
# ===----------------------------------------------------------------------=== #


def _strong_probable_prime(
    x: BigInt, base: BigInt, odd_part: BigInt, shift: Int
) raises -> Bool:
    """Whether `x` is a strong probable prime to one base.

    Args:
        x: The odd value under test, at least three.
        base: The base to test with.
        odd_part: The odd `d` in `x - 1 = d * 2^shift`.
        shift: The exponent of two in `x - 1`.

    Returns:
        True if the base fails to witness that `x` is composite, which for a
        prime `x` is always.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    A base that is a multiple of `x` says nothing at all -- `0^d` is `0` --
    and is reported as no witness rather than as a composite, since the bases
    here are fixed and small while `x` can be any size.
    """
    var residue = base % x
    if residue.is_zero():
        return True

    var value = mod_pow(residue, odd_part, x)
    if value.is_one() or value == x - BigInt.one():
        return True

    # Square up through the remaining factors of two, looking for `-1`.
    for _ in range(shift - 1):
        value = (value * value) % x
        if value == x - BigInt.one():
            return True
    return False


def _miller_rabin(x: BigInt, bases: List[Int]) raises -> Bool:
    """Runs Miller-Rabin over a list of bases.

    Args:
        x: The odd value under test, at least three.
        bases: The bases to test with.

    Returns:
        True if every base failed to witness a composite.

    Raises:
        Error: Propagated from the arithmetic.
    """
    var one = BigInt.one()
    var even_part = x - one
    var shift = trailing_zeros(even_part)
    var odd_part = even_part >> shift
    for base in bases:
        if not _strong_probable_prime(x, BigInt(base), odd_part, shift):
            return False
    return True


# ===----------------------------------------------------------------------=== #
# Baillie-PSW
# ===----------------------------------------------------------------------=== #


def _half_modulo(x: BigInt, n: BigInt) raises -> BigInt:
    """Halves `x` modulo an odd `n`.

    Args:
        x: A residue in `[0, n)`.
        n: The odd modulus.

    Returns:
        The residue `x / 2` modulo `n`.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    An odd `x` has no half among the integers, but it has one modulo an odd
    `n`: adding `n` makes it even without changing what it stands for.
    """
    if not test_bit(x, 0):
        return x >> 1
    return (x + n) >> 1


def _is_perfect_square(x: BigInt) raises -> Bool:
    """Whether `x` is the square of an integer.

    Args:
        x: The value, which must not be negative.

    Returns:
        True if the integer square root is exact.

    Raises:
        Error: Propagated from the square root.
    """
    var parts = sqrt_rem(x)
    return parts[1].is_zero()


def _strong_lucas_probable_prime(x: BigInt) raises -> Bool:
    """Whether `x` passes a strong Lucas test with Selfridge's parameters.

    Args:
        x: The odd value under test, at least three, with no factor below a
            hundred.

    Returns:
        True if `x` is a strong Lucas probable prime.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    Selfridge's method A takes the first `D` in `5, -7, 9, -11, 13, ...` whose
    Jacobi symbol over `x` is `-1`, then `P = 1` and `Q = (1 - D) / 4`. A
    symbol of `0` means `D` and `x` share a factor, which for these small
    candidates means `x` is composite unless `x` is that factor -- the caller
    has removed every factor below a hundred, so the first candidates cannot
    be `x` itself.

    The search only fails to terminate for a perfect square, where no
    non-residue exists, so the candidates are capped and a square is tested
    for once they run out.

    With `U` and `V` the Lucas sequences for those parameters and
    `x + 1 = d * 2^s` with `d` odd, `x` is a strong Lucas probable prime when
    `U_d` vanishes modulo `x`, or `V` vanishes at `d * 2^r` for some `r` below
    `s`. The sequences are walked from the top bit of `d` down, doubling the
    index at every step and adding one where the bit is set, which is the same
    ladder a modular exponentiation walks.
    """
    var one = BigInt.one()
    var two = BigInt(2)
    var discriminant = BigInt(5)
    var found = False
    for attempt in range(_LUCAS_DISCRIMINANT_TRIES):
        var symbol = jacobi(discriminant, x)
        if symbol == -1:
            found = True
            break
        if symbol == 0:
            # A shared factor, and the caller has ruled out `x` being it.
            return False
        # 5, -7, 9, -11, ... : the magnitude grows by two and the sign flips.
        var magnitude = BigInt(2 * attempt + 7)
        discriminant = -magnitude if attempt % 2 == 0 else magnitude^
    if not found:
        # Only a square has no non-residue to find, and a square above one is
        # composite.
        return False
    if _is_perfect_square(x):
        return False

    var q = (one - discriminant) // BigInt(4)
    q = q % x

    var even_part = x + one
    var shift = trailing_zeros(even_part)
    var odd_part = even_part >> shift

    # Index one: U = 1, V = P = 1, and the running power of Q is Q itself.
    var u = one.copy()
    var v = one.copy()
    var q_power = q.copy()

    for i in range(odd_part.bit_length() - 2, -1, -1):
        # Double the index.
        u = (u * v) % x
        v = (v * v - two * q_power) % x
        q_power = (q_power * q_power) % x
        if test_bit(odd_part, i):
            # And step it up by one. Both halves read the doubled pair, so
            # neither may be written before the other is formed.
            var next_u = _half_modulo((u + v) % x, x)
            var next_v = _half_modulo((discriminant * u + v) % x, x)
            u = next_u^
            v = next_v^
            q_power = (q_power * q) % x

    if u.is_zero() or v.is_zero():
        return True

    # `V` at `d * 2^r` for the remaining `r`, each a doubling of the last.
    for _ in range(shift - 1):
        v = (v * v - two * q_power) % x
        if v.is_zero():
            return True
        q_power = (q_power * q_power) % x
    return False


# ===----------------------------------------------------------------------=== #
# The test
# ===----------------------------------------------------------------------=== #


def is_prime(x: BigInt) raises -> Bool:
    """Whether `x` is prime.

    Args:
        x: The value to test.

    Returns:
        True if `x` is prime. Below `2^64` that is certain. Above it the
        answer is Baillie-PSW's, which no composite is known to fool but
        which proves nothing: a True there means probable prime.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    Trial division by the primes below a hundred comes first, and settles the
    answer by itself for anything below `101^2`.

    Anything below two is not prime, negative values included. Primality here
    is the arithmetic of the natural numbers, where `-7` is not a prime, which
    is also what `sympy.isprime` and Java's `isProbablePrime` answer. A ring
    theorist calling `-7` a prime element of the integers is asking a
    different question than this function answers.
    """
    if x < BigInt(2):
        return False

    var factor = _trial_division(x)
    if factor != 0:
        return x == BigInt(factor)
    if x < BigInt(_TRIAL_DIVISION_DECIDES_BELOW):
        return True

    # Deterministic below 2^64 with Sinclair's seven bases; see the module
    # documentation for where that bound comes from.
    if x < (BigInt.one() << 64):
        return _miller_rabin(
            x, [2, 325, 9375, 28178, 450775, 9780504, 1795265022]
        )

    if not _miller_rabin(x, [2]):
        return False
    return _strong_lucas_probable_prime(x)


def is_prime(x: BigUInt) raises -> Bool:
    """Whether `x` is prime.

    Args:
        x: The value to test.

    Returns:
        True if `x` is prime, with the same certainty as the signed version:
        exact below `2^64` and Baillie-PSW's answer above it.

    Raises:
        Error: Propagated from the arithmetic.
    """
    return is_prime(BigInt.from_biguint(x))


def next_prime(x: BigInt) raises -> BigInt:
    """The smallest prime above `x`.

    Args:
        x: The value to start above. May be negative, where the answer is
            two.

    Returns:
        The next prime, strictly greater than `x`.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    The answer carries the certainty `is_prime` has at its size, so above
    `2^64` it is the next probable prime.

    Candidates skip the even numbers, and the multiples of three as well by
    stepping four instead of two where the next odd number is one. That is a
    third of the integers tested rather than a half, for the cost of the one
    division the step decision makes.
    """
    var two = BigInt(2)
    if x < two:
        return two^

    var candidate = x + BigInt.one()
    if not test_bit(candidate, 0):
        candidate = candidate + BigInt.one()
    # `candidate` is odd and at least three.
    while True:
        if is_prime(candidate):
            return candidate^
        var step = two.copy()
        if ((candidate + two) % BigInt(3)).is_zero():
            step = BigInt(4)
        candidate = candidate + step


def prev_prime(x: BigInt) raises -> BigInt:
    """The largest prime below `x`.

    Args:
        x: The value to start below.

    Returns:
        The previous prime, strictly less than `x`.

    Raises:
        ValueError: If `x` is three or less, since two is the smallest prime
            and there is nothing below it to return. An answer of zero or of
            `-1` would be a number that is not a prime, which is worse than
            refusing.
        Error: Propagated from the arithmetic.

    Notes:

    The answer carries the certainty `is_prime` has at its size, so above
    `2^64` it is the previous probable prime.

    The candidates come down the same wheel `next_prime` goes up, and cannot
    run off the bottom: the descent only starts at five or above, and three
    and five are both prime.
    """
    var two = BigInt(2)
    if x <= two:
        raise ValueError(
            message="There is no prime below two.",
            function="prev_prime()",
        )
    if x == BigInt(3):
        return two^

    var candidate = x - BigInt.one()
    if not test_bit(candidate, 0):
        candidate = candidate - BigInt.one()
    # `candidate` is odd and at least three.
    while True:
        if is_prime(candidate):
            return candidate^
        var step = two.copy()
        if ((candidate - two) % BigInt(3)).is_zero():
            step = BigInt(4)
        candidate = candidate - step


def primes_below(bound: Int) raises -> List[Int]:
    """The primes below `bound`, by sieve.

    Args:
        bound: The exclusive upper bound. Must not be negative.

    Returns:
        The primes strictly below `bound`, in order. Empty for a bound of two
        or less.

    Raises:
        ValueError: If `bound` is negative.

    Notes:

    The cost is the caller's to judge, so it is stated here: the sieve holds
    one byte for every odd number below the bound, which is `bound / 2` bytes,
    and the list it returns holds eight for every prime it finds. A bound of
    a billion is half a gigabyte of sieve and about four hundred megabytes of
    answer. There is no way to sieve to `2^64`, which is why this takes an
    `Int` rather than a `BigInt`: a bound that does not fit in memory is not a
    bound a sieve can use.

    Only the odd numbers are held, with two written into the answer directly.
    """
    if bound < 0:
        raise ValueError(
            message="A sieve bound cannot be negative.",
            function="primes_below()",
        )
    var primes = List[Int]()
    if bound <= 2:
        return primes^
    primes.append(2)
    if bound == 3:
        return primes^

    # `odd[i]` stands for the number `2 * i + 3`, so the slot for `n` is
    # `(n - 3) / 2` and the largest number held is the last odd below `bound`.
    var count = (bound - 2) // 2
    var odd = List[UInt8](length=count, fill=1)
    var index = 0
    while True:
        var value = 2 * index + 3
        if value * value >= bound:
            break
        if odd[index] != 0:
            # Start at the square: everything below it has a smaller factor.
            var multiple = (value * value - 3) // 2
            while multiple < count:
                odd[multiple] = 0
                multiple += value
        index += 1

    for i in range(count):
        if odd[i] != 0:
            primes.append(2 * i + 3)
    return primes^
