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

"""
Tests primality testing for BigInt.

Two anchors hold these tests down. One is outside the library: the list of
primes below a thousand, the hard composites and the large reference values
were all computed in Python and pasted here, never recalled. The other is
inside it but shares no code with what it checks: the sieve and Miller-Rabin
arrive at primality by different routes, so running both over a range and
comparing is a real test of each.

The composites are chosen to be the ones that fool something. A Carmichael
number passes Fermat's test to every base coprime to it. A base-2 strong
pseudoprime passes the first Miller-Rabin round, which is why the set has
seven bases and not one. And a composite Fermat number passes that round at a
size where no witness set is proven, so the only thing that can reject it is
the Lucas half of Baillie-PSW -- which makes it the one case that tests that
half at all.
"""

from std import testing
from std.testing import assert_equal, assert_false, assert_true

from decimo.bigint.bigint import BigInt
from decimo.bigint.primality import (
    is_prime,
    next_prime,
    prev_prime,
    primes_below,
)
from decimo.biguint.biguint import BigUInt


def _two_hundred_digit_prime() raises -> BigInt:
    """A prime of two hundred digits, found in Python with a wide witness set.

    Returns:
        The prime.
    """
    return BigInt(
        "909360444017462602758551187017250289556232945419934964685121025139"
        "857343005519604227877104895079216255435034670060337794919405211465"
        "79992988539438580779003417364712470158105840961389350494305858671869"
    )


def _another_two_hundred_digit_prime() raises -> BigInt:
    """A second one, so that their product is a four-hundred-digit composite.

    Returns:
        The prime.
    """
    return BigInt(
        "768477317880952896438020930410163402651535059186729639247944670786"
        "225480960570956881689854142196929223725342963427823273374385787226"
        "97110947005174154130686784081329026526712991194455369827602186300507"
    )


def test_the_sieve_lists_the_primes_below_a_thousand() raises:
    """The whole list, as a Python sieve produced it.

    This is the one test with an expected value from outside the library, so
    everything else can be checked against the sieve instead of against
    another primality test.
    """
    var expected = [
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
        101,
        103,
        107,
        109,
        113,
        127,
        131,
        137,
        139,
        149,
        151,
        157,
        163,
        167,
        173,
        179,
        181,
        191,
        193,
        197,
        199,
        211,
        223,
        227,
        229,
        233,
        239,
        241,
        251,
        257,
        263,
        269,
        271,
        277,
        281,
        283,
        293,
        307,
        311,
        313,
        317,
        331,
        337,
        347,
        349,
        353,
        359,
        367,
        373,
        379,
        383,
        389,
        397,
        401,
        409,
        419,
        421,
        431,
        433,
        439,
        443,
        449,
        457,
        461,
        463,
        467,
        479,
        487,
        491,
        499,
        503,
        509,
        521,
        523,
        541,
        547,
        557,
        563,
        569,
        571,
        577,
        587,
        593,
        599,
        601,
        607,
        613,
        617,
        619,
        631,
        641,
        643,
        647,
        653,
        659,
        661,
        673,
        677,
        683,
        691,
        701,
        709,
        719,
        727,
        733,
        739,
        743,
        751,
        757,
        761,
        769,
        773,
        787,
        797,
        809,
        811,
        821,
        823,
        827,
        829,
        839,
        853,
        857,
        859,
        863,
        877,
        881,
        883,
        887,
        907,
        911,
        919,
        929,
        937,
        941,
        947,
        953,
        967,
        971,
        977,
        983,
        991,
        997,
    ]
    var sieved = primes_below(1000)
    assert_equal(len(sieved), len(expected), "the count of primes below 1000")
    for i in range(len(expected)):
        assert_equal(
            sieved[i], expected[i], String("the prime at position ") + String(i)
        )

    # The small bounds, where the odd-only sieve has the fewest slots to get
    # right.
    assert_equal(len(primes_below(0)), 0, "no primes below nothing")
    assert_equal(len(primes_below(2)), 0, "two is not below two")
    assert_equal(len(primes_below(3)), 1, "only two is below three")
    assert_equal(len(primes_below(4)), 2, "two and three")
    assert_equal(len(primes_below(10)), 4, "two, three, five and seven")


def test_the_test_and_the_sieve_agree_over_a_range() raises:
    """Miller-Rabin against the sieve, for every number below twenty thousand.

    The two have no code in common: one divides out multiples and the other
    exponentiates modulo the candidate. Agreeing over two thousand primes and
    eighteen thousand composites is what makes either believable.

    Trial division settles everything below `101^2` on its own, so it is the
    upper half of this range that exercises the witness set, and the bound is
    what it is to keep the file inside a sensible test budget. The exhaustive
    check to ten million lives outside the suite, in the script that verified
    the set in the first place.
    """
    var bound = 20000
    var sieved = primes_below(bound)
    var marked = List[Bool](length=bound, fill=False)
    for p in sieved:
        marked[p] = True

    for n in range(bound):
        assert_equal(
            is_prime(BigInt(n)),
            marked[n],
            String("the primality of ") + String(n),
        )


def test_nothing_below_two_is_prime() raises:
    """Zero, one and the negative numbers are not prime.

    Primality here is the arithmetic of the natural numbers, so `-7` is not a
    prime however interesting it is as a prime element of the integers. The
    answer is False rather than an error, because asking is reasonable.
    """
    for n in [-561, -7, -2, -1, 0, 1]:
        assert_false(
            is_prime(BigInt(n)), String("the primality of ") + String(n)
        )
    assert_true(is_prime(BigInt(2)), "two is prime")
    assert_true(is_prime(BigInt(3)), "and so is three")


def test_a_carmichael_number_is_not_prime() raises:
    """A composite that passes Fermat's test to every base coprime to it.

    Fermat's test cannot tell these from primes at all, which is the reason
    the strong test exists: squaring up through the factors of two of `n - 1`
    looks for a square root of one that is neither one nor minus one, and a
    Carmichael number has them.
    """
    for n in [561, 1105, 1729, 2821, 6601, 8911]:
        assert_false(
            is_prime(BigInt(n)),
            String("the Carmichael number ") + String(n),
        )


def test_a_base_two_strong_pseudoprime_is_not_prime() raises:
    """A composite that survives the first Miller-Rabin round.

    Each of these passes the strong test to base 2, so a one-base test calls
    them prime. They are what the other six bases are for.
    """
    for n in [2047, 3277, 4033, 4681, 8321]:
        assert_false(
            is_prime(BigInt(n)),
            String("the base-2 strong pseudoprime ") + String(n),
        )


def test_the_lucas_half_catches_what_the_base_two_round_lets_through() raises:
    """A composite Fermat number above 2^64 is rejected, and only Lucas can.

    `2^(2^k) + 1` is a strong pseudoprime to base 2 whenever it is composite:
    with `n - 1` a power of two the odd part is one, and `2^(2^k)` is `-1`
    modulo `n` by construction, which is exactly what the strong test looks
    for. Each of these three was checked in Python to pass that round.

    They are above `2^64`, so the deterministic witness set does not apply and
    the test is Baillie-PSW. Their smallest factors are 274177, 59649589127497217
    and 1238926361552897, none of which trial division reaches. So the only
    thing left that can return False is the strong Lucas test, and these are
    the cases that show it works.
    """
    var fermat_6 = BigInt("18446744073709551617")
    var fermat_7 = BigInt("340282366920938463463374607431768211457")
    var fermat_8 = BigInt(
        "115792089237316195423570985008687907853269984665640564039457584007"
        "913129639937"
    )
    assert_false(is_prime(fermat_6), "2^64 + 1 is 274177 times 67280421310721")
    assert_false(is_prime(fermat_7), "2^128 + 1 is composite")
    assert_false(is_prime(fermat_8), "2^256 + 1 is composite")


def test_the_values_around_two_to_the_sixty_four() raises:
    """Both sides of the boundary between certainty and probability.

    `is_prime` changes method at `2^64`, so the values either side of it are
    where a mistake in the dispatch would show.
    """
    assert_true(
        is_prime(BigInt("2305843009213693951")),
        "2^61 - 1 is a Mersenne prime",
    )
    assert_true(
        is_prime(BigInt("18446744073709551557")),
        "the largest prime below 2^64",
    )
    assert_false(
        is_prime(BigInt("18446744073709551616")), "2^64 itself is even"
    )
    assert_true(
        is_prime(BigInt("18446744073709551629")),
        "the smallest prime above 2^64, where Baillie-PSW takes over",
    )
    assert_true(
        is_prime(BigInt("162259276829213363391578010288127")),
        "2^107 - 1 is a Mersenne prime",
    )
    assert_false(
        is_prime(BigInt("651693055693681")),
        "a Carmichael number with three factors",
    )


def test_two_hundred_digit_primes_and_their_product() raises:
    """The size the Lucas test is really for, and a composite of twice it.

    The product has four hundred digits and no small factor, so rejecting it
    is the whole of Baillie-PSW doing its work. Factoring it would be out of
    reach; recognising it as composite costs two modular exponentiations.
    """
    var p = _two_hundred_digit_prime()
    var q = _another_two_hundred_digit_prime()
    assert_true(is_prime(p), "the first two-hundred-digit prime")
    assert_true(is_prime(q), "the second")
    assert_false(is_prime(p * q), "and their product is not prime")


def test_next_prime_steps_over_a_gap() raises:
    """The next prime, including across the longest gap under two thousand.

    Nothing between 1327 and 1361 is prime, a run of thirty-three composites,
    which is where a stepping mistake would be caught.
    """
    assert_equal(next_prime(BigInt(1000)), BigInt(1009), "after a round number")
    assert_equal(next_prime(BigInt(1327)), BigInt(1361), "over the gap")
    assert_equal(next_prime(BigInt(7919)), BigInt(7927), "after a prime")
    assert_equal(next_prime(BigInt(2)), BigInt(3), "after the first prime")
    assert_equal(next_prime(BigInt(1)), BigInt(2), "before any prime")
    assert_equal(next_prime(BigInt(-5)), BigInt(2), "from below zero")
    assert_equal(
        next_prime(BigInt("1000000000000000000000000000000")),
        BigInt("1000000000000000000000000000057"),
        "after ten to the thirtieth, where every candidate costs a Baillie-PSW",
    )


def test_prev_prime_refuses_to_go_below_two() raises:
    """There is no prime below two, so there is nothing to return.

    Zero or minus one would be a number that is not prime, which is a worse
    answer than an error.
    """
    for n in [-5, 0, 1, 2]:
        var raised = False
        try:
            _ = prev_prime(BigInt(n))
        except:
            raised = True
        assert_true(raised, String("a prime was claimed below ") + String(n))

    assert_equal(prev_prime(BigInt(3)), BigInt(2), "below three is two")
    assert_equal(prev_prime(BigInt(4)), BigInt(3), "below four is three")
    assert_equal(prev_prime(BigInt(1000)), BigInt(997), "below a thousand")
    assert_equal(
        prev_prime(BigInt(7920)), BigInt(7919), "below a prime plus one"
    )
    assert_equal(
        prev_prime(BigInt("1000000000000000000000000000000")),
        BigInt("999999999999999999999999999989"),
        "below ten to the thirtieth",
    )


def test_the_sieve_refuses_a_negative_bound() raises:
    """A bound below zero is a mistake, not an empty answer."""
    var raised = False
    try:
        _ = primes_below(-1)
    except:
        raised = True
    assert_true(raised, "a negative bound was accepted")


def test_the_unsigned_overload_answers_the_same() raises:
    """`BigUInt` has no sign to consider, and otherwise nothing changes."""
    for n in [0, 1, 2, 97, 561, 7919, 8911]:
        assert_equal(
            is_prime(BigUInt(n)),
            is_prime(BigInt(n)),
            String("the two overloads on ") + String(n),
        )
    assert_true(
        is_prime(BigUInt.from_string("18446744073709551629")),
        "and the unsigned one reaches past 2^64 as well",
    )


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
