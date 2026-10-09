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

"""Integer factorization for BigInt, and the functions that need it.

Factoring is the one operation in this library that can be asked a question
nobody can answer. Addition of two million-digit numbers is slow; factoring a
product of two four-hundred-digit primes is not slow, it is beyond everything
now built. So `factor` is given a budget and is allowed to come back without
an answer, and `Factorization` has a `cofactor` field that says what it could
not split. A caller can always tell `7 * 11` from `I gave up`, which is the
difference that matters: a function that hangs instead tells the caller
nothing and cannot be interrupted.

The method is trial division by the small numbers, then Pollard's rho in
Brent's variant for whatever is left, with `is_prime` deciding at each step
whether a part needs splitting at all. Trial division removes every factor
below `TRIAL_DIVISION_BOUND` for about fourteen hundred divisions, which is
most of what real inputs are made of. Rho then finds a factor `p` in about
the square root of `p` iterations, so the budget -- counted in exactly those
iterations -- translates into a size of factor the caller can expect to get.

What `factor` returns above `2^64` is as certain as `is_prime` is there, and
no more: the parts are probable primes in the Baillie-PSW sense. The product
is exact either way, and `Factorization.value()` recovers it.

The rest of the file is the arithmetic that a factorization decides:
Euler's totient, the Moebius function, the divisors and their count and their
power sums, and the multiplicative order of a residue. Each takes a budget of
its own and raises rather than guesses when the factorization comes back
incomplete.
"""

from decimo.bigint.arithmetics import absolute, floor_divmod, power
from decimo.bigint.bigint import BigInt
from decimo.bigint.bitwise import trailing_zeros
from decimo.bigint.exponential import isqrt
from decimo.bigint.number_theory import gcd, mod_pow
from decimo.bigint.primality import is_prime
from decimo.errors import ValueError

comptime _TRIAL_DIVISION_BOUND_BITS = 12
"""The bits in `TRIAL_DIVISION_BOUND`, which the square root shortcut in
`_trial_division_limit` needs to know."""

comptime TRIAL_DIVISION_BOUND = 1 << _TRIAL_DIVISION_BOUND_BITS
"""Trial division covers every factor below this, which is 4 096.

A value whose every prime factor is under the bound is therefore factored
completely and without any use of the budget. The cost is one division for
each of the integers below the bound that the wheel does not skip, about
fourteen hundred of them.

Why not higher: rho reaches a factor `p` in about the square root of `p`
iterations and trial division in about a third of `p` divisions, so beyond a
few thousand the search is the cheaper of the two and the divisions are only
there to clear the small factors out of its way. Raising the bound to 65 536
cost four to six times as much on the values in the test suite and found
nothing that rho did not.
"""

comptime DEFAULT_FACTOR_BUDGET = 1 << 20
"""How many rho iterations `factor` spends before giving up, by default.

Rho finds a factor `p` in roughly the square root of `p` iterations, so a
million of them reach a factor of around `10^12`, which with the trial
division before it covers everything a sixty-four-bit integer can hold except
a product of two primes above `10^12`. A caller who wants more can ask for
more: four times the budget doubles the reach.
"""

comptime _GCD_BATCH = 128
"""How many rho differences are multiplied together before one GCD.

A GCD costs far more than a modular multiplication, so the differences are
accumulated into a product and the GCD taken once per batch. Brent's paper
takes the same step. The cost of the batch is that a factor is found up to
`_GCD_BATCH` iterations late, and the batch has to be walked back when the
product turns out to be a multiple of `n`.
"""


# ===----------------------------------------------------------------------=== #
# The result
# ===----------------------------------------------------------------------=== #


struct Factorization(Copyable, Deinitable, Movable, Sized, Writable):
    """What `factor` found, which may not be everything.

    The primes are in increasing order, and `powers[i]` is the exponent of
    `primes[i]`. `cofactor` is what the budget did not reach: one when the
    factorization is complete, and otherwise a composite whose factors are
    all larger than anything in `primes`.
    """

    var primes: List[BigInt]
    """The distinct prime factors found, in increasing order."""
    var powers: List[Int]
    """The exponent of each prime in `primes`, at the same index."""
    var cofactor: BigInt
    """The part that could not be factored within the budget; one when the
    factorization is complete."""

    def __init__(out self):
        """Initializes the factorization of one: no primes and no cofactor."""
        self.primes = List[BigInt]()
        self.powers = List[Int]()
        self.cofactor = BigInt.one()

    def __len__(self) -> Int:
        """Returns the number of distinct prime factors found.

        Returns:
            The length of `primes`, which counts each prime once however
            often it divides.
        """
        return len(self.primes)

    def is_complete(self) -> Bool:
        """Whether every factor was found.

        Returns:
            True when the cofactor is one, so that the primes and their
            exponents account for the whole value.
        """
        return self.cofactor.is_one()

    def value(self) raises -> BigInt:
        """Rebuilds the value this is the factorization of.

        Returns:
            The product of the prime powers and the cofactor. Exact whether
            or not the factorization is complete.

        Raises:
            Error: Propagated from the arithmetic.
        """
        var product = self.cofactor.copy()
        for i in range(len(self.primes)):
            product = product * power(self.primes[i], self.powers[i])
        return product^

    def write_to[W: Writer](self, mut writer: W):
        """Writes the factorization as a product.

        Parameters:
            W: A type conforming to the `Writer` interface.

        Args:
            writer: The writer instance.

        Notes:

        A complete factorization of twelve reads `2^2 * 3`, and one is
        written as `1`. An exponent of one is left off. A cofactor that the
        budget did not reach is named as such rather than printed beside the
        primes, where it would read as one of them.
        """
        if len(self.primes) == 0 and self.is_complete():
            writer.write("1")
            return
        for i in range(len(self.primes)):
            if i > 0:
                writer.write(" * ")
            writer.write(self.primes[i].to_string())
            if self.powers[i] != 1:
                writer.write("^", self.powers[i])
        if not self.is_complete():
            if len(self.primes) > 0:
                writer.write(" * ")
            writer.write("(unfactored ", self.cofactor.to_string(), ")")

    @no_inline
    def __str__(self) -> String:
        """Returns the factorization written as a product.

        Returns:
            The string representation.
        """
        return String(self)


# ===----------------------------------------------------------------------=== #
# Internal helpers
# ===----------------------------------------------------------------------=== #


def _record(
    mut primes: List[BigInt], mut powers: List[Int], p: BigInt, count: Int
):
    """Adds `count` copies of the prime `p` to a factor list.

    Args:
        primes: The primes found so far, in no particular order.
        powers: Their exponents, at matching indices.
        p: The prime to add.
        count: How many times it divides.

    Notes:

    Rho can hand back the same prime twice -- a square splits into two equal
    halves -- so a prime already in the list has its exponent raised rather
    than a second entry made for it.
    """
    for i in range(len(primes)):
        if primes[i] == p:
            powers[i] += count
            return
    primes.append(p.copy())
    powers.append(count)


def _sort_by_prime(mut primes: List[BigInt], mut powers: List[Int]):
    """Puts a factor list in increasing order of prime.

    Args:
        primes: The primes, reordered in place.
        powers: Their exponents, moved with them.

    Notes:

    Insertion sort, because the list is as long as the number of distinct
    prime factors: fifteen for a value that fits in sixty-four bits, and
    never more than the number of bits.
    """
    for i in range(1, len(primes)):
        var j = i
        while j > 0 and primes[j] < primes[j - 1]:
            var held = primes[j].copy()
            primes[j] = primes[j - 1].copy()
            primes[j - 1] = held^
            var held_power = powers[j]
            powers[j] = powers[j - 1]
            powers[j - 1] = held_power
            j -= 1


def _trial_division_limit(remaining: BigInt) raises -> Int:
    """The largest trial divisor worth trying against `remaining`.

    Args:
        remaining: The value still to be factored.

    Returns:
        The smaller of `TRIAL_DIVISION_BOUND` and the integer square root of
        `remaining`. A divisor above the square root cannot divide a value
        with no divisor below it.

    Raises:
        Error: Propagated from the square root.

    Notes:

    The square root is only taken when it could come out below the bound,
    which is a value of at most twice the bound's bits. Everything larger
    returns the bound without the root being computed at all, so the common
    case of a big input costs nothing here.
    """
    if remaining.bit_length() > 2 * _TRIAL_DIVISION_BOUND_BITS:
        return TRIAL_DIVISION_BOUND
    return min(TRIAL_DIVISION_BOUND, Int(isqrt(remaining)))


def _absolute_difference(x: BigInt, y: BigInt) -> BigInt:
    """The distance between two values.

    Args:
        x: The first value.
        y: The second value.

    Returns:
        `|x - y|`.
    """
    return absolute(x - y)


def _rho_attempt(
    n: BigInt, c: BigInt, mut budget: Int
) raises -> Tuple[BigInt, Bool]:
    """One pass of Brent's rho over `n` with the additive constant `c`.

    Args:
        n: The odd composite to split.
        c: The constant in the iteration `y -> y^2 + c`.
        budget: The iterations left to spend, decremented by every one taken.

    Returns:
        A pair of the factor found and whether this pass finished. The factor
        is zero when the pass found nothing; the flag separates the two
        reasons for that -- `True` means this `c` led to a cycle that gave
        back `n` itself and another `c` is worth trying, `False` means the
        budget ran out mid-pass and nothing more is worth trying.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    The iteration walks `y -> y^2 + c` modulo `n` and looks for two indices
    whose values agree modulo some factor of `n`, which shows up as a
    non-trivial GCD. Brent's variant compares against a held value `x` taken
    at every power of two and runs the comparison in batches, so a factor
    costs one GCD per `_GCD_BATCH` iterations rather than one per iteration.

    When the batched product turns out to be a multiple of `n` -- two
    different factors found inside one batch, or a collision modulo `n`
    itself -- the batch is walked again one step at a time from the value
    held at its start, which is what `ys` is kept for.
    """
    var one = BigInt.one()
    var y = BigInt(2)
    var x = y.copy()
    var ys = y.copy()
    var q = one.copy()
    var g = one.copy()
    var r = 1

    while g.is_one():
        x = y.copy()
        for _ in range(r):
            if budget <= 0:
                return (BigInt.zero(), False)
            y = (y * y + c) % n
            budget -= 1
        var k = 0
        while k < r and g.is_one():
            ys = y.copy()
            var batch = min(_GCD_BATCH, r - k)
            for _ in range(batch):
                if budget <= 0:
                    return (BigInt.zero(), False)
                y = (y * y + c) % n
                budget -= 1
                q = (q * _absolute_difference(x, y)) % n
            g = gcd(q, n)
            k += batch
        r *= 2

    if g == n:
        # The batch hid the answer. Walk it again one step at a time.
        g = one.copy()
        while g.is_one():
            if budget <= 0:
                return (BigInt.zero(), False)
            ys = (ys * ys + c) % n
            budget -= 1
            g = gcd(_absolute_difference(x, ys), n)

    if g == n:
        return (BigInt.zero(), True)
    return (g^, True)


def _rho_factor(n: BigInt, mut budget: Int) raises -> BigInt:
    """A non-trivial factor of the odd composite `n`, or zero.

    Args:
        n: The value to split, which must be composite, odd and larger than
            one.
        budget: The iterations left to spend, decremented by every one taken.

    Returns:
        A factor strictly between one and `n`, not necessarily prime, or zero
        when the budget ran out before one was found.

    Raises:
        Error: Propagated from the arithmetic.

    Notes:

    A pass can fail for its own reasons rather than for want of budget, so
    the constant is stepped and the pass repeated. Every pass spends at least
    one iteration, which is what stops this from looping forever.
    """
    var c = BigInt.one()
    while True:
        var attempt = _rho_attempt(n, c, budget)
        if not attempt[0].is_zero():
            return attempt[0].copy()
        if not attempt[1]:
            return BigInt.zero()
        c = c + BigInt.one()


# ===----------------------------------------------------------------------=== #
# Factorization
# ===----------------------------------------------------------------------=== #


def factor(
    x: BigInt, budget: Int = DEFAULT_FACTOR_BUDGET
) raises -> Factorization:
    """Factors `x` into primes, as far as the budget allows.

    Args:
        x: The value to factor, which must be positive.
        budget: How many rho iterations may be spent. See
            `DEFAULT_FACTOR_BUDGET` for what that buys.

    Returns:
        The primes and exponents found, together with the part that was not
        factored. `Factorization.is_complete()` says whether there is such a
        part, and `Factorization.value()` is `x` either way.

    Raises:
        ValueError: If `x` is not positive. Zero is divisible by every prime
            to every power, and a negative number is minus one times the
            factorization of its magnitude -- minus one is a unit and not a
            prime, so rather than return it among the primes or drop the sign
            in silence, this asks the caller to take the magnitude.
        ValueError: If the budget is negative.
        Error: Propagated from the arithmetic.

    Notes:

    The factors are prime with the certainty `is_prime` has at their size:
    exact below `2^64`, and probable in the Baillie-PSW sense above it. The
    product is exact regardless.

    The budget is for the whole call, not for each part, so a value with
    several hard pieces cannot cost several times what was allowed.
    """
    if not x.is_positive():
        raise ValueError(
            message=(
                "Only a positive number has a factorization into primes; for"
                " a negative one, factor its magnitude."
            ),
            function="factor()",
        )
    if budget < 0:
        raise ValueError(
            message="A factoring budget cannot be negative.",
            function="factor()",
        )

    var result = Factorization()
    if x.is_one():
        return result^

    var remaining = x.copy()

    # The powers of two, which the bit pattern gives away without a division.
    var twos = trailing_zeros(remaining)
    if twos > 0:
        remaining = remaining >> twos
        _record(result.primes, result.powers, BigInt(2), twos)

    # Then three, and then the numbers that are neither even nor a multiple
    # of three: five, seven, eleven, thirteen, and so on by two and four.
    var limit = _trial_division_limit(remaining)
    var candidate = 3
    var step = 2
    while candidate <= limit:
        var divisor = BigInt(candidate)
        var count = 0
        while True:
            var division = floor_divmod(remaining, divisor)
            if not division[1].is_zero():
                break
            remaining = division[0].copy()
            count += 1
        if count > 0:
            _record(result.primes, result.powers, divisor, count)
            limit = _trial_division_limit(remaining)
        if candidate == 3:
            candidate = 5
        else:
            candidate += step
            step = 6 - step

    if remaining.is_one():
        _sort_by_prime(result.primes, result.powers)
        return result^

    # Past the square root of what is left, so what is left is prime.
    if limit < TRIAL_DIVISION_BOUND:
        _record(result.primes, result.powers, remaining, 1)
        _sort_by_prime(result.primes, result.powers)
        return result^

    # What is left has no factor below the bound. Split it with rho until
    # every part is prime or the budget is gone.
    var budget_left = budget
    var pending = List[BigInt]()
    pending.append(remaining^)
    var unfactored = BigInt.one()

    while len(pending) > 0:
        var part = pending.pop()
        if part.is_one():
            continue
        if is_prime(part):
            _record(result.primes, result.powers, part, 1)
            continue
        var found = _rho_factor(part, budget_left)
        if found.is_zero():
            unfactored = unfactored * part
            continue
        pending.append(found.copy())
        pending.append(part // found)

    result.cofactor = unfactored^
    _sort_by_prime(result.primes, result.powers)
    return result^


def _complete_factorization(
    x: BigInt, budget: Int, function: String
) raises -> Factorization:
    """Factors `x` completely or raises.

    Args:
        x: The value to factor, which must be positive.
        budget: How many rho iterations may be spent.
        function: The name to report in an error.

    Returns:
        A complete factorization of `x`.

    Raises:
        ValueError: If `x` is not positive, or if the budget ran out with
            part of `x` still unfactored. Everything in this file below
            `factor` is a product over the primes of `x`, and there is no
            honest answer to give for a value whose primes are not known.
        Error: Propagated from the arithmetic.
    """
    var parts = factor(x, budget)
    if not parts.is_complete():
        raise ValueError(
            message=(
                "The factorization is incomplete, so this cannot be computed: "
                + parts.cofactor.to_string()
                + " was not split within the budget of "
                + String(budget)
                + " iterations. A larger budget may reach it."
            ),
            function=function,
        )
    return parts^


# ===----------------------------------------------------------------------=== #
# What a factorization decides
# ===----------------------------------------------------------------------=== #


def euler_phi(x: BigInt, budget: Int = DEFAULT_FACTOR_BUDGET) raises -> BigInt:
    """Euler's totient: how many of `1 ... x` are coprime to `x`.

    Args:
        x: The value, which must be positive.
        budget: How many rho iterations the factorization may spend.

    Returns:
        The count of integers in `[1, x]` sharing no factor with `x`. One for
        `x = 1`, since one is coprime to itself.

    Raises:
        ValueError: If `x` is not positive, or if `x` could not be factored
            within the budget.
        Error: Propagated from the arithmetic.

    Notes:

    The totient is the product over the prime powers `p^e` of `x` of
    `p^(e-1) * (p - 1)`.
    """
    var parts = _complete_factorization(x, budget, "euler_phi()")
    var total = BigInt.one()
    for i in range(len(parts.primes)):
        var p = parts.primes[i].copy()
        total = total * power(p, parts.powers[i] - 1) * (p - BigInt.one())
    return total^


def moebius(x: BigInt, budget: Int = DEFAULT_FACTOR_BUDGET) raises -> Int:
    """The Moebius function of `x`.

    Args:
        x: The value, which must be positive.
        budget: How many rho iterations the factorization may spend.

    Returns:
        Zero if a square divides `x`, and otherwise minus one to the power of
        the number of prime factors: `1` for `x = 1`, `-1` for a prime,
        `1` for a product of two distinct primes, and so on.

    Raises:
        ValueError: If `x` is not positive, or if `x` could not be factored
            within the budget.
        Error: Propagated from the arithmetic.
    """
    var parts = _complete_factorization(x, budget, "moebius()")
    for i in range(len(parts.primes)):
        if parts.powers[i] > 1:
            return 0
    return 1 if len(parts.primes) % 2 == 0 else -1


def divisor_count(
    x: BigInt, budget: Int = DEFAULT_FACTOR_BUDGET
) raises -> BigInt:
    """How many positive divisors `x` has.

    Args:
        x: The value, which must be positive.
        budget: How many rho iterations the factorization may spend.

    Returns:
        The product of `e + 1` over the prime powers `p^e` of `x`. One for
        `x = 1`, two for a prime.

    Raises:
        ValueError: If `x` is not positive, or if `x` could not be factored
            within the budget.
        Error: Propagated from the arithmetic.

    Notes:

    The count is a `BigInt` rather than an `Int` because it need not fit in
    one: a product of seventy distinct primes has `2^70` divisors, and that
    value is small enough to factor in an instant.
    """
    var parts = _complete_factorization(x, budget, "divisor_count()")
    var total = BigInt.one()
    for i in range(len(parts.primes)):
        total = total * BigInt(parts.powers[i] + 1)
    return total^


def divisor_sum(
    x: BigInt, power_of_divisor: Int = 1, budget: Int = DEFAULT_FACTOR_BUDGET
) raises -> BigInt:
    """The sum of the divisors of `x`, each raised to a power.

    Args:
        x: The value, which must be positive.
        power_of_divisor: The power each divisor is raised to before being
            summed. One, the default, sums the divisors themselves; zero
            counts them.
        budget: How many rho iterations the factorization may spend.

    Returns:
        The sum over the positive divisors `d` of `x` of `d` to the given
        power.

    Raises:
        ValueError: If `x` is not positive, if the power is negative --
            a sum of reciprocal divisors is not an integer -- or if `x`
            could not be factored within the budget.
        Error: Propagated from the arithmetic.

    Notes:

    The sum is a product over the prime powers `p^e` of `x`, each factor
    being the geometric series `(p^(k(e+1)) - 1) / (p^k - 1)` for a power `k`.
    At `k = 0` that series is `e + 1`, which the division cannot say, so the
    count is taken separately.
    """
    if power_of_divisor < 0:
        raise ValueError(
            message=(
                "The power must not be negative: a sum of reciprocal divisors"
                " is not an integer."
            ),
            function="divisor_sum()",
        )
    var parts = _complete_factorization(x, budget, "divisor_sum()")
    var one = BigInt.one()
    var total = one.copy()
    for i in range(len(parts.primes)):
        var exponent = parts.powers[i]
        if power_of_divisor == 0:
            total = total * BigInt(exponent + 1)
            continue
        var base = power(parts.primes[i], power_of_divisor)
        total = total * ((power(base, exponent + 1) - one) // (base - one))
    return total^


def divisors(
    x: BigInt, budget: Int = DEFAULT_FACTOR_BUDGET
) raises -> List[BigInt]:
    """Every positive divisor of `x`, in increasing order.

    Args:
        x: The value, which must be positive.
        budget: How many rho iterations the factorization may spend.

    Returns:
        The divisors from one to `x`, ascending. A single `1` for `x = 1`.

    Raises:
        ValueError: If `x` is not positive, or if `x` could not be factored
            within the budget.
        Error: Propagated from the arithmetic.

    Notes:

    The cost is the caller's to judge, so it is stated here: the list holds
    one `BigInt` per divisor, and `divisor_count` says in advance how many
    that is. A highly composite number has a great many -- the product of the
    primes below a hundred has thirty-three million -- and asking for them
    all is asking for the memory to hold them.

    The order comes out of the construction rather than from a sort. The
    divisors of a value are those of it with one prime power removed, each
    multiplied by `1, p, ..., p^e`; those products are `e + 1` ascending runs
    over the same list, so merging them keeps the whole list ascending.
    """
    var parts = _complete_factorization(x, budget, "divisors()")
    var found = List[BigInt]()
    found.append(BigInt.one())

    for i in range(len(parts.primes)):
        var exponent = parts.powers[i]
        # The multipliers for this prime: 1, p, p^2, ..., p^e.
        var multipliers = List[BigInt](capacity=exponent + 1)
        multipliers.append(BigInt.one())
        for k in range(exponent):
            multipliers.append(multipliers[k] * parts.primes[i])

        # Merge the runs. `cursors[k]` is how far the run through
        # `multipliers[k]` has been consumed.
        var cursors = List[Int](length=exponent + 1, fill=0)
        var merged = List[BigInt](capacity=len(found) * (exponent + 1))
        for _ in range(len(found) * (exponent + 1)):
            var best = -1
            var best_value = BigInt.zero()
            for k in range(exponent + 1):
                if cursors[k] >= len(found):
                    continue
                var candidate = found[cursors[k]] * multipliers[k]
                if best < 0 or candidate < best_value:
                    best = k
                    best_value = candidate^
            cursors[best] += 1
            merged.append(best_value^)
        found = merged^

    return found^


def multiplicative_order(
    a: BigInt, modulus: BigInt, budget: Int = DEFAULT_FACTOR_BUDGET
) raises -> BigInt:
    """The least positive `k` with `a^k` congruent to one modulo `modulus`.

    Args:
        a: The residue, of either sign, which must be coprime to the modulus.
        modulus: The modulus, which must be positive.
        budget: How many rho iterations each factorization may spend. Two are
            needed -- of the modulus and of its totient -- and each is
            allowed this many.

    Returns:
        The multiplicative order of `a` modulo `modulus`. One when the
        modulus is one, where every power is congruent to everything.

    Raises:
        ValueError: If the modulus is not positive, if `a` and the modulus
            share a factor -- no power of `a` is then congruent to one, so
            there is no order to return -- or if a factorization did not
            finish within the budget.
        Error: Propagated from the arithmetic.

    Notes:

    The order divides the totient, so the search starts there and divides out
    one prime of it at a time, keeping the quotient whenever `a` raised to it
    is still one. That needs the totient factored as well as the modulus.
    """
    if not modulus.is_positive():
        raise ValueError(
            message="The modulus must be positive.",
            function="multiplicative_order()",
        )
    if modulus.is_one():
        return BigInt.one()
    if not gcd(a, modulus).is_one():
        raise ValueError(
            message=(
                "The residue and the modulus share a factor, so no power of"
                " the residue is congruent to one."
            ),
            function="multiplicative_order()",
        )

    var order = euler_phi(modulus, budget)
    var totient_parts = _complete_factorization(
        order, budget, "multiplicative_order()"
    )
    for i in range(len(totient_parts.primes)):
        var p = totient_parts.primes[i].copy()
        for _ in range(totient_parts.powers[i]):
            var reduced = order // p
            if not mod_pow(a, reduced, modulus).is_one():
                break
            order = reduced^
    return order^
